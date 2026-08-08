import os
import json
import uuid
import io
import time
import pandas as pd
import requests
import psycopg2
from pgvector.psycopg2 import register_vector
import boto3
from botocore.exceptions import ClientError
import streamlit as st
from pypdf import PdfReader

# ReportLab imports for PDF audit report generation
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors

# ==============================================================================
# 1. Configuration Setup
# ==============================================================================
LOCALSTACK_ENDPOINT = os.getenv("LOCALSTACK_ENDPOINT", "http://localhost:4566")
DYNAMODB_TABLE = "AgentChatHistory"

KODEKLOUD_URL = os.getenv("KODEKLOUD_URL", "https://api.ai.kodekloud.com")
KODEKLOUD_API_KEY = os.getenv("KODEKLOUD_API_KEY", "password")
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434")
EMBEDDING_MODEL = "nomic-embed-text"
LLM_MODEL = "google/gemini-3.1-flash-lite"

PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = int(os.getenv("PG_PORT", "5433"))
PG_DB = os.getenv("PG_DB", "vectordb")
PG_USER = os.getenv("PG_USER", "aiuser")
PG_PASSWORD = os.getenv("PG_PASSWORD", "Password123")

# ==============================================================================
# 2. Database Handler (PGVector with GIN & HNSW Indexing)
# ==============================================================================
class HybridPGVectorDB:
    def __init__(self):
        self.conn = None
        self.connect()

    def connect(self):
        """Establishes connection to PostgreSQL database on Docker (Port 5433)."""
        try:
            self.conn = psycopg2.connect(
                host=PG_HOST,
                port=PG_PORT,
                dbname=PG_DB,
                user=PG_USER,
                password=PG_PASSWORD
            )
            self.conn.autocommit = True
            register_vector(self.conn)
            self._setup_schema()
        except Exception as e:
            st.error(f"❌ PostgreSQL Connection Error: {e}")

    def _setup_schema(self):
        """Configures PGVector extension, schemas, and performance indexes."""
        if not self.conn:
            return
        with self.conn.cursor() as cur:
            # 1. Enable PGVector extension
            cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
            
            # 2. Base table schema
            cur.execute("""
                CREATE TABLE IF NOT EXISTS document_embeddings (
                    id SERIAL PRIMARY KEY,
                    document_name VARCHAR(255),
                    chunk_text TEXT,
                    embedding vector(768)
                );
            """)
            
            # 3. Full-Text Search tsvector generated column
            cur.execute("""
                DO $$ 
                BEGIN 
                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns 
                        WHERE table_name='document_embeddings' AND column_name='fts_doc'
                    ) THEN
                        ALTER TABLE document_embeddings 
                        ADD COLUMN fts_doc tsvector GENERATED ALWAYS AS (to_tsvector('english', chunk_text)) STORED;
                    END IF;
                END $$;
            """)
            
            # 4. GIN Index for keyword full-text search
            cur.execute("CREATE INDEX IF NOT EXISTS fts_idx ON document_embeddings USING gin(fts_doc);")
            
            # 5. HNSW Index for high-performance Cosine Distance vector search
            cur.execute("""
                CREATE INDEX IF NOT EXISTS embedding_hnsw_idx 
                ON document_embeddings USING hnsw (embedding vector_cosine_ops);
            """)

    def insert_chunk(self, doc_name: str, chunk_text: str, embedding: list) -> bool:
        """Inserts text chunk and vector embedding into database."""
        if not self.conn:
            return False
        try:
            with self.conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO document_embeddings (document_name, chunk_text, embedding) VALUES (%s, %s, %s);",
                    (doc_name, chunk_text, embedding)
                )
            return True
        except Exception as e:
            st.error(f"Error inserting chunk: {e}")
            return False

    def hybrid_search(self, query: str, query_vector: list, top_k: int = 3) -> list:
        """Executes Reciprocal Rank Fusion (RRF) combining Full-Text Keyword and Vector search."""
        if not self.conn:
            return []
        try:
            with self.conn.cursor() as cur:
                sql_query = """
                    WITH vector_search AS (
                        SELECT id, chunk_text, ROW_NUMBER() OVER (ORDER BY embedding <=> %s::vector) AS rank
                        FROM document_embeddings LIMIT 10
                    ),
                    text_search AS (
                        SELECT id, chunk_text, ROW_NUMBER() OVER (ORDER BY ts_rank(fts_doc, plainto_tsquery('english', %s)) DESC) AS rank
                        FROM document_embeddings WHERE fts_doc @@ plainto_tsquery('english', %s) LIMIT 10
                    )
                    SELECT COALESCE(v.chunk_text, t.chunk_text) AS content,
                           (COALESCE(1.0 / (60 + v.rank), 0.0) + COALESCE(1.0 / (60 + t.rank), 0.0)) AS rrf_score
                    FROM vector_search v
                    FULL OUTER JOIN text_search t ON v.id = t.id
                    ORDER BY rrf_score DESC LIMIT %s;
                """
                cur.execute(sql_query, (query_vector, query, query, top_k))
                results = cur.fetchall()
                return [row[0] for row in results]
        except Exception as e:
            st.error(f"Hybrid search failed: {e}")
            return []

# ==============================================================================
# 3. Helper Services (Ollama, LocalStack, LLM Gateway)
# ==============================================================================
def get_ollama_embedding(text: str) -> list:
    """Fetches 768-dimensional embeddings from local Ollama service."""
    try:
        response = requests.post(
            f"{OLLAMA_URL}/api/embeddings",
            json={"model": EMBEDDING_MODEL, "prompt": text},
            timeout=15
        )
        response.raise_for_status()
        return response.json().get("embedding", [])
    except Exception as e:
        st.error(f"⚠️ Ollama Service Error: Ensure 'ollama serve' is running on http://localhost:11434. Detail: {e}")
        return []

def execute_kodekloud_llm(prompt: str, system_prompt: str = "You are a helpful AI assistant.") -> str:
    """Sends completions request to Cloud LLM Gateway API."""
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
            ]
        }
        res = requests.post(endpoint, json=payload, headers=headers, timeout=60)
        res.raise_for_status()
        return res.json()["choices"][0]["message"]["content"]
    except Exception as e:
        return f"❌ LLM Invocation Error: {e}"

def get_dynamo_table():
    """Returns LocalStack DynamoDB Table instance, creating it safely only if absent."""
    try:
        dynamo = boto3.resource(
            "dynamodb",
            endpoint_url=LOCALSTACK_ENDPOINT,
            aws_access_key_id="test",
            aws_secret_access_key="test",
            region_name="us-east-1"
        )
        table = dynamo.Table(DYNAMODB_TABLE)
        try:
            # Check if table already exists to avoid 400 ResourceInUseException spam
            table.load()
            return table
        except ClientError as ce:
            if ce.response['Error']['Code'] == 'ResourceNotFoundException':
                table = dynamo.create_table(
                    TableName=DYNAMODB_TABLE,
                    KeySchema=[
                        {'AttributeName': 'SessionId', 'KeyType': 'HASH'},
                        {'AttributeName': 'Timestamp', 'KeyType': 'RANGE'}
                    ],
                    AttributeDefinitions=[
                        {'AttributeName': 'SessionId', 'AttributeType': 'S'},
                        {'AttributeName': 'Timestamp', 'AttributeType': 'S'}
                    ],
                    BillingMode='PAY_PER_REQUEST'
                )
                time.sleep(1)
                return table
            else:
                raise ce
    except Exception as e:
        st.error(f"LocalStack DynamoDB Error: {e}")
        return None

def log_to_dynamodb(session_id: str, action: str, status: str):
    """Logs action audit events to LocalStack DynamoDB."""
    table = get_dynamo_table()
    if table:
        try:
            table.put_item(Item={
                "SessionId": session_id,
                "Timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "ActionLog": action,
                "Status": status
            })
        except Exception as e:
            st.warning(f"Audit log writing failed: {e}")

def generate_pdf_report(logs_data: list) -> bytes:
    """Generates styled PDF audit log report using ReportLab."""
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=letter)
    styles = getSampleStyleSheet()
    story = []

    title_style = ParagraphStyle(
        'TitleStyle',
        parent=styles['Heading1'],
        fontSize=18,
        textColor=colors.HexColor('#1E3A8A'),
        spaceAfter=12
    )
    story.append(Paragraph("LocalStack DynamoDB Audit Log Report", title_style))
    story.append(Spacer(1, 12))

    table_data = [["Session ID", "Timestamp", "Action Log", "Status"]]
    for item in logs_data:
        table_data.append([
            str(item.get("SessionId", "")),
            str(item.get("Timestamp", "")),
            str(item.get("ActionLog", ""))[:45] + "...",
            str(item.get("Status", ""))
        ])

    table = Table(table_data, colWidths=[80, 110, 210, 100])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1E3A8A')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 8),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.grey)
    ]))
    story.append(table)

    doc.build(story)
    buffer.seek(0)
    return buffer.getvalue()

# ==============================================================================
# 4. Multi-Agent Orchestrator
# ==============================================================================
class OrchestratorAgent:
    def __init__(self, db: HybridPGVectorDB):
        self.db = db

    def classify_intent(self, user_query: str) -> str:
        """Determines execution intent using lightweight LLM routing."""
        prompt = (
            f"Classify the following query into exactly ONE category:\n"
            f"- CODE_GEN: Programming, scripts, code fixes, algorithms.\n"
            f"- ANALYTICS_SQL: Database analytics, metrics, cluster status, numerical data.\n"
            f"- DOCUMENT_RAG: Context, document lookup, uploaded PDF questions.\n"
            f"- GENERAL_CHAT: Casual chat, general knowledge.\n\n"
            f"User Query: '{user_query}'\n\n"
            f"Return ONLY the category name."
        )
        intent = execute_kodekloud_llm(prompt, "You are an intent classification router.")
        intent_clean = intent.strip().upper()
        
        for category in ["CODE_GEN", "ANALYTICS_SQL", "DOCUMENT_RAG", "GENERAL_CHAT"]:
            if category in intent_clean:
                return category
        return "GENERAL_CHAT"

    def execute_code_agent(self, query: str) -> str:
        """Handles code generation with syntax highlighting."""
        system_prompt = "You are an expert Lead Software Engineer. Provide complete, syntax-highlighted code and clear technical explanations."
        return execute_kodekloud_llm(query, system_prompt)

    def execute_rag_agent(self, query: str) -> str:
        """Executes Hybrid Vector Search and synthesizes answer."""
        query_vector = get_ollama_embedding(query)
        if not query_vector:
            return "❌ Unable to generate query embeddings via local Ollama service."
        
        chunks = self.db.hybrid_search(query, query_vector, top_k=3)
        context = "\n---\n".join(chunks) if chunks else "No relevant context found in database."
        
        system_prompt = "You are a Document RAG Assistant. Answer the question strictly using the provided context."
        prompt = f"Context:\n{context}\n\nQuestion: {query}"
        return execute_kodekloud_llm(prompt, system_prompt)

    def execute_analytics_agent(self, query: str) -> str:
        """Executes Databricks SQL Warehouse analytical tool."""
        mock_analytics = {
            "total_documents_processed": 142,
            "avg_embedding_latency_ms": 45,
            "top_queried_service": "AWS LocalStack Lambda",
            "cluster_status": "SERVERLESS_ACTIVE",
            "active_nodes": 4
        }
        context = json.dumps(mock_analytics, indent=2)
        system_prompt = "You are a Data Analytics Specialist. Summarize performance metrics cleanly."
        prompt = f"Metrics Data:\n{context}\n\nUser Request: {query}"
        return execute_kodekloud_llm(prompt, system_prompt)

# ==============================================================================
# 5. Streamlit User Interface
# ==============================================================================
st.set_page_config(page_title="Multi-Agent Responsive Platform", page_icon="🤖", layout="wide")

st.title("🤖 Autonomous Multi-Agent Responsive Platform")
st.caption("100% Free Stack: Streamlit + PGVector (Docker 5433) + LocalStack + Ollama + KodeKloud LLM")

# Initialize Session State
if "messages" not in st.session_state:
    st.session_state.messages = []
if "pending_action" not in st.session_state:
    st.session_state.pending_action = None
if "session_id" not in st.session_state:
    st.session_state.session_id = str(uuid.uuid4())[:8]

db = HybridPGVectorDB()
orchestrator = OrchestratorAgent(db)

# ------------------------------------------------------------------------------
# Sidebar Controls
# ------------------------------------------------------------------------------
with st.sidebar:
    st.header("📄 PDF Document Ingestion")
    uploaded_file = st.file_uploader("Upload Multi-Page PDF to PGVector", type=["pdf"])
    
    if uploaded_file is not None:
        if st.button("⚡ Process & Ingest PDF"):
            with st.spinner("Extracting text and generating embeddings..."):
                try:
                    pdf_reader = PdfReader(uploaded_file)
                    total_chunks = 0
                    
                    for page_num, page in enumerate(pdf_reader.pages):
                        text = page.extract_text()
                        lines = [line.strip() for line in text.split("\n") if line.strip()]
                        
                        for line in lines:
                            if len(line) > 20:
                                emb = get_ollama_embedding(line)
                                if emb:
                                    if db.insert_chunk(uploaded_file.name, line, emb):
                                        total_chunks += 1
                                        
                    st.success(f"Ingested {total_chunks} chunks into PGVector from '{uploaded_file.name}'!")
                    log_to_dynamodb(st.session_state.session_id, f"Uploaded PDF: {uploaded_file.name}", "COMPLETED")
                except Exception as e:
                    st.error(f"Failed to process PDF: {e}")

    st.markdown("---")
    st.header("⚙️ Audit Logs & Exports")
    
    if st.button("Fetch LocalStack DynamoDB Logs"):
        table = get_dynamo_table()
        if table:
            try:
                scan_res = table.scan()
                items = scan_res.get("Items", [])
                st.session_state.logs = items
            except Exception as e:
                st.error(f"Error reading logs: {e}")

    if "logs" in st.session_state and st.session_state.logs:
        df_logs = pd.DataFrame(st.session_state.logs)
        st.dataframe(df_logs, height=200)

        col_a, col_b = st.columns(2)
        with col_a:
            csv_bytes = df_logs.to_csv(index=False).encode('utf-8')
            st.download_button("📥 Export CSV", data=csv_bytes, file_name="audit_logs.csv", mime="text/csv")
        with col_b:
            pdf_bytes = generate_pdf_report(st.session_state.logs)
            st.download_button("📄 Export PDF Report", data=pdf_bytes, file_name="audit_report.pdf", mime="application/pdf")

# ------------------------------------------------------------------------------
# Main Chat & Orchestration Workflow
# ------------------------------------------------------------------------------
for msg in st.session_state.messages:
    with st.chat_message(msg["role"]):
        st.markdown(msg["content"])

user_input = st.chat_input("Ask anything (e.g., Python code, PDF context, cluster metrics)...")

if user_input:
    st.session_state.messages.append({"role": "user", "content": user_input})
    with st.chat_message("user"):
        st.markdown(user_input)

    # Classify User Intent
    with st.spinner("🤖 Orchestrator analyzing request intent..."):
        intent = orchestrator.classify_intent(user_input)

    if intent == "ANALYTICS_SQL":
        # Pause execution for Human-in-the-Loop (HITL) Approval
        st.session_state.pending_action = {
            "query": user_input,
            "type": "ANALYTICS_SQL",
            "details": f"Execute Databricks SQL Warehouse Tool for query: '{user_input}'"
        }
        st.rerun()

    else:
        with st.chat_message("assistant"):
            with st.spinner(f"Routing to Specialized Sub-Agent ({intent})..."):
                if intent == "CODE_GEN":
                    response = orchestrator.execute_code_agent(user_input)
                elif intent == "DOCUMENT_RAG":
                    response = orchestrator.execute_rag_agent(user_input)
                else:
                    response = execute_kodekloud_llm(user_input)

                st.markdown(response)
                st.session_state.messages.append({"role": "assistant", "content": response})
                log_to_dynamodb(st.session_state.session_id, f"Agent Executed ({intent})", "COMPLETED")

# ------------------------------------------------------------------------------
# Human-in-the-Loop (HITL) Guardrail UI Banner
# ------------------------------------------------------------------------------
if st.session_state.pending_action:
    st.warning("⚠️ **Human-in-the-Loop Approval Required**")
    st.write(f"**Action Requested:** {st.session_state.pending_action['details']}")
    
    col1, col2 = st.columns(2)
    with col1:
        if st.button("✅ Approve Action"):
            with st.chat_message("assistant"):
                with st.spinner("Executing approved Databricks SQL Warehouse Tool..."):
                    response = orchestrator.execute_analytics_agent(st.session_state.pending_action['query'])
                    st.markdown(response)
                    st.session_state.messages.append({"role": "assistant", "content": response})
                    log_to_dynamodb(st.session_state.session_id, "Databricks SQL Execution", "HUMAN_APPROVED")

            st.session_state.pending_action = None
            st.rerun()

    with col2:
        if st.button("❌ Reject Action"):
            rejection_msg = "❌ Action execution rejected by user guardrail."
            st.error(rejection_msg)
            st.session_state.messages.append({"role": "assistant", "content": rejection_msg})
            log_to_dynamodb(st.session_state.session_id, "Databricks SQL Execution", "HUMAN_REJECTED")

            st.session_state.pending_action = None
            st.rerun()