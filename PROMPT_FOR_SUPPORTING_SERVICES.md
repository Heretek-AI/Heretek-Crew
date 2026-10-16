# Master Research & Specification Prompt: Supporting Software & Sidecar Services for Autonomous Agent Fleets

You are an expert Systems Architect and Infrastructure Specialist. Your mission is to research, evaluate, and produce a production-grade specification of **Supporting Software, Sidecars, and Microservices** that run alongside **Paperclip** and **OpenCode v2** in Docker Compose to supercharge autonomous agents with specialized capabilities (e.g. Firecrawl, containerized Ghidra, stealth browser engines, code search engines, sandboxes, and vector stores).

Every recommendation must be an **active, maintained, container-ready open-source or self-hostable tool** with verified Docker images and client integration mechanisms (MCP, REST API, or CLI bridge).

---

## 1. Scope & Categories of Supporting Software

Research and specify candidate services across these 8 core domains:

### Category A: Web Ingestion, Crawling & Search
- **Firecrawl** (Self-hosted web scraper & markdown extractor designed for LLMs)
- **Crawl4AI** (Lightweight, asynchronous open-source LLM-friendly crawler)
- **SearXNG** (Self-hosted privacy-focused metasearch engine giving agents real web search without vendor API quotas)
- Clean article extractors & document converters (e.g., Trafilatura, Tika, or Gotenberg for PDF generation/conversion)

### Category B: Resilient & Stealth Browser Automation
- **Stealth Chromium / Browserless** (Dockerized headless browser pre-configured with stealth anti-detection plugins, evasion of fingerprinting, and CDP endpoints)
- **Playwright Server / Chrome CDP Sidecars** (Persistent browser daemon allowing agents to take high-fidelity screenshots, interact with SPAs, and inspect DOM trees without bundling heavy browser binaries into the agent runner)
- Proxy & Session Management tools (e.g. Squid or mitmproxy for auditing agent HTTP traffic)

### Category C: Defensive Binary Analysis, Decompilation & Reverse Engineering
- **Headless Ghidra Server / REST Bridge** (Containerized Ghidra running headless scripts for disassembly, decompilation to C, symbol export, and cross-reference analysis)
- **Radare2 / Rizin / Cutter Container** (Fast command-line disassembly and binary triage with r2pipe REST/WebSocket interface)
- Firmware & ELF inspection tools (e.g. Binwalk container, strings, objdump, and capstone/keystone engines)

### Category D: Fast Codebase Search, Indexing & AST Analysis
- **ast-grep** (Fast syntactic code search, linting, and structural replacement across 20+ languages)
- **Semgrep Daemon / Engine** (Local semantic code scanning, pattern matching, and security auditing)
- Code search & indexing engines (e.g. Zoekt, OpenGrok, or Hound for instant symbol and regex search across multi-gigabyte repos)

### Category E: Isolated Execution Sandboxes & Code Runners
- **Isolated Docker Socket Proxy** (e.g., `docker-socket-proxy` restricting Docker daemon API access to prevent container escape)
- **Judge0 / Piston / Daytona Sandbox Runner** (Safe, multi-language code execution engine with strict CPU/memory timeouts for testing arbitrary agent-written scripts)
- Lightweight virtualization & runtime isolation tools (e.g., rootless Podman, gVisor `runsc`)

### Category F: Agent Memory, Vector Stores & Knowledge Graphs
- **Qdrant / ChromaDB** (Vector database for semantic search, memory retrieval, and embedding search)
- **Mem0 / Zep Server** (Autonomous agent long-term memory engine for maintaining cross-session user and company facts)
- **Graph Databases** (e.g. Neo4j / Kùzu for codebase knowledge graphs and architectural dependency mapping)

### Category G: LLM Gateways, Caching & Local Inference
- **LiteLLM Proxy** (OpenAI-compatible gateway supporting 100+ LLMs, load balancing, fallback routing, virtual API keys, budget enforcement, and spend tracking)
- **Ollama / vLLM** (Local model inference server for zero-cost embeddings, fast code completion, or air-gapped agent steps)
- Semantic caching layers (e.g. Redis for caching identical prompt/response pairs)

### Category H: Developer Testing, Mocking & Observability
- **Mailpit** (Mock SMTP server & web UI for testing email flows, password resets, and notifications without sending real emails)
- **LocalStack / MinIO** (Local AWS emulator and S3-compatible object storage for artifact hosting and cloud SDK testing)
- **WireMock / Mockoon** (Configurable HTTP mock server for third-party API contract testing)
- **OpenTelemetry Collector & Jaeger** (Distributed tracing sidecar to track latency, token usage, and subagent call trees)

---

## 2. Specification Standard (Per Supporting Service)

For **EACH** evaluated service, deliver:

1. **Service Identity & Purpose**:
   - Name, official repository, and current version tag.
   - Core value proposition: Why this service is better as a shared Compose sidecar rather than installed inside the agent container.
   - Target agent roles (e.g., Designer, QA, Reverse Engineer, Programmer).

2. **Docker Compose Service Block**:
   - Complete, copy-paste-ready YAML snippet.
   - Pinned official image tag (NO `:latest`).
   - Network isolation (attached to internal network; ports bound to `127.0.0.1` or omitted when accessible only internally).
   - Healthcheck definition (`test`, `interval`, `timeout`, `retries`).
   - Resource reservations & limits (`mem_limit`, `cpus`).
   - Volume mounts for persistent state/caches.
   - Compose Profile recommendation (`core`, `research`, `qa`, `devsec`, `media`).

3. **Agent Integration & Interface**:
   - How OpenCode v2 agents consume this service:
     - **Option 1: MCP Server**: Exact npm/PyPI package and `mcp` JSON block in `opencode.json`.
     - **Option 2: REST / HTTP API**: Endpoint URL (e.g. `http://firecrawl:3002/v1/scrape`), headers, and sample curl/fetch command.
     - **Option 3: CLI / Client Tool**: Binary or client library used by the agent to communicate with the service.

4. **Security, Sandboxing & Resource Footprint**:
   - Default memory and CPU consumption (idle vs peak).
   - Security considerations: Authentication tokens, rate limits, read-only filesystem flags, and sandboxing requirements.

---

## 3. Architecture & Composition Strategy

Provide a synthesized architectural plan for Docker Compose:

1. **Compose Profiles Architecture**:
   - Design a modular Compose profile strategy so users can start only what they need:
     - `default` / `core`: Paperclip + Postgres + OpenCode v2.
     - `--profile web-research`: Adds SearXNG + Firecrawl + Browserless.
     - `--profile devsec`: Adds Headless Ghidra + Semgrep + Docker-Socket-Proxy.
     - `--profile ai-gateway`: Adds LiteLLM + Qdrant.
     - `--profile qa-testing`: Adds Mailpit + MinIO + WireMock.
2. **Master `docker-compose.sidecars.yml`**:
   - Provide a complete, cohesive multi-service Docker Compose file integrating the top-tier supporting services with healthchecks, shared internal networks, and profile tags.
3. **OpenCode v2 Role Mapping Table**:
   - A cross-reference table mapping each specialist role to the sidecar services and MCP endpoints it connects to.

---

## 4. Deliverables & Output Format

- Write the complete research and specification report to `SUPPORTING_SERVICES.md`.
- Ensure all Docker image names and tags are verified against Docker Hub / GitHub Container Registry.
- Include a Mermaid architecture diagram visualizing how the Paperclip orchestrator, OpenCode agent fleet, and sidecar services communicate over the internal Docker network.
