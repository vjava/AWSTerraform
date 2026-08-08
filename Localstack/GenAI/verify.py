import requests

API_URL = "https://api.ai.kodekloud.com"
API_PASSWORD = "password" # अपना पासवर्ड यहाँ रखें

headers_options = [
    {"Authorization": f"Bearer {API_PASSWORD}", "Content-Type": "application/json"},
    {"x-api-key": API_PASSWORD, "Content-Type": "application/json"},
    {"api-key": API_PASSWORD, "Content-Type": "application/json"}
]

endpoints = [
    f"{API_URL}/chat/completions",
    f"{API_URL}/v1/chat/completions",
    f"{API_URL}/openai/v1/chat/completions"
]

payload = {
    "model": "llama-3",
    "messages": [{"role": "user", "content": "Hi"}]
}

print("Testing API Connections...\n")

for ep in endpoints:
    for idx, h in enumerate(headers_options):
        try:
            res = requests.post(ep, json=payload, headers=h, timeout=10)
            print(f"Endpoint: {ep} | Header Config {idx+1} | Status: {res.status_code}")
            if res.status_code == 200:
                print(">>> SUCCESS! Working Response:", res.json())
                break
        except Exception as e:
            print(f"Error testing {ep}: {str(e)}")