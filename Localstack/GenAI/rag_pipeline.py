import os
import json
import boto3
import requests
import psycopg2
from pgvector.psycopg2 import register_vector

# ==============================================================================
# Configuration Setup
# ==============================================================================
# AWS LocalStack Config
LOCALSTACK_ENDPOINT = "http://localhost:4566"
S3_BUCKET_NAME = "genai-doc-storage"
DOCUMENT_KEY = "sample_knowledge.txt"

# LLM & Embedding Config
KODEKLOUD_URL = "https://api.ai.kodekloud.com"
KODEKLOUD_API_KEY = "password"  # अपना KodeKloud API पासवर्ड यहाँ रखें
OLLAMA_URL = "http://localhost:11434"
EMBEDDING_MODEL = "nomic-embed-text"

# PostgreSQL / PGVector Config (Port 5433)
PG_HOST = "localhost"
PG_PORT = 5433
PG_DB = "vectordb"
PG_USER = "aiuser"
PG_PASSWORD = "Password123"

# ==============================================================================
# 1. Hybrid Client (Ollama Embeddings + KodeKloud Generation)
# ==============================================================================
class HybridRAGClient:
    def __init__(self, kodekloud_url, api_key, ollama_url):
        self.kodekloud_url = kodekloud_url.rstrip("/")
        self.api_key = api_key
        self.ollama_url = ollama_url.rstrip("/")
        self.headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }

    def get_embedding(self, text: str) -> list:
        """Generates embeddings using local Ollama nomic-embed-text model (768 dimensions)."""
        endpoint = f"{self.ollama_url}/api/embeddings"
        payload = {
            "model": EMBEDDING_MODEL,
            "prompt": text
        }
        try:
            res = requests.post(endpoint, json=payload, timeout=15)
            res.raise_for_status()
            return res.json().get("embedding", [])
        except Exception as e:
            print(f"[ERROR] Ollama Embedding Failed: {e}")
            return []

    def generate_answer(self, query: str, context: str) -> str:
        """Generates response using KodeKloud LLM."""
        endpoint = f"{self.kodekloud_url}/v1/chat/completions"
        system_prompt = (
            "You are a helpful AI assistant. Answer the user's question strictly "
            "based on the provided context below. If the answer is not in the context, "
            "say 'I cannot find the answer in the provided documents.'"
        )
        prompt = f"Context:\n{context}\n\nQuestion: {query}"
        
        payload = {
            "model": "google/gemini-3.1-flash-lite",
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt}
            ]
        }
        try:
            res = requests.post(endpoint, json=payload, headers=self.headers, timeout=60)
            res.raise_for_status()
            return res.json()["choices"][0]["message"]["content"]
        except Exception as e:
            if hasattr(e, 'response') and e.response is not None:
                return f"[ERROR] KodeKloud Response: {e.response.text}"
            return f"[ERROR] KodeKloud LLM Failed: {e}"

# ==============================================================================
# 2. LocalStack S3 Operations
# ==============================================================================
def upload_sample_doc_to_localstack():
    """Uploads sample knowledge text file to LocalStack S3."""
    s3_client = boto3.client(
        "s3",
        endpoint_url=LOCALSTACK_ENDPOINT,
        aws_access_key_id="test",
        aws_secret_access_key="test",
        region_name="us-east-1"
    )
    try:
        s3_client.create_bucket(Bucket=S3_BUCKET_NAME)
    except Exception:
        pass

    sample_text = (
        "Project Alpha is a cloud-native serverless architecture deployed on AWS.\n"
        "It uses AWS Lambda for microservices and DynamoDB for low-latency state persistence.\n"
        "Databricks Free Edition is utilized for running PySpark transformations and ETL jobs.\n"
        "For AI capabilities, the system uses Ollama nomic-embed-text for local embeddings and "
        "KodeKloud LLM for natural language processing.\n"
        "All vector embeddings are stored persistently in a PostgreSQL DB with PGVector extension."
    )
    
    s3_client.put_object(Bucket=S3_BUCKET_NAME, Key=DOCUMENT_KEY, Body=sample_text.encode("utf-8"))
    print(f"[S3] Sample document uploaded to LocalStack 's3://{S3_BUCKET_NAME}/{DOCUMENT_KEY}'.")

def fetch_doc_from_localstack() -> str:
    """Retrieves document text from LocalStack S3."""
    s3_client = boto3.client(
        "s3",
        endpoint_url=LOCALSTACK_ENDPOINT,
        aws_access_key_id="test",
        aws_secret_access_key="test",
        region_name="us-east-1"
    )
    obj = s3_client.get_object(Bucket=S3_BUCKET_NAME, Key=DOCUMENT_KEY)
    return obj["Body"].read().decode("utf-8")

# ==============================================================================
# 3. Embedded PGVector Database Handler (Port 5433)
# ==============================================================================
class PGVectorHandler:
    def __init__(self):
        self.conn = psycopg2.connect(
            host=PG_HOST,
            port=PG_PORT,
            dbname=PG_DB,
            user=PG_USER,
            password=PG_PASSWORD
        )
        self.conn.autocommit = True
        register_vector(self.conn)
        self.init_db()

    def init_db(self):
        """Enable PGVector extension and create target table."""
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
            # Clear old records for a fresh pipeline run
            cur.execute("TRUNCATE TABLE document_embeddings;")
            print("[PGVector] Extension verified and table 'document_embeddings' initialized.")

    def store_chunk(self, doc_name: str, chunk_text: str, embedding: list):
        """Insert text chunk and its vector embedding into PGVector."""
        with self.conn.cursor() as cur:
            cur.execute(
                "INSERT INTO document_embeddings (document_name, chunk_text, embedding) VALUES (%s, %s, %s);",
                (doc_name, chunk_text, embedding)
            )

    def search_similar_chunks(self, query_vector: list, top_k: int = 2) -> list:
        """Perform Cosine Distance similarity search using PGVector (<=> operator)."""
        with self.conn.cursor() as cur:
            cur.execute(
                """
                SELECT chunk_text, (1 - (embedding <=> %s::vector)) AS similarity
                FROM document_embeddings
                ORDER BY embedding <=> %s::vector
                LIMIT %s;
                """,
                (query_vector, query_vector, top_k)
            )
            results = cur.fetchall()
            return [row[0] for row in results]

    def close(self):
        self.conn.close()

# ==============================================================================
# 4. Main Execution Flow
# ==============================================================================
if __name__ == "__main__":
    print("==================================================================")
    print("  Phase 2 RAG Pipeline with PGVector (Port 5433) & Ollama         ")
    print("==================================================================")

    client = HybridRAGClient(KODEKLOUD_URL, KODEKLOUD_API_KEY, OLLAMA_URL)
    pg_db = PGVectorHandler()

    # Step A: Setup & Fetch Document from LocalStack S3
    print("\n=== Step 1: Fetching Knowledge Base from LocalStack S3 ===")
    upload_sample_doc_to_localstack()
    raw_document = fetch_doc_from_localstack()

    chunks = [line.strip() for line in raw_document.split("\n") if line.strip()]
    print(f"[CHUNKING] Document split into {len(chunks)} text chunks.")

    # Step B: Generate Vectors & Store in PGVector Database
    print("\n=== Step 2: Embedding Chunks & Storing in PGVector (Port 5433) ===")
    for idx, chunk in enumerate(chunks):
        vector = client.get_embedding(chunk)
        if vector:
            pg_db.store_chunk(DOCUMENT_KEY, chunk, vector)
            print(f" -> Chunk {idx + 1} stored in PostgreSQL PGVector.")

    # Step C: User Query & Vector Search in PGVector
    print("\n=== Step 3: Performing Vector Search in PGVector ===")
    user_query = "Where are vector embeddings stored and what AI tools are used?"
    print(f"User Query: '{user_query}'")

    query_vector = client.get_embedding(user_query)
    retrieved_chunks = pg_db.search_similar_chunks(query_vector, top_k=2)

    context = "\n".join(retrieved_chunks)
    print("\n[RETRIEVED CONTEXT FROM PGVECTOR]:")
    print("--------------------------------------------------")
    print(context)
    print("--------------------------------------------------")

    # Step D: Final LLM Generation
    print("\n=== Step 4: Generating LLM Response via KodeKloud ===")
    final_response = client.generate_answer(user_query, context)
    print("\n[LLM RESPONSE]:")
    print(final_response)

    # Cleanup Database Connection
    pg_db.close()