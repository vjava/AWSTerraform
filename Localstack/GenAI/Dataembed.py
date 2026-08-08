import requests
from sentence_transformers import SentenceTransformer

# 1. HuggingFace Open-Source Embedding Model (Free & In-Memory)
print("Loading Embedding Model (all-MiniLM-L6-v2)...")
embed_model = SentenceTransformer("all-MiniLM-L6-v2")

class CloudLLMClient:
    def __init__(self, api_url: str, api_password: str, default_model: str = "llama-3"):
        self.api_url = api_url.rstrip("/")
        self.api_password = api_password
        self.default_model = default_model
        self.headers = {
            "Authorization": f"Bearer {self.api_password}",
            "Content-Type": "application/json"
        }

    def generate_text(self, prompt: str, system_prompt: str = "You are a helpful AI assistant.") -> str:
        endpoint = f"{self.api_url}/chat/completions"
        payload = {
            "model": self.default_model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt}
            ],
            "temperature": 0.7
        }
        
        try:
            response = requests.post(endpoint, json=payload, headers=self.headers, timeout=60)
            response.raise_for_status()
            return response.json()['choices'][0]['message']['content']
        except Exception as e:
            return f"Error calling Chat API: {str(e)}"

    def get_embedding(self, text: str) -> list:
        # Generate 384-dimensional dense vector embeddings
        vector = embed_model.encode(text).tolist()
        return vector

# --- Verification & Testing ---
API_URL = "https://api.ai.kodekloud.com"
API_PASSWORD = "password" # अपना पासवर्ड यहाँ रखें

llm_client = CloudLLMClient(api_url=API_URL, api_password=API_PASSWORD, default_model="llama-3")

# 1. Test Text Generation (KodeKloud API)
print("\n=== Text Generation Test ===")
response = llm_client.generate_text("Explain RAG in two sentences.")
print(response)

# 2. Test Text Embeddings (SentenceTransformers)
print("\n=== Embeddings Test ===")
sample_vector = llm_client.get_embedding("AWS LocalStack with Databricks and KodeKloud LLM")
print(f"Vector Dimensions Received: {len(sample_vector)}")
print(f"Sample Vector (First 5 dimensions): {sample_vector[:5]}")