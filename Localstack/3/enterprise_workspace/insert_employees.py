import time
import boto3
from botocore.exceptions import ClientError

def populate_enterprise_employees():
    endpoint_url = "http://localhost:4566"
    region_name = "us-east-1"

    print("Connecting to LocalStack DynamoDB...")
    ddb = boto3.client(
        "dynamodb",
        endpoint_url=endpoint_url,
        region_name=region_name,
        aws_access_key_id="test",
        aws_secret_access_key="test"
    )

    table_name = "EnterpriseEmployees"
    total_records = 100000
    batch_size = 25
    requests = []

    print(f"Starting high-speed batch insertion of {total_records} employee records...")
    start_time = time.time()

    for i in range(1, total_records + 1):
        emp_id = f"EMP-{i:06d}"
        item = {
            "PutRequest": {
                "Item": {
                    "EmployeeId": {"S": emp_id},
                    "FirstName": {"S": f"FirstName{i}"},
                    "LastName": {"S": f"LastName{i}"},
                    "Department": {"S": "Engineering" if i % 2 == 0 else "Finance"},
                    "Email": {"S": f"employee{i}@enterprise.internal"},
                    "Salary": {"N": str(60000 + (i % 40000))}
                }
            }
        }
        requests.append(item)

        if len(requests) == batch_size or i == total_records:
            try:
                response = ddb.batch_write_item(RequestItems={table_name: requests})
                unprocessed = response.get("UnprocessedItems", {})
                while unprocessed:
                    response = ddb.batch_write_item(RequestItems=unprocessed)
                    unprocessed = response.get("UnprocessedItems", {})
            except ClientError as e:
                print(f"Batch write error: {e}")
            requests = []

        if i % 20000 == 0:
            print(f"Progress: {i}/{total_records} records injected...")

    end_time = time.time()
    print(f"Successfully inserted {total_records} records into '{table_name}' in {round(end_time - start_time, 2)} seconds!")

if __name__ == "__main__":
    populate_enterprise_employees()
