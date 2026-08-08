# ==============================================================================
# Master PowerShell Deployment Script (Employee Management System)
# LocalStack 3.7.0 Fix included
# ==============================================================================

param(
    [string]$RootDir = "$PSScriptRoot\EmployeeManagementSystem"
)

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  🚀 Initializing Deployment with LocalStack 3.7.0 Fix" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Create Directory Structure
if (!(Test-Path $RootDir)) { New-Item -ItemType Directory -Path $RootDir | Out-Null }
if (!(Test-Path "$RootDir\backend")) { New-Item -ItemType Directory -Path "$RootDir\backend" | Out-Null }
if (!(Test-Path "$RootDir\frontend\src")) { New-Item -ItemType Directory -Path "$RootDir\frontend\src" | Out-Null }
if (!(Test-Path "$RootDir\frontend\public")) { New-Item -ItemType Directory -Path "$RootDir\frontend\public" | Out-Null }

Set-Location $RootDir

# 2. Create Backend files
$backendMain = @'
import os
import boto3
import uuid
from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from typing import List
from botocore.config import Config

app = FastAPI(title="Employee Management System API (DynamoDB)", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

AWS_ENDPOINT = os.getenv("AWS_ENDPOINT_URL", "http://localstack:4566")

class EmployeeCreate(BaseModel):
    name: str
    email: EmailStr
    department: str
    salary: float

class EmployeeResponse(BaseModel):
    id: str
    name: str
    email: str
    department: str
    salary: float

def get_dynamodb_resource():
    return boto3.resource(
        'dynamodb',
        endpoint_url=AWS_ENDPOINT,
        region_name='us-east-1',
        aws_access_key_id='test',
        aws_secret_access_key='test',
        config=Config(
            connect_timeout=3,
            read_timeout=3,
            retries={'max_attempts': 2}
        )
    )

def ensure_tables_exist():
    try:
        dynamodb = get_dynamodb_resource()
        existing_tables = [t.name for t in dynamodb.tables.all()]
        
        if 'Employees' not in existing_tables:
            dynamodb.create_table(
                TableName='Employees',
                KeySchema=[{'AttributeName': 'EmployeeId', 'KeyType': 'HASH'}],
                AttributeDefinitions=[{'AttributeName': 'EmployeeId', 'AttributeType': 'S'}],
                ProvisionedThroughput={'ReadCapacityUnits': 5, 'WriteCapacityUnits': 5}
            )
                
        if 'EmployeeAuditLogs' not in existing_tables:
            dynamodb.create_table(
                TableName='EmployeeAuditLogs',
                KeySchema=[{'AttributeName': 'LogId', 'KeyType': 'HASH'}],
                AttributeDefinitions=[{'AttributeName': 'LogId', 'AttributeType': 'S'}],
                ProvisionedThroughput={'ReadCapacityUnits': 5, 'WriteCapacityUnits': 5}
            )
    except Exception as e:
        print(f"Table creation warning: {e}")

@app.get("/")
def root():
    return {"message": "Employee Management System API is running. Go to /docs for Swagger UI."}

@app.get("/employees", response_model=List[EmployeeResponse])
def get_employees():
    try:
        ensure_tables_exist()
        dynamodb = get_dynamodb_resource()
        table = dynamodb.Table('Employees')
        response = table.scan()
        items = response.get('Items', [])
        
        employees = [{
            "id": item['EmployeeId'],
            "name": item['Name'],
            "email": item['Email'],
            "department": item['Department'],
            "salary": float(item['Salary'])
        } for item in items]
        
        return employees
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/employees", response_model=EmployeeResponse, status_code=status.HTTP_201_CREATED)
def create_employee(emp: EmployeeCreate):
    try:
        ensure_tables_exist()
        dynamodb = get_dynamodb_resource()
        table = dynamodb.Table('Employees')
        
        emp_id = str(uuid.uuid4())
        item = {
            'EmployeeId': emp_id,
            'Name': emp.name,
            'Email': emp.email,
            'Department': emp.department,
            'Salary': str(emp.salary)
        }
        
        table.put_item(Item=item)
        return {
            "id": emp_id,
            "name": emp.name,
            "email": emp.email,
            "department": emp.department,
            "salary": emp.salary
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/employees/{emp_id}")
def delete_employee(emp_id: str):
    try:
        ensure_tables_exist()
        dynamodb = get_dynamodb_resource()
        table = dynamodb.Table('Employees')
        
        response = table.get_item(Key={'EmployeeId': emp_id})
        if 'Item' not in response:
            raise HTTPException(status_code=404, detail="Employee not found")
            
        table.delete_item(Key={'EmployeeId': emp_id})
        return {"message": "Employee deleted successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
'@
Set-Content -Path "backend\main.py" -Value $backendMain -Encoding ascii

$backendReq = @"
fastapi
uvicorn
boto3
pydantic[email]
"@
Set-Content -Path "backend\requirements.txt" -Value $backendReq -Encoding ascii

$backendDocker = @"
FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
"@
Set-Content -Path "backend\Dockerfile" -Value $backendDocker -Encoding ascii


# 3. Create Frontend files
$frontendIndexHtml = @"
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Employee Management System (DynamoDB)</title>
  </head>
  <body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root"></div>
  </body>
</html>
"@
Set-Content -Path "frontend\public\index.html" -Value $frontendIndexHtml -Encoding ascii

$frontendIndexJs = @'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
'@
Set-Content -Path "frontend\src\index.js" -Value $frontendIndexJs -Encoding ascii

$frontendAppJs = @'
import React, { useState, useEffect } from 'react';
import axios from 'axios';

const API_BASE = "http://127.0.0.1:8000";

function App() {
  const [employees, setEmployees] = useState([]);
  const [form, setForm] = useState({ name: '', email: '', department: '', salary: '' });
  const [loading, setLoading] = useState(false);

  const fetchEmployees = async () => {
    try {
      const res = await axios.get(`${API_BASE}/employees`);
      setEmployees(res.data);
    } catch (err) { console.error("Error fetching employees", err); }
  };

  useEffect(() => { fetchEmployees(); }, []);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      await axios.post(`${API_BASE}/employees`, {
        name: form.name, email: form.email, department: form.department, salary: parseFloat(form.salary)
      });
      setForm({ name: '', email: '', department: '', salary: '' });
      fetchEmployees();
    } catch (err) {
      alert("Error adding employee: " + (err.response?.data?.detail || err.message));
    } finally { setLoading(false); }
  };

  const handleDelete = async (id) => {
    if (window.confirm("Are you sure you want to delete this employee?")) {
      try {
        await axios.delete(`${API_BASE}/employees/${id}`);
        fetchEmployees();
      } catch (err) { alert("Error deleting employee"); }
    }
  };

  return (
    <div style={{ fontFamily: 'Arial, sans-serif', padding: '30px', maxWidth: '900px', margin: '0 auto', background: '#f8f9fa', minHeight: '100vh' }}>
      <header style={{ textAlign: 'center', marginBottom: '30px' }}>
        <h1 style={{ color: '#333' }}>Enterprise Employee Management System</h1>
        <p style={{ color: '#666' }}>FastAPI + LocalStack DynamoDB + React</p>
      </header>

      <div style={{ background: '#fff', padding: '20px', borderRadius: '8px', boxShadow: '0 2px 4px rgba(0,0,0,0.1)', marginBottom: '30px' }}>
        <h2>Add New Employee</h2>
        <form onSubmit={handleSubmit} style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '15px' }}>
          <input type="text" placeholder="Full Name" value={form.name} onChange={e => setForm({...form, name: e.target.value})} required style={{ padding: '10px' }} />
          <input type="email" placeholder="Email Address" value={form.email} onChange={e => setForm({...form, email: e.target.value})} required style={{ padding: '10px' }} />
          <input type="text" placeholder="Department" value={form.department} onChange={e => setForm({...form, department: e.target.value})} required style={{ padding: '10px' }} />
          <input type="number" placeholder="Salary ($)" value={form.salary} onChange={e => setForm({...form, salary: e.target.value})} required style={{ padding: '10px' }} />
          <button type="submit" disabled={loading} style={{ gridColumn: 'span 2', padding: '12px', background: '#007bff', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}>
            {loading ? "Saving..." : "Add Employee"}
          </button>
        </form>
      </div>

      <div style={{ background: '#fff', padding: '20px', borderRadius: '8px', boxShadow: '0 2px 4px rgba(0,0,0,0.1)' }}>
        <h2>Employee Directory (DynamoDB)</h2>
        <table style={{ width: '100%', borderCollapse: 'collapse', marginTop: '15px' }}>
          <thead>
            <tr style={{ background: '#f1f1f1', textAlign: 'left' }}>
              <th style={{ padding: '10px', borderBottom: '2px solid #ddd' }}>ID</th>
              <th style={{ padding: '10px', borderBottom: '2px solid #ddd' }}>Name</th>
              <th style={{ padding: '10px', borderBottom: '2px solid #ddd' }}>Email</th>
              <th style={{ padding: '10px', borderBottom: '2px solid #ddd' }}>Department</th>
              <th style={{ padding: '10px', borderBottom: '2px solid #ddd' }}>Salary</th>
              <th style={{ padding: '10px', borderBottom: '2px solid #ddd' }}>Action</th>
            </tr>
          </thead>
          <tbody>
            {employees.length === 0 ? (
              <tr><td colSpan="6" style={{ textAlign: 'center', padding: '20px', color: '#888' }}>No employees found.</td></tr>
            ) : (
              employees.map(emp => (
                <tr key={emp.id} style={{ borderBottom: '1px solid #ddd' }}>
                  <td style={{ padding: '10px', fontSize: '12px', color: '#555' }}>{emp.id}</td>
                  <td style={{ padding: '10px' }}>{emp.name}</td>
                  <td style={{ padding: '10px' }}>{emp.email}</td>
                  <td style={{ padding: '10px' }}>{emp.department}</td>
                  <td style={{ padding: '10px' }}>${emp.salary.toLocaleString()}</td>
                  <td style={{ padding: '10px' }}>
                    <button onClick={() => handleDelete(emp.id)} style={{ background: '#dc3545', color: '#fff', border: 'none', padding: '6px 12px', borderRadius: '4px', cursor: 'pointer' }}>Delete</button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
export default App;
'@
Set-Content -Path "frontend\src\App.js" -Value $frontendAppJs -Encoding ascii

$frontendPkg = @"
{
  "name": "frontend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "axios": "^1.6.8",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build"
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  }
}
"@
Set-Content -Path "frontend\package.json" -Value $frontendPkg -Encoding ascii

$frontendDocker = @"
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
"@
Set-Content -Path "frontend\Dockerfile" -Value $frontendDocker -Encoding ascii


# 4. Create Docker Compose Orchestrator (Using LocalStack 3.7.0 Stable)
$dockerCompose = @"
services:
  localstack:
    image: localstack/localstack:3.7.0
    container_name: localstack
    ports:
      - "4566:4566"
    environment:
      - SERVICES=dynamodb

  backend:
    build: ./backend
    container_name: backend
    ports:
      - "8000:8000"
    environment:
      - AWS_ENDPOINT_URL=http://localstack:4566
    depends_on:
      - localstack

  frontend:
    build: ./frontend
    container_name: frontend
    ports:
      - "3000:3000"
    environment:
      - REACT_APP_API_URL=http://127.0.0.1:8000
    depends_on:
      - backend
"@
Set-Content -Path "docker-compose.yml" -Value $dockerCompose -Encoding ascii

# 5. Build and Deploy
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  🚀 Rebuilding and Deploying System..." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Green

docker-compose down -v
docker-compose up --build -d

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  🎉 System Deployed Successfully!" -ForegroundColor Green
Write-Host "  👉 Open Frontend UI: http://127.0.0.1:3000" -ForegroundColor Cyan
Write-Host "  👉 Backend API Docs: http://127.0.0.1:8000/docs" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Green