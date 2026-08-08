import csv
import random
import uuid
import sys
import boto3
from datetime import datetime, timezone

LOCALSTACK_ENDPOINT = "http://localhost:4566"
BUCKET_NAME = "raw-transactions-bucket"

def generate_mixed_transactions():
    records = []
    # 80 Valid Records
    for _ in range(80):
        records.append({
            "transaction_id": str(uuid.uuid4()),
            "user_id": f"USR_{random.randint(1000, 9999)}",
            "amount": round(random.uniform(10.0, 500.0), 2),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "status": "SUCCESS"
        })
    # 20 Corrupted/Invalid Records
    for i in range(20):
        records.append({
            "transaction_id": str(uuid.uuid4()) if i % 2 == 0 else "",
            "user_id": f"USR_{random.randint(1000, 9999)}" if i % 2 != 0 else "",
            "amount": -25.00 if i % 3 == 0 else "INVALID_AMOUNT",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "status": "CORRUPTED"
        })
    random.shuffle(records)
    return records

def save_to_csv(records, filename):
    fieldnames = ["transaction_id", "user_id", "amount", "timestamp", "status"]
    with open(filename, mode="w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(records)

def upload_to_s3(filename, bucket):
    s3_client = boto3.client(
        "s3",
        endpoint_url=LOCALSTACK_ENDPOINT,
        aws_access_key_id="test",
        aws_secret_access_key="test",
        region_name="us-east-1"
    )
    s3_client.upload_file(filename, bucket, filename)
    print(f"[CLIENT] Uploaded '{filename}' (100 records) to S3 bucket '{bucket}'.")

if __name__ == "__main__":
    file_name = sys.argv[1] if len(sys.argv) > 1 else "transactions.csv"
    print(f"[CLIENT] Generating 100 new mock records (80 valid + 20 invalid)...")
    txs = generate_mixed_transactions()
    save_to_csv(txs, file_name)
    upload_to_s3(file_name, BUCKET_NAME)
