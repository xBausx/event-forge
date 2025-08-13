# scripts/create_presigned_url.py

import argparse
import logging
import boto3
from botocore.exceptions import ClientError

# Configure basic logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def create_url(bucket: str, object_name: str, expiration: int, method: str) -> str:
    """
    Generates a pre-signed URL for an S3 object using the user's local AWS credentials.

    Args:
        bucket (str): The name of the S3 bucket.
        object_name (str): The key of the object in the S3 bucket.
        expiration (int): The URL's expiration time in seconds.
        method (str): The HTTP method ('GET' or 'PUT').

    Returns:
        str: The pre-signed URL, or an error message if generation fails.
    """
    s3_client = boto3.client('s3')
    http_method_map = {
        "GET": "get_object",
        "PUT": "put_object",
    }
    client_method = http_method_map.get(method.upper())

    if not client_method:
        return "Error: Invalid HTTP method specified. Use 'GET' or 'PUT'."

    try:
        url = s3_client.generate_presigned_url(
            ClientMethod=client_method,
            Params={'Bucket': bucket, 'Key': object_name},
            ExpiresIn=expiration
        )
        return url
    except ClientError as e:
        logger.error(f"Failed to generate pre-signed URL: {e}")
        return f"Error: Could not generate URL. Check your AWS credentials and permissions. Details: {e}"

def main():
    """Main function to parse arguments and generate the URL."""
    parser = argparse.ArgumentParser(description="Generate a pre-signed S3 URL.")
    parser.add_argument("--bucket", required=True, help="The name of the S3 bucket.")
    parser.add_argument("--key", required=True, help="The object key (path/to/file.ext) in the bucket.")
    parser.add_argument("--method", default="PUT", choices=["GET", "PUT"], help="The HTTP method (GET or PUT). Default is PUT.")
    parser.add_argument("--expires", type=int, default=3600, help="Expiration time in seconds. Default is 3600 (1 hour).")

    args = parser.parse_args()

    logger.info(f"Generating a {args.method} URL for s3://{args.bucket}/{args.key}...")
    url = create_url(args.bucket, args.key, args.expires, args.method)
    print("\n" + "="*80)
    if "Error:" in url:
        print(f" FAILED\n {url}")
    else:
        print(f" SUCCESS!\n\nPre-signed URL (expires in {args.expires} seconds):\n{url}")
        if args.method == "PUT":
            print(f"\nExample usage with curl:\ncurl --upload-file \"/path/to/your/local/file.pdf\" \"{url}\"")
    print("="*80)

if __name__ == "__main__":
    main()
