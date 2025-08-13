# src/common/adobe.py

import logging
from typing import Any, Dict, Optional

import requests

# Initialize logger
logger = logging.getLogger(__name__)

# Constants for the Adobe APIs
IMS_URL = "https://ims-na1.adobelogin.com/ims/token/v3"
INDESIGN_API_BASE_URL = "https://indesign.adobe.io"
# The scope required for InDesign API access
API_SCOPE = "openid,AdobeID,indesign_services,creative_cloud,creative_sdk"


class AdobeClient:
    """
    A client for interacting with the Adobe InDesign API.

    Purpose:
        Encapsulates the logic for authentication, submitting design
        rendition jobs, and checking their status.
    """

    def __init__(self, client_id: str, client_secret: str):
        """
        Initializes the AdobeClient.

        Args:
            client_id (str): The Adobe API Client ID (API Key).
            client_secret (str): The Adobe API Client Secret.
        """
        self.client_id = client_id
        self.client_secret = client_secret
        self.access_token = None

    def _authenticate(self) -> bool:
        """
        Retrieves an OAuth 2.0 access token from Adobe's Identity Management System (IMS).

        Purpose:
            To get a short-lived access token required for all subsequent API calls.
            This token is stored on the client instance.

        Returns:
            bool: True if authentication was successful, False otherwise.
        """
        payload = {
            "grant_type": "client_credentials",
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "scope": API_SCOPE,
        }
        try:
            logger.info("Requesting new Adobe API access token.")
            response = requests.post(IMS_URL, data=payload)
            response.raise_for_status()
            token_data = response.json()
            self.access_token = token_data["access_token"]
            logger.info("Successfully retrieved Adobe API access token.")
            return True
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to authenticate with Adobe IMS: {e}")
            if e.response is not None:
                logger.error(f"Adobe IMS Response: {e.response.text}")
            return False

    def _get_headers(self) -> Dict[str, str]:
        """Constructs the required headers for API calls."""
        return {
            "Authorization": f"Bearer {self.access_token}",
            "x-api-key": self.client_id,
            "Content-Type": "application/json",
        }

    def submit_rendition_job(
        self, template_url: str, output_url: str, data: Dict[str, Any]
    ) -> Optional[str]:
        """
        Submits a data-driven rendition job to the Adobe InDesign API.

        Purpose:
            This is the primary method to start a poster generation job. It is
            asynchronous.

        Args:
            template_url (str): A pre-signed GET URL for the InDesign template (.indt).
            output_url (str): A pre-signed PUT URL for the resulting PDF.
            data (Dict[str, Any]): The data to be merged into the template.

        Returns:
            Optional[str]: The job status URL if submission was successful, otherwise None.
        """
        if not self.access_token and not self._authenticate():
            return None  # Failed to get a token

        # The Rendition API can accept data for merging just like the Data Merge API
        rendition_endpoint = f"{INDESIGN_API_BASE_URL}/v1/jobs/rendition"
        payload = {
            "input": {
                "storage": "EXTERNAL",
                "href": template_url,
                "type": "application/vnd.adobe.indesign-template",
            },
            "data": {"storage": "INLINE", "json": data},
            "output": {
                "storage": "EXTERNAL",
                "href": output_url,
                "type": "application/pdf",
            },
        }

        try:
            logger.info("Submitting rendition job to Adobe InDesign API.")
            logger.debug(f"Adobe API Payload: {payload}")
            response = requests.post(
                rendition_endpoint, headers=self._get_headers(), json=payload
            )
            response.raise_for_status()

            # The response body itself contains the link to check the job status
            response_data = response.json()
            job_status_url = response_data.get("_links", {}).get("self", {}).get("href")

            if not job_status_url:
                logger.error("Adobe API did not return a job status URL.")
                return None

            logger.info(f"Successfully submitted job. Status URL: {job_status_url}")
            return job_status_url

        except requests.exceptions.RequestException as e:
            logger.error(f"Error submitting job to Adobe API: {e}")
            if e.response is not None:
                logger.error(f"Adobe API Response: {e.response.text}")
            return None

    def check_job_status(self, job_url: str) -> Optional[Dict[str, Any]]:
        """
        Checks the status of a previously submitted rendition job.

        Args:
            job_url (str): The full URL of the job to check (returned by submit_rendition_job).

        Returns:
            Optional[Dict[str, Any]]: A dictionary containing the status information.
                                        Common statuses are 'running', 'succeeded', 'failed'.
                                        Returns None on communication error.
        """
        if not self.access_token and not self._authenticate():
            return None  # Failed to get a token

        try:
            logger.info(f"Checking status for job: {job_url}")
            response = requests.get(job_url, headers=self._get_headers())
            response.raise_for_status()

            status_data = response.json()
            logger.debug(f"Received status data: {status_data}")
            return status_data

        except requests.exceptions.RequestException as e:
            logger.error(f"Error checking job status for {job_url}: {e}")
            if e.response is not None:
                logger.error(f"Adobe API Response: {e.response.text}")
            return None
