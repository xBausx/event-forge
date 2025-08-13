# src/common/aws.py

import logging
from typing import Dict, Optional

import boto3
from botocore.exceptions import ClientError

# Initialize logger
logger = logging.getLogger(__name__)

# Initialize boto3 clients globally to reuse connections
# The region will be sourced from the Lambda environment variable AWS_REGION
session = boto3.Session()
secrets_manager_client = session.client("secretsmanager")
s3_client = session.client("s3")


def get_secret(secret_name: str) -> Optional[str]:
    """
    Retrieves a secret string from AWS Secrets Manager.

    Purpose:
        To securely fetch credentials or configuration stored in Secrets Manager.
        This function assumes the execution role has the necessary IAM permissions.

    Args:
        secret_name (str): The name or ARN of the secret to retrieve.

    Returns:
        Optional[str]: The secret string if found, otherwise None.
    """
    try:
        get_secret_value_response = secrets_manager_client.get_secret_value(
            SecretId=secret_name
        )
        return get_secret_value_response["SecretString"]
    except ClientError as e:
        logger.error(f"Failed to retrieve secret '{secret_name}': {e}")
        # Depending on the error code, you might want to handle different exceptions
        # For example, ResourceNotFoundException
        return None


def create_presigned_url(
    bucket: str, object_name: str, expiration: int = 3600, method: str = "GET"
) -> Optional[str]:
    """
    Generates a pre-signed URL for an S3 object.

    Purpose:
        To provide secure, time-limited access to S3 objects without
        exposing credentials. Can be used for both GET (downloads) and
        PUT (uploads).

    Args:
        bucket (str): The name of the S3 bucket.
        object_name (str): The key of the object in the S3 bucket.
        expiration (int): The URL's expiration time in seconds. Defaults to 3600.
        method (str): The HTTP method ('GET' or 'PUT'). Defaults to 'GET'.

    Returns:
        Optional[str]: The pre-signed URL if generated successfully, otherwise None.
    """
    http_method_map = {
        "GET": "get_object",
        "PUT": "put_object",
    }
    client_method = http_method_map.get(method.upper())

    if not client_method:
        logger.error(f"Invalid HTTP method '{method}' for pre-signed URL.")
        return None

    try:
        params = {"Bucket": bucket, "Key": object_name}
        if method.upper() == "PUT":
            # You can add content-type restrictions for uploads if needed
            # params['ContentType'] = 'application/pdf'
            pass

        url = s3_client.generate_presigned_url(
            ClientMethod=client_method, Params=params, ExpiresIn=expiration
        )
        return url
    except ClientError as e:
        logger.error(
            f"Failed to generate pre-signed URL for {bucket}/{object_name}: {e}"
        )
        return None
