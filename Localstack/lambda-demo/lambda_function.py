import json

def lambda_handler(event, context):

    print("========================================")
    print("Hello from LocalStack Lambda")
    print("Incoming Event:")
    print(event)
    print("========================================")

    return {
        "statusCode":200,
        "body":{
            "message":"Hello from LocalStack",
            "name":event.get("name"),
            "city":event.get("city")
        }
    }
