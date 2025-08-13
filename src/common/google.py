# src/common/google.py

import logging
from typing import List, Dict, Any, Optional
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from google.auth import aws
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

# Initialize logger
logger = logging.getLogger(__name__)

# The scopes required for Google Drive (to watch for changes) and Sheets (to read)
DRIVE_READONLY_SCOPE = "https://www.googleapis.com/auth/drive.readonly"
SHEETS_READONLY_SCOPE = "https://www.googleapis.com/auth/spreadsheets.readonly"


def get_google_credentials(
    gcp_service_account_email: str, scopes: List[str]
) -> Optional[Credentials]:
    """
    Generates Google Cloud credentials using AWS Workload Identity Federation.

    Purpose:
        To securely authenticate with Google Cloud APIs from an AWS environment
        (like Lambda) without using a static service account key file. It exchanges
        the Lambda's IAM role credentials for Google Cloud credentials.

    Args:
        gcp_service_account_email (str): The email of the Google Cloud Service
                                            Account to impersonate.
        scopes (List[str]): The list of OAuth scopes required for the API calls.

    Returns:
        Optional[Credentials]: A Google credentials object if successful, else None.
    """
    try:
        logger.info(
            "Generating Google credentials via AWS Workload Identity Federation."
        )
        # This is the core of Workload Identity Federation.
        # It uses the default AWS credentials chain (e.g., the Lambda's IAM role)
        # to request credentials for the specified Google Service Account.
        creds = aws.Credentials(
            source_credentials=None,  # Uses the default Boto3 session
            service_account_impersonation_url=(
                f"https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/"
                f"{gcp_service_account_email}:generateAccessToken"
            ),
            scopes=scopes,
        )
        # The credentials need to be refreshed to be usable.
        creds.refresh(Request())
        logger.info("Successfully generated Google credentials.")
        return creds
    except Exception as e:
        logger.error(f"Failed to generate Google credentials: {e}")
        return None


def read_google_sheet(
    creds: Credentials, spreadsheet_id: str, sheet_range: str = "A:Z"
) -> Optional[List[Dict[str, Any]]]:
    """
    Reads data from a Google Sheet and returns it as a list of dictionaries.

    Purpose:
        To fetch the content of a specified sheet and transform it into a
        structured format (list of dicts) where the first row of the sheet
        is assumed to be the header.

    Args:
        creds (Credentials): The authenticated Google credentials object.
        spreadsheet_id (str): The ID of the Google Sheet to read.
        sheet_range (str): The range to read from the sheet, e.g., "Sheet1!A:Z".
                            If only "A:Z" is provided, it reads from the first visible sheet.

    Returns:
        Optional[List[Dict[str, Any]]]: A list of dictionaries representing the rows,
                                        or None if an error occurs.
    """
    try:
        logger.info(f"Connecting to Google Sheets API for spreadsheet: {spreadsheet_id}")
        service = build("sheets", "v4", credentials=creds)
        sheet = service.spreadsheets()
        result = (
            sheet.values()
            .get(spreadsheetId=spreadsheet_id, range=sheet_range)
            .execute()
        )
        values = result.get("values", [])

        if not values:
            logger.warning(f"Google Sheet '{spreadsheet_id}' appears to be empty.")
            return []

        # The first row is the header, which will become the keys for our dicts.
        header = [h.strip() for h in values[0]]
        # The rest of the rows are the data.
        data_rows = values[1:]

        # Create a list of dictionaries
        records = []
        for row in data_rows:
            # Create a dict for the row, padding with None if row is shorter than header
            row_data = dict(zip(header, row))
            # Only add non-empty rows
            if any(row_data.values()):
                records.append(row_data)

        logger.info(f"Successfully read {len(records)} records from the sheet.")
        return records

    except HttpError as e:
        logger.error(f"Google Sheets API error: {e}")
        return None
    except Exception as e:
        logger.error(f"An unexpected error occurred while reading the sheet: {e}")
        return None