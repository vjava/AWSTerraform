import psycopg2
from psycopg2.extras import execute_values
import random
import time
import uuid

host = 'compliant-rds-pg-af5a80fb.c5aqwue841nx.us-east-1.rds.amazonaws.com'
user = 'postgres'
password = 'LabPassword123!'
database = 'transaction_db'

print(f"Connecting to PostgreSQL at {host}...")

connected = False
for i in range(15):
    try:
        conn = psycopg2.connect(
            host=host,
            user=user,
            password=password,
            dbname=database,
            port=5432,
            connect_timeout=10
        )
        connected = True
        print("Connected successfully!")
        break
    except Exception as e:
        print(f"Waiting for database instance to accept connections... ({i+1}/15)")
        time.sleep(10)

if not connected:
    print("Error: Could not connect to PostgreSQL Database Endpoint.")
    exit(1)

cursor = conn.cursor()

create_table_query = '''
CREATE TABLE IF NOT EXISTS transactions (
    transaction_id SERIAL PRIMARY KEY,
    reference_code VARCHAR(64) UNIQUE NOT NULL,
    account_number VARCHAR(20) NOT NULL,
    transaction_type VARCHAR(20) NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
'''
cursor.execute(create_table_query)
conn.commit()
print("Table 'transactions' created successfully.")

txn_types = ['CREDIT', 'DEBIT', 'TRANSFER', 'REFUND', 'PAYMENT']
statuses = ['COMPLETED', 'PENDING', 'FAILED', 'PROCESSING']

records = []
for i in range(1, 1001):
    ref_code = f"PGTXN-{uuid.uuid4().hex[:12].upper()}"
    acc_num = f"ACC{random.randint(10000000, 99999999)}"
    t_type = random.choice(txn_types)
    amount = round(random.uniform(5.00, 15000.00), 2)
    status = random.choice(statuses)
    records.append((ref_code, acc_num, t_type, amount, status))

insert_query = '''
INSERT INTO transactions (reference_code, account_number, transaction_type, amount, status)
VALUES %s;
'''
execute_values(cursor, insert_query, records)
conn.commit()

print("Successfully inserted 1000 records into 'transactions' table.")

cursor.execute("SELECT COUNT(*) FROM transactions;")
print(f"Verification: Total records in DB = {cursor.fetchone()[0]}")

cursor.close()
conn.close()