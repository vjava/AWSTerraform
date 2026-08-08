import pytest
import requests
import psycopg2
from pgvector.psycopg2 import register_vector
import boto3

# Configurations
OLLAMA_URL = "http://localhost:11434"
EMBEDDING_MODEL = "nomic-embed-text"
LOCALSTACK_ENDPOINT = "http://localhost:4566"
DYNAMODB_TABLE = "AgentChatHistory"

PG_HOST = "localhost"
PG_PORT = 5433
PG_DB = "vectordb"
PG_USER = "aiuser"
PG_PASSWORD = "Password123"

# ==============================================================================
# 1. Test Ollama Embedding Service
# ==============================================================================
def test_ollama_service_running():
    """Verify Ollama is active and returning 768-dimensional embeddings."""
    url = f"{OLLAMA_URL}/api/embeddings"
    payload = {"model": EMBEDDING_MODEL, "prompt": "PyTest health check"}
    
    response = requests.post(url, json=payload, timeout=10)
    assert response.status_code == 200, "Ollama service should return HTTP 200"
    
    data = response.json()
    assert "embedding" in data, "Response must contain 'embedding' key"
    assert len(data["embedding"]) == 768, "Embedding dimension must be exactly 768"

# ==============================================================================
# 2. Test PostgreSQL PGVector Connection & Schema
# ==============================================================================
def test_pgvector_database_connection():
    """Verify PostgreSQL PGVector connection and document_embeddings table structure."""
    conn = psycopg2.connect(
        host=PG_HOST, port=PG_PORT, dbname=PG_DB, user=PG_USER, password=PG_PASSWORD
    )
    assert conn is not None, "PostgreSQL connection should be successful"
    
    register_vector(conn)
    with conn.cursor() as cur:
        cur.execute("SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'document_embeddings');")
        table_exists = cur.fetchone()[0]
        assert table_exists is True, "Table 'document_embeddings' must exist in PGVector database"
        
    conn.close()

# ==============================================================================
# 3. Test LocalStack DynamoDB Connectivity
# ==============================================================================
def test_localstack_dynamodb_connectivity():
    """Verify LocalStack AWS DynamoDB is responsive and table exists."""
    dynamo = boto3.resource(
        "dynamodb",
        endpoint_url=LOCALSTACK_ENDPOINT,
        aws_access_key_id="test",
        aws_secret_access_key="test",
        region_name="us-east-1"
    )
    table = dynamo.Table(DYNAMODB_TABLE)
    assert table.table_status in ["ACTIVE", "UPDATING"], "DynamoDB table 'AgentChatHistory' must be active"

# ==============================================================================
# 4. Test End-to-End PGVector Hybrid Insertion & Search
# ==============================================================================
def test_pgvector_hybrid_insertion_and_search():
    """Test vector insertion and Hybrid Search execution in PGVector."""
    conn = psycopg2.connect(
        host=PG_HOST, port=PG_PORT, dbname=PG_DB, user=PG_USER, password=PG_PASSWORD
    )
    conn.autocommit = True
    register_vector(conn)
    
    test_doc = "PyTest Automated System Verification Unit Test Chunk."
    
    # 1. Generate Embedding
    res = requests.post(f"{OLLAMA_URL}/api/embeddings", json={"model": EMBEDDING_MODEL, "prompt": test_doc}, timeout=10)
    embedding = res.json().get("embedding", [])
    assert len(embedding) == 768, "Embedding generation failed"
    
    # 2. Insert Test Record
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO document_embeddings (document_name, chunk_text, embedding) VALUES (%s, %s, %s);",
            ("pytest_suite.txt", test_doc, embedding)
        )
        
    # 3. Perform Hybrid Search Query
    with conn.cursor() as cur:
        sql_query = """
            SELECT chunk_text 
            FROM document_embeddings 
            ORDER BY embedding <=> %s::vector 
            LIMIT 1;
        """
        cur.execute(sql_query, (embedding,))
        result = cur.fetchone()
        assert result is not None, "Hybrid Search should return at least one result"
        assert len(result[0]) > 0, "Retrieved text chunk should not be empty"
        
    conn.close()