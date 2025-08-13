#!/bin/bash

# ==============================================================================
# add_sheet_watch.sh
# ==============================================================================
#
# Purpose:
#   This script adds a new Google Sheet to the monitoring system. It performs
#   two main actions:
#   1. Calls the Google Drive API to create a `files.watch` notification channel.
#   2. Writes the details of this new channel (channel ID, resource ID, expiration)
#      into the SheetWatchRegistry DynamoDB table.
#
# Usage:
#   You must set the following environment variables before running:
#   - GOOGLE_SHEET_ID: The ID of the Google Sheet to watch.
#   - INGEST_WEBHOOK_URL: The full Inngest webhook URL that Google will POST to.
#   - APP_ENV: The environment (dev, staging, prod) to operate on.
#
# Example:
#   export GOOGLE_SHEET_ID="12345abcde"
#   export INGEST_WEBHOOK_URL="https://..."
#   export APP_ENV="dev"
#   ./scripts/add_sheet_watch.sh
#
# ==============================================================================

set -e # Exit immediately if a command exits with a non-zero status.

# --- Input Validation ---
if [ -z "$GOOGLE_SHEET_ID" ]; then
    echo "Error: GOOGLE_SHEET_ID environment variable is not set."
    exit 1
fi
if [ -z "$INGEST_WEBHOOK_URL" ]; then
    echo "Error: INGEST_WEBHOOK_URL environment variable is not set."
    exit 1
fi
if [ -z "$APP_ENV" ]; then
    echo "Error: APP_ENV environment variable is not set. Please set to 'dev', 'staging', or 'prod'."
    exit 1
fi

# --- Helper Functions ---
function print_header() {
    echo ""
    echo "---- $1 ----"
}

# --- Main Logic ---
print_header "Script Configuration"
echo "  Environment (APP_ENV): $APP_ENV"
echo "  Google Sheet ID:       $GOOGLE_SHEET_ID"
echo "  Inngest Webhook URL:   $INGEST_WEBHOOK_URL"

# Generate a unique ID for the new channel
CHANNEL_ID=$(uuidgen)
echo "  Generated Channel ID:  $CHANNEL_ID"

print_header "Step 1: Creating Google Drive Watch Channel"
WATCH_RESPONSE=$(gcloud alpha drive watch "$GOOGLE_SHEET_ID" \
    --channel-id "$CHANNEL_ID" \
    --address "$INGEST_WEBHOOK_URL" \
    --format="json")

    if [ -z "$WATCH_RESPONSE" ]; then
    echo "Error: Failed to create Google Drive watch channel. The response was empty."
    echo "Please check your 'gcloud' authentication and permissions."
    exit 1
fi

echo "Successfully received response from Google API:"
echo "$WATCH_RESPONSE"

# Extract details from the JSON response
RESOURCE_ID=$(echo "$WATCH_RESPONSE" | jq -r '.resourceId')
EXPIRATION_MS=$(echo "$WATCH_RESPONSE" | jq -r '.expiration') # Expiration is in milliseconds since epoch

if [ -z "$RESOURCE_ID" ] || [ -z "$EXPIRATION_MS" ]; then
    echo "Error: Could not parse resourceId or expiration from Google's response."
    exit 1
fi

print_header "Step 2: Registering Channel in DynamoDB"
TABLE_NAME="SheetWatchRegistry-${APP_ENV}"
echo "  Target DynamoDB Table: $TABLE_NAME"

aws dynamodb put-item \
    --table-name "$TABLE_NAME" \
    --item '{
        "sheet_id": {"S": "'"$GOOGLE_SHEET_ID"'"},
        "channel_id": {"S": "'"$CHANNEL_ID"'"},
        "resource_id": {"S": "'"$RESOURCE_ID"'"},
        "expiration_ms": {"N": "'"$EXPIRATION_MS"'"}
        }' \
    --return-consumed-capacity NONE

echo "Successfully registered watch channel in DynamoDB."

print_header "Process Complete"
echo "The system will now monitor s_sheet_id for changes."