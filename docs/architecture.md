# Architecture Document (v3.1)

This document outlines the architecture for the **Event-Forge** system, an event-driven pipeline for generating design assets.

## 1. Core Principles

The system is designed according to the following principles:

-   **Event-Driven**: The entire process is initiated by an external event (a file change in Google Drive) and composed of loosely coupled, event-driven components.
-   **Serverless-First**: We use managed services (AWS Lambda, Inngest Cloud, S3, Secrets Manager) to minimize operational overhead, reduce cost, and enable automatic scaling.
-   **Infrastructure as Code (IaC)**: All cloud resources are provisioned and managed using Terraform, ensuring consistency, repeatability, and version control of our infrastructure.
-   **Least Privilege Security**: All components operate with the minimum permissions required. We use Workload Identity Federation instead of static service account keys and encrypt all data at rest.
-   **Resilience & Observability**: The system is designed for failure with built-in retries, dead-letter queues, structured logging, and end-to-end tracing to ensure we can debug and recover from issues quickly.

## 2. System Components & Data Flow

The pipeline consists of the following key components and stages:

![Architecture Diagram](https://i.imgur.com/your-diagram-image.png) <!-- Placeholder for a real diagram -->

**Data Flow:**

1.  **Trigger**: A user updates a specific Google Sheet. Google Drive sends a Push Notification to a registered webhook endpoint. This endpoint is an Inngest API endpoint, which creates a new event.
    -   *Payload*: Contains `resourceId` (the file) and `revisionId` (the version).
    -   *Idempotency*: The `revisionId` is used as an idempotency key in Inngest to prevent duplicate processing of the same sheet update.

2.  **Orchestration (Inngest)**: The Inngest event triggers a multi-step workflow function (`fan-out-and-generate`).
    -   **Step 1: Get Sheet Data (`read_sheet` Lambda)**: Inngest invokes the `read_sheet` Lambda. This function uses Google Workload Identity Federation to authenticate, fetches the Google Sheet content, and validates each row against a JSON schema (`schemas/product_row.schema.json`). It returns a list of valid product data objects.
    -   **Step 2: Fan-Out**: The orchestrator iterates through the list of valid rows. For each row, it sends a new event (`poster/generate.request`). This decouples row processing.
    -   **Step 3: Generate Poster (`generate_poster` Lambda)**: A separate Inngest function, triggered by the `poster/generate.request` event, invokes the `generate_poster` Lambda.
        -   The Lambda generates pre-signed URLs for downloading the InDesign template from S3 and for uploading the final output PDF.
        -   It submits a job to the Adobe InDesign API, providing the template location, output location, and the row data.
        -   It does *not* wait for the job to complete.
    -   **Step 4: Poll for Status (Inngest `step.sleep`)**: The Inngest function waits for a configured duration (e.g., `15s`) and then polls the Adobe API for the job status. It continues to sleep and poll until the job succeeds or fails.
    -   **Step 5: Aggregate and Report (`send_report` Lambda)**: Once all fan-out steps are complete, the main workflow invokes the `send_report` Lambda, which generates a summary report (e.g., via email or Slack) of successful and failed poster generations.

3.  **Storage (AWS S3)**:
    -   `event-forge-assets-<env>`: Stores InDesign templates (`.indt`), fonts (`.otf`, `.ttf`), and custom scripts (`.jsx`). Access is read-only for the Lambda functions.
    -   `event-forge-outputs-<env>`: Stores the generated posters (`.pdf`, `.jpg`). Lambda functions get short-lived, pre-signed URLs to write into this bucket.

## 3. Security & Authentication

-   **Google Cloud**: We use **Workload Identity Federation** to exchange a GitHub Actions OIDC token (for deployment) or an AWS IAM role (for runtime) for a short-lived Google Cloud access token. This completely avoids the use and management of static Service Account JSON keys.
-   **AWS**:
    -   All IAM roles follow the principle of least privilege.
    -   Secrets (API keys for Adobe, etc.) are stored in AWS Secrets Manager and retrieved at runtime.
    -   All S3 buckets are encrypted at rest using AWS KMS.
    -   Lambda Function URLs are protected by IAM authentication, only allowing invocation from Inngest's AWS account.
-   **Adobe API**: The API key is stored in Secrets Manager. Concurrency limits are enforced by the application logic to prevent hitting API rate limits.

## 4. Reliability & Error Handling

-   **Idempotency**: Handled by Inngest using `revisionId` from the Google Drive webhook.
-   **Retries**: Inngest automatically retries failed steps with exponential backoff.
-   **Dead-Letter Queue (DLQ)**: If a fan-out event (`poster/generate.request`) fails repeatedly, Inngest will send it to a designated SQS DLQ for manual inspection. A runbook (`dlq-drain.md`) documents the reprocessing procedure.
-   **Concurrency Control**: Inngest's concurrency settings are used to limit the number of parallel `generate_poster` functions running to avoid overwhelming the Adobe API.