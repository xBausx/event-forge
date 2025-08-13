# Runbook: Managing Watched Google Sheets

**Purpose:** This document outlines the procedures for adding a new Google Sheet to the monitoring system and removing an existing one.

**Frequency:** As needed, whenever a new sheet needs to be processed by the Event-Forge pipeline or an old one needs to be decommissioned.

**Owner:** Cloud Engineering Team

---

## 1. Background

The Event-Forge system can monitor multiple Google Sheets simultaneously. Each monitored sheet has its own Google Drive Push Notification "channel." Information about these channels, including their expiration dates, is stored in a central DynamoDB table (`SheetWatchRegistry`).

While channel _renewal_ is designed to be an automated process (handled by a scheduled Lambda), the initial act of **adding** a sheet to watch or **removing** it is a manual, deliberate action performed by an operator.

## 2. Prerequisites

- **Sheet Access:** The Google Service Account used by our system must have at least "Viewer" access to the Google Sheet you intend to add.
- **Permissions:** You must have AWS credentials with permissions to run the management scripts and access the `SheetWatchRegistry` DynamoDB table.
- **Tools:** `bash`, `aws` CLI, `gcloud` CLI.
- **Sheet ID:** You must have the Google Sheet File ID, which can be extracted from its URL: `https://docs.google.com/spreadsheets/d/THIS_IS_THE_FILE_ID/edit`.

## 3. Procedure: Adding a New Sheet

This process is handled by the `scripts/add_sheet_watch.sh` script.

1.  **Grant Access:** Ensure the system's Google Service Account has Viewer permissions on the target Google Sheet.
2.  **Set Environment Variables:** Export the configuration needed for the script. The webhook URL is constant for the environment.
    ```bash
    export GOOGLE_SHEET_ID="the-new-sheet-id-to-watch"
    export INGEST_WEBHOOK_URL="the-inngest-webhook-url-for-this-env"
    ```
3.  **Run the Add Script:**
    ```bash
    ./scripts/add_sheet_watch.sh
    ```
4.  **Verify Success:**
    - The script will output the new channel details from Google.
    - More importantly, it will confirm that a new item has been written to the `SheetWatchRegistry` DynamoDB table.
    - You can double-check this in the AWS Console by viewing the table's items. You should see a new entry with the `sheet_id`, `channel_id`, and `expiration_timestamp`.

## 4. Procedure: Removing a Watched Sheet

This process involves stopping the Google notification channel and deleting the corresponding item from our DynamoDB table. This is handled by `scripts/remove_sheet_watch.sh`.

1.  **Set Environment Variable:**
    ```bash
    export GOOGLE_SHEET_ID="the-sheet-id-to-remove"
    ```
2.  **Run the Remove Script:**
    ```bash
    ./scripts/remove_sheet_watch.sh
    ```
3.  **Verify Success:**
    - The script will first query DynamoDB to find the `channel_id` and `resource_id` associated with the `GOOGLE_SHEET_ID`.
    - It will then call the Google API to stop the channel.
    - Finally, it will delete the item from the `SheetWatchRegistry` DynamoDB table.
    - Verify in the AWS Console that the item for the sheet has been removed from the table.

## 5. Troubleshooting

- **"Access Denied" on DynamoDB:** Your IAM user/role lacks the necessary `dynamodb:PutItem`, `dynamodb:Query`, or `dynamodb:DeleteItem` permissions for the `SheetWatchRegistry` table.
- **"Google API Error 404 (Not Found)":** This can happen during removal if the channel already expired or was manually stopped. If the item is successfully removed from DynamoDB, you can consider the operation successful. It can also happen during addition if the `GOOGLE_SHEET_ID` is incorrect or the service account does not have access.
- **"401 Unauthorized" from Google:** The `gcloud` authentication is invalid. Ensure Workload Identity Federation is correctly configured.
