import os
import re
import json
import base64
import requests
import pandas as pd
from dotenv import load_dotenv
from databricks import sql
from databricks.sdk import WorkspaceClient
from databricks.sdk.service import workspace
from mcp.server.fastmcp import FastMCP

load_dotenv()

mcp = FastMCP("Databricks-Advanced")

KODEKLOUD_URL = os.getenv("KODEKLOUD_URL", "https://api.ai.kodekloud.com")
KODEKLOUD_API_KEY = os.getenv("KODEKLOUD_API_KEY", "YOUR_API_PASSWORD")
LLM_MODEL = "deepseek/deepseek-v4-flash"

def call_llm(prompt: str, system_prompt: str) -> str:
    try:
        endpoint = f"{KODEKLOUD_URL}/v1/chat/completions"
        headers = {
            "Authorization": f"Bearer {KODEKLOUD_API_KEY}",
            "Content-Type": "application/json"
        }
        payload = {
            "model": LLM_MODEL,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt}
            ],
            "temperature": 0.2
        }
        res = requests.post(endpoint, json=payload, headers=headers, timeout=60)
        res.raise_for_status()
        return res.json()["choices"][0]["message"]["content"].strip()
    except Exception as e:
        return f"LLM Error: {e}"

def get_db_connection():
    try:
        connection = sql.connect(
            server_hostname=os.getenv("DATABRICKS_SERVER_HOSTNAME"),
            http_path=os.getenv("DATABRICKS_HTTP_PATH"),
            access_token=os.getenv("DATABRICKS_TOKEN")
        )
        return connection
    except Exception as e:
        raise RuntimeError(f"Database connection failed: {e}")

@mcp.tool()
def list_tables(catalog: str = "workspace", schema: str = "default") -> str:
    query = f"SHOW TABLES IN {catalog}.{schema};"
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(query)
        rows = cursor.fetchall()
        columns = [desc[0] for desc in cursor.description]
        df = pd.DataFrame(rows, columns=columns)
        cursor.close()
        conn.close()
        return df.to_json(orient="records", indent=2)
    except Exception as e:
        return f"Error listing tables: {str(e)}"

@mcp.tool()
def get_table_schema(table_name: str) -> str:
    query = f"DESCRIBE {table_name};"
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(query)
        rows = cursor.fetchall()
        columns = [desc[0] for desc in cursor.description]
        df = pd.DataFrame(rows, columns=columns)
        cursor.close()
        conn.close()
        schema_info = [f"{row['col_name']} ({row['data_type']})" for _, row in df.iterrows()]
        return "Columns:\n" + "\n".join(schema_info)
    except Exception as e:
        return f"Error retrieving schema for {table_name}: {str(e)}"

@mcp.tool()
def execute_sql_query(query: str) -> str:
    if not re.match(r"^\s*SELECT", query, re.IGNORECASE):
        return "SECURITY ERROR: Only SELECT queries are permitted."
    
    clean_query = query.strip().rstrip(";")
    if not re.search(r"\bLIMIT\b", clean_query, re.IGNORECASE):
        clean_query = f"{clean_query} LIMIT 100"
        
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(clean_query)
        rows = cursor.fetchall()
        columns = [desc[0] for desc in cursor.description]
        df = pd.DataFrame(rows, columns=columns)
        cursor.close()
        conn.close()
        return df.to_json(orient="records", indent=2)
    except Exception as e:
        return f"SQL Execution Error: {str(e)}"

@mcp.tool()
def get_table_insights_and_recommendations(table_name: str) -> str:
    schema_desc = get_table_schema(table_name)
    if "Error" in schema_desc:
        return f"Could not fetch insights: {schema_desc}"
    sample_data_json = execute_sql_query(f"SELECT * FROM {table_name} LIMIT 5")
    system_prompt = "You are an expert Enterprise Data Architect and ML Engineer. Analyze schema and sample data."
    user_prompt = f"Table Name: {table_name}\n\nSchema:\n{schema_desc}\n\nSample Data:\n{sample_data_json}"
    return call_llm(user_prompt, system_prompt)

@mcp.tool()
def query_with_natural_language(table_name: str, natural_language_question: str) -> str:
    schema_desc = get_table_schema(table_name)
    if "Error" in schema_desc:
        return json.dumps({"error": schema_desc})
    sql_system_prompt = "You are a Databricks SQL Expert. Write ONLY a valid SQL SELECT query with LIMIT 100. No markdown."
    sql_prompt = f"Table: {table_name}\nSchema: {schema_desc}\nQuestion: {natural_language_question}"
    generated_sql = call_llm(sql_prompt, sql_system_prompt).replace("```sql", "").replace("```", "").strip()
    
    result_json = execute_sql_query(generated_sql)
    if any(result_json.startswith(err) for err in ["Error", "SECURITY ERROR", "SQL Execution Error", "LLM Error"]):
        return json.dumps({"generated_sql": generated_sql, "natural_language_answer": f"Failed: {result_json}", "raw_data": result_json}, indent=2)
    
    try:
        parsed_data = json.loads(result_json)
    except Exception:
        parsed_data = result_json

    summary_system_prompt = "You are a professional Data Analyst. Summarize the query results into a clear answer."
    summary_prompt = f"Question: {natural_language_question}\nSQL Used: {generated_sql}\nData Result: {result_json}"
    final_answer = call_llm(summary_prompt, summary_system_prompt)
    
    return json.dumps({
        "generated_sql": generated_sql,
        "natural_language_answer": final_answer,
        "raw_data": parsed_data
    }, indent=2)

@mcp.tool()
def detect_anomalies_and_outliers(table_name: str) -> str:
    schema_desc = get_table_schema(table_name)
    if "Error" in schema_desc:
        return schema_desc
    sample_data_json = execute_sql_query(f"SELECT * FROM {table_name} LIMIT 20")
    return call_llm(f"Table Name: {table_name}\nSchema:\n{schema_desc}\nSample Data:\n{sample_data_json}", "You are a Data Quality Engineer. Identify anomalies.")

@mcp.tool()
def generate_executive_summary_report(table_name: str) -> str:
    schema_desc = get_table_schema(table_name)
    if "Error" in schema_desc:
        return schema_desc
    sample_data_json = execute_sql_query(f"SELECT * FROM {table_name} LIMIT 15")
    return call_llm(f"Table Name: {table_name}\nSchema:\n{schema_desc}\nSample Records:\n{sample_data_json}", "You are a Chief Data Officer. Create an Executive Summary Report.")

@mcp.tool()
def suggest_sql_optimizations_and_indexes(table_name: str) -> str:
    schema_desc = get_table_schema(table_name)
    if "Error" in schema_desc:
        return schema_desc
    return call_llm(f"Table Name: {table_name}\nSchema:\n{schema_desc}", "You are a Databricks Performance Expert. Recommend Partitioning and Z-Order.")

@mcp.tool()
def generate_dashboard_sql(table_name: str, metric_goal: str) -> str:
    schema_desc = get_table_schema(table_name)
    if "Error" in schema_desc:
        return schema_desc
    prompt = f"Table: {table_name}\nSchema: {schema_desc}\nDashboard Goal: {metric_goal}"
    return call_llm(prompt, "Write ONLY a valid SQL query with GROUP BY and aggregation for charts. No markdown.").replace("```sql", "").replace("```", "").strip()

@mcp.tool()
def generate_production_ready_notebook(table_name: str, pipeline_objective: str) -> str:
    schema_desc = get_table_schema(table_name)
    if "Error" in schema_desc:
        return schema_desc
    prompt = f"Target Table: {table_name}\nSchema:\n{schema_desc}\nPipeline Objective: {pipeline_objective}"
    return call_llm(prompt, "Create a production-ready PySpark notebook script for Databricks with error handling and logging. Return inside Python markdown code block.")

@mcp.tool()
def automated_data_quality_tests(table_name: str) -> str:
    schema_desc = get_table_schema(table_name)
    if "Error" in schema_desc:
        return schema_desc
    return call_llm(f"Table Name: {table_name}\nSchema:\n{schema_desc}", "Generate automated Data Quality checks (non-null, unique, range) using PySpark/SQL.")

@mcp.tool()
def ml_feature_store_recommendation(table_name: str) -> str:
    schema_desc = get_table_schema(table_name)
    if "Error" in schema_desc:
        return schema_desc
    return call_llm(f"Table Name: {table_name}\nSchema:\n{schema_desc}", "Analyze table schema and design a Databricks Feature Store specification.")

@mcp.tool()
def execute_spark_code_snippet(sql_or_transform_query: str) -> str:
    clean_query = sql_or_transform_query.strip()
    if not re.match(r"^\s*SELECT", clean_query, re.IGNORECASE):
        if re.match(r"^\s*(DESCRIBE|SHOW)\b", clean_query, re.IGNORECASE):
            try:
                conn = get_db_connection()
                cursor = conn.cursor()
                cursor.execute(clean_query)
                rows = cursor.fetchall()
                columns = [desc[0] for desc in cursor.description]
                df = pd.DataFrame(rows, columns=columns)
                cursor.close()
                conn.close()
                return df.to_json(orient="records", indent=2)
            except Exception as e:
                return f"Execution Error: {str(e)}"
        return f"EXECUTION NOTICE: Non-SELECT statements are restricted in sandbox query test."
    return execute_sql_query(clean_query)

@mcp.tool()
def create_databricks_notebook_via_api(notebook_path: str, notebook_content: str) -> str:
    """
    Creates a notebook directly inside the user's Databricks Workspace using the Databricks SDK.
    """
    try:
        w = WorkspaceClient(
            host=os.getenv("DATABRICKS_SERVER_HOSTNAME"),
            token=os.getenv("DATABRICKS_TOKEN")
        )
        encoded_content = base64.b64encode(notebook_content.encode('utf-8')).decode('utf-8')
        w.workspace.import_(
            path=notebook_path,
            format=workspace.ImportFormat.SOURCE,
            language=workspace.Language.PYTHON,
            content=encoded_content,
            overwrite=True
        )
        return f"SUCCESS: Notebook successfully created and saved in Databricks workspace at path: {notebook_path}"
    except Exception as e:
        return f"Failed to create notebook in Databricks: {str(e)}"

if __name__ == "__main__":
    mcp.run()