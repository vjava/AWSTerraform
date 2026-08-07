import json
import os
import boto3

def validate_pipeline():
    endpoint_url = os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566")
    region = os.environ.get("AWS_REGION", "us-east-1")

    boto_kwargs = {
        "endpoint_url": endpoint_url,
        "region_name": region,
        "aws_access_key_id": "test",
        "aws_secret_access_key": "test"
    }

    kinesis = boto3.client("kinesis", **boto_kwargs)
    ddb = boto3.client("dynamodb", **boto_kwargs)

    stream_name = "BankingTransactionStream"
    table_name = "AnalyticsTransactions"

    # 1. Put record into Kinesis Stream
    sample_data = {
        "TransactionId": "TXN-99901",
        "CustomerId": "CUST-8888",
        "Amount": 1500.00,
        "Currency": "INR",
        "Status": "COMPLETED"
    }

    print(f"Sending record to Kinesis Stream: {stream_name}")
    kinesis.put_record(
        StreamName=stream_name,
        Data=json.dumps(sample_data),
        PartitionKey="CUST-8888"
    )

    # 2. Store corresponding audit record in DynamoDB
    print(f"Writing audit record to DynamoDB: {table_name}")
    ddb.put_item(
        TableName=table_name,
        Item={
            "TransactionId": {"S": "TXN-99901"},
            "CustomerId": {"S": "CUST-8888"},
            "Amount": {"N": "1500.00"},
            "State": {"S": "INGESTED"}
        }
    )
    print("Validation data successfully published and recorded.")

if __name__ == "__main__":
    validate_pipeline()
