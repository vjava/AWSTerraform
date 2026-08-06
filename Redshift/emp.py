import random
import subprocess
import psycopg2
import psycopg2.extras


# Terraform से ऑटोमैटिक पासवर्ड निकालने का फंक्शन
def get_tf_password():
  try:
    result = subprocess.run(
        ["terraform", "output", "-raw", "admin_password"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()
  except Exception:
    return "AdminPassword123!"


# Redshift Serverless Connection Details
DB_HOST = "compliant-redshift-workgroup.767397762089.us-east-1.redshift-serverless.amazonaws.com"
DB_NAME = "dev"
DB_USER = "adminuser"
DB_PASSWORD = get_tf_password()
DB_PORT = "5439"

try:
  print("Connecting to Redshift Serverless with SSL...")
  conn = psycopg2.connect(
      dbname=DB_NAME,
      user=DB_USER,
      password=DB_PASSWORD,
      host=DB_HOST,
      port=DB_PORT,
      sslmode="require",
  )
  conn.autocommit = True
  cursor = conn.cursor()
  print("Connected successfully!")

  # 1. Create Table
  print("Creating 'employees' table...")
  cursor.execute("""
        CREATE TABLE IF NOT EXISTS employees (
            emp_id INT,
            first_name VARCHAR(50),
            last_name VARCHAR(50),
            department VARCHAR(50),
            salary DECIMAL(10, 2),
            hire_date DATE
        );
    """)
  print("Table ready.")

  # 2. Generate 10000 Records and Insert in Optimal Batches of 400
  print("Generating 10000 records...")
  departments = ["Engineering", "HR", "Sales", "Marketing", "Finance"]
  first_names = [
      "Aarav",
      "Vivaan",
      "Aditya",
      "Vihaan",
      "Arjun",
      "Sai",
      "Reyansh",
      "Ayaan",
      "Krishna",
      "Ishaan",
      "Diya",
      "Saanvi",
      "Ananya",
      "Aadhya",
      "Pari",
      "Kavya",
      "Riya",
      "Navya",
      "Anvi",
      "Prisha",
  ]
  last_names = [
      "Sharma",
      "Verma",
      "Gupta",
      "Malhotra",
      "Mehta",
      "Jain",
      "Singh",
      "Kumar",
      "Patel",
      "Reddy",
  ]

  all_records = []
  for i in range(1, 10001):
    emp_id = i
    f_name = random.choice(first_names)
    l_name = random.choice(last_names)
    dept = random.choice(departments)
    salary = round(random.uniform(40000, 120000), 2)
    hire_date = (
        f"202{random.randint(0,5)}-{random.randint(1,12):02d}-{random.randint(1,28):02d}"
    )
    all_records.append((emp_id, f_name, l_name, dept, salary, hire_date))

  print("Starting fast batch inserts (Ideal Batch Size = 400)...")
  batch_size = 400  # <--- सबसे तेज और प्रमाणित बैच साइज
  insert_query = """
        INSERT INTO employees (emp_id, first_name, last_name, department, salary, hire_date)
        VALUES %s
    """

  total_batches = (len(all_records) + batch_size - 1) // batch_size

  for i in range(0, len(all_records), batch_size):
    batch = all_records[i : i + batch_size]
    batch_num = (i // batch_size) + 1

    # डेटाबेस में बल्क इंसर्ट करना
    psycopg2.extras.execute_values(cursor, insert_query, batch)

    # हर बैच के बाद का स्पष्ट लॉग
    print(
        f"[LOG] Batch {batch_num}/{total_batches} successfully written to Redshift"
        f" (Records {i + 1} to {min(i + batch_size, len(all_records))})"
    )

  print("All 10000 records inserted successfully with optimal speed!")

  # 3. Verify data count
  cursor.execute("SELECT COUNT(*) FROM employees;")
  count = cursor.fetchone()[0]
  print(f"Total rows in employees table: {count}")

  cursor.close()
  conn.close()

except Exception as e:
  print(f"An error occurred: {e}")