# Event-Driven Design Automation Pipeline

This project implements a secure, scalable, and resilient serverless system for automatically generating posters from data in a Google Sheet. It is triggered by changes in Google Drive, orchestrated by Inngest, and uses AWS Lambda with the Adobe InDesign API for design rendering.

## Table of Contents

- [Event-Driven Design Automation Pipeline](#event-driven-design-automation-pipeline)
  - [Table of Contents](#table-of-contents)
    - [Overview](#overview)
    - [Architecture](#architecture)
    - [Getting Started](#getting-started)
    - [Development](#development)
- [from your repo root](#from-your-repo-root)
- [verify](#verify)
- [run the same commands your CI uses](#run-the-same-commands-your-ci-uses)
- [install the git hook (so it runs on commit locally)](#install-the-git-hook-so-it-runs-on-commit-locally)
  - [Deployment](#deployment)
  - [Observability \& Monitoring](#observability--monitoring)
  - [Runbooks](#runbooks)

---

### Overview

The primary goal of this system is to automate the creation of design assets (e.g., marketing posters) by linking a Google Sheet data source directly to Adobe InDesign templates. When a user updates the designated Google Sheet, this pipeline automatically triggers, validates the data, and generates a new poster for each valid row.

- **Trigger**: Google Drive Push Notifications on Sheet modification.
- **Orchestration**: Inngest Cloud for managing the multi-step workflow.
- **Compute**: AWS Lambda (Python) for business logic.
- **Design Engine**: Adobe InDesign API for template rendering.

### Architecture

The detailed system architecture, including component diagrams, data flow, and security considerations, is documented in the [Architecture Document](./docs/architecture.md).

### Getting Started

To set up the project for local development, you will need AWS credentials, Terraform, Node.js, and Python configured.

1.  **Clone the repository:**

    ```bash
    git clone <repository-url>
    cd design-automation
    ```

2.  **Configure Environment:**
    Copy the `.env.example` file to `.env` and populate it with credentials and configuration details for your local environment. This file is git-ignored.

3.  **Bootstrap Local Dependencies:**
    Run the bootstrap script to install necessary tools and set up pre-commit hooks.
    ```bash
    ./scripts/local_dev_bootstrap.sh
    ```

### Development

This project uses a combination of Python for AWS Lambda functions and TypeScript for the Inngest orchestration layer.

- **Infrastructure**: Managed via Terraform in the `infra/` directory.
- **Lambda Functions**: Located in `src/lambdas/`. Each function is a separate package with its own `requirements.txt`.
- **Orchestration Logic**: Defined in `src/orchestration/`.
- **Shared Code**: Common utilities are located in `src/common/`.

See the [Makefile](./Makefile) for common development commands (e.g., `make lint`, `make test`).

# from your repo root

    ```bash
    py -3.12 -m venv .venv
    .\.venv\Scripts\Activate.ps1    # if you get a policy error, run: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
    python -m pip install -U pip
    pip install pre-commit
    ```

# verify

    ```bash
    pre-commit --version
    ```

# run the same commands your CI uses

    ```bash
    pre-commit clean
    pre-commit run --all-files
    ```

# install the git hook (so it runs on commit locally)

    ```bash
    pre-commit install
    ```

### Deployment

The system is deployed using a CI/CD pipeline defined in `.github/workflows/ci-cd.yml`. The pipeline automates the following for `dev`, `staging`, and `prod` environments:

1.  Linting and static analysis.
2.  Terraform plan and apply.
3.  Packaging and deploying AWS Lambda functions.
4.  Deploying Inngest functions.

Manual deployments can be performed by running the appropriate jobs in GitHub Actions.

### Observability & Monitoring

- **Logs**: All Lambda functions emit structured JSON logs using AWS Lambda Powertools. Logs are ingested into CloudWatch.
- **Traces**: Inngest provides end-to-end tracing for the entire workflow, visible in the Inngest Cloud dashboard.
- **Alarms**: Critical CloudWatch Alarms are defined in Terraform for high error rates, DLQ visibility, and function timeouts.

### Runbooks

Operational procedures for maintenance, incident response, and manual interventions are documented in the `docs/runbooks/` directory.

- [Webhook Renewal](./docs/runbooks/webhook-renewal.md): Steps to manually renew the Google Drive Push Notification channel.
- [DLQ Message Draining](./docs/runbooks/dlq-drain.md): Procedure for reprocessing failed events from the SQS Dead-Letter Queue.
- [Re-rendering by Job ID](./docs/runbooks/re-render-by-jobid.md): How to manually trigger a re-render for a specific job.
