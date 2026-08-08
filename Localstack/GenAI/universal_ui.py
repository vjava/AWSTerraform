import streamlit as st
import pandas as pd
import json
import os
from dotenv import load_dotenv

from universal_ai_engine import (
    generate_universal_code,
    tech_discussion_and_consulting,
    generate_structured_config,
    quick_chat_response,
    translate_code_snippet,
    upload_artifact_to_localstack_s3
)

load_dotenv()

st.set_page_config(page_title="Universal Polyglot GenAI Engine", page_icon="⚡", layout="wide")

# Sidebar - Mode Selector (Cloud vs Local Ollama)
st.sidebar.title("⚙️ Engine Mode")
use_local_llm = st.sidebar.toggle("Use Local Ollama (Offline Mode)", value=False, help="Switch between Cloud Gateway and Local Ollama.")
st.sidebar.info(f"Active LLM: {'Local Ollama' if use_local_llm else 'Cloud Gateway (DeepSeek/KodeKloud)'}")

st.title("⚡ Universal Polyglot GenAI & Architecture Engine")
st.markdown("Interactive Chat, Cross-Language Code Translation, Universal Code Generation, Tech Consulting, and Sandbox Management.")

# Navigation Tabs (Now with 6 Advanced Tabs)
tab1, tab2, tab3, tab4, tab5, tab6 = st.tabs([
    "💻 Code Generator",
    "💬 Tech Consulting",
    "⚙️ Config Synthesizer",
    "🗨️ Quick Chat",
    "🔄 Code Translator",
    "☁️ LocalStack Sandbox"
])

with tab1:
    st.subheader("💻 Universal Polyglot Code Generator")
    st.markdown("Generate production-grade code in Python, Java, C++, Go, React, Kubernetes manifests, SQL, or Terraform.")
    
    col_c1, col_c2 = st.columns(2)
    target_lang = col_c1.selectbox("Target Language / Framework", [
        "Python", "Java (Spring Boot)", "Node.js / TypeScript", "Go", 
        "React / Frontend", "Terraform / IaC", "Kubernetes Manifests", "SQL / PL-SQL", "C++"
    ])
    objective = st.text_area("What do you want to build?", placeholder="Write a high-performance multithreaded caching mechanism in Java Spring Boot with Redis integration.")
    
    if st.button("Generate Production Code"):
        if not objective.strip():
            st.warning("⚠️ Please provide an objective.")
        else:
            with st.spinner(f"Synthesizing {target_lang} code..."):
                code_output = generate_universal_code(objective, target_lang, use_local_llm)
                st.markdown(code_output)

with tab2:
    st.subheader("💬 Tech Consulting & Expert Discussion")
    st.markdown("Ask anything about software engineering, system design, scaling, cloud architecture, or market technologies.")
    
    tech_query = st.text_area("Your Tech Question / Discussion Topic", placeholder="Compare Kafka vs RabbitMQ for high-throughput financial event streaming.")
    
    if st.button("Consult AI Architect"):
        if not tech_query.strip():
            st.warning("⚠️ Please enter a question or topic.")
        else:
            with st.spinner("Analyzing market patterns and architecture..."):
                consult_output = tech_discussion_and_consulting(tech_query, use_local_llm)
                st.markdown(consult_output)

with tab3:
    st.subheader("⚙️ Universal Config, JSON, & Schema Synthesizer")
    st.markdown("Generate valid configuration files, JSON structures, Dockerfiles, or CI/CD pipelines.")
    
    conf_type = st.selectbox("Configuration Type", ["JSON Schema", "Docker & Docker-Compose", "GitHub Actions CI/CD Pipeline", "Kubernetes Deployment YAML", "Terraform AWS VPC Module"])
    conf_reqs = st.text_area("Configuration Requirements", placeholder="Create a multi-container Docker setup for a Python FastAPI app and PostgreSQL database with persistent volumes.")
    
    if st.button("Synthesize Configuration"):
        if not conf_reqs.strip():
            st.warning("⚠️ Please provide requirements.")
        else:
            with st.spinner("Generating configuration..."):
                conf_output = generate_structured_config(conf_reqs, conf_type, use_local_llm)
                st.code(conf_output, language="yaml" if "YAML" in conf_type or "Docker" in conf_type else "json")

with tab4:
    st.subheader("🗨️ Quick Chat with LLM")
    st.markdown("Chat interactively with the AI. Ask short questions, get instant crisp answers.")
    
    # Initialize Streamlit chat history session state
    if "chat_messages" not in st.session_state:
        st.session_state.chat_messages = []

    # Display prior chat messages
    for message in st.session_state.chat_messages:
        with st.chat_message(message["role"]):
            st.markdown(message["content"])

    # Chat input box
    if prompt := st.chat_input("Type your message here... (e.g., 'What is dependency injection in Java?')"):
        # Append user message
        st.session_state.chat_messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)

        # Generate LLM response
        with st.chat_message("assistant"):
            with st.spinner("Thinking..."):
                # Pass message history to backend tool
                reply = quick_chat_response(st.session_state.chat_messages, use_local_llm)
                st.markdown(reply)
                st.session_state.chat_messages.append({"role": "assistant", "content": reply})

    if st.button("Clear Chat History"):
        st.session_state.chat_messages = []
        st.rerun()

with tab5:
    st.subheader("🔄 Cross-Language Code Translator")
    st.markdown("Instantly convert source code from one language to another (e.g., Python to Java, Java to Go, etc.).")
    
    col_t1, col_t2 = st.columns(2)
    source_lang = col_t1.selectbox("Source Language", ["Python", "Java", "JavaScript / TypeScript", "Go", "C++", "C#", "Ruby", "PHP"], index=0)
    target_lang_code = col_t2.selectbox("Target Language", ["Java", "Python", "Go", "JavaScript / TypeScript", "C++", "C#", "Rust"], index=0)
    
    source_code_input = st.text_area(
        "Paste Source Code Here", 
        placeholder="class Calculator:\n    def add(self, a, b):\n        return a + b",
        height=180
    )
    
    if st.button("Translate Code Now"):
        if not source_code_input.strip():
            st.warning("⚠️ Please provide source code to translate.")
        else:
            with st.spinner(f"Translating code from {source_lang} to {target_lang_code}..."):
                translated_output = translate_code_snippet(source_code_input, source_lang, target_lang_code, use_local_llm)
                st.markdown("### 🎯 Translated Output:")
                st.markdown(translated_output)

with tab6:
    st.subheader("☁️ LocalStack AWS Sandbox Storage")
    st.markdown("Save your generated code, configurations, or documents into a local mock S3 bucket.")
    
    col_s1, col_s2 = st.columns(2)
    bucket_n = col_s1.text_input("Bucket Name", value="polyglot-artifacts")
    file_n = col_s2.text_input("Artifact Filename", value="Service.java")
    file_c = st.text_area("Artifact Content", value="// Generated code or config content here...")
    
    if st.button("Upload Artifact to LocalStack S3"):
        if not bucket_n.strip() or not file_n.strip():
            st.warning("⚠️ Enter bucket and filename.")
        else:
            with st.spinner("Saving to LocalStack..."):
                res = upload_artifact_to_localstack_s3(bucket_n, file_n, file_c)
                st.success(res)