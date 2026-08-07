import mysql.connector
import random
import time

host = 'compliant-mysql-db-b15e9052.c5aqwue841nx.us-east-1.rds.amazonaws.com'
user = 'admin'
password = 'LabPassword123!'
database = 'company_db'

print(f"Connecting to MySQL RDS instance at {host}...")

# Retry loop for DB availability
connected = False
for i in range(12):
    try:
        conn = mysql.connector.connect(
            host=host,
            user=user,
            password=password,
            database=database,
            port=3306,
            connect_timeout=10
        )
        connected = True
        break
    except Exception as e:
        print(f"Waiting for database connection... ({i+1}/12)")
        time.sleep(10)

if not connected:
    print("Error: Could not connect to RDS Instance.")
    exit(1)

cursor = conn.cursor()

# 1. Create Employee Table
create_table_query = '''
CREATE TABLE IF NOT EXISTS employee (
    emp_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    department VARCHAR(50),
    salary DECIMAL(10, 2),
    hire_date DATE
)
'''
cursor.execute(create_table_query)
print("Table 'employee' created successfully.")

# 2. Generate 100 Records
first_names = ['Amit', 'Priya', 'Rahul', 'Sneha', 'Vikas', 'Ananya', 'Rohan', 'Kavya', 'Suresh', 'Pooja']
last_names = ['Sharma', 'Verma', 'Patel', 'Singh', 'Kumar', 'Das', 'Reddy', 'Joshi', 'Nair', 'Gupta']
departments = ['Engineering', 'HR', 'Marketing', 'Sales', 'Finance', 'Operations']

records = []
for i in range(1, 101):
    fn = random.choice(first_names)
    ln = random.choice(last_names)
    dept = random.choice(departments)
    salary = round(random.uniform(40000, 120000), 2)
    hire_date = f"{random.randint(2018, 2025)}-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}"
    records.append((fn, ln, dept, salary, hire_date))

# 3. Batch Insert Records
insert_query = '''
INSERT INTO employee (first_name, last_name, department, salary, hire_date)
VALUES (%s, %s, %s, %s, %s)
'''
cursor.executemany(insert_query, records)
conn.commit()

print(f"Successfully inserted {cursor.rowcount} records into 'employee' table.")

# 4. Verify Total Records
cursor.execute("SELECT COUNT(*) FROM employee;")
total_count = cursor.fetchone()[0]
print(f"Verification: Total records in 'employee' table = {total_count}")

# 5. Display sample records
cursor.execute("SELECT * FROM employee LIMIT 5;")
print("\nSample Output (First 5 records):")
print("-" * 60)
for row in cursor.fetchall():
    print(row)
print("-" * 60)

cursor.close()
conn.close()