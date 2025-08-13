# src/lambdas/generate_poster/handler.py

import json
import os
from typing import Any, Dict

# Import our common modules
from src.common import adobe, aws, config
from src.common.logging import logger

# ==============================================================================
# Global Scope: Load configuration once per container reuse
# ==============================================================================
try:
    # Load environment-specific settings (dev.yaml, staging.yaml, etc.)
    app_config = config.load_config()

    # Inject service name and log level from config into the logger
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
    AWS Lambda handler for generating a poster using the Adobe InDesign API.

    Purpose:
        This function is triggered by an Inngest event containing a single,
        validated row of data. It generates pre-signed URLs for the template
        and output, fetches the Adobe API key, and submits a rendition job.
        It returns the job URL for Inngest to poll.

    Args:
        event (Dict[str, Any]): The event payload from Inngest. It is expected
                                to contain `event['data']['row_data']`.
        context (object): The AWS Lambda context object (unused).

    Returns:
        Dict[str, Any]: A dictionary containing a 'statusCode' and a 'body'
                        with the Adobe job status URL.
    """
    if not app_config:
        logger.error("Handler cannot execute due to missing configuration.")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Internal server configuration error"}),
        }

    # 1. Extract row data and SKU from the incoming event
    try:
        row_data = event["data"]["row_data"]
        sku = row_data.get("sku")
        if not sku:
            raise ValueError("SKU is missing from row_data")
        logger.append_keys(
            sku=sku
        )  # Add SKU to all subsequent logs for this invocation
        logger.info(
            "Processing poster generation request.", extra={"row_data": row_data}
        )
    except (KeyError, ValueError) as e:
        logger.warning(
            "Incoming event is missing or has malformed data.", extra={"error": str(e)}
        )
        return {
            "statusCode": 400,
            "body": json.dumps({"error": f"Invalid event data: {e}"}),
        }

    # 2. Fetch Adobe API credentials from AWS Secrets Manager
    # We assume the secret contains a JSON string with 'client_id' and 'client_secret' keys
    adobe_secret_name = app_config["aws"]["secrets_manager"]["adobe_api_key_name"]
    adobe_creds_str = aws.get_secret(adobe_secret_name)
    if not adobe_creds_str:
        logger.error("Failed to retrieve Adobe API credentials from Secrets Manager.")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Could not fetch Adobe credentials"}),
        }

    try:
        adobe_creds = json.loads(adobe_creds_str)
        client_id = adobe_creds["client_id"]
        client_secret = adobe_creds["client_secret"]
    except (json.JSONDecodeError, KeyError):
        logger.error("Adobe secret is not a valid JSON or is missing keys.")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Malformed Adobe credentials secret"}),
        }

    # 3. Generate Pre-signed URLs for S3 assets
    # The template name could be dynamic based on event data in a future version
    template_name = "default_template.indt"
    output_name = f"{sku}_poster.pdf"

    assets_bucket = app_config["aws"]["s3"]["assets_bucket_name"]
    outputs_bucket = app_config["aws"]["s3"]["outputs_bucket_name"]

    template_url = aws.create_presigned_url(
        assets_bucket, f"templates/{template_name}", method="GET"
    )
    output_url = aws.create_presigned_url(
        outputs_bucket, f"generated/{output_name}", method="PUT"
    )

    if not template_url or not output_url:
        logger.error("Failed to create one or more S3 pre-signed URLs.")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Failed to generate S3 URLs"}),
        }

    # 4. Initialize Adobe API Client and Submit Job
    adobe_client = adobe.AdobeClient(client_id=client_id, client_secret=client_secret)
    job_status_url = adobe_client.submit_rendition_job(
        template_url=template_url, output_url=output_url, data=row_data
    )

    if not job_status_url:
        logger.error("Failed to submit job to Adobe API.")
        return {
            "statusCode": 502,
            "body": json.dumps(
                {"error": "Bad Gateway: Adobe API job submission failed"}
            ),
        }

    # 5. Return the job status URL to the Inngest orchestrator
    # Inngest will use this URL in a `step.sleep()` and polling loop.
    logger.info(
        "Successfully submitted job to Adobe. Returning status URL to orchestrator."
    )
    return {
        "statusCode": 202,  # 202 Accepted, as the job is not yet complete
        "body": json.dumps(
            {
                "message": "Job successfully submitted to Adobe API.",
                "job_status_url": job_status_url,
                "output_bucket": outputs_bucket,
                "output_key": f"generated/{output_name}",
            }
        ),
    }
