# Runbook: Re-rendering a Poster by Job ID

**Purpose:** This document explains how to manually trigger a re-render for a single poster without needing to modify the source Google Sheet. This is useful for recovering from one-off transient errors or fulfilling a specific request to regenerate an asset.

**Frequency:** On-demand, as needed.

**Owner:** Cloud Engineering / Support Team

---

## 1. Background

The main workflow reads all rows from a Google Sheet and "fans out" an individual processing event for each row. The Inngest function that listens for these events is what handles the poster generation. The event it listens for is named `poster/generate.request`.

To re-render a single poster, we need to re-send this specific event with the exact data payload from the original attempt.

## 2. Prerequisites

- **Job Data Payload:** You must have the complete JSON data payload for the specific sheet row you want to re-render.
- **Permissions:** Access to the Inngest Cloud Dashboard with "replay" permissions is required for the preferred method.

## 3. Procedure

### Step 1: Locate the Original Job Data

The critical first step is to find the data payload for the job that needs to be re-run.

#### Option A: Using the Inngest Dashboard (Preferred)

1.  **Navigate to Inngest:** Log in to the Inngest Cloud dashboard.
2.  **Find the Parent Run:** Locate the main workflow run that corresponds to the sheet update in question. You can filter by the function name (`fan-out-and-generate`) or by the trigger time.
3.  **Inspect the "Fan-Out" Step:** Inside the run's trace, find the step where events were sent. It will show a list of all the `poster/generate.request` events that were generated.
4.  **Find the Failed Event:** Identify the specific event that failed or needs to be re-run. The event data (the row from the Google Sheet) will be visible.
5.  **Copy the Payload:** Copy the entire JSON data payload. You will need this if you have to use the manual method, but for a simple replay, you might not need to paste it.

#### Option B: Using CloudWatch Logs

If the run is old or hard to find in Inngest, you can find the data in the logs of the `read_sheet` Lambda.

1.  **Navigate to CloudWatch:** Go to the CloudWatch Log Groups in the AWS Console.
2.  **Find the Log Group:** Locate the log group for the `read_sheet` Lambda function (e.g., `/aws/lambda/event-forge-read-sheet-dev`).
3.  **Search Logs:** Search the logs for the timeframe of the original event. The logs for a successful run will contain the list of all valid rows that were about to be sent to Inngest.
4.  **Copy the Payload:** Find the JSON object corresponding to the row you need and copy it.

### Step 2: Trigger the Re-render

#### Method 1: Replay from the Inngest Dashboard (Easiest)

1.  In the Inngest dashboard, find the specific function run for the `generate_poster` function that failed.
2.  Most Inngest UIs provide a **"Replay"** or **"Re-run"** button on the failed run's page.
3.  Clicking this button will re-trigger the function with the exact same event that it originally received. This is the safest and most reliable method.

#### Method 2: Manually Triggering a New Event (Advanced)

If a direct replay is not possible, you can send a new event.

1.  Navigate to the "Events" page in the Inngest dashboard.
2.  Click "Send Event".
3.  **Event Name:** `poster/generate.request`
4.  **Payload:** Paste the JSON data payload you retrieved in Step 1.
5.  This will trigger the `generate_poster` function as if it were a new request.

### Step 3: Verify Success

1.  **Monitor Inngest:** Watch the Inngest dashboard for the new function run to appear. Monitor its progress.
2.  **Check Logs:** Check the new run's logs in CloudWatch for any errors.
3.  **Confirm Output:** Once the run completes successfully, verify that the newly rendered poster exists in the appropriate S3 output bucket (`event-forge-outputs-<env>`).
