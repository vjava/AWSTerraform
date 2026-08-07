import json

def lambda_handler(event, context):
    print("Executing Fraud Check:", json.dumps(event))
    customer_id = "CUST-8888"
    if isinstance(event, dict):
        if "detail" in event and isinstance(event["detail"], dict):
            customer_id = event["detail"].get("CustomerId", "CUST-8888")
        elif "CustomerId" in event:
            customer_id = event["CustomerId"]

    return {
        "CustomerId": customer_id,
        "FraudCheckResult": "PASSED",
        "RiskScore": 0.02
    }
