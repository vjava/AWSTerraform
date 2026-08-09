# ==============================================================================
# KodeKloud-Dedicated AI-Powered Employee System Deployment Script
# Clean Standard Strings (Zero Here-String Parser Errors Guaranteed)
# ==============================================================================

$TargetDir = Join-Path -Path $PSScriptRoot -ChildPath "AgenticAISystem"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Building Agentic AI System Directory Structure..." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

function Write-CleanTextFile {
    param([string]$Path, [string]$Content)
    $fullPath = Join-Path -Path $TargetDir -ChildPath $Path
    $parent = Split-Path -Path $fullPath -Parent
    if (!(Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($fullPath, $Content, $utf8WithoutBom)
}

# Create Base Directory Structure
$dirs = @(
    "$TargetDir",
    "$TargetDir\backend",
    "$TargetDir\backend\agent",
    "$TargetDir\backend\services",
    "$TargetDir\frontend",
    "$TargetDir\frontend\public",
    "$TargetDir\frontend\src",
    "$TargetDir\frontend\src\components"
)

foreach ($dir in $dirs) {
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

Write-Host "Generating Backend Files..." -ForegroundColor Yellow

# 1. backend\requirements.txt
Write-CleanTextFile -Path "backend\requirements.txt" -Content 'fastapi==0.104.1
uvicorn==0.24.0
boto3==1.28.84
pydantic==2.5.2
pydantic-settings==2.1.0
requests==2.31.0'

# 2. backend\config.py
Write-CleanTextFile -Path "backend\config.py" -Content 'import os
from botocore.config import Config

AWS_ENDPOINT_URL = os.getenv("AWS_ENDPOINT_URL", "http://localstack:4566")

# KodeKloud Configuration
KODEKLOUD_URL = os.getenv("KODEKLOUD_URL", "")
KODEKLOUD_PASSWORD = os.getenv("KODEKLOUD_PASSWORD", "")
LLM_MODEL = os.getenv("LLM_MODEL", "mistral")

BOTO3_CONFIG = Config(
    region_name="us-east-1",
    signature_version="v4",
    retries={"max_attempts": 3}
)

def get_dynamodb_resource():
    import boto3
    return boto3.resource(
        "dynamodb",
        endpoint_url=AWS_ENDPOINT_URL,
        region_name="us-east-1",
        aws_access_key_id="test",
        aws_secret_access_key="test",
        config=BOTO3_CONFIG
    )'

# 3. backend\database.py
Write-CleanTextFile -Path "backend\database.py" -Content 'import time
import uuid
from datetime import datetime
from config import get_dynamodb_resource

def ensure_tables():
    dynamodb = get_dynamodb_resource()
    existing_tables = [table.name for table in dynamodb.tables.all()]
    
    if "Employees" not in existing_tables:
        print("Creating Employees Table...")
        table = dynamodb.create_table(
            TableName="Employees",
            KeySchema=[{"AttributeName": "EmployeeId", "KeyType": "HASH"}],
            AttributeDefinitions=[
                {"AttributeName": "EmployeeId", "AttributeType": "S"},
                {"AttributeName": "Location", "AttributeType": "S"},
                {"AttributeName": "Salary", "AttributeType": "N"}
            ],
            GlobalSecondaryIndexes=[
                {
                    "IndexName": "Location-Salary-index",
                    "KeySchema": [
                        {"AttributeName": "Location", "KeyType": "HASH"},
                        {"AttributeName": "Salary", "KeyType": "RANGE"}
                    ],
                    "Projection": {"ProjectionType": "ALL"},
                    "ProvisionedThroughput": {"ReadCapacityUnits": 5, "WriteCapacityUnits": 5}
                }
            ],
            ProvisionedThroughput={"ReadCapacityUnits": 5, "WriteCapacityUnits": 5}
        )
        table.wait_until_exists()

    if "Transactions" not in existing_tables:
        print("Creating Transactions Table...")
        table = dynamodb.create_table(
            TableName="Transactions",
            KeySchema=[{"AttributeName": "TransactionId", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "TransactionId", "AttributeType": "S"}],
            ProvisionedThroughput={"ReadCapacityUnits": 5, "WriteCapacityUnits": 5}
        )
        table.wait_until_exists()

def seed_data():
    dynamodb = get_dynamodb_resource()
    emp_table = dynamodb.Table("Employees")
    
    if len(emp_table.scan(Limit=1).get("Items", [])) > 0:
        return

    print("Seeding Employees...")
    employees = [
        {"Name": "Aarav Singh", "Email": "aarav@example.com", "Department": "Engineering", "Location": "Pune", "Salary": 60000},
        {"Name": "Kavya Dixit", "Email": "kavya@example.com", "Department": "Content", "Location": "Pune", "Salary": 55000},
        {"Name": "Rohan Sharma", "Email": "rohan@example.com", "Department": "HR", "Location": "Bangalore", "Salary": 45000},
        {"Name": "Priya Patel", "Email": "priya@example.com", "Department": "Engineering", "Location": "Mumbai", "Salary": 80000},
        {"Name": "Amit Kumar", "Email": "amit@example.com", "Department": "Sales", "Location": "Delhi", "Salary": 40000},
    ]

    for emp in employees:
        emp_table.put_item(Item={
            "EmployeeId": str(uuid.uuid4()),
            "Name": emp["Name"],
            "Email": emp["Email"],
            "Department": emp["Department"],
            "Location": emp["Location"],
            "Salary": emp["Salary"],
            "Role": "Staff",
            "CreatedAt": datetime.utcnow().isoformat()
        })'

# 4. backend\services\employee_service.py
Write-CleanTextFile -Path "backend\services\employee_service.py" -Content 'from config import get_dynamodb_resource
from boto3.dynamodb.conditions import Key, Attr

def get_all_employees():
    table = get_dynamodb_resource().Table("Employees")
    return table.scan().get("Items", [])

def search_employees_by_location_and_salary(location: str, min_salary: float, max_salary: float):
    table = get_dynamodb_resource().Table("Employees")
    response = table.query(
        IndexName="Location-Salary-index",
        KeyConditionExpression=Key("Location").eq(location) & Key("Salary").between(min_salary, max_salary)
    )
    return response.get("Items", [])

def aggregate_salary_by_department(department: str):
    table = get_dynamodb_resource().Table("Employees")
    response = table.scan(FilterExpression=Attr("Department").eq(department))
    items = response.get("Items", [])
    total = sum(float(item["Salary"]) for item in items)
    return {"department": department, "count": len(items), "total_salary": total}

def count_employees_by_filter(location: str = None, min_salary: float = None):
    table = get_dynamodb_resource().Table("Employees")
    filter_exp = None
    if location: filter_exp = Attr("Location").eq(location)
    if min_salary: 
        sal_exp = Attr("Salary").gte(min_salary)
        filter_exp = filter_exp & sal_exp if filter_exp else sal_exp
        
    kwargs = {}
    if filter_exp: kwargs["FilterExpression"] = filter_exp
    
    response = table.scan(**kwargs)
    return {"count": len(response.get("Items", []))}'

# 5. backend\agent\tools.py
Write-CleanTextFile -Path "backend\agent\tools.py" -Content 'from pydantic import BaseModel
from typing import Optional

class SearchEmployeesInput(BaseModel):
    location: str
    min_salary: float
    max_salary: float

class AggregateSalaryInput(BaseModel):
    department: str

class CountEmployeesInput(BaseModel):
    location: Optional[str] = None
    min_salary: Optional[float] = None'

# 6. backend\agent\agent_engine.py
Write-CleanTextFile -Path "backend\agent\agent_engine.py" -Content 'import requests
import json
from config import KODEKLOUD_URL, KODEKLOUD_PASSWORD, LLM_MODEL
from services.employee_service import (
    search_employees_by_location_and_salary,
    aggregate_salary_by_department,
    count_employees_by_filter,
    get_all_employees
)

SYSTEM_PROMPT = """You are an AI Agent Router. Map the user query to one of the available tools.
Respond ONLY in strict JSON format with keys "tool", "parameters", and "reasoning".

Tools:
1. "search_employees" : requires location (string), min_salary (number), max_salary (number)
2. "search_by_name" : requires name (string)
3. "aggregate_salary" : requires department (string)
4. "count_employees" : requires location (string), min_salary (number)

Example Output:
{"tool": "search_by_name", "parameters": {"name": "Priya"}, "reasoning": "User wants employees named Priya"}"""

def call_kodekloud_llm(user_query: str):
    if not KODEKLOUD_URL:
        return None

    base_url = KODEKLOUD_URL.rstrip("/")
    url = base_url + "/v1/chat/completions" if not base_url.endswith("/v1/chat/completions") else base_url

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {KODEKLOUD_PASSWORD}"
    }
    
    payload = {
        "model": LLM_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_query}
        ],
        "temperature": 0.0,
        "response_format": {"type": "json_object"}
    }

    try:
        res = requests.post(url, json=payload, headers=headers, timeout=10)
        if res.status_code == 401:
            res = requests.post(url, json=payload, headers={"Content-Type": "application/json"}, auth=("", KODEKLOUD_PASSWORD), timeout=10)

        if res.status_code == 200:
            data = res.json()
            return data["choices"][0]["message"]["content"]
            
    except Exception as e:
        print(f"[KodeKloud LLM Error]: {str(e)}")

    q_lower = user_query.lower()
    if "priya" in q_lower:
        return "{\"tool\": \"search_by_name\", \"parameters\": {\"name\": \"Priya\"}, \"reasoning\": \"Fallback Router: Name search for Priya\"}"
    elif "aarav" in q_lower:
        return "{\"tool\": \"search_by_name\", \"parameters\": {\"name\": \"Aarav\"}, \"reasoning\": \"Fallback Router: Name search for Aarav\"}"
    elif "kavya" in q_lower:
        return "{\"tool\": \"search_by_name\", \"parameters\": {\"name\": \"Kavya\"}, \"reasoning\": \"Fallback Router: Name search for Kavya\"}"
    elif "pune" in q_lower:
        return "{\"tool\": \"search_employees\", \"parameters\": {\"location\": \"Pune\", \"min_salary\": 0, \"max_salary\": 9999999}, \"reasoning\": \"Fallback Router: Pune location search\"}"

    return "{\"tool\": \"get_all\", \"parameters\": {}, \"reasoning\": \"Fallback Router: Returning all employees\"}"

def execute_agent_query(user_query: str):
    llm_response = call_kodekloud_llm(user_query)
    
    if not llm_response:
        return {"query": user_query, "error": "Could not parse query or LLM unreachable."}
        
    try:
        parsed = json.loads(llm_response)
        tool = parsed.get("tool")
        params = parsed.get("parameters", {})
        reasoning = parsed.get("reasoning", "")
        
        data = []
        if tool == "search_by_name":
            all_emp = get_all_employees()
            target_name = params.get("name", "").lower()
            data = [e for e in all_emp if target_name in e.get("Name", "").lower()]
        elif tool == "search_employees":
            data = search_employees_by_location_and_salary(
                params.get("location", "Pune"), 
                float(params.get("min_salary", 0)), 
                float(params.get("max_salary", 9999999))
            )
        elif tool == "aggregate_salary":
            data = aggregate_salary_by_department(params.get("department", "Engineering"))
        elif tool == "count_employees":
            data = count_employees_by_filter(params.get("location"), params.get("min_salary"))
        elif tool == "get_all":
            data = get_all_employees()
        else:
            return {"query": user_query, "error": "Unknown tool requested: " + str(tool)}
            
        return {
            "query": user_query,
            "reasoning_step": reasoning,
            "tool_used": tool,
            "result_type": "TABLE" if isinstance(data, list) else "SUMMARY",
            "data": data
        }
    except Exception as e:
        return {"query": user_query, "error": str(e)}'

# 7. backend\main.py
Write-CleanTextFile -Path "backend\main.py" -Content 'import time
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from database import ensure_tables, seed_data
from services.employee_service import get_all_employees
from agent.agent_engine import execute_agent_query
from pydantic import BaseModel

app = FastAPI(title="Agentic AI Employee System")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
def startup_event():
    for _ in range(5):
        try:
            ensure_tables()
            seed_data()
            print("DynamoDB Initialized Successfully.")
            break
        except Exception as e:
            print("Waiting for LocalStack... " + str(e))
            time.sleep(3)

class GenAIRequest(BaseModel):
    query: str

@app.get("/api/v1/employees")
def api_get_employees():
    return get_all_employees()

@app.post("/api/v1/genai/query")
def api_genai_query(req: GenAIRequest):
    return execute_agent_query(req.query)'

# 8. backend\Dockerfile
Write-CleanTextFile -Path "backend\Dockerfile" -Content 'FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]'

Write-Host "Generating Frontend Files..." -ForegroundColor Yellow

# 9. frontend\package.json
Write-CleanTextFile -Path "frontend\package.json" -Content '{
  "name": "agentic-frontend",
  "version": "1.0.0",
  "dependencies": {
    "axios": "^1.6.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1"
  },
  "scripts": {
    "start": "react-scripts start"
  },
  "browserslist": {
    "development": ["last 1 chrome version"]
  }
}'

# 10. frontend\public\index.html
Write-CleanTextFile -Path "frontend\public\index.html" -Content '<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Agentic AI System</title>
    <style>
      body { font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif; margin: 0; background: #f3f4f6; }
      .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
      .nav { display: flex; gap: 20px; margin-bottom: 20px; border-bottom: 2px solid #e5e7eb; padding-bottom: 10px; }
      .nav button { background: none; border: none; font-size: 16px; cursor: pointer; padding: 10px; color: #4b5563; }
      .nav button.active { color: #2563eb; border-bottom: 2px solid #2563eb; font-weight: bold; }
      .card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
      table { width: 100%; border-collapse: collapse; margin-top: 15px; }
      th, td { text-align: left; padding: 12px; border-bottom: 1px solid #e5e7eb; }
      th { background-color: #f9fafb; }
      .input-group { display: flex; gap: 10px; margin-bottom: 20px; }
      .input-group input { flex: 1; padding: 12px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 16px; }
      .input-group button { background: #2563eb; color: white; border: none; padding: 12px 24px; border-radius: 6px; cursor: pointer; }
      .agent-reasoning { background: #fef3c7; padding: 10px; border-left: 4px solid #f59e0b; margin-bottom: 15px; font-size: 14px; }
      .json-block { background: #1f2937; color: #e5e7eb; padding: 15px; border-radius: 6px; overflow-x: auto; font-family: monospace; }
    </style>
  </head>
  <body><div id="root"></div></body>
</html>'

# 11. frontend\src\index.js
Write-CleanTextFile -Path "frontend\src\index.js" -Content 'import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App/>);'

# 12. frontend\src\App.js
Write-CleanTextFile -Path "frontend\src\App.js" -Content 'import React, { useState } from "react";
import EmployeeTable from "./components/EmployeeTable";
import GenAICopilot from "./components/GenAICopilot";

export default function App() {
  const [activeTab, setActiveTab] = useState("directory");

  return (
    <div className="container">
      <h1 style={{ color: "#111827" }}>Agentic Employee & Transaction System</h1>
      <div className="nav">
        <button className={activeTab === "directory" ? "active" : ""} onClick={() => setActiveTab("directory")}>Directory</button>
        <button className={activeTab === "copilot" ? "active" : ""} onClick={() => setActiveTab("copilot")}>GenAI Copilot</button>
      </div>
      
      <div className="card">
        {activeTab === "directory" ? <EmployeeTable/> : <GenAICopilot/>}
      </div>
    </div>
  );
}'

# 13. frontend\src\components\EmployeeTable.js
Write-CleanTextFile -Path "frontend\src\components\EmployeeTable.js" -Content 'import React, { useState, useEffect } from "react";
import axios from "axios";

export default function EmployeeTable() {
  const [employees, setEmployees] = useState([]);

  useEffect(() => {
    axios.get("http://localhost:8000/api/v1/employees")
      .then(res => setEmployees(res.data))
      .catch(err => console.error(err));
  }, []);

  return (
    <div>
      <h2>Employee Directory (DynamoDB)</h2>
      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>Email</th>
            <th>Department</th>
            <th>Location</th>
            <th>Salary</th>
          </tr>
        </thead>
        <tbody>
          {employees.map((e, idx) => (
            <tr key={idx}>
              <td>{e.Name}</td>
              <td>{e.Email}</td>
              <td>{e.Department}</td>
              <td>{e.Location}</td>
              <td>${e.Salary}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}'

# 14. frontend\src\components\GenAICopilot.js
Write-CleanTextFile -Path "frontend\src\components\GenAICopilot.js" -Content 'import React, { useState } from "react";
import axios from "axios";
import AgentResultCard from "./AgentResultCard";

export default function GenAICopilot() {
  const [query, setQuery] = useState("How many employees in Pune earn more than 50000?");
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);

  const executeQuery = async () => {
    setLoading(true);
    try {
      const res = await axios.post("http://localhost:8000/api/v1/genai/query", { query });
      setResult(res.data);
    } catch (err) {
      setResult({ error: err.message });
    }
    setLoading(false);
  };

  return (
    <div>
      <h2>Ask the Agent</h2>
      <div className="input-group">
        <input value={query} onChange={e => setQuery(e.target.value)} placeholder="Type natural language query..." />
        <button onClick={executeQuery}>{loading ? "Thinking..." : "Execute"}</button>
      </div>
      {result && <AgentResultCard result={result}/>}
    </div>
  );
}'

# 15. frontend\src\components\AgentResultCard.js
Write-CleanTextFile -Path "frontend\src\components\AgentResultCard.js" -Content 'import React from "react";

export default function AgentResultCard({ result }) {
  if (result.error) {
    return <div style={{ color: "red", marginTop: "20px" }}><strong>Error:</strong> {result.error}</div>;
  }

  return (
    <div style={{ marginTop: "20px" }}>
      <div className="agent-reasoning">
        <strong>Agent Reasoning Step:</strong> {result.reasoning_step} <br/>
        <strong>Tool Invoked:</strong> {result.tool_used}
      </div>
      
      <h3>DynamoDB Result:</h3>
      {result.result_type === "TABLE" && Array.isArray(result.data) ? (
        <table>
          <thead>
            <tr><th>Name</th><th>Location</th><th>Salary</th><th>Department</th></tr>
          </thead>
          <tbody>
            {result.data.map((item, i) => (
              <tr key={i}>
                <td>{item.Name}</td><td>{item.Location}</td><td>${item.Salary}</td><td>{item.Department}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <pre className="json-block">{JSON.stringify(result.data, null, 2)}</pre>
      )}
    </div>
  );
}'

# 16. frontend\Dockerfile
Write-CleanTextFile -Path "frontend\Dockerfile" -Content 'FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["npm", "start"]'

Write-Host "Generating Docker Compose and README..." -ForegroundColor Yellow

# 17. docker-compose.yml
Write-CleanTextFile -Path "docker-compose.yml" -Content 'services:
  localstack:
    image: localstack/localstack:3.7.0
    container_name: agentic_localstack
    ports:
      - "4566:4566"
    environment:
      - SERVICES=dynamodb
      - DEBUG=1

  backend:
    build: ./backend
    container_name: agentic_backend
    ports:
      - "8000:8000"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - AWS_ENDPOINT_URL=http://localstack:4566
      - KODEKLOUD_URL=https://your-kodekloud-url.com
      - KODEKLOUD_PASSWORD=your_password_here
      - LLM_MODEL=mistral
    depends_on:
      - localstack

  frontend:
    build: ./frontend
    container_name: agentic_frontend
    ports:
      - "3000:3000"
    depends_on:
      - backend'

# 18. README.md
Write-CleanTextFile -Path "README.md" -Content '# Agentic AI-Powered Employee System

System combining AWS DynamoDB (LocalStack) with a dynamic AI Agent.

## KodeKloud Setup
Update docker-compose.yml with your KODEKLOUD_URL and KODEKLOUD_PASSWORD.

## Run Project
```bash
.\main.ps1
cd AgenticAISystem
docker-compose up --build -d
```'

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Project Generated Successfully!" -ForegroundColor Green
Write-Host "  Directory: $TargetDir" -ForegroundColor Cyan
Write-Host "  To start the project, run: " -ForegroundColor White
Write-Host "  cd '$TargetDir'; docker-compose up --build -d" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green