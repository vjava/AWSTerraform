import time
import boto3
from botocore.exceptions import ClientError

def create_and_populate_employee_table():
    # LocalStack या AWS Endpoint कॉन्फ़िगरेशन
    endpoint_url = "http://localhost:4566"
    region_name = "us-east-1"

    print("Connecting to DynamoDB...")
    ddb = boto3.client(
        "dynamodb",
        endpoint_url=endpoint_url,
        region_name=region_name,
        aws_access_key_id="test",
        aws_secret_access_key="test"
    )

    table_name = "EnterpriseEmployees"

    # 1. नया एम्प्लॉय टेबल बनाएँ (यदि पहले से नहीं है)
    existing_tables = ddb.list_tables()["TableNames"]
    if table_name not in existing_tables:
        print(f"Creating table '{table_name}'...")
        ddb.create_table(
            TableName=table_name,
            KeySchema=[
                {"AttributeName": "EmployeeId", "KeyType": "HASH"}  # Partition Key
            ],
            AttributeDefinitions=[
                {"AttributeName": "EmployeeId", "AttributeType": "S"}
            ],
            BillingMode="PAY_PER_REQUEST"
        )
        print("Waiting for table to become active...")
        time.sleep(3)
    else:
        print(f"Table '{table_name}' already exists.")

    # 2. 100,000 रिकॉर्ड्स जनरेट करना और बैच में इन्सर्ट करना
    total_records = 100000
    batch_size = 25  # DynamoDB batch_write_item की अधिकतम सीमा 25 है
    requests = []

    print(f"Generating and inserting {total_records} employee records...")
    start_time = time.time()

    for i in range(1, total_records + 1):
        emp_id = f"EMP-{i:06d}"
        item = {
            "PutRequest": {
                "Item": {
                    "EmployeeId": {"S": emp_id},
                    "FirstName": {"S": f"First{i}"},
                    "LastName": {"S": f"Last{i}"},
                    "Department": {"S": "Engineering" if i % 2 == 0 else "Finance"},
                    "Email": {"S": f"employee{i}@company.internal"},
                    "Salary": {"N": str(50000 + (i % 50000))}
                }
            }
        }
        requests.append(item)

        # जब बैच 25 का हो जाए, तब DynamoDB में भेजें
        if len(requests) == batch_size or i == total_records:
            try:
                response = ddb.batch_write_item(
                    RequestItems={
                        table_name: requests
                    }
                )
                # Unprocessed items हैंडल करने के लिए (यदि कोई हो)
                unprocessed = response.get("UnprocessedItems", {})
                while unprocessed:
                    response = ddb.batch_write_item(RequestItems=unprocessed)
                    unprocessed = response.get("UnprocessedItems", {})
            except ClientError as e:
                print(f"Error during batch write: {e}")
            
            requests = []  # लिस्ट खाली करें अगले बैच के लिए

        if i % 10000 == 0:
            print(f"Progress: {i}/{total_records} records inserted...")

    end_time = time.time()
    print(f"Successfully inserted {total_records} employee records in {round(end_time - start_time, 2)} seconds!")

if __name__ == "__main__":
    create_and_populate_employee_table()