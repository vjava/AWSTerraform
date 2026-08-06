import subprocess
import psycopg2


# Terraform से ऑटोमैटिक पासवर्ड प्राप्त करने का फंक्शन
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
  print("Connecting to Redshift Serverless to fetch data...")
  conn = psycopg2.connect(
      dbname=DB_NAME,
      user=DB_USER,
      password=DB_PASSWORD,
      host=DB_HOST,
      port=DB_PORT,
      sslmode="require",
  )
  cursor = conn.cursor()
  print("Connected successfully!\n")

  # कर्मचारियों का डेटा फेच करना (पहले 10 रिकॉर्ड्स)
  print("Fetching top 10 employee records from Redshift:")
  print("DB_PASSWORD:", DB_PASSWORD)
  print("-" * 80)
  print(
      f"{'ID':<5} | {'First Name':<12} | {'Last Name':<12} | {'Department':<12}"
      f" | {'Salary':<10} | {'Hire Date'}"
  )
  print("-" * 80)

  cursor.execute(
      "SELECT emp_id, first_name, last_name, department, salary, hire_date FROM"
      " employees ORDER BY emp_id LIMIT 10;"
  )
  rows = cursor.fetchall()

  for row in rows:
    emp_id, f_name, l_name, dept, salary, hire_date = row
    print(
        f"{emp_id:<5} | {f_name:<12} | {l_name:<12} | {dept:<12} |"
        f" ${salary:<9.2f} | {hire_date}"
    )

  print("-" * 80)

  # कुल रिकॉर्ड्स की संख्या देखना
  cursor.execute("SELECT COUNT(*) FROM employees;")
  total_count = cursor.fetchone()[0]
  print(f"\nTotal Employees in Database: {total_count}")

  cursor.close()
  conn.close()

except Exception as e:
  print(f"An error occurred: {e}")