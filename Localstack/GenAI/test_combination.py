import requests

API_URL = "https://api.ai.kodekloud.com"
API_KEY = "password"  # अपना KodeKloud API पासवर्ड रखें

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

endpoints = [
    f"{API_URL}/chat/completions",
    f"{API_URL}/v1/chat/completions",
    f"{API_URL}/openai/v1/chat/completions"
]

models_to_try = ["kodekey-pro", "kodekloud-pro", "default"]

for ep in endpoints:
    for model in models_to_try:
        payload = {
            "model": model,
            "messages": [{"role": "user", "content": "Hi"}]
        }
        try:
            res = requests.post(ep, json=payload, headers=headers, timeout=10)
            print(f"Endpoint: {ep} | Model: '{model}' | Status: {res.status_code}")
            if res.status_code == 200:
                print(">>> WORKING COMBINATION FOUND! Response:", res.json())
                exit(0)
            else:
                print("   Detail:", res.text[:150])
        except Exception as e:
            print(f"   Error: {e}")