import json
import logging
import os
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")

ALLOWED_EXTENSIONS = {
    ext.strip().lower()
    for ext in os.environ["ALLOWED_EXTENSIONS"].split(",")
}

REQUIRED_METADATA = {
    key.strip().lower()
    for key in os.environ["REQUIRED_METADATA"].split(",")
}


def lambda_handler(event, context):
    for record in event["Records"]:

        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]
        
        # retrieve the object metadata from S3 using head_object using try and catch
        try:
          response = s3.head_object(Bucket=bucket, Key=key)
        except Exception:
          logger.exception("Failed to inspect uploaded object")
          raise

        metadata = {
            k.lower(): v
            for k, v in response.get("Metadata", {}).items()
        }

        violations = []
        # check only the last part of the key after the last dot for the file extension, and convert it to lowercase
        extension = key.rsplit(".", 1)[-1].lower()

        if extension not in ALLOWED_EXTENSIONS:
            violations.append(
                f"Unsupported file extension '{extension}'"
            )

        for field in REQUIRED_METADATA:
            if field not in metadata:
                violations.append(
                    f"Missing metadata '{field}'"
                )

        if violations:
            logger.warning(
                json.dumps(
                    {
                        "bucket": bucket,
                        "object": key,
                        "status": "NON_COMPLIANT",
                        "violations": violations,
                    }
                )
            )
        else:
            logger.info(
                json.dumps(
                    {
                        "bucket": bucket,
                        "object": key,
                        "status": "COMPLIANT",
                    }
                )
            )

    return {"statusCode": 200}