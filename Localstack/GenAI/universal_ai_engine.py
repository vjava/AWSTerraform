import os
import re
import json
import requests
import boto3
import pandas as pd
from typing import Optional, List, Dict
from dotenv import load_dotenv
from mcp.server.fastmcp import FastMCP

load_dotenv()

# Initialize Universal MCP Server
mcp = FastMCP("Universal-Enterprise-GenAI-Engine")

# Dual-Mode LLM Configuration
KODEKLOUD_URL = os.getenv("KODEKLOUD_URL", "https://api.ai.kodekloud.com")
KODEKLOUD_API_KEY = os.getenv("KODEKLOUD_API_KEY", "YOUR_API_PASSWORD")
LLM_MODEL = os.getenv("LLM_MODEL", "deepseek/deepseek-v4-flash")

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434/v1/chat/completions")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3")

AWS_ENDPOINT = os.getenv("AWS_ENDPOINT_URL", "http://localhost:4566")
AWS_REGION = os.getenv("AWS_DEFAULT_REGION", "us-east-1")

def call_universal_llm(messages: List[Dict[str, str]], use_local: bool = False, temperature: float = 0.2) -> str:
    """
    Universal LLM Router supporting multi-turn message history for chat, translation, and generation.
    """
    if use_local:
        try:
            payload = {"model": OLLAMA_MODEL, "messages": messages, "temperature": temperature, "stream": False}
            res = requests.post(OLLAMA_URL, json=payload, timeout=120)
            res.raise_for_status()
            return res.json()["choices"][0]["message"]["content"].strip()
        except Exception as e:
            return f"Local Ollama Error: {str(e)}. Ensure Ollama is running locally."
    else:
        try:
            endpoint = f"{KODEKLOUD_URL}/v1/chat/completions"
            headers = {
                "Authorization": f"Bearer {KODEKLOUD_API_KEY}",
                "Content-Type": "application/json"
            }
            payload = {
                "model": LLM_MODEL,
                "messages": messages,
                "temperature": temperature
            }
            res = requests.post(endpoint, json=payload, headers=headers, timeout=180)
            res.raise_for_status()
            return res.json()["choices"][0]["message"]["content"].strip()
        except Exception as e:
            return f"Cloud API Error: {str(e)}"

# ==============================================================================
# 1. Universal Code & Artifact Generator
# ==============================================================================
@mcp.tool()
def generate_universal_code(objective: str, target_language_or_framework: str, use_local: bool = False) -> str:
    messages = [
        {"role": "system", "content": f"You are an elite Principal Software Architect. Generate production-grade {target_language_or_framework} code with error handling."},
        {"role": "user", "content": objective}
    ]
    return call_universal_llm(messages, use_local, temperature=0.2)

# ==============================================================================
# 2. General Tech Consulting & Discussion
# ==============================================================================
@mcp.tool()
def tech_discussion_and_consulting(question_or_topic: str, use_local: bool = False) -> str:
    messages = [
        {"role": "system", "content": "You are an Elite Enterprise Technical Consultant. Provide deep industry insights and trade-offs."},
        {"role": "user", "content": question_or_topic}
    ]
    return call_universal_llm(messages, use_local, temperature=0.3)

# ==============================================================================
# 3. Universal Config, JSON, & Schema Synthesizer
# ==============================================================================
@mcp.tool()
def generate_structured_config(requirements: str, config_format: str = "JSON", use_local: bool = False) -> str:
    messages = [
        {"role": "system", "content": f"You are a Senior DevOps Engineer. Output ONLY valid {config_format} code block."},
        {"role": "user", "content": requirements}
    ]
    return call_universal_llm(messages, use_local, temperature=0.1)

# ==============================================================================
# 4. Quick Interactive Chat Agent
# ==============================================================================
@mcp.tool()
def quick_chat_response(chat_history: List[Dict[str, str]], use_local: bool = False) -> str:
    """
    Handles conversational multi-turn messaging for quick answers and general assistant interactions.
    """
    system_msg = {"role": "system", "content": "You are a helpful, concise, and smart AI assistant. Provide direct, clear, and well-structured answers."}
    full_messages = [system_msg] + chat_history
    return call_universal_llm(full_messages, use_local, temperature=0.4)

# ==============================================================================
# 5. Cross-Language Code Translator (e.g., Python to Java)
# ==============================================================================
@mcp.tool()
def translate_code_snippet(source_code: str, source_lang: str, target_lang: str, use_local: bool = False) -> str:
    """
    Translates code from one programming language to another with complete idiomatic syntax and explanation.
    """
    system_prompt = (
        f"You are an Expert Polyglot Refactoring Engineer. Translate the given {source_lang} code "
        f"into idiomatic, production-ready, highly optimized {target_lang} code. "
        f"Include necessary imports, classes, types, and comments explaining key translation choices."
    )
    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": f"Source Code ({source_lang}):\n{source_code}"}
    ]
    return call_universal_llm(messages, use_local, temperature=0.1)

# ==============================================================================
# 6. LocalStack AWS Sandbox Utility
# ==============================================================================
@mcp.tool()
def upload_artifact_to_localstack_s3(bucket_name: str, file_name: str, file_content: str) -> str:
    try:
        s3 = boto3.client(
            's3',
            endpoint_url=AWS_ENDPOINT,
            region_name=AWS_REGION,
            aws_access_key_id='test',
            aws_secret_access_key='test'
        )
        try:
            s3.head_bucket(Bucket=bucket_name)
        except:
            s3.create_bucket(Bucket=bucket_name)
            
        s3.put_object(Bucket=bucket_name, Key=file_name, Body=file_content.encode('utf-8'))
        return f"SUCCESS: Artifact '{file_name}' securely saved to LocalStack S3 bucket '{bucket_name}'."
    except Exception as e:
        return f"LocalStack S3 Error: {str(e)}"

if __name__ == "__main__":
    mcp.run()