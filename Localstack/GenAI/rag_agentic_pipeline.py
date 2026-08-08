import os
import json
import boto3
import requests
import psycopg2
from pgvector.psycopg2 import register_vector

# ==============================================================================
# Configuration Setup
# ==============================================================================
# AWS LocalStack
LOCALSTACK_ENDPOINT = "http://localhost:4566"
S3_BUCKET_NAME = "genai-doc-storage"
DYNAMODB_TABLE = "AgentChatHistory"

# LLM & Embedding Config
KODEKLOUD_URL = "https://api.ai.kodekloud.com"
KODEKLOUD_API_KEY = "password"  # अपना KodeKloud API पासवर्ड यहाँ रखें
OLLAMA_URL = "http://localhost:11434"
EMBEDDING_MODEL = "nomic-embed-text"
LLM_MODEL = "google/gemini-3.1-flash-lite"

# PostgreSQL / PGVector Config (Port 5433)
PG_HOST = "localhost"
PG_PORT = 5433
PG_DB = "vectordb"
PG_USER = "aiuser"
PG_PASSWORD = "Password123"

# ==============================================================================
# 1. Hybrid PGVector Database Engine (Full-Text + Vector Cosine Search)
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
        """Sets up PGVector extension, table, full-text tsvector column, and indexes safely."""
        with self.conn.cursor() as cur:
            cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
            cur.execute("""
                CREATE TABLE IF NOT EXISTS document_embeddings (
                    id SERIAL PRIMARY KEY,
                    document_name VARCHAR(255),
                    chunk_text TEXT,
                    embedding vector(768)
                );
            """)
            # Safely add generated fts_doc column if missing from existing table
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
            cur.execute("CREATE INDEX IF NOT EXISTS fts_idx ON document_embeddings USING gin(fts_doc);")
            cur.execute("TRUNCATE TABLE document_embeddings;")
            print("[PGVector DB] Schema initialized safely with Hybrid Search (Full-Text + Vector).")

    def insert_chunk(self, doc_name: str, chunk_text: str, embedding: list):
        with self.conn.cursor() as cur:
            cur.execute(
                "INSERT INTO document_embeddings (document_name, chunk_text, embedding) VALUES (%s, %s, %s);",
                (doc_name, chunk_text, embedding)
            )

    def hybrid_search(self, query: str, query_vector: list, top_k: int = 2) -> list:
        """
        Executes Reciprocal Rank Fusion (RRF) combining Full-Text Keyword Search 
        and Vector Cosine Similarity.
        """
        with self.conn.cursor() as cur:
            sql_query = """
                WITH vector_search AS (
                    SELECT id, chunk_text, ROW_NUMBER() OVER (ORDER BY embedding <=> %s::vector) AS rank
                    FROM document_embeddings
                    LIMIT 10
                ),
                text_search AS (
                    SELECT id, chunk_text, ROW_NUMBER() OVER (ORDER BY ts_rank(fts_doc, plainto_tsquery('english', %s)) DESC) AS rank
                    FROM document_embeddings
                    WHERE fts_doc @@ plainto_tsquery('english', %s)
                    LIMIT 10
                )
                SELECT COALESCE(v.chunk_text, t.chunk_text) AS content,
                       (COALESCE(1.0 / (60 + v.rank), 0.0) + COALESCE(1.0 / (60 + t.rank), 0.0)) AS rrf_score
                FROM vector_search v
                FULL OUTER JOIN text_search t ON v.id = t.id
                ORDER BY rrf_score DESC
                LIMIT %s;
            """
            cur.execute(sql_query, (query_vector, query, query, top_k))
            results = cur.fetchall()
            return [row[0] for row in results]

    def close(self):
        self.conn.close()

# ==============================================================================
# 2. Agentic AI Tools Definition
# ==============================================================================
class AgentTools:
    def __init__(self, db: HybridPGVectorDB):
        self.db = db
        self.ollama_url = OLLAMA_URL
        self.s3 = boto3.client("s3", endpoint_url=LOCALSTACK_ENDPOINT, aws_access_key_id="test", aws_secret_access_key="test", region_name="us-east-1")
        self.dynamodb = boto3.resource("dynamodb", endpoint_url=LOCALSTACK_ENDPOINT, aws_access_key_id="test", aws_secret_access_key="test", region_name="us-east-1")
        self._ensure_dynamodb_table()

        
    def _ensure_dynamodb_table(self):
        """Creates DynamoDB table in LocalStack if it doesn't exist."""
        try:
            self.dynamodb.create_table(
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
            print("[LocalStack] DynamoDB Table 'AgentChatHistory' created successfully.")
        except Exception:
            pass  # Table already exists

    def tool_pgvector_hybrid_search(self, query: str) -> str:
        """Tool 1: Executes Hybrid Vector + Keyword search on PGVector DB."""
        print(f" 🛠️ [Tool Executing] PGVector Hybrid Search for: '{query}'")
        res = requests.post(f"{self.ollama_url}/api/embeddings", json={"model": EMBEDDING_MODEL, "prompt": query}, timeout=15)
        query_vector = res.json().get("embedding", [])
        chunks = self.db.hybrid_search(query, query_vector, top_k=2)
        return "\n".join(chunks) if chunks else "No relevant knowledge found."

    def tool_databricks_sql_warehouse(self, query: str) -> str:
        """Tool 2: Simulates Databricks Serverless SQL Warehouse Execution."""
        print(f" 🛠️ [Tool Executing] Databricks SQL Warehouse Tool for query: '{query}'")
        # Simulating SQL Analytical Aggregation
        mock_analytics = {
            "total_documents_processed": 142,
            "avg_embedding_latency_ms": 45,
            "top_queried_service": "AWS LocalStack Lambda",
            "cluster_status": "SERVERLESS_ACTIVE"
        }
        return json.dumps(mock_analytics, indent=2)

    def tool_localstack_aws_logger(self, session_id: str, action_log: str):
        """Tool 3: Writes Agent State and Audit Logs to LocalStack DynamoDB."""
        print(f" 🛠️ [Tool Executing] LocalStack DynamoDB Logger")
        try:
            table = self.dynamodb.Table(DYNAMODB_TABLE)
            table.put_item(Item={
                "SessionId": session_id,
                "Timestamp": "2026-08-08T20:00:00Z",
                "ActionLog": action_log,
                "Status": "AGENT_COMPLETED"
            })
            print("    -> State persisted to DynamoDB successfully.")
        except Exception as e:
            print(f"    -> DynamoDB Log Warning: {e}")

# ==============================================================================
# 3. Autonomous AI Agent (LangGraph Reasoning Logic)
# ==============================================================================
class AutonomousAgent:
    def __init__(self, tools: AgentTools):
        self.tools = tools
        self.kodekloud_url = KODEKLOUD_URL
        self.headers = {"Authorization": f"Bearer {KODEKLOUD_API_KEY}", "Content-Type": "application/json"}

    def run(self, user_goal: str):
        print(f"\n🤖 [AGENT STARTED] Goal: '{user_goal}'")
        
        # Step 1: Agent Decides Strategy (Tool Selection Routing)
        print("\n--- Step 1: Agent Reasoning & Tool Decision ---")
        if "analytics" in user_goal.lower() or "metrics" in user_goal.lower():
            tool_output = self.tools.tool_databricks_sql_warehouse(user_goal)
            context_source = "Databricks SQL Warehouse"
        else:
            tool_output = self.tools.tool_pgvector_hybrid_search(user_goal)
            context_source = "PGVector Hybrid Search (Port 5433)"

        # Step 2: Agent Formulates Final Synthesis via LLM
        print(f"\n--- Step 2: LLM Synthesis via KodeKloud ({LLM_MODEL}) ---")
        endpoint = f"{self.kodekloud_url}/v1/chat/completions"
        system_prompt = f"You are an Autonomous AI Agent. Use the context retrieved from {context_source} to answer the user request."
        prompt = f"Retrieved Tool Context:\n{tool_output}\n\nUser Goal: {user_goal}"

        payload = {
            "model": LLM_MODEL,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt}
            ]
        }
        res = requests.post(endpoint, json=payload, headers=self.headers, timeout=60)
        final_answer = res.json()["choices"][0]["message"]["content"]

        # Step 3: Agent Audit Logging
        print("\n--- Step 3: Persistence & Audit Logging ---")
        self.tools.tool_localstack_aws_logger("session_agent_99", f"Processed goal using {context_source}")

        return final_answer

# ==============================================================================
# 4. Main Setup & Execution Flow
# ==============================================================================
if __name__ == "__main__":
    print("==================================================================")
    print("  Phase 4: Multi-Tool Agentic AI with PGVector Hybrid Search     ")
    print("==================================================================")

    # Initialize PGVector & Populate Knowledge
    pg_db = HybridPGVectorDB()
    
    # Upload Sample Chunks
    sample_texts = [
        "Project Alpha utilizes PGVector on Port 5433 for hybrid semantic and full-text document retrieval.",
        "Databricks Free Edition executes serverless SQL transformations and ETL pipeline jobs.",
        "AWS LocalStack simulates S3 document buckets, DynamoDB session tables, and SQS queues locally.",
        "The system uses Ollama nomic-embed-text for 768-dim embeddings and KodeKloud Gemini 3.1 Flash Lite."
    ]

    print("\n[Knowledge Setup] Embedding and inserting documents into PGVector...")
    for idx, text in enumerate(sample_texts):
        res = requests.post(f"{OLLAMA_URL}/api/embeddings", json={"model": EMBEDDING_MODEL, "prompt": text}, timeout=15)
        emb = res.json().get("embedding", [])
        if emb:
            pg_db.insert_chunk("knowledge_base.txt", text, emb)
    
    # Initialize Agent Tools & Reasoning Engine
    agent_tools = AgentTools(pg_db)
    agent = AutonomousAgent(agent_tools)

    # Scenario A: RAG Search Request (Triggers PGVector Hybrid Search Tool)
    result_a = agent.run("Where are embeddings stored and how is search performed in Project Alpha?")
    print("\n[AGENT FINAL RESPONSE - SCENARIO A]:")
    print(result_a)

    print("\n" + "="*66)

    # Scenario B: Analytical Query Request (Triggers Databricks SQL Tool)
    result_b = agent.run("Show me the analytics and metrics for document processing clusters.")
    print("\n[AGENT FINAL RESPONSE - SCENARIO B]:")
    print(result_b)

    pg_db.close()