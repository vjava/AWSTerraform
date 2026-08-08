import os
import re
import pandas as pd
from dotenv import load_dotenv
from databricks import sql
from mcp.server.fastmcp import FastMCP

# Load environment variables
load_dotenv()

# Initialize FastMCP Server
mcp = FastMCP("Databricks")

def get_db_connection():
    """Establishes a robust connection to Databricks SQL."""
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
    """
    Returns a list of available tables in the specified catalog and schema.
    """
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
    """
    Returns the column names and data types for a specific table.
    """
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
        
        # Format cleanly for the LLM
        schema_info = [f"{row['col_name']} ({row['data_type']})" for _, row in df.iterrows()]
        return "Columns:\n" + "\n".join(schema_info)
    except Exception as e:
        return f"Error retrieving schema for {table_name}: {str(e)}"

@mcp.tool()
def execute_sql_query(query: str) -> str:
    """
    Executes a raw SQL SELECT query against the Databricks database.
    """
    # Security Guardrail: Reject non-SELECT queries
    if not re.match(r"^\s*SELECT", query, re.IGNORECASE):
        return "SECURITY ERROR: Only SELECT queries are permitted. Modifying data is blocked."
    
    # Clean up trailing semicolons and whitespace so LIMIT 100 appends correctly
    clean_query = query.strip().rstrip(";")
    
    # Performance Guardrail: Append LIMIT 100 if no limit exists
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
        return f"SQL Execution Error: {str(e)}. Please correct your SQL syntax and try again."

if __name__ == "__main__":
    # Start the standard input/output MCP server
    mcp.run()