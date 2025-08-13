# src/lambdas/read_sheet/handler.py

import json
from typing import Any, Dict

# Import our common modules
from src.common import config, google, schema
from src.common.logging import logger

# ==============================================================================
# Global Scope: Load configuration and schema once per container reuse
# ==============================================================================
# By loading these here, we leverage Lambda's container reuse for performance.
# The configuration and schema will be loaded only on the first invocation
# (a "cold start") and will be available immediately for subsequent "warm"
# invocations.

try:
    # Load environment-specific settings (dev.yaml, staging.yaml, etc.)
    app_config = config.load_config()

    # Load the JSON schema for validating rows
    schema_path = config.project_root / "schemas" / "product_row.schema.json"
    with open(schema_path, "r") as f:
        product_row_schema = json.load(f)

    # Inject service name and log level from config into the logger
    logger.set_service(app_config["logging"]["powertools_service_name"])
    logger.set_level(app_config["logging"]["level"])

except (ValueError, FileNotFoundError) as e:
    # If config fails to load, this is a fatal misconfiguration.
    # The Lambda cannot operate, so we log the error and prepare to fail invocations.
    logger.error(
        "FATAL: Could not load configuration or schema.", extra={"error": str(e)}
    )
    app_config = None
    product_row_schema = None


# ==============================================================================
# Lambda Handler
# ==============================================================================


@logger.inject_lambda_context(log_event=True)
def handler(event: Dict[str, Any], context: object) -> Dict[str, Any]:
    """
    AWS Lambda handler for reading and validating data from a Google Sheet.

    Purpose:
        This function is triggered by an Inngest event that contains information
        about a modified Google Sheet. It uses Workload Identity Federation to
        authenticate with Google, reads the sheet's content, validates each
        row against a JSON schema, and returns a list of valid rows.

    Args:
        event (Dict[str, Any]): The event payload from Inngest. It is expected
                                to contain `event['data']['file_id']`.
        context (object): The AWS Lambda context object (unused).

    Returns:
        Dict[str, Any]: A dictionary containing a 'statusCode' and a 'body'
                        with the list of valid data rows.
    """
    # Fail fast if the configuration was not loaded correctly
    if not app_config or not product_row_schema:
        logger.error("Handler cannot execute due to missing configuration.")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Internal server configuration error"}),
        }

    # 1. Extract spreadsheet ID from the incoming Inngest event
    try:
        spreadsheet_id = event["data"]["file_id"]
        logger.info(f"Processing request for spreadsheet ID: {spreadsheet_id}")
    except KeyError:
        logger.warning("Incoming event is missing 'data.file_id'.")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Missing file_id in event data"}),
        }

    # 2. Get Google Credentials using Workload Identity Federation
    # The email is fetched from our environment-specific config.
    gcp_sa_email = app_config["aws"]["secrets_manager"][
        "google_credentials_name"
    ]  # We'll store the email here for simplicity
    creds = google.get_google_credentials(
        gcp_service_account_email=gcp_sa_email,
        scopes=[google.DRIVE_READONLY_SCOPE, google.SHEETS_READONLY_SCOPE],
    )
    if not creds:
        logger.error("Failed to acquire Google credentials.")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Failed to authenticate with Google"}),
        }

    # 3. Read data from the Google Sheet
    # The range is hardcoded for now but could be made configurable.
    rows = google.read_google_sheet(creds, spreadsheet_id, sheet_range="A:Z")
    if rows is None:
        logger.error("Failed to read data from Google Sheet.")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Failed to read sheet data"}),
        }

    # 4. Validate each row and collect valid/invalid rows
    valid_rows = []
    invalid_rows = []
    for row in rows:
        # The 'is_active' column from a sheet is often a string "TRUE" or "FALSE"
        # We need to convert it to a boolean for schema validation.
        if "is_active" in row:
            row["is_active"] = str(row["is_active"]).upper() == "TRUE"

        if schema.validate_row_data(row, product_row_schema):
            valid_rows.append(row)
        else:
            invalid_rows.append(row)

    logger.info(
        f"Validation complete. Valid rows: {len(valid_rows)}, Invalid rows: {len(invalid_rows)}."
    )

    # 5. Return the list of valid rows for Inngest to process
    # The orchestrator will use this output to fan out the generation jobs.
    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "valid_rows": valid_rows,
                "invalid_rows_count": len(invalid_rows),
                "spreadsheet_id": spreadsheet_id,
            }
        ),
    }
