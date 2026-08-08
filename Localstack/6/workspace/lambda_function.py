import json
import csv
import os
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

LOCALSTACK_HOSTNAME = os.environ.get("LOCALSTACK_HOSTNAME", "localhost")
EDGE_PORT = os.environ.get("EDGE_PORT", "4566")
ENDPOINT_URL = f"http://{LOCALSTACK_HOSTNAME}:{EDGE_PORT}"

s3_client = boto3.client("s3", endpoint_url=ENDPOINT_URL)
dynamodb = boto3.resource("dynamodb", endpoint_url=ENDPOINT_URL)
sqs_client = boto3.client("sqs", endpoint_url=ENDPOINT_URL)

TABLE_NAME = os.environ.get("TABLE_NAME", "TransactionsTable")
DLQ_URL = os.environ.get("DLQ_URL", "")

def validate_record(record):
    if not record.get("transaction_id"):
        return False, "Missing transaction_id"
    if not record.get("user_id"):
        return False, "Missing user_id"
    try:
        amount = float(record.get("amount", 0))
        if amount <= 0:
            return False, "Non-positive amount"
    except (ValueError, TypeError):
        return False, "Invalid numeric format"
    return True, "Valid"

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")
    table = dynamodb.Table(TABLE_NAME)
    processed_count = 0
    invalid_count = 0

    detail = event.get("detail", {})
    bucket = detail.get("bucket", {}).get("name", "raw-transactions-bucket")
    key = detail.get("object", {}).get("key", "transactions.csv")
    
    response = s3_client.get_object(Bucket=bucket, Key=key)
    lines = response["Body"].read().decode("utf-8").splitlines()
    reader = csv.DictReader(lines)
    
    with table.batch_writer() as batch:
        for row in reader:
            is_valid, reason = validate_record(row)
            if is_valid:
                row["amount"] = str(row["amount"])
                batch.put_item(Item=row)
                processed_count += 1
            else:
                invalid_count += 1
                if DLQ_URL:
                    dlq_payload = {
                        "failed_record": row,
                        "rejection_reason": reason,
                        "source_file": key
                    }
                    sqs_client.send_message(
                        QueueUrl=DLQ_URL,
                        MessageBody=json.dumps(dlq_payload)
                    )

    return {
        "status": "COMPLETED",
        "processed_records": processed_count,
        "invalid_records": invalid_count,
        "source_file": key
    }
