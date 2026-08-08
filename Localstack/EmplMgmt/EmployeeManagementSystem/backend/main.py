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
