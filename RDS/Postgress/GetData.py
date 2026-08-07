import psycopg2
from psycopg2.extras import execute_values
import subprocess

# Terraform outputs से असली Endpoint और DB Name ऑटोमैटिक फेच करें
try:
    DB_HOST = subprocess.check_output(["terraform", "output", "-raw", "aurora_endpoint"], text=True).strip()
    DB_NAME = subprocess.check_output(["terraform", "output", "-raw", "db_name"], text=True).strip()
except Exception:
    # यदि ऑटो-फेच न चले तो मैन्युअल endpoint का प्रयोग करें
    DB_HOST = "compliant-rds-pg-af5a80fb.c5aqwue841nx.us-east-1.rds.amazonaws.com"
    DB_NAME = "transaction_db"

DB_USER = "postgres"
DB_PASS = "LabPassword123!"
DB_PORT = 5432

print(f"Connecting to Database at {DB_HOST}...")

try:
    conn = psycopg2.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
        port=DB_PORT,
        connect_timeout=10
    )
    cursor = conn.cursor()
    print("Connected successfully!\n")

    # DB से इंसर्ट किए गए डेटा की जाँच (Fetch Sample Data)
    cursor.execute("SELECT COUNT(*) FROM transactions;")
    print(f"Total Transactions Record Count: {cursor.fetchone()[0]}")

    cursor.execute("SELECT transaction_type, COUNT(*), SUM(amount) FROM transactions GROUP BY transaction_type;")
    print("\nSummary by Transaction Type:")
    print("-" * 55)
    for row in cursor.fetchall():
        print(f"Type: {row[0]:<10} | Count: {row[1]:<5} | Total Amount: ${row[2]:,.2f}")
    print("-" * 55)

    cursor.close()
    conn.close()

except Exception as e:
    print(f"Error connecting to DB: {e}")