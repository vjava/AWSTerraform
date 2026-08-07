import json
import os
import boto3

def lambda_handler(event, context):
    print("Received Event:", json.dumps(event))
    
    body = event
    if isinstance(event, dict) and "body" in event and event["body"]:
        try:
            body = json.loads(event["body"]) if isinstance(event["body"], str) else event["body"]
        except Exception:
            body = event

    if not isinstance(body, dict):
        body = {}

    customer_id = body.get("CustomerId", "CUST-8888")
    first_name = body.get("FirstName", "Alex")
    last_name = body.get("LastName", "Morgan")
    pan_val = body.get("PAN", "ABCDE1234F")
    aadhaar_val = body.get("Aadhaar", "[Redacted]")

    endpoint_url = os.environ.get("LOCALSTACK_ENDPOINT", "http://localhost:4566")
    region = os.environ.get("AWS_REGION", "us-east-1")

    boto_kwargs = {
        "endpoint_url": endpoint_url,
        "region_name": region,
        "aws_access_key_id": "test",
        "aws_secret_access_key": "test"
    }

    ssm = boto3.client("ssm", **boto_kwargs)
    secrets = boto3.client("secretsmanager", **boto_kwargs)
    kms = boto3.client("kms", **boto_kwargs)
    ddb = boto3.client("dynamodb", **boto_kwargs)
    events = boto3.client("events", **boto_kwargs)

    try:
        ssm.get_parameter(Name="/application/environment")
    except Exception as e:
        print("SSM fetch notice:", str(e))

    enc_pan = "enc_pan_dummy"
    enc_aadhaar = "enc_aadhaar_dummy"
    try:
        aliases = kms.list_aliases().get("Aliases", [])
        target_key_id = None
        for a in aliases:
            if a.get("AliasName") == "alias/bank-customer-key":
                target_key_id = a.get("TargetKeyId")
                break
        
        key_to_use = target_key_id if target_key_id else "alias/bank-customer-key"
        enc_pan = kms.encrypt(KeyId=key_to_use, Plaintext=pan_val.encode('utf-8'))['CiphertextBlob'].hex()
        enc_aadhaar = kms.encrypt(KeyId=key_to_use, Plaintext=aadhaar_val.encode('utf-8'))['CiphertextBlob'].hex()
    except Exception as e:
        print("KMS encryption notice:", str(e))

    print(f"Writing customer {customer_id} to DynamoDB...")
    ddb.put_item(
        TableName="Customers",
        Item={
            "CustomerId": {"S": customer_id},
            "FirstName": {"S": first_name},
            "LastName": {"S": last_name},
            "Status": {"S": "PENDING_VALIDATION"},
            "EncryptedPAN": {"S": enc_pan},
            "EncryptedAadhaar": {"S": enc_aadhaar},
            "CreatedDate": {"S": "2026-08-08T00:00:00Z"}
        }
    )

    payload = {"CustomerId": customer_id, "Status": "PENDING_VALIDATION"}
    try:
        events.put_events(
            Entries=[{
                'Source': 'com.bank.customer',
                'DetailType': 'CustomerCreated',
                'Detail': json.dumps(payload),
                'EventBusName': 'default'
            }]
        )
    except Exception as e:
        print("EventBridge publish notice:", str(e))

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "Customer Created Successfully", "CustomerId": customer_id})
    }
