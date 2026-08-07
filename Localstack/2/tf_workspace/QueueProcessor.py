import json
import os
import boto3

def lambda_handler(event, context):
    print("Processing SQS Queue Event:", json.dumps(event))
    endpoint_url = os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566")
    region = os.environ.get("AWS_REGION", "us-east-1")

    boto_kwargs = {
        "endpoint_url": endpoint_url,
        "region_name": region,
        "aws_access_key_id": "test",
        "aws_secret_access_key": "test"
    }

    ddb = boto3.client("dynamodb", **boto_kwargs)
    sns = boto3.client("sns", **boto_kwargs)

    for record in event.get("Records", []):
        body = json.loads(record["body"]) if isinstance(record["body"], str) else record["body"]
        customer_id = body.get("CustomerId", "CUST-8888")

        print(f"Updating status for customer {customer_id} to ACTIVE_VERIFIED...")
        ddb.update_item(
            TableName="Customers",
            Key={"CustomerId": {"S": customer_id}},
            UpdateExpression="SET #s = :status",
            ExpressionAttributeNames={"#s": "Status"},
            ExpressionAttributeValues={":status": {"S": "ACTIVE_VERIFIED"}}
        )

        try:
            topics = sns.list_topics()["Topics"]
            target_arn = [t["TopicArn"] for t in topics if "CustomerNotification" in t["TopicArn"]][0]

            sns.publish(
                TopicArn=target_arn,
                Subject="Account Activation Notice",
                Message=f"Customer {customer_id} verified and updated to ACTIVE_VERIFIED."
            )
        except Exception as e:
            print("SNS publish notice:", str(e))

    return {"status": "SUCCESS"}
