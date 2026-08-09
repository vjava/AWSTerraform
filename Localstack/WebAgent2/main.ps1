# ==============================================================================
# Multi-Agent Enterprise System Deployment Script
# Features: General Chat Tab, GenAI Copilot, Employee & Project Directories, Architecture Agent
# ==============================================================================

$TargetDir = Join-Path -Path $PSScriptRoot -ChildPath "AgenticAISystem"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Building Multi-Agent Architecture with General Chat Tab..." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

function Write-CleanTextFile {
    param([string]$Path, [string]$Content)
    $fullPath = Join-Path -Path $TargetDir -ChildPath $Path
    $parent = Split-Path -Path $fullPath -Parent
    if (!(Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($fullPath, $Content, $utf8WithoutBom)
}

# Base Directory Structure
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

# KodeKloud / Custom LLM Configuration
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
    
    # 1. Employees Table
    if "Employees" not in existing_tables:
        print("Creating Employees Table...")
        dynamodb.create_table(
            TableName="Employees",
            KeySchema=[{"AttributeName": "EmployeeId", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "EmployeeId", "AttributeType": "S"}],
            ProvisionedThroughput={"ReadCapacityUnits": 5, "WriteCapacityUnits": 5}
        ).wait_until_exists()

    # 2. Projects Table
    if "Projects" not in existing_tables:
        print("Creating Projects Table...")
        dynamodb.create_table(
            TableName="Projects",
            KeySchema=[{"AttributeName": "ProjectId", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "ProjectId", "AttributeType": "S"}],
            ProvisionedThroughput={"ReadCapacityUnits": 5, "WriteCapacityUnits": 5}
        ).wait_until_exists()

    # 3. ProjectAssignments Table
    if "ProjectAssignments" not in existing_tables:
        print("Creating ProjectAssignments Table...")
        dynamodb.create_table(
            TableName="ProjectAssignments",
            KeySchema=[{"AttributeName": "AssignmentId", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "AssignmentId", "AttributeType": "S"}],
            ProvisionedThroughput={"ReadCapacityUnits": 5, "WriteCapacityUnits": 5}
        ).wait_until_exists()

def seed_data():
    dynamodb = get_dynamodb_resource()
    emp_table = dynamodb.Table("Employees")
    proj_table = dynamodb.Table("Projects")
    assign_table = dynamodb.Table("ProjectAssignments")
    
    # Seed Projects if empty
    if len(proj_table.scan(Limit=1).get("Items", [])) == 0:
        print("Seeding Projects...")
        projects = [
            {"ProjectId": "proj-alpha", "ProjectName": "Project Alpha (AI Copilot)", "Budget": 150000, "Status": "Active"},
            {"ProjectId": "proj-beta", "ProjectName": "Project Beta (Cloud Migration)", "Budget": 90000, "Status": "In Progress"}
        ]
        for proj in projects:
            proj_table.put_item(Item=proj)

    # Seed Employees if empty
    if len(emp_table.scan(Limit=1).get("Items", [])) == 0:
        print("Seeding Employees...")
        e1_id, e2_id, e3_id, e4_id = "emp-101", "emp-102", "emp-103", "emp-104"
        employees = [
            {"EmployeeId": e1_id, "Name": "Aarav Singh", "Email": "aarav@example.com", "Department": "Engineering", "Location": "Pune", "Salary": 60000},
            {"EmployeeId": e2_id, "Name": "Kavya Dixit", "Email": "kavya@example.com", "Department": "Content", "Location": "Pune", "Salary": 55000},
            {"EmployeeId": e3_id, "Name": "Rohan Sharma", "Email": "rohan@example.com", "Department": "HR", "Location": "Bangalore", "Salary": 45000},
            {"EmployeeId": e4_id, "Name": "Priya Patel", "Email": "priya@example.com", "Department": "Engineering", "Location": "Mumbai", "Salary": 80000},
        ]
        for emp in employees:
            emp_table.put_item(Item=emp)

    # Seed Assignments if empty
    if len(assign_table.scan(Limit=1).get("Items", [])) == 0:
        print("Seeding Assignments...")
        assignments = [
            {"AssignmentId": "as-1", "EmployeeId": "emp-101", "ProjectId": "proj-alpha", "Role": "Tech Lead", "AllocationPct": 100},
            {"AssignmentId": "as-2", "EmployeeId": "emp-104", "ProjectId": "proj-alpha", "Role": "Senior Engineer", "AllocationPct": 80},
            {"AssignmentId": "as-3", "EmployeeId": "emp-102", "ProjectId": "proj-beta", "Role": "Content Lead", "AllocationPct": 50},
            {"AssignmentId": "as-4", "EmployeeId": "emp-103", "ProjectId": "proj-beta", "Role": "HR Specialist", "AllocationPct": 30},
        ]
        for assign in assignments:
            assign_table.put_item(Item=assign)'

# 4. backend\services\data_service.py
Write-CleanTextFile -Path "backend\services\data_service.py" -Content 'from config import get_dynamodb_resource

def get_all_employees():
    return get_dynamodb_resource().Table("Employees").scan().get("Items", [])

def get_all_projects():
    return get_dynamodb_resource().Table("Projects").scan().get("Items", [])

def get_all_assignments():
    return get_dynamodb_resource().Table("ProjectAssignments").scan().get("Items", [])

def get_employee_projects_joined():
    employees = {e["EmployeeId"]: e for e in get_all_employees()}
    projects = {p["ProjectId"]: p for p in get_all_projects()}
    assignments = get_all_assignments()

    joined_data = []
    for a in assignments:
        emp = employees.get(a["EmployeeId"], {})
        proj = projects.get(a["ProjectId"], {})
        alloc = a.get("AllocationPct", 0)
        joined_data.append({
            "EmployeeName": emp.get("Name", "Unknown"),
            "Department": emp.get("Department", "Unknown"),
            "ProjectName": proj.get("ProjectName", "Unknown"),
            "RoleInProject": a.get("Role", "Contributor"),
            "Allocation": str(alloc) + "%",
            "Salary": emp.get("Salary", 0),
            "Location": emp.get("Location", "Unknown")
        })
    return joined_data'

# 5. backend\agent\agent_engine.py
Write-CleanTextFile -Path "backend\agent\agent_engine.py" -Content 'import requests
import json
import re
from config import KODEKLOUD_URL, KODEKLOUD_PASSWORD, LLM_MODEL
from services.data_service import (
    get_all_employees,
    get_all_projects,
    get_employee_projects_joined
)

SYSTEM_PROMPT = """You are a Supervisor AI Agent orchestrating specialized agents:
1. "general_chat_agent": Handles general questions, chit-chat, and queries not tied to local tables.
2. "architecture_agent": Answers questions about tech stack, system design, execution flow, or database schemas.
3. "employee_agent": Handles employee database searches (Name, City, Department, Email).
4. "project_agent": Handles project queries with optional filtering parameters: min_budget (number), max_budget (number), status (string).
5. "cross_table_agent": Handles joins between employees and project assignments.

Respond ONLY in strict JSON format with keys "agent", "parameters", and "reasoning".
Example Output:
{"agent": "project_agent", "parameters": {"min_budget": 90008}, "reasoning": "User requested projects with budget greater than 90008"}"""

ARCHITECTURE_CONTEXT = """
SYSTEM ARCHITECTURE & TECHNICAL CONTEXT:
- Overview: Enterprise GenAI Multi-Agent System with local cloud orchestration.
- Frontend Stack: React 18, Axios, Responsive Modern CSS Dashboard.
- Backend Stack: Python 3.10, FastAPI, Uvicorn, Boto3 SDK, Pydantic.
- Database Layer: AWS DynamoDB simulated locally via LocalStack 3.7.
- Tables & Primary Keys:
  * Employees (PK: EmployeeId) -> Name, Email, Department, Location, Salary
  * Projects (PK: ProjectId) -> ProjectName, Budget, Status
  * ProjectAssignments (PK: AssignmentId) -> EmployeeId, ProjectId, Role, AllocationPct
"""

def query_configured_llm(user_query: str, system_context: str = ""):
    if KODEKLOUD_URL and "your-kodekloud-url.com" not in KODEKLOUD_URL:
        base_url = KODEKLOUD_URL.rstrip("/")
        url = base_url + "/v1/chat/completions" if not base_url.endswith("/v1/chat/completions") else base_url

        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {KODEKLOUD_PASSWORD}"
        }
        
        sys_msg = "You are a helpful Enterprise AI Assistant."
        if system_context:
            sys_msg += f"\nContext:\n{system_context}"

        payload = {
            "model": LLM_MODEL,
            "messages": [
                {"role": "system", "content": sys_msg},
                {"role": "user", "content": user_query}
            ],
            "temperature": 0.3
        }

        try:
            res = requests.post(url, json=payload, headers=headers, timeout=12)
            if res.status_code == 401:
                res = requests.post(url, json=payload, headers={"Content-Type": "application/json"}, auth=("", KODEKLOUD_PASSWORD), timeout=12)

            if res.status_code == 200:
                data = res.json()
                return data["choices"][0]["message"]["content"]
        except Exception as e:
            print(f"[Configured LLM Call Failed]: {str(e)}")

    return None

def call_supervisor_llm(user_query: str):
    llm_res = query_configured_llm(user_query, SYSTEM_PROMPT)
    if llm_res:
        try:
            start_idx = llm_res.find("{")
            end_idx = llm_res.rfind("}")
            if start_idx != -1 and end_idx != -1:
                clean_json = llm_res[start_idx:end_idx+1]
                return clean_json
        except Exception:
            pass

    # Deterministic Local Rule Matcher
    q_lower = user_query.lower()

    if any(k in q_lower for k in ["architecture", "tech", "technology", "stack", "execution", "flow", "how it works", "design", "schema", "database"]):
        return json.dumps({
            "agent": "architecture_agent",
            "parameters": {},
            "reasoning": "Local Router: Matched architecture or system execution intent"
        })

    if "project" in q_lower and ("employee" in q_lower or "who" in q_lower or "working" in q_lower or "assigned" in q_lower):
        proj_keyword = "Alpha" if "alpha" in q_lower else ("Beta" if "beta" in q_lower else "")
        return json.dumps({
            "agent": "cross_table_agent",
            "parameters": {"project_name": proj_keyword},
            "reasoning": "Local Router: Matched employee to project assignment join"
        })

    if "project" in q_lower or "budget" in q_lower:
        params = {}
        numbers = [float(n) for n in re.findall(r"\b\d+\b", q_lower)]
        if numbers:
            if any(k in q_lower for k in ["greater", "more", "above", "higher", ">"]):
                params["min_budget"] = max(numbers)
            elif any(k in q_lower for k in ["less", "below", "under", "lower", "<"]):
                params["max_budget"] = min(numbers)

        return json.dumps({
            "agent": "project_agent",
            "parameters": params,
            "reasoning": f"Local Router: Matched project query with parameters {params}"
        })

    params = {}
    for dept in ["engineering", "content", "hr", "sales"]:
        if dept in q_lower: params["department"] = dept.capitalize()
    for city in ["pune", "mumbai", "bangalore", "delhi"]:
        if city in q_lower: params["city"] = city.capitalize()
    for name in ["priya", "aarav", "kavya", "rohan", "amit"]:
        if name in q_lower: params["name"] = name.capitalize()

    if params:
        return json.dumps({
            "agent": "employee_agent",
            "parameters": params,
            "reasoning": "Local Router: Matched employee attribute filter"
        })

    return json.dumps({
        "agent": "general_chat_agent",
        "parameters": {},
        "reasoning": "Forwarding query to General Chat Agent / Configured LLM."
    })

def execute_agent_query(user_query: str):
    llm_response = call_supervisor_llm(user_query)
    
    try:
        parsed = json.loads(llm_response)
        agent = parsed.get("agent", "general_chat_agent")
        params = parsed.get("parameters", {})
        reasoning = parsed.get("reasoning", "")

        if agent == "architecture_agent":
            llm_arch_answer = query_configured_llm(user_query, ARCHITECTURE_CONTEXT)
            data_output = {"Answer": llm_arch_answer} if llm_arch_answer else {
                "System Overview": "Agentic AI System running with FastAPI & LocalStack DynamoDB.",
                "Frontend": "React 18 Dashboard",
                "Backend": "Python 3.10 + FastAPI",
                "Database": "AWS DynamoDB (LocalStack 3.7)"
            }

            return {
                "query": user_query,
                "reasoning_step": reasoning,
                "tool_used": "System Architecture AI Specialist",
                "result_type": "SUMMARY",
                "data": data_output
            }

        elif agent == "cross_table_agent":
            joined_data = get_employee_projects_joined()
            proj_filter = params.get("project_name", "").lower()
            if proj_filter:
                joined_data = [d for d in joined_data if proj_filter in d["ProjectName"].lower()]
            return {
                "query": user_query,
                "reasoning_step": reasoning,
                "tool_used": "Cross-Table Join (Employees + Projects + Assignments)",
                "result_type": "TABLE",
                "data": joined_data
            }

        elif agent == "project_agent":
            projects = get_all_projects()
            filtered_projects = projects

            if "min_budget" in params and params["min_budget"] is not None:
                filtered_projects = [p for p in filtered_projects if float(p.get("Budget", 0)) > float(params["min_budget"])]
            if "max_budget" in params and params["max_budget"] is not None:
                filtered_projects = [p for p in filtered_projects if float(p.get("Budget", 0)) < float(params["max_budget"])]

            return {
                "query": user_query,
                "reasoning_step": reasoning,
                "tool_used": "Project-Table Query Agent",
                "result_type": "TABLE",
                "data": filtered_projects
            }

        elif agent == "employee_agent":
            employees = get_all_employees()
            if params.get("name"):
                employees = [e for e in employees if params["name"].lower() in e.get("Name", "").lower()]
            if params.get("city"):
                employees = [e for e in employees if params["city"].lower() in e.get("Location", "").lower()]
            if params.get("department"):
                employees = [e for e in employees if params["department"].lower() in e.get("Department", "").lower()]
                
            return {
                "query": user_query,
                "reasoning_step": reasoning,
                "tool_used": "Employee-Table Query Agent",
                "result_type": "TABLE",
                "data": employees
            }

        else:
            llm_general_answer = query_configured_llm(user_query)
            data_output = {"LLM_Response": llm_general_answer} if llm_general_answer else {
                "Message": "Hello! I am your Enterprise AI Assistant. How can I help you today?",
                "Capabilities": ["Employee Data Filtering", "Project Budget Calculations", "Architecture & Workflow Explanations"]
            }

            return {
                "query": user_query,
                "reasoning_step": reasoning,
                "tool_used": "General Conversational AI Agent",
                "result_type": "SUMMARY",
                "data": data_output
            }

    except Exception as e:
        return {"query": user_query, "error": str(e)}'

# 6. backend\main.py
Write-CleanTextFile -Path "backend\main.py" -Content 'import time
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from database import ensure_tables, seed_data
from services.data_service import get_all_employees, get_all_projects
from agent.agent_engine import execute_agent_query
from pydantic import BaseModel

app = FastAPI(title="Multi-Agent Enterprise GenAI System")

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
            print("Multi-Table DynamoDB Initialized Successfully.")
            break
        except Exception as e:
            print("Waiting for LocalStack... " + str(e))
            time.sleep(3)

class GenAIRequest(BaseModel):
    query: str

@app.get("/api/v1/employees")
def api_get_employees():
    return get_all_employees()

@app.get("/api/v1/projects")
def api_get_projects():
    return get_all_projects()

@app.post("/api/v1/genai/query")
def api_genai_query(req: GenAIRequest):
    return execute_agent_query(req.query)'

# 7. backend\Dockerfile
Write-CleanTextFile -Path "backend\Dockerfile" -Content 'FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]'

Write-Host "Generating Frontend Files..." -ForegroundColor Yellow

# 8. frontend\package.json
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

# 9. frontend\public\index.html
Write-CleanTextFile -Path "frontend\public\index.html" -Content '<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Multi-Agent Enterprise System</title>
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
      .agent-reasoning { background: #e0f2fe; padding: 12px; border-left: 4px solid #0284c7; margin-bottom: 15px; font-size: 14px; }
      .json-block { background: #1f2937; color: #e5e7eb; padding: 15px; border-radius: 6px; overflow-x: auto; font-family: monospace; white-space: pre-wrap; }
    </style>
  </head>
  <body><div id="root"></div></body>
</html>'

# 10. frontend\src\index.js
Write-CleanTextFile -Path "frontend\src\index.js" -Content 'import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App/>);'

# 11. frontend\src\App.js (Updated with General Chat Tab)
Write-CleanTextFile -Path "frontend\src\App.js" -Content 'import React, { useState } from "react";
import EmployeeTable from "./components/EmployeeTable";
import ProjectTable from "./components/ProjectTable";
import GenAICopilot from "./components/GenAICopilot";
import GeneralChat from "./components/GeneralChat";

export default function App() {
  const [activeTab, setActiveTab] = useState("copilot");

  return (
    <div className="container">
      <h1 style={{ color: "#111827" }}>Enterprise Multi-Agent GenAI Platform</h1>
      <div className="nav">
        <button className={activeTab === "copilot" ? "active" : ""} onClick={() => setActiveTab("copilot")}>GenAI Multi-Agent Copilot</button>
        <button className={activeTab === "chat" ? "active" : ""} onClick={() => setActiveTab("chat")}>General Chat Assistant</button>
        <button className={activeTab === "directory" ? "active" : ""} onClick={() => setActiveTab("directory")}>Employees</button>
        <button className={activeTab === "projects" ? "active" : ""} onClick={() => setActiveTab("projects")}>Projects</button>
      </div>
      
      <div className="card">
        {activeTab === "copilot" && <GenAICopilot/>}
        {activeTab === "chat" && <GeneralChat/>}
        {activeTab === "directory" && <EmployeeTable/>}
        {activeTab === "projects" && <ProjectTable/>}
      </div>
    </div>
  );
}'

# 12. frontend\src\components\GeneralChat.js (NEW Component)
Write-CleanTextFile -Path "frontend\src\components\GeneralChat.js" -Content 'import React, { useState } from "react";
import axios from "axios";
import AgentResultCard from "./AgentResultCard";

export default function GeneralChat() {
  const [query, setQuery] = useState("Hello! What can you do?");
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
      <h2>General Chat AI Assistant</h2>
      <p style={{ color: "#6b7280" }}>Chat with the AI assistant for general questions, greetings, or non-database queries.</p>
      <div className="input-group">
        <input value={query} onChange={e => setQuery(e.target.value)} placeholder="Type a message or ask a general question..." />
        <button onClick={executeQuery}>{loading ? "Thinking..." : "Send Message"}</button>
      </div>
      {result && <AgentResultCard result={result}/>}
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
      <h2>Employee Directory</h2>
      <table>
        <thead>
          <tr><th>Name</th><th>Email</th><th>Department</th><th>Location</th><th>Salary</th></tr>
        </thead>
        <tbody>
          {employees.map((e, idx) => (
            <tr key={idx}><td>{e.Name}</td><td>{e.Email}</td><td>{e.Department}</td><td>{e.Location}</td><td>${e.Salary}</td></tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}'

# 14. frontend\src\components\ProjectTable.js
Write-CleanTextFile -Path "frontend\src\components\ProjectTable.js" -Content 'import React, { useState, useEffect } from "react";
import axios from "axios";

export default function ProjectTable() {
  const [projects, setProjects] = useState([]);

  useEffect(() => {
    axios.get("http://localhost:8000/api/v1/projects")
      .then(res => setProjects(res.data))
      .catch(err => console.error(err));
  }, []);

  return (
    <div>
      <h2>Active Projects Directory</h2>
      <table>
        <thead>
          <tr><th>Project Name</th><th>Budget</th><th>Status</th></tr>
        </thead>
        <tbody>
          {projects.map((p, idx) => (
            <tr key={idx}><td>{p.ProjectName}</td><td>${p.Budget}</td><td>{p.Status}</td></tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}'

# 15. frontend\src\components\GenAICopilot.js
Write-CleanTextFile -Path "frontend\src\components\GenAICopilot.js" -Content 'import React, { useState } from "react";
import axios from "axios";
import AgentResultCard from "./AgentResultCard";

export default function GenAICopilot() {
  const [query, setQuery] = useState("projects with budget greater than 90008");
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
      <h2>Multi-Agent GenAI Assistant</h2>
      <div className="input-group">
        <input value={query} onChange={e => setQuery(e.target.value)} placeholder="Ask about local data (employees, projects) or system architecture..." />
        <button onClick={executeQuery}>{loading ? "Orchestrating..." : "Execute Query"}</button>
      </div>
      {result && <AgentResultCard result={result}/>}
    </div>
  );
}'

# 16. frontend\src\components\AgentResultCard.js
Write-CleanTextFile -Path "frontend\src\components\AgentResultCard.js" -Content 'import React from "react";

export default function AgentResultCard({ result }) {
  if (result.error) {
    return <div style={{ color: "red", marginTop: "20px" }}><strong>Error:</strong> {result.error}</div>;
  }

  const keys = result.data && Array.isArray(result.data) && result.data.length > 0 ? Object.keys(result.data[0]) : [];

  return (
    <div style={{ marginTop: "20px" }}>
      <div className="agent-reasoning">
        <strong>Routing Reasoning:</strong> {result.reasoning_step} <br/>
        <strong>Sub-Agent / Tool Used:</strong> {result.tool_used}
      </div>
      
      <h3>Response:</h3>
      {result.result_type === "TABLE" && Array.isArray(result.data) ? (
        <table>
          <thead>
            <tr>{keys.map((k, i) => <th key={i}>{k}</th>)}</tr>
          </thead>
          <tbody>
            {result.data.map((item, i) => (
              <tr key={i}>{keys.map((k, j) => <td key={j}>{item[k]}</td>)}</tr>
            ))}
          </tbody>
        </table>
      ) : (
        <pre className="json-block">{JSON.stringify(result.data, null, 2)}</pre>
      )}
    </div>
  );
}'

# 17. frontend\Dockerfile
Write-CleanTextFile -Path "frontend\Dockerfile" -Content 'FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["npm", "start"]'

# 18. docker-compose.yml
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

# 19. README.md
Write-CleanTextFile -Path "README.md" -Content '# Multi-Agent Enterprise GenAI System

System with General Chat Tab, Multi-Table Local Data Support, and Dynamic Configured LLM Fallback Routing.
'

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Project Generated Successfully!" -ForegroundColor Green
Write-Host "  Directory: $TargetDir" -ForegroundColor Cyan
Write-Host "  To start: cd '$TargetDir'; docker-compose up --build -d" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Green