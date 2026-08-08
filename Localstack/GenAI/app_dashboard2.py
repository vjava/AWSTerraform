import streamlit as st
import json
import boto3
import requests
import psycopg2
from pgvector.psycopg2 import register_vector
import uuid
import pandas as pd
from pypdf import PdfReader
import io

# ReportLab imports for PDF generation
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors

# ==============================================================================
# 1. Configuration Setup
# ==============================================================================
LOCALSTACK_ENDPOINT = "http://localhost:4566"
DYNAMODB_TABLE = "AgentChatHistory"

KODEKLOUD_URL = "https://api.ai.kodekloud.com"
KODEKLOUD_API_KEY = "password"  # Replace with your KodeKloud API key/password
OLLAMA_URL = "http://localhost:11434"
EMBEDDING_MODEL = "nomic-embed-text"
LLM_MODEL = "google/gemini-3.1-flash-lite"

PG_HOST = "localhost"
PG_PORT = 5433
PG_DB = "vectordb"
PG_USER = "aiuser"
PG_PASSWORD = "Password123"

# ==============================================================================
# 2. Database & AWS Setup
# ==============================================================================
class HybridPGVectorDB:
    def __init__(self):
        self.conn = psycopg2.connect(
            host=PG_HOST, port=PG_PORT, dbname=PG_DB, user=PG_USER, password=PG_PASSWORD
        )
        self.conn.autocommit = True
        register_vector(self.conn)
        self._setup_schema()

    def _setup_schema(self):
        """Sets up PGVector extension, table, full-text tsvector column, GIN index, and HNSW vector index."""
        with self.conn.cursor() as cur:
            # 1. Enable PGVector extension
            cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
            
            # 2. Create base table
            cur.execute("""
                CREATE TABLE IF NOT EXISTS document_embeddings (
                    id SERIAL PRIMARY KEY,
                    document_name VARCHAR(255),
                    chunk_text TEXT,
                    embedding vector(768)
                );
            """)
            
            # 3. Add generated tsvector column for Full-Text Search if missing
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
            
            # 4. GIN Index for Full-Text Keyword Search
            cur.execute("CREATE INDEX IF NOT EXISTS fts_idx ON document_embeddings USING gin(fts_doc);")
            
            # 5. HNSW Index for High-Performance Cosine Distance Vector Search
            cur.execute("""
                CREATE INDEX IF NOT EXISTS embedding_hnsw_idx 
                ON document_embeddings USING hnsw (embedding vector_cosine_ops);
            """)
            print("[PGVector DB] Schema initialized with GIN and HNSW Indexes.")

    def insert_chunk(self, doc_name: str, chunk_text: str, embedding: list):
        with self.conn.cursor() as cur:
            cur.execute(
                "INSERT INTO document_embeddings (document_name, chunk_text, embedding) VALUES (%s, %s, %s);",
                (doc_name, chunk_text, embedding)
            )

    def hybrid_search(self, query: str, query_vector: list, top_k: int = 2) -> list:
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

def get_dynamo_resource():
    dynamo = boto3.resource("dynamodb", endpoint_url=LOCALSTACK_ENDPOINT, aws_access_key_id="test", aws_secret_access_key="test", region_name="us-east-1")
    try:
        dynamo.create_table(
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
    except Exception:
        pass
    return dynamo

# ==============================================================================
# 3. PDF Generator Utility Function
# ==============================================================================
def generate_pdf_report(logs_data):
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
            str(item.get("ActionLog", ""))[:40] + "...",
            str(item.get("Status", ""))
        ])

    table = Table(table_data, colWidths=[80, 120, 200, 100])
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
# 4. Streamlit Application
# ==============================================================================
st.set_page_config(page_title="Multi-Tool Agentic AI Dashboard", page_icon="🤖", layout="wide")

st.title("🤖 Multi-Tool Agentic AI Dashboard")
st.subheader("PDF Ingestion + PGVector Hybrid Search + Databricks SQL + Audit Log Export")

if "messages" not in st.session_state:
    st.session_state.messages = []
if "pending_action" not in st.session_state:
    st.session_state.pending_action = None

db = HybridPGVectorDB()
dynamo = get_dynamo_resource()

# Sidebar Setup
with st.sidebar:
    st.header("📄 PDF Document Processor")
    uploaded_file = st.file_uploader("Upload PDF Document to PGVector", type=["pdf"])
    
    if uploaded_file is not None:
        if st.button("⚡ Process & Ingest PDF"):
            with st.spinner("Extracting text and generating embeddings..."):
                pdf_reader = PdfReader(uploaded_file)
                total_chunks = 0
                
                for page_num, page in enumerate(pdf_reader.pages):
                    text = page.extract_text()
                    lines = [line.strip() for line in text.split("\n") if line.strip()]
                    
                    for line in lines:
                        if len(line) > 20:
                            res = requests.post(
                                f"{OLLAMA_URL}/api/embeddings",
                                json={"model": EMBEDDING_MODEL, "prompt": line},
                                timeout=15
                            )
                            emb = res.json().get("embedding", [])
                            if emb:
                                db.insert_chunk(uploaded_file.name, line, emb)
                                total_chunks += 1
                                
                st.success(f"Ingested {total_chunks} text chunks into PGVector from '{uploaded_file.name}'!")

    st.markdown("---")
    st.header("⚙️ Audit Logs & Exports")
    
    if st.button("Fetch Real-time Audit Logs"):
        try:
            table = dynamo.Table(DYNAMODB_TABLE)
            scan_res = table.scan()
            items = scan_res.get("Items", [])
            st.session_state.logs = items
        except Exception as e:
            st.error(f"Error fetching logs: {e}")

    if "logs" in st.session_state and st.session_state.logs:
        df_logs = pd.DataFrame(st.session_state.logs)
        st.dataframe(df_logs)

        # CSV Download
        csv_data = df_logs.to_csv(index=False).encode('utf-8')
        st.download_button(
            label="📥 Download Logs as CSV",
            data=csv_data,
            file_name="audit_logs.csv",
            mime="text/csv"
        )

        # PDF Download
        pdf_bytes = generate_pdf_report(st.session_state.logs)
        st.download_button(
            label="📄 Download Logs as PDF",
            data=pdf_bytes,
            file_name="audit_logs_report.pdf",
            mime="application/pdf"
        )

# Chat Messages Interface
for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])

user_input = st.chat_input("Ask a question about your uploaded PDF or cluster analytics...")

if user_input:
    st.session_state.messages.append({"role": "user", "content": user_input})
    with st.chat_message("user"):
        st.markdown(user_input)

    if any(keyword in user_input.lower() for keyword in ["analytics", "metrics", "cluster"]):
        st.session_state.pending_action = {
            "query": user_input,
            "type": "DATABRICKS_SQL_WAREHOUSE",
            "details": f"Executing Serverless SQL Query on Databricks Warehouse for request: '{user_input}'"
        }
    else:
        with st.chat_message("assistant"):
            with st.spinner("🤖 Agent executing PGVector Hybrid Search..."):
                res = requests.post(f"{OLLAMA_URL}/api/embeddings", json={"model": EMBEDDING_MODEL, "prompt": user_input}, timeout=15)
                query_vector = res.json().get("embedding", [])
                chunks = db.hybrid_search(user_input, query_vector, top_k=3)
                context = "\n".join(chunks) if chunks else "No relevant context found in database."

                endpoint = f"{KODEKLOUD_URL}/v1/chat/completions"
                headers = {"Authorization": f"Bearer {KODEKLOUD_API_KEY}", "Content-Type": "application/json"}
                prompt = f"Context from PGVector:\n{context}\n\nUser Question: {user_input}"
                payload = {
                    "model": LLM_MODEL,
                    "messages": [
                        {"role": "system", "content": "You are an Autonomous AI Agent."},
                        {"role": "user", "content": prompt}
                    ]
                }
                llm_res = requests.post(endpoint, json=payload, headers=headers, timeout=60)
                answer = llm_res.json()["choices"][0]["message"]["content"]

                st.markdown(answer)
                st.session_state.messages.append({"role": "assistant", "content": answer})

                table = dynamo.Table(DYNAMODB_TABLE)
                table.put_item(Item={
                    "SessionId": str(uuid.uuid4())[:8],
                    "Timestamp": "2026-08-08T20:45:00Z",
                    "ActionLog": f"PGVector Hybrid Search executed for: {user_input[:30]}...",
                    "Status": "COMPLETED"
                })

# Human-in-the-Loop Interface
if st.session_state.pending_action:
    st.warning("⚠️ **Human Approval Required (Human-in-the-Loop)**")
    st.write(f"**Action Requested:** {st.session_state.pending_action['details']}")
    
    col1, col2 = st.columns(2)
    with col1:
        if st.button("✅ Approve Action"):
            with st.chat_message("assistant"):
                with st.spinner("Executing approved Databricks SQL Query..."):
                    mock_analytics = {
                        "total_documents_processed": 142,
                        "avg_embedding_latency_ms": 45,
                        "top_queried_service": "AWS LocalStack Lambda",
                        "cluster_status": "SERVERLESS_ACTIVE"
                    }
                    context = json.dumps(mock_analytics, indent=2)

                    endpoint = f"{KODEKLOUD_URL}/v1/chat/completions"
                    headers = {"Authorization": f"Bearer {KODEKLOUD_API_KEY}", "Content-Type": "application/json"}
                    prompt = f"Retrieved Databricks Metrics:\n{context}\n\nUser Question: {st.session_state.pending_action['query']}"
                    payload = {
                        "model": LLM_MODEL,
                        "messages": [
                            {"role": "system", "content": "You are an Autonomous AI Agent."},
                            {"role": "user", "content": prompt}
                        ]
                    }
                    llm_res = requests.post(endpoint, json=payload, headers=headers, timeout=60)
                    answer = llm_res.json()["choices"][0]["message"]["content"]

                    st.markdown(answer)
                    st.session_state.messages.append({"role": "assistant", "content": answer})

                    table = dynamo.Table(DYNAMODB_TABLE)
                    table.put_item(Item={
                        "SessionId": str(uuid.uuid4())[:8],
                        "Timestamp": "2026-08-08T20:46:00Z",
                        "ActionLog": f"HUMAN_APPROVED: Databricks SQL executed",
                        "Status": "APPROVED_AND_EXECUTED"
                    })

            st.session_state.pending_action = None
            st.rerun()

    with col2:
        if st.button("❌ Reject Action"):
            st.error("Action execution rejected by user.")
            st.session_state.messages.append({"role": "assistant", "content": "❌ Action execution rejected by user."})
            
            table = dynamo.Table(DYNAMODB_TABLE)
            table.put_item(Item={
                "SessionId": str(uuid.uuid4())[:8],
                "Timestamp": "2026-08-08T20:46:00Z",
                "ActionLog": f"HUMAN_REJECTED: Databricks SQL cancelled",
                "Status": "REJECTED"
            })

            st.session_state.pending_action = None
            st.rerun()