import streamlit as st
import pandas as pd
import json
import os
from dotenv import load_dotenv

# Import the MCP tools directly from your server script
from databricks_mcp import list_tables, get_table_schema, execute_sql_query

load_dotenv()

st.set_page_config(page_title="Databricks MCP UI", page_icon="🧊", layout="wide")
st.title("🧊 Databricks MCP Server Dashboard")
st.markdown("UI interface to interact with your local Databricks MCP tools.")

# Authentication Check
if not os.getenv("DATABRICKS_TOKEN"):
    st.error("⚠️ Environment variables (DATABRICKS_TOKEN, etc.) are missing. Please configure your .env file.")
    st.stop()

tab1, tab2, tab3 = st.tabs(["📋 List Tables", "🔍 View Schema", "⚡ Run Safe SQL"])

with tab1:
    st.subheader("Discover Tables")
    col1, col2 = st.columns(2)
    catalog = col1.text_input("Catalog", value="workspace")
    schema = col2.text_input("Schema", value="default")
    
    if st.button("Fetch Tables"):
        with st.spinner("Calling MCP Tool: list_tables..."):
            result_json = list_tables(catalog, schema)
            try:
                df = pd.read_json(result_json)
                st.dataframe(df, use_container_width=True)
            except:
                st.error(result_json)

with tab2:
    st.subheader("Explore Table Schema")
    table_name = st.text_input("Full Table Name", placeholder="workspace.default.my_table")
    
    if st.button("Get Schema"):
        with st.spinner("Calling MCP Tool: get_table_schema..."):
            schema_info = get_table_schema(table_name)
            st.code(schema_info, language="text")

with tab3:
    st.subheader("Query Data (Guarded)")
    st.info("💡 Security Guardrail: Only SELECT queries are permitted. LIMIT 100 is auto-appended.")
    sql_query = st.text_area("SQL Query", placeholder="SELECT * FROM workspace.default.my_table")
    
    if st.button("Execute Query"):
        with st.spinner("Calling MCP Tool: execute_sql_query..."):
            result_json = execute_sql_query(sql_query)
            try:
                df = pd.read_json(result_json)
                st.dataframe(df, use_container_width=True)
            except:
                if "ERROR" in result_json.upper():
                    st.error(result_json)
                else:
                    st.write(result_json)