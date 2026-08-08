import json
import boto3

LOCALSTACK_ENDPOINT = "http://localhost:4566"
sqs = boto3.client("sqs", endpoint_url=LOCALSTACK_ENDPOINT, aws_access_key_id="test", aws_secret_access_key="test", region_name="us-east-1")

def check_queues():
    queue_url = sqs.get_queue_url(QueueName="TransactionAuditQueue")["QueueUrl"]
    dlq_url = sqs.get_queue_url(QueueName="TransactionDLQ")["QueueUrl"]
    
    print("\n[CONSUMER] Audit Queue Check...")
    resp = sqs.receive_message(QueueUrl=queue_url, MaxNumberOfMessages=5, WaitTimeSeconds=2)
    for msg in resp.get("Messages", []):
        body = json.loads(msg["Body"])
        payload = json.loads(body["Message"]) if "Message" in body else body
        print("========== SUCCESS AUDIT SUMMARY ==========")
        print(json.dumps(payload, indent=2))

    print("\n[CONSUMER] Dead Letter Queue (DLQ) Check...")
    attr = sqs.get_queue_attributes(QueueUrl=dlq_url, AttributeNames=["ApproximateNumberOfMessages"])
    print(f"DLQ contains {attr['Attributes'].get('ApproximateNumberOfMessages')} rejected items.")

if __name__ == "__main__":
    check_queues()
