import requests
import json

API_URL = "https://api.ai.kodekloud.com"
API_KEY = "password" # अपना पासवर्ड रखें

# Test different models supported by KodeKloud
models_to_test = [
    "llama-3",
    "meta-llama/llama-3-8b-instruct",
    "meta-llama/Meta-Llama-3-8B-Instruct",
    "gpt-3.5-turbo",
    "mistralai/Mistral-7B-Instruct-v0.2"
]

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json",
    "Accept": "application/json"
}

print("=== Testing KodeKloud Model Payload Routing ===")

for model in models_to_test:
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": "Hi"}],
        "temperature": 0.7
    }
    
    url = f"{API_URL}/v1/chat/completions"
    try:
        res = requests.post(url, json=payload, headers=headers, timeout=10)
        print(f"\nModel: '{model}' | Status: {res.status_code}")
        print(f"Response Body: {res.text[:200]}")
        if res.status_code == 200:
            print(f" SUCCESS with model: {model}")
            break
    except Exception as e:
        print(f"Error: {e}")