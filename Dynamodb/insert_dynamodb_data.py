import boto3
import random
import time
import uuid
from decimal import Decimal

users_table_name = 'UsersTable-9c6e0a98'
orders_table_name = 'OrdersTable-9c6e0a98'
region = 'us-east-1'

dynamodb = boto3.resource('dynamodb', region_name=region)
users_table = dynamodb.Table(users_table_name)
orders_table = dynamodb.Table(orders_table_name)

print("Starting Batch Ingestion into DynamoDB Tables...\n")

# 1. Insert 1000 records into Users Table
print(f"Inserting 1,000 records into '{users_table_name}'...")
start_time = time.time()

user_cities = ['Bengaluru', 'Mumbai', 'Delhi', 'Hyderabad', 'Chennai']
try:
    with users_table.batch_writer() as batch:
        for i in range(1, 1001):
            user_item = {
                'user_id': f"USR-{1000 + i}",
                'name': f"User_{i}",
                'email': f"user_{i}@example.com",
                'city': random.choice(user_cities),
                'age': random.randint(18, 65),
                'created_at': int(time.time())
            }
            batch.put_item(Item=user_item)
    print(f"Successfully inserted 1,000 records into '{users_table_name}' in {round(time.time() - start_time, 2)} seconds.")
except Exception as e:
    print(f"Error inserting into Users Table: {e}")

# 2. Insert 1000 records into Orders Table (Safely handled with Decimal)
print(f"\nInserting 1,000 records into '{orders_table_name}'...")
start_time = time.time()

status_list = ['PENDING', 'COMPLETED', 'SHIPPED', 'CANCELLED']

try:
    with orders_table.batch_writer() as batch:
        for i in range(1, 1001):
            random_amount = f"{random.uniform(10.0, 1500.0):.2f}"
            order_item = {
                'order_id': f"ORD-{uuid.uuid4().hex[:10].upper()}",
                'user_id': f"USR-{random.randint(1001, 2000)}",
                'amount': Decimal(random_amount),
                'status': random.choice(status_list),
                'timestamp': int(time.time())
            }
            batch.put_item(Item=order_item)
    print(f"Successfully inserted 1,000 records into '{orders_table_name}' in {round(time.time() - start_time, 2)} seconds.")
except Exception as e:
    print(f"Error in batch_writer for Orders Table: {e}")
    print("Falling back to put_item loop...")
    for i in range(1, 1001):
        random_amount = f"{random.uniform(10.0, 1500.0):.2f}"
        order_item = {
            'order_id': f"ORD-{uuid.uuid4().hex[:10].upper()}",
            'user_id': f"USR-{random.randint(1001, 2000)}",
            'amount': Decimal(random_amount),
            'status': random.choice(status_list),
            'timestamp': int(time.time())
        }
        orders_table.put_item(Item=order_item)

# 3. Verify Item Counts by Scanning Tables Directly
print("\n" + "="*60)
print("VERIFYING ACTUAL ITEM COUNTS VIA TABLE SCAN")
print("="*60)

users_scan = users_table.scan(Select='COUNT')
orders_scan = orders_table.scan(Select='COUNT')

print(f"Actual Records in '{users_table_name}': {users_scan.get('Count', 0)}")
print(f"Actual Records in '{orders_table_name}': {orders_scan.get('Count', 0)}")

# Fetch and display a sample item from Orders Table
sample = orders_table.scan(Limit=1)
if sample.get('Items'):
    print("\nSample Item from Orders Table:")
    print(sample['Items'][0])

print("="*60)