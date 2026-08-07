import boto3
import random
import time
import uuid
from decimal import Decimal
import subprocess

# Terraform output से असली Orders Table Name फेच करें
try:
    orders_table_name = subprocess.check_output(["terraform", "output", "-raw", "orders_table_name"], text=True).strip()
except Exception:
    print("Terraform output lookup failed. Ensure you are in the Terraform directory.")
    exit(1)

region = 'us-east-1'
dynamodb = boto3.resource('dynamodb', region_name=region)
orders_table = dynamodb.Table(orders_table_name)

print(f"Checking data in Table: '{orders_table_name}'...")

# Scan Table to count actual stored records
response = orders_table.scan(Select='COUNT')
actual_count = response.get('Count', 0)

print(f"Current Actual Items Found via Scan: {actual_count}")

# If data is missing or incomplete, insert 1000 items
if actual_count < 1000:
    print("\nData missing or incomplete. Inserting 1,000 records using Batch Writer...")
    status_list = ['PENDING', 'COMPLETED', 'SHIPPED', 'CANCELLED']
    
    start_time = time.time()
    with orders_table.batch_writer() as batch:
        for i in range(1, 1001):
            amount_val = str(round(random.uniform(10.0, 1500.0), 2))
            order_item = {
                'order_id': f"ORD-{uuid.uuid4().hex[:10].upper()}",
                'user_id': f"USR-{random.randint(1001, 2000)}",
                'amount': Decimal(amount_val),
                'status': random.choice(status_list),
                'timestamp': int(time.time())
            }
            batch.put_item(Item=order_item)
            
    print(f"Batch write completed in {round(time.time() - start_time, 2)} seconds.")
    
    # Re-verify count
    re_verify = orders_table.scan(Select='COUNT')
    print(f"Updated Item Count in '{orders_table_name}': {re_verify.get('Count', 0)}")

# Fetch and print 3 sample items
print("\nSample Data Records from Orders Table:")
print("-" * 60)
scan_sample = orders_table.scan(Limit=3)
for item in scan_sample.get('Items', []):
    print(item)
print("-" * 60)