#!/bin/bash

# ==============================================================================
# remove_sheet_watch.sh
# ==============================================================================
#
# Purpose:
#   This script removes a Google Sheet from the monitoring system. It performs
#   three main actions:
#   1. Queries the SheetWatchRegistry DynamoDB table to find the channelId and
#      resourceId associated with the given GOOGLE_SHEET_ID.
#   2. Calls the Google Drive API to stop the notification channel.
#   3. Deletes the item from the SheetWatchRegistry DynamoDB table.
#
# Usage:
#   You must set the following environment variables before running:
#   - GOOGLE_SHEET_ID: The ID of the Google Sheet to stop watching.
#   - APP_ENV: The environment (dev, staging, prod) to operate on.
#
# Example:
#   export GOOGLE_SHEET_ID="12345abcde"
#   export APP_ENV="dev"
#   ./scripts/remove_sheet_watch.sh
#
# ==============================================================================

set -e # Exit immediately if a command exits with a non-zero status.

# --- Input Validation ---
if [ -z "$GOOGLE_SHEET_ID" ]; then
    echo "Error: GOOGLE_SHEET_ID environment variable is not set."
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
TABLE_NAME="SheetWatchRegistry-${APP_ENV}"
echo "  Environment (APP_ENV): $APP_ENV"
echo "  Google Sheet ID:       $GOOGLE_SHEET_ID"
echo "  DynamoDB Table:        $TABLE_NAME"

print_header "Step 1: Fetching Channel Info from DynamoDB"

ITEM_JSON=$(aws dynamodb get-item \
    --table-name "$TABLE_NAME" \
    --key '{"sheet_id": {"S": "'"$GOOGLE_SHEET_ID"'"}}' \
    --projection-expression "channel_id, resource_id")

if [ -z "$ITEM_JSON" ] || [ "$(echo "$ITEM_JSON" | jq -r '.Item')" == "null" ]; then
    echo "Warning: No watch channel found in DynamoDB for sheet ID '$GOOGLE_SHEET_ID'."
    echo "The sheet may have already been removed. Exiting gracefully."
    exit 0
fi

CHANNEL_ID=$(echo "$ITEM_JSON" | jq -r '.Item.channel_id.S')
RESOURCE_ID=$(echo "$ITEM_JSON" | jq -r '.Item.resource_id.S')

if [ -z "$CHANNEL_ID" ] || [ -z "$RESOURCE_ID" ]; then
    echo "Error: Could not parse channel_id or resource_id from DynamoDB item."
    echo "Item data: $ITEM_JSON"
    exit 1
fi

echo "  Found Channel ID:  $CHANNEL_ID"
echo "  Found Resource ID: $RESOURCE_ID"

print_header "Step 2: Stopping Google Drive Watch Channel"
# We add `|| true` because gcloud exits with an error if the channel is already
# expired or gone, but we still want to proceed to delete it from our DB.
gcloud alpha drive channels stop "$CHANNEL_ID" "$RESOURCE_ID" --format="none" || true
echo "Successfully sent stop command to Google API."

print_header "Step 3: Deleting Channel from DynamoDB"
aws dynamodb delete-item \
    --table-name "$TABLE_NAME" \
    --key '{
        "sheet_id": {"S": "'"$GOOGLE_SHEET_ID"'"}
    }'

echo "Successfully deleted watch channel registration from DynamoDB."

print_header "Process Complete"
echo "The system will no longer monitor sheet $GOOGLE_SHEET_ID for changes."
