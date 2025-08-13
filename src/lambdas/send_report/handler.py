# src/lambdas/send_report/handler.py

import json
import os
from typing import Any, Dict

import requests

# Import our common modules
from src.common import aws, config
from src.common.logging import logger

# ==============================================================================
# Global Scope: Load configuration once per container reuse
# ==============================================================================
try:
    app_config = config.load_config()
    logger.set_service(app_config["logging"]["powertools_service_name"])
    logger.set_level(app_config["logging"]["level"])
except (ValueError, FileNotFoundError) as e:
    logger.error("FATAL: Could not load configuration.", extra={"error": str(e)})
    app_config = None

# ==============================================================================
# Lambda Handler
# ==============================================================================


@logger.inject_lambda_context(log_event=True)
def handler(event: Dict[str, Any], context: object) -> Dict[str, Any]:
    """
    AWS Lambda handler for sending a summary report of the generation process.

    Purpose:
        This function is the final step in the workflow. It is triggered by
        Inngest and receives the aggregated results of all poster generation
        jobs. It formats these results into a human-readable summary and sends
        it as a notification (e.g., to Slack).

    Args:
        event (Dict[str, Any]): The event payload from Inngest. Expected to
                                contain `event['data']['results']`.
        context (object): The AWS Lambda context object (unused).

    Returns:
        Dict[str, Any]: A standard Lambda proxy response.
    """
    if not app_config:
        logger.error("Handler cannot execute due to missing configuration.")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Internal server configuration error"}),
        }

    # 1. Extract results from the incoming Inngest event
    try:
        results = event["data"]["results"]
        spreadsheet_id = results.get("spreadsheet_id", "N/A")
        successful_jobs = results.get("successful_jobs", [])
        failed_jobs = results.get("failed_jobs", [])
        invalid_rows_count = results.get("invalid_rows_count", 0)
        logger.info("Generating report.", extra={"results": results})
    except KeyError:
        logger.warning("Incoming event is missing 'data.results'.")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Missing results in event data"}),
        }

    # 2. Fetch the Slack Webhook URL from Secrets Manager
    # We will need to create a secret named 'event-forge/slack-webhook-url-dev'
    slack_webhook_secret_name = (
        "event-forge/slack-webhook-url-" + app_config["environment"]
    )
    slack_url = aws.get_secret(slack_webhook_secret_name)

    if not slack_url:
        logger.error(
            "Failed to retrieve Slack webhook URL from Secrets Manager. Cannot send report."
        )
        # We return 200 OK because failing here could cause an infinite retry loop.
        # The core workflow succeeded; only the notification failed.
        return {
            "statusCode": 200,
            "body": json.dumps({"warning": "Report could not be sent."}),
        }

    # 3. Format the Slack message
    message_text = f"""
:art: *Event-Forge: Poster Generation Report* :art:

A workflow has completed for Google Sheet: `{spreadsheet_id}`

*Summary:*
- :white_check_mark: *Successful Posters:* {len(successful_jobs)}
- :x: *Failed Posters:* {len(failed_jobs)}
- :warning: *Skipped Invalid Rows:* {invalid_rows_count}

"""
    if failed_jobs:
        failed_skus = ", ".join([job.get("sku", "N/A") for job in failed_jobs])
        message_text += f"\n*Failed SKUs:* `{failed_skus}`"

    slack_payload = {"text": message_text}

    # 4. Send the report to Slack
    try:
        logger.info("Sending report to Slack.")
        response = requests.post(slack_url, json=slack_payload, timeout=10)
        response.raise_for_status()
        logger.info("Successfully sent report to Slack.")
    except requests.exceptions.RequestException as e:
        logger.error("Failed to send report to Slack.", extra={"error": str(e)})
        # Again, return 200 OK to avoid retries on notification failure.
        return {
            "statusCode": 200,
            "body": json.dumps({"warning": "Report could not be sent."}),
        }

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Report sent successfully."}),
    }
