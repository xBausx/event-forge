# Runbook: SQS Dead-Letter Queue (DLQ) Draining

**Purpose:** This document provides the procedure for analyzing and reprocessing failed events that have been sent to a Dead-Letter Queue (DLQ).

**Frequency:** On-demand, typically triggered by a CloudWatch Alarm indicating messages are present in a DLQ.

**Owner:** Cloud Engineering Team

---

## 1. Background

In our architecture, when Inngest fans out events (e.g., `poster/generate.request`), if an event fails processing repeatedly, Inngest will move it to a designated Amazon SQS DLQ. This prevents a single poison pill message from halting all other processing.

The presence of messages in a DLQ is an anomaly that requires investigation. Simply redriving them without understanding the cause will likely result in them failing again.

The primary DLQ in our system is associated with the fan-out processing queue for poster generation.

## 2. Prerequisites

- **AWS Permissions:** You need IAM permissions to access SQS (List, Get, Purge) and CloudWatch Logs (Read).
- **CloudWatch Alarm:** A CloudWatch alarm, `DLQ-Messages-Visible-Alarm`, should have notified you of this situation.

## 3. Investigation and Draining Procedure

### Step 1: Acknowledge the Alarm

Acknowledge the CloudWatch alarm to inform the team that the issue is being investigated.

### Step 2: Analyze the Failed Messages

1.  **Navigate to SQS:** In the AWS Management Console, go to the Amazon SQS service.
2.  **Find the DLQ:** Locate the relevant DLQ. Its name will be based on our Terraform configuration, typically `event-forge-generate-poster-dlq-<env>`.
3.  **View Messages:** Click on the queue and select "Send and receive messages". Click "Poll for messages".
4.  **Inspect a Message:**
    - Click on a message to view its `Body`. The body contains the full Inngest event payload (e.g., the specific row data from the Google Sheet).
    - Go to the `Attributes` tab. Look for attributes like `ApproximateReceiveCount`.
    - Crucially, check for custom error attributes that the Lambda function may have added.
5.  **Correlate with Logs:**
    - Use the `traceId` or `runId` from the message body to find the corresponding execution logs in CloudWatch Logs for the `generate_poster` Lambda function.
    - Analyze the logs to understand the root cause of the failure. Common causes include:
      - A bug in the Lambda handler.
      - Invalid data that passed initial validation but failed during processing.
      - Downstream API errors (e.g., from the Adobe API).
      - Permission errors or misconfigurations.

### Step 3: Resolve the Root Cause

**Do not proceed to redrive until you have a fix or a mitigation strategy.**

- If it's a code bug, deploy a hotfix.
- If it's a configuration issue, apply a fix via Terraform.
- If it's a transient downstream issue, confirm the downstream service is healthy again.
- If the message is permanently invalid ("poison pill"), you may decide to discard it.

### Step 4: Redrive Messages to the Source Queue

The SQS console provides a safe, built-in mechanism for this.

1.  In the SQS console, select the DLQ.
2.  Click the **"Start DLQ redrive"** button.
3.  This will present a dialog to move the messages from the DLQ back to its configured source queue (e.g., `event-forge-generate-poster-queue-<env>`).
4.  You can leave the settings as default. Click **"DLQ redrive"**.

### Step 5: Verify Success

1.  **Monitor Queue Depths:** Watch the DLQ message count decrease to zero and the source queue's message count increase, then decrease as the Lambda processes them.
2.  **Check Lambda Logs:** Monitor the CloudWatch Logs for the `generate_poster` function to ensure the redriven messages are now being processed successfully.
3.  **Resolve the Alarm:** Once the DLQ is empty and processing is normal, the CloudWatch alarm will return to the `OK` state.

## 4. Discarding "Poison Pill" Messages

If you determine that messages are malformed and can never be processed, you should purge them from the DLQ to prevent the alarm from firing continuously.

1.  Navigate to the DLQ in the SQS console.
2.  Click the **"Purge"** button.
3.  **Warning:** This action is irreversible and will permanently delete all messages in the queue. Confirm the purge.
