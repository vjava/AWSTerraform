import streamlit as st
import pandas as pd
import json
import io
import os
from dotenv import load_dotenv

from databricks_mcp import (
    list_tables, 
    get_table_schema, 
    execute_sql_query, 
    get_table_insights_and_recommendations, 
    query_with_natural_language,
    detect_anomalies_and_outliers,
    generate_executive_summary_report,
    suggest_sql_optimizations_and_indexes,
    generate_dashboard_sql,
    generate_production_ready_notebook,
    automated_data_quality_tests,
    ml_feature_store_recommendation,
    execute_spark_code_snippet,
    create_databricks_notebook_via_api
)

load_dotenv()

st.set_page_config(page_title="Databricks DeepSeek Advanced MCP UI", page_icon="🧊", layout="wide")
st.title("🧊 Databricks Enterprise AI MCP Dashboard (Powered by DeepSeek)")
st.markdown("Explore tables, AI Architect insights, Natural Language queries, Notebook generation, Execution Sandbox, Data Quality, and Workspace Export.")

if not os.getenv("DATABRICKS_TOKEN"):
    st.error("⚠️ Environment variables (DATABRICKS_TOKEN, etc.) are missing. Please configure your .env file.")
    st.stop()

tab1, tab2, tab3, tab4, tab5, tab6, tab7, tab8, tab9, tab10, tab11, tab12 = st.tabs([
    "📋 List Tables", 
    "🔍 View Schema", 
    "⚡ Run Safe SQL", 
    "💡 AI Architect", 
    "💬 Natural Language",
    "🕵️‍♂️ Anomaly Detection",
    "📊 Executive Report",
    "🚀 Performance Optimizer",
    "📈 Executive Charts",
    "📓 Production Notebook & Run",
    "🛡️ Data Quality Tests",
    "🤖 ML Feature Store"
])

with tab1:
    st.subheader("Discover Tables")
    col1, col2 = st.columns(2)
    catalog = col1.text_input("Catalog", value="workspace")
    schema = col2.text_input("Schema", value="default")
    
    if st.button("Fetch Tables"):
        with st.spinner("Fetching tables..."):
            result_json = list_tables(catalog, schema)
            try:
                df = pd.read_json(io.StringIO(result_json))
                st.dataframe(df, use_container_width=True)
            except:
                st.error(result_json)

with tab2:
    st.subheader("Explore Table Schema")
    table_name_s = st.text_input("Full Table Name (Schema)", placeholder="workspace.default.raw_customer")
    
    if st.button("Get Schema"):
        if not table_name_s.strip():
            st.warning("⚠️ कृपया टेबल का नाम दर्ज करें!")
        else:
            with st.spinner("Retrieving schema..."):
                schema_info = get_table_schema(table_name_s)
                st.code(schema_info, language="text")

with tab3:
    st.subheader("Query Data (Guarded)")
    st.info("💡 Security Guardrail: Only SELECT queries permitted. LIMIT 100 auto-appended.")
    sql_query = st.text_area("SQL Query", placeholder="SELECT * FROM workspace.default.raw_customer")
    
    if st.button("Execute Query"):
        if not sql_query.strip():
            st.warning("⚠️ कृपया SQL क्वेरी दर्ज करें!")
        else:
            with st.spinner("Executing query..."):
                result_json = execute_sql_query(sql_query)
                try:
                    df = pd.read_json(io.StringIO(result_json))
                    st.dataframe(df, use_container_width=True)
                except:
                    st.error(result_json)

with tab4:
    st.subheader("💡 AI Table Insights & Architecture Advisor")
    table_name_i = st.text_input("Full Table Name (AI Architect)", placeholder="workspace.default.raw_customer")
    
    if st.button("Analyze Table"):
        if not table_name_i.strip():
            st.warning("⚠️ कृपया टेबल का नाम दर्ज करें!")
        else:
            with st.spinner("🤖 DeepSeek AI Architect profiling table..."):
                insights = get_table_insights_and_recommendations(table_name_i)
                st.markdown(insights)

with tab5:
    st.subheader("💬 Natural Language to Data Agent")
    table_name_nl = st.text_input("Target Table Name (NLP Query)", placeholder="workspace.default.raw_customer")
    user_question = st.text_input("Your Question in Plain English", placeholder="How many customers are in this table?")
    
    if st.button("Ask AI Agent"):
        if not table_name_nl.strip() or not user_question.strip():
            st.warning("⚠️ कृपया टेबल का नाम और प्रश्न दोनों भरें!")
        else:
            with st.spinner("🤖 Processing natural language query via DeepSeek..."):
                response_str = query_with_natural_language(table_name_nl, user_question)
                try:
                    resp_dict = json.loads(response_str)
                    st.markdown("### 📝 AI Answer:")
                    st.success(resp_dict.get("natural_language_answer"))
                    
                    with st.expander("🛠️ View Generated SQL Query"):
                        st.code(resp_dict.get("generated_sql"), language="sql")
                        
                    with st.expander("📊 View Raw Table Data"):
                        raw_d = resp_dict.get("raw_data")
                        if isinstance(raw_d, list) and len(raw_d) > 0:
                            st.dataframe(pd.DataFrame(raw_d), use_container_width=True)
                        else:
                            st.write(raw_d)
                except Exception as e:
                    st.error(f"Error: {e}")

with tab6:
    st.subheader("🕵️‍♂️ AI Anomaly & Outlier Detector")
    table_name_an = st.text_input("Full Table Name (Anomalies)", placeholder="workspace.default.raw_customer")
    
    if st.button("Detect Anomalies"):
        if not table_name_an.strip():
            st.warning("⚠️ कृपया टेबल का नाम दर्ज करें!")
        else:
            with st.spinner("🔍 Scanning records for outliers using DeepSeek..."):
                report = detect_anomalies_and_outliers(table_name_an)
                st.markdown(report)

with tab7:
    st.subheader("📊 Executive Business Summary Report")
    table_name_ex = st.text_input("Full Table Name (Executive Report)", placeholder="workspace.default.raw_customer")
    
    if st.button("Generate Executive Report"):
        if not table_name_ex.strip():
            st.warning("⚠️ कृपया टेबल का नाम दर्ज करें!")
        else:
            with st.spinner("📈 Compiling executive business summary..."):
                report = generate_executive_summary_report(table_name_ex)
                st.markdown(report)

with tab8:
    st.subheader("🚀 Databricks Performance & Indexing Optimizer")
    table_name_op = st.text_input("Full Table Name (Optimizer)", placeholder="workspace.default.raw_customer")
    
    if st.button("Get Optimization Suggestions"):
        if not table_name_op.strip():
            st.warning("⚠️ कृपया टेबल का नाम दर्ज करें!")
        else:
            with st.spinner("⚡ Analyzing partitioning and z-order strategies..."):
                suggestions = suggest_sql_optimizations_and_indexes(table_name_op)
                st.markdown(suggestions)

with tab9:
    st.subheader("📈 AI-Powered Executive Dashboard & Charts")
    table_name_ch = st.text_input("Target Table Name for Charts", placeholder="workspace.default.raw_customer")
    dashboard_goal = st.text_input("Dashboard Metric Goal", placeholder="Group by status and count total customers")
    
    if st.button("Generate Dashboard Charts"):
        if not table_name_ch.strip() or not dashboard_goal.strip():
            st.warning("⚠️ कृपया टेबल का नाम और डैशबोर्ड गोल दोनों दर्ज करें!")
        else:
            with st.spinner("📊 Generating aggregation query and rendering charts..."):
                agg_sql = generate_dashboard_sql(table_name_ch, dashboard_goal)
                result_json = execute_sql_query(agg_sql)
                
                try:
                    df_chart = pd.read_json(io.StringIO(result_json))
                    if not df_chart.empty and len(df_chart.columns) >= 2:
                        st.success("✅ Dashboard generated successfully!")
                        
                        with st.expander("🛠️ View Aggregation SQL Query"):
                            st.code(agg_sql, language="sql")
                            
                        label_col = df_chart.columns[0]
                        value_col = df_chart.columns[1]
                        
                        col_a, col_b = st.columns(2)
                        with col_a:
                            st.markdown("### 📊 Bar Chart View")
                            st.bar_chart(df_chart.set_index(label_col)[value_col])
                            
                        with col_b:
                            st.markdown("### 📈 Area Chart View")
                            st.area_chart(df_chart.set_index(label_col)[value_col])
                            
                        st.markdown("### 📋 Underlying Aggregated Data")
                        st.dataframe(df_chart, use_container_width=True)
                    else:
                        st.error("⚠️ The generated query did not return enough tabular columns.")
                        st.code(agg_sql, language="sql")
                except Exception as e:
                    st.error(f"Failed to render charts: {e}")

with tab10:
    st.subheader("📓 Production Notebook & Pipeline Execution")
    st.markdown("Generate a Databricks PySpark notebook code, execute test queries, or publish directly into your Databricks Workspace.")
    table_name_nb = st.text_input("Target Table Name for Notebook", placeholder="workspace.default.raw_customer")
    pipeline_goal = st.text_input("Pipeline Objective", placeholder="Select records or aggregate statistics from the table")
    
    if "generated_nb_code" not in st.session_state:
        st.session_state.generated_nb_code = ""

    if st.button("Generate Production Notebook"):
        if not table_name_nb.strip() or not pipeline_goal.strip():
            st.warning("⚠️ कृपया टेबल का नाम और पाइपलाइन का उद्देश्य दर्ज करें!")
        else:
            with st.spinner("🤖 Generating production-ready PySpark notebook code via DeepSeek..."):
                st.session_state.generated_nb_code = generate_production_ready_notebook(table_name_nb, pipeline_goal)
                st.success("✅ Notebook script generated successfully!")

    if st.session_state.generated_nb_code:
        st.markdown("### 📜 Generated Notebook Script:")
        st.markdown(st.session_state.generated_nb_code)
        
        st.markdown("---")
        st.subheader("☁️ Export & Create Notebook in Databricks Workspace")
        db_notebook_path = st.text_input("Databricks Notebook Workspace Path", value="/Workspace/Users/default_user/ai_generated_pipeline")
        
        if st.button("🚀 Create Notebook in Databricks Workspace"):
            with st.spinner("Creating notebook in Databricks via API..."):
                api_result = create_databricks_notebook_via_api(db_notebook_path, st.session_state.generated_nb_code)
                if "SUCCESS" in api_result:
                    st.success(api_result)
                    st.info("💡 अब आप अपने Databricks Workspace में जाकर इस नोटबुक को खोलकर सीधे रन कर सकते हैं!")
                else:
                    st.error(api_result)

        st.markdown("---")
        st.subheader("▶️ Execute Pipeline Test Query on Databricks")
        test_query = st.text_area("Enter verification SQL/Transform query to run on Databricks", value=f"SELECT * FROM {table_name_nb} LIMIT 10")
        
        if st.button("Run Pipeline on Databricks Cluster"):
            with st.spinner("⚙️ Executing pipeline snippet on Databricks..."):
                exec_result = execute_spark_code_snippet(test_query)
                
                if exec_result.strip().startswith("EXECUTION NOTICE") or exec_result.strip().startswith("Error") or exec_result.strip().startswith("SQL Execution Error"):
                    st.info(exec_result)
                else:
                    try:
                        df_exec = pd.read_json(io.StringIO(exec_result))
                        if not df_exec.empty:
                            st.success("✅ Pipeline Executed Successfully!")
                            st.dataframe(df_exec, use_container_width=True)
                        else:
                            st.warning("⚠️ The query executed successfully but returned zero rows.")
                    except Exception:
                        st.write(exec_result)

with tab11:
    st.subheader("🛡️ Automated Data Quality & Contracts Generator")
    table_name_dq = st.text_input("Target Table Name for Data Quality", placeholder="workspace.default.raw_customer")
    
    if st.button("Generate Data Quality Tests"):
        if not table_name_dq.strip():
            st.warning("⚠️ कृपया टेबल का नाम दर्ज करें!")
        else:
            with st.spinner("🛡️ Building automated data quality assertions..."):
                dq_tests = automated_data_quality_tests(table_name_dq)
                st.markdown(dq_tests)

with tab12:
    st.subheader("🤖 ML Feature Store Recommendation Engine")
    table_name_fs = st.text_input("Target Table Name for Feature Store", placeholder="workspace.default.raw_customer")
    
    if st.button("Generate Feature Store Spec"):
        if not table_name_fs.strip():
            st.warning("⚠️ कृपया टेबल का नाम दर्ज करें!")
        else:
            with st.spinner("🧠 Designing MLOps Feature Store schema..."):
                fs_spec = ml_feature_store_recommendation(table_name_fs)
                st.markdown(fs_spec)