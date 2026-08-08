# ==============================================================================
# Master PowerShell Deployment Script for GenAI Serverless Studio (English Only)
# ==============================================================================

param(
    [string]$ProjectDir = "$PSScriptRoot"
)

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Initializing Clean Deployment & GenAI Studio Setup" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. CLEAN-UP: Delete existing previous generated files if they exist
Write-Host "[+] Step 1: Cleaning up existing old files and artifacts..." -ForegroundColor Yellow
$filesToDelete = @("requirements.txt", ".env", "lambda_function.py", "main.tf", "lambda_ui.py", "lambda_function.zip")
foreach ($file in $filesToDelete) {
    if (Test-Path $file) {
        Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
        Write-Host "    - Deleted old: $file" -ForegroundColor DarkGray
    }
}
if (Test-Path ".terraform") {
    Remove-Item -Path ".terraform" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "    - Deleted old: .terraform directory" -ForegroundColor DarkGray
}
if (Test-Path "terraform.tfstate") {
    Remove-Item -Path "terraform.tfstate" -Force -ErrorAction SilentlyContinue
    Write-Host "    - Deleted old: terraform.tfstate" -ForegroundColor DarkGray
}

# 2. Create requirements.txt
Write-Host "[+] Step 2: Generating requirements.txt..." -ForegroundColor Yellow
$reqContent = @"
streamlit
requests
python-dotenv
boto3
pydantic
pandas
"@
Set-Content -Path "requirements.txt" -Value $reqContent -Encoding utf8

# 3. Create .env Configuration Template
Write-Host "[+] Step 3: Generating .env configuration file..." -ForegroundColor Yellow
$envContent = @"
KODEKLOUD_URL=URL
KODEKLOUD_API_KEY=password
LLM_MODEL=Model
AWS_ENDPOINT_URL=URL
AWS_DEFAULT_REGION=us-east-1
"@
Set-Content -Path ".env" -Value $envContent -Encoding utf8

# 4. Create Backend Lambda Function Code (`lambda_function.py`)
Write-Host "[+] Step 4: Generating lambda_function.py..." -ForegroundColor Yellow
$lambdaContent = @'
import os
import json
import requests
from dotenv import load_dotenv

load_dotenv()

KODEKLOUD_URL = os.getenv("KODEKLOUD_URL", "https://api.ai.kodekloud.com")
KODEKLOUD_API_KEY = os.getenv("KODEKLOUD_API_KEY", "YOUR_API_PASSWORD")
LLM_MODEL = os.getenv("LLM_MODEL", "deepseek/deepseek-v4-flash")

def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body", "{}")) if isinstance(event.get("body"), str) else event.get("body", {})
        action = body.get("action", "chat")
        payload = body.get("payload", {})
        
        messages = [{"role": "system", "content": "You are an enterprise AI data architect and assistant."}]
        
        if action == "generate_code":
            target = payload.get("target_lang", "Python")
            objective = payload.get("objective", "")
            messages.append({"role": "user", "content": f"Write production-grade {target} code for: {objective}"})
        elif action == "translate":
            source_lang = payload.get("source_lang", "Python")
            target_lang = payload.get("target_lang", "Java")
            source_code = payload.get("source_code", "")
            messages.append({"role": "user", "content": f"Translate this {source_lang} code to {target_lang}:\n{source_code}"})
        elif action == "databricks_sql":
            table = payload.get("table_name", "users")
            question = payload.get("question", "")
            messages.append({"role": "user", "content": f"Write a Databricks SQL SELECT query for table '{table}' based on this question: {question}. Output ONLY valid SQL."})
        elif action == "validate_json":
            code_snippet = payload.get("code_snippet", "")
            messages.append({"role": "user", "content": f"Validate and check for syntax errors or security issues in this code/JSON snippet. Provide corrected version if needed:\n{code_snippet}"})
        elif action == "markdown_doc":
            topic = payload.get("topic", "")
            messages.append({"role": "user", "content": f"Create a comprehensive, production-ready Markdown documentation and architecture guide for: {topic}"})
        elif action == "databricks_agent":
            task = payload.get("task_description", "")
            messages.append({"role": "user", "content": f"You are a Databricks Expert. Write PySpark/Delta Lake code or architecture strategy for this task: {task}"})
        elif action == "file_validator":
            file_type = payload.get("file_type", "CSV")
            file_sample = payload.get("file_sample", "")
            messages.append({"role": "user", "content": f"Validate if this sample structure is a valid {file_type} format. Check for common formatting issues, delimiter mismatches, or schema corruption:\n{file_sample}"})
        else:
            chat_history = payload.get("history", [])
            messages.extend(chat_history)

        endpoint = f"{KODEKLOUD_URL}/v1/chat/completions"
        headers = {"Authorization": f"Bearer {KODEKLOUD_API_KEY}", "Content-Type": "application/json"}
        req_payload = {"model": LLM_MODEL, "messages": messages, "temperature": 0.2}
        
        res = requests.post(endpoint, json=req_payload, headers=headers, timeout=60)
        res.raise_for_status()
        ai_response = res.json()["choices"][0]["message"]["content"].strip()

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"status": "success", "result": ai_response})
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"status": "error", "message": str(e)})
        }
'@
Set-Content -Path "lambda_function.py" -Value $lambdaContent -Encoding utf8

# 5. Create Terraform Infrastructure File (`main.tf`)
Write-Host "[+] Step 5: Generating Terraform main.tf..." -ForegroundColor Yellow
$tfContent = @'
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  s3_use_path_style           = false
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    iam        = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    apigateway = "http://localhost:4566"
    sts        = "http://localhost:4566"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "genai_lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "genai_lambda" {
  filename         = "lambda_function.zip"
  function_name    = "genai_polyglot_engine"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

output "lambda_function_arn" {
  value = aws_lambda_function.genai_lambda.arn
}
'@
Set-Content -Path "main.tf" -Value $tfContent -Encoding utf8

# 6. Create Streamlit UI Client (`lambda_ui.py`) with 8 Functional Tabs (English Only)
Write-Host "[+] Step 6: Generating lambda_ui.py with 8 tabs..." -ForegroundColor Yellow
$uiContent = @'
import streamlit as st
import json
from lambda_function import lambda_handler

st.set_page_config(page_title="Enterprise GenAI Studio", page_icon="⚡", layout="wide")

st.sidebar.title("Configuration")
st.sidebar.info("Direct Lambda Execution Mode • Connected to LLM Gateway")

st.title("Enterprise Serverless GenAI Studio")
st.markdown("Polyglot Generative AI platform managed via Terraform and executed via Lambda backend.")

# 8 Functional Tabs (Clean English)
tab1, tab2, tab3, tab4, tab5, tab6, tab7, tab8 = st.tabs([
    "Code Generator", 
    "Code Translator", 
    "Chatbot", 
    "Databricks SQL Agent", 
    "JSON Validator", 
    "Architecture Docs",
    "Databricks AI Agent",
    "File Format Validator"
])

with tab1:
    st.subheader("Serverless Code Generation")
    lang = st.selectbox("Language", ["Python", "Java", "Go", "TypeScript", "Terraform", "C++"])
    obj = st.text_input("Objective", placeholder="Create a secure user authentication function...")
    if st.button("Invoke Generation"):
        if not obj.strip(): st.warning("Please enter an objective.")
        else:
            with st.spinner("Generating code via LLM..."):
                event = {"body": json.dumps({"action": "generate_code", "payload": {"target_lang": lang, "objective": obj}})}
                res = lambda_handler(event, None)
                data = json.loads(res["body"])
                if data.get("status") == "success": st.markdown(data.get("result"))
                else: st.error(data.get("message"))

with tab2:
    st.subheader("Cross-Language Code Translator")
    s_lang = st.selectbox("From Language", ["Python", "Java", "JavaScript", "Go"])
    t_lang = st.selectbox("To Language", ["Java", "Python", "Go", "TypeScript"])
    code_text = st.text_area("Source Code", placeholder="def add(a, b):\n    return a + b", height=150)
    if st.button("Invoke Translation"):
        if not code_text.strip(): st.warning("Please provide source code.")
        else:
            with st.spinner("Translating code..."):
                event = {"body": json.dumps({"action": "translate", "payload": {"source_lang": s_lang, "target_lang": t_lang, "source_code": code_text}})}
                res = lambda_handler(event, None)
                data = json.loads(res["body"])
                if data.get("status") == "success": st.markdown(data.get("result"))
                else: st.error(data.get("message"))

with tab3:
    st.subheader("Serverless Chatbot")
    if "chat" not in st.session_state: st.session_state.chat = []
    for msg in st.session_state.chat:
        with st.chat_message(msg["role"]): st.markdown(msg["content"])
    if prompt := st.chat_input("Ask AI anything..."):
        st.session_state.chat.append({"role": "user", "content": prompt})
        with st.chat_message("user"): st.markdown(prompt)
        with st.chat_message("assistant"):
            with st.spinner("Thinking..."):
                event = {"body": json.dumps({"action": "chat", "payload": {"history": st.session_state.chat}})}
                res = lambda_handler(event, None)
                data = json.loads(res["body"])
                reply = data.get("result", data.get("message", "Error"))
                st.markdown(reply)
                st.session_state.chat.append({"role": "assistant", "content": reply})

with tab4:
    st.subheader("Databricks SQL & Analytics Agent")
    tbl_name = st.text_input("Databricks Table Name", value="workspace.default.customers")
    sql_question = st.text_input("Plain English Question", placeholder="Find total spend grouped by region where spend > 500")
    if st.button("Generate Databricks SQL"):
        if not sql_question.strip(): st.warning("Please enter a question.")
        else:
            with st.spinner("Generating Databricks SQL query..."):
                event = {"body": json.dumps({"action": "databricks_sql", "payload": {"table_name": tbl_name, "question": sql_question}})}
                res = lambda_handler(event, None)
                data = json.loads(res["body"])
                if data.get("status") == "success": st.code(data.get("result"), language="sql")
                else: st.error(data.get("message"))

with tab5:
    st.subheader("JSON & Code Validator / Linter")
    snippet = st.text_area("Paste JSON or Code to Validate", placeholder='{"name": "test", "value": 123}', height=150)
    if st.button("Validate & Fix"):
        if not snippet.strip(): st.warning("Please provide code or JSON.")
        else:
            with st.spinner("Validating snippet..."):
                event = {"body": json.dumps({"action": "validate_json", "payload": {"code_snippet": snippet}})}
                res = lambda_handler(event, None)
                data = json.loads(res["body"])
                if data.get("status") == "success": st.markdown(data.get("result"))
                else: st.error(data.get("message"))

with tab6:
    st.subheader("Architecture Documentation & Markdown Generator")
    doc_topic = st.text_input("Project or System Topic", placeholder="Microservices Event-Driven Architecture with Kafka & AWS Lambda")
    if st.button("Generate Documentation"):
        if not doc_topic.strip(): st.warning("Please enter a topic.")
        else:
            with st.spinner("Writing production-grade documentation..."):
                event = {"body": json.dumps({"action": "markdown_doc", "payload": {"topic": doc_topic}})}
                res = lambda_handler(event, None)
                data = json.loads(res["body"])
                if data.get("status") == "success": st.markdown(data.get("result"))
                else: st.error(data.get("message"))

with tab7:
    st.subheader("Databricks AI Assistant & PySpark Expert")
    db_task = st.text_area("Databricks / PySpark Task Description", placeholder="Write an optimized PySpark script to read a massive CSV file, drop duplicates, and write as Delta Lake format with Z-Order partitioning.")
    if st.button("Generate Databricks Solution"):
        if not db_task.strip(): st.warning("Please enter a task description.")
        else:
            with st.spinner("Generating PySpark / Databricks code..."):
                event = {"body": json.dumps({"action": "databricks_agent", "payload": {"task_description": db_task}})}
                res = lambda_handler(event, None)
                data = json.loads(res["body"])
                if data.get("status") == "success": st.markdown(data.get("result"))
                else: st.error(data.get("message"))

with tab8:
    st.subheader("File Format & Schema Validator (CSV, Parquet, JSON)")
    f_type = st.selectbox("Select File Format", ["CSV", "JSON", "Parquet Schema", "Avro"])
    f_sample = st.text_area("Paste File Sample / Header / Schema Preview", placeholder="id,name,email,created_at\n1,Alice,alice@example.com,2026-01-01", height=150)
    if st.button("Validate File Format"):
        if not f_sample.strip(): st.warning("Please provide file sample data.")
        else:
            with st.spinner("Validating file format and structure..."):
                event = {"body": json.dumps({"action": "file_validator", "payload": {"file_type": f_type, "file_sample": f_sample}})}
                res = lambda_handler(event, None)
                data = json.loads(res["body"])
                if data.get("status") == "success": st.markdown(data.get("result"))
                else: st.error(data.get("message"))
'@
Set-Content -Path "lambda_ui.py" -Value $uiContent -Encoding utf8

# 7. Initialize Terraform and Apply
Write-Host "[+] Step 7: Initializing Terraform infrastructure..." -ForegroundColor Yellow
terraform init | Out-Null
terraform apply -auto-approve | Out-Null

# 8. Setup Python Virtual Environment and Install Requirements
Write-Host "[+] Step 8: Setting up Python Virtual Environment..." -ForegroundColor Yellow
if (!(Test-Path "venv")) {
    python -m venv venv
}
& ".\venv\Scripts\Activate.ps1"
python -m pip install --upgrade pip | Out-Null
pip install -r requirements.txt | Out-Null

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Fully Loaded GenAI Studio Deployed Successfully!" -ForegroundColor Green
Write-Host "  Launching Streamlit UI Dashboard..." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Green

# 9. Run Streamlit UI
streamlit run lambda_ui.py