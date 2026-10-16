# Supporting Software & Sidecar Services for Autonomous Agent Fleets
**Architecture, Evaluation & Production Specification for Paperclip + OpenCode v2**

---

## Executive Summary & Architectural Philosophy

Autonomous agent fleets running on **OpenCode v2** orchestrated by **Paperclip** require access to specialized, compute-heavy, and high-privilege capabilities: dynamic web scraping, headless reverse engineering, AST code queries, untrusted script execution, vector/graph memory retrieval, and distributed observability.

### Why Shared Sidecars Outperform Monolithic "Fat" Agent Containers
In early agent deployments, developers often attempt to install browsers, Java runtimes (for Ghidra), language toolchains, and database clients directly into the agent container. This pattern fails rapidly in production:
1. **Container Bloat & Rebuild Friction**: Bundling Chromium (1 GB+), OpenJDK/Ghidra (1.5 GB+), and multiple language compilers inflates agent container images to 8–15 GB, slowing CI/CD pipelines and deployment rollouts.
2. **Resource Exhaustion & Lack of Throttling**: A rogue agent spawning 10 headless browser instances or compiling large C++ binaries inside its own process will crash the agent runner and corrupt in-flight Paperclip tasks.
3. **Privilege Separation & Security Isolation**: Binary analysis tools (Ghidra, Radare2) and code runners execute potentially adversarial payloads. Isolating them behind network sidecars and gVisor/seccomp sandboxes prevents agent process takeover and container escapes.
4. **State Persistence & Multi-Agent Caching**: When an agent searches a 5 GB codebase or decompiles a firmware blob, downstream agents (QA, Refactorer, Reviewer) should consume the pre-indexed AST or decompiled C output via shared volumes or REST endpoints without repeating expensive work.

### Network Topology & Security Boundaries
All sidecars connect to an internal, user-defined Docker bridge network (`heretek`). No sidecar service binds directly to `0.0.0.0`. Where host inspection is necessary (such as web UIs for Jaeger, Mailpit, or SearXNG), ports are strictly bound to `127.0.0.1` (loopback) or guarded behind Paperclip's Caddy reverse proxy or Tailscale mesh sidecar.

```mermaid
flowchart TB
    subgraph Host ["Host System / Firewall"]
        direction TB

        subgraph External ["Host Ingress (Loopback or Mesh Only)"]
            Caddy["Caddy Reverse Proxy (:80/443)"]
            Tailscale["Tailscale Sidecar (Mesh IP)"]
            LocalBrowser["Dev Browser (127.0.0.1:3100)"]
        end

        subgraph InternalNet ["Docker Network: heretek (172.28.0.0/16)"]
            direction TB
            
            subgraph CoreGroup ["Profile: core (Always Running)"]
                Paperclip["Paperclip Orchestrator<br/>(Port 3100)"]
                Postgres[("PostgreSQL 17<br/>(Internal :5432)")]
                OpenCodePool["OpenCode v2 Fleet<br/>(Worker Processes)"]
            end

            subgraph WebResearch ["Profile: web-research"]
                SearXNG["SearXNG Metasearch<br/>(:8080)"]
                Firecrawl["Firecrawl Engine<br/>(:3002)"]
                Browserless["Browserless Stealth<br/>(:3000)"]
                Gotenberg["Gotenberg PDF/HTML<br/>(:3000)"]
                RedisWeb[("Redis Cache<br/>(:6379)")]
            end

            subgraph DevSec ["Profile: devsec"]
                Ghidra["Headless Ghidra<br/>(Bridge/MCP :1337)"]
                Radare["Radare2 / r2mcp<br/>(:9090)"]
                Semgrep["Semgrep Engine<br/>(:8000)"]
                SockProxy["Docker Socket Proxy<br/>(:2375 ro)"]
            end

            subgraph MemoryGraph ["Profile: ai-gateway"]
                LiteLLM["LiteLLM Gateway<br/>(:4000)"]
                Qdrant[("Qdrant Vector DB<br/>(:6333)")]
                Neo4j[("Neo4j Graph DB<br/>(:7474 / :7687)")]
                Ollama["Ollama Local LLM<br/>(:11434)"]
            end

            subgraph QATesting ["Profile: qa-testing"]
                Piston["Piston Code Sandbox<br/>(:2000)"]
                Mailpit["Mailpit SMTP/Web<br/>(:1025 / :8025)"]
                WireMock["WireMock API Mock<br/>(:8080)"]
                MinIO[("MinIO S3 Storage<br/>(:9000 / :9001)")]
            end

            subgraph Observability ["Profile: observability"]
                OTel["OTel Collector<br/>(:4317 / :4318)"]
                Jaeger["Jaeger Tracing UI<br/>(:16686)"]
            end
        end
    end

    LocalBrowser --> Paperclip
    Caddy --> Paperclip
    Tailscale --> Paperclip
    Paperclip <--> Postgres
    Paperclip --> OpenCodePool

    OpenCodePool -->|"HTTP / MCP"| WebResearch
    OpenCodePool -->|"HTTP / MCP"| DevSec
    OpenCodePool -->|"OpenAI API / Vector"| MemoryGraph
    OpenCodePool -->|"REST / SMTP"| QATesting
    OpenCodePool -->|"gRPC / OTLP"| Observability
```

---

## 1. Category A: Web Ingestion, Crawling & Search

### Service A.1: Firecrawl
* **Service Identity**: Firecrawl (`mendableai/firecrawl`)
* **Repository**: [https://github.com/mendableai/firecrawl](https://github.com/mendableai/firecrawl)
* **Image Tag**: `ghcr.io/mendableai/firecrawl:v1.17.2`
* **Core Value Proposition**: Monolithic scrapers struggle with JavaScript-heavy SPAs, paywalls, and cookie banners. Firecrawl orchestrates headless Playwright browsers behind a clean REST and WebSocket interface, automatically converting messy DOM structures into pristine, LLM-optimized Markdown while stripping advertising trackers, navigations, and styling scripts. Running Firecrawl as a sidecar keeps massive browser memory footprints and Playwright dependencies outside the agent runtime.
* **Target Roles**: Technical Researcher, Market Research Analyst, Competitive Intelligence Specialist, Documentation Lead, Bug Triage Specialist.

#### Docker Compose Service Block
```yaml
  firecrawl-redis:
    image: redis:7.4.1-alpine
    profiles: ["web-research"]
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes", "--maxmemory", "512mb", "--maxmemory-policy", "noeviction"]
    expose:
      - "6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    volumes:
      - firecrawl-redis-data:/data
    networks:
      - heretek
    cpus: "0.5"
    mem_limit: 768m

  firecrawl:
    image: ghcr.io/mendableai/firecrawl:v1.17.2
    profiles: ["web-research"]
    restart: unless-stopped
    depends_on:
      firecrawl-redis:
        condition: service_healthy
    expose:
      - "3002"
    environment:
      PORT: "3002"
      REDIS_URL: "redis://firecrawl-redis:6379"
      USE_PUPPETEER_CACHE: "true"
      PUPPETEER_WS_ENDPOINT: "ws://browserless:3000"
      NUM_WORKERS_PER_QUEUE: "4"
      LOGGING_LEVEL: "warn"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:3002/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 20s
    networks:
      - heretek
    cpus: "1.5"
    mem_limit: 2g
```

#### Agent Integration & Interface
* **Option 1: MCP Server (`firecrawl-mcp`)**
  In the agent role's `opencode.json`:
  ```json
  {
    "mcp": {
      "firecrawl": {
        "command": "npx",
        "args": ["-y", "firecrawl-mcp"],
        "env": {
          "FIRECRAWL_API_URL": "http://firecrawl:3002"
        }
      }
    }
  }
  ```
* **Option 2: REST / HTTP API**
  Endpoint: `POST http://firecrawl:3002/v1/scrape`
  ```bash
  curl -s -X POST http://firecrawl:3002/v1/scrape \
    -H "Content-Type: application/json" \
    -d '{
      "url": "https://docs.docker.com/compose/",
      "formats": ["markdown"],
      "onlyMainContent": true
    }' | jq -r '.data.markdown'
  ```
* **Option 3: CLI / Client Tool**
  OpenCode agents can invoke Python scripts utilizing `firecrawl-py`:
  ```python
  from firecrawl import FirecrawlApp
  app = FirecrawlApp(api_url="http://firecrawl:3002")
  scrape_result = app.scrape_url("https://example.com", params={"formats": ["markdown"]})
  ```

#### Security, Sandboxing & Resource Footprint
* **Resource Profile**: Idle: 120MB RAM, 0.05 CPU. Peak (during multi-page recursive crawling): 1.8GB RAM, 1.4 CPU.
* **Security Considerations**: Restrict crawling to external URLs and prevent Server-Side Request Forgery (SSRF) against internal metadata endpoints (e.g. `169.254.169.254` or internal Docker DNS) via Firecrawl's URL validation flags. Run as unprivileged user inside container.

---

### Service A.2: Crawl4AI
* **Service Identity**: Crawl4AI (`unclecode/crawl4ai`)
* **Repository**: [https://github.com/unclecode/crawl4ai](https://github.com/unclecode/crawl4ai)
* **Image Tag**: `unclecode/crawl4ai:0.9.4`
* **Core Value Proposition**: Crawl4AI is a lightning-fast, asynchronous web crawler purpose-built for LLMs. Unlike heavy browser farms, Crawl4AI provides direct pipeline extraction for CSS selectors, structured JSON extraction using Pydantic schemas, and media metadata capture without requiring external task brokers.
* **Target Roles**: Data Mining Specialist, LLM Fine-Tuning Engineer, Documentation Harvester.

#### Docker Compose Service Block
```yaml
  crawl4ai:
    image: unclecode/crawl4ai:0.9.4
    profiles: ["web-research"]
    restart: unless-stopped
    expose:
      - "11235"
    shm_size: "2gb"
    environment:
      CRAWL4AI_API_TOKEN: "${CRAWL4AI_API_TOKEN:-heretek-crawler-token}"
      MAX_CONCURRENT_TASKS: "5"
    healthcheck:
      test: ["CMD-SHELL", "python3 -c 'import urllib.request; urllib.request.urlopen(\"http://127.0.0.1:11235/health\")' || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "1.5"
    mem_limit: 2.5g
```

#### Agent Integration & Interface
* **Option 1: MCP Server**
  ```json
  {
    "mcp": {
      "crawl4ai": {
        "command": "uvx",
        "args": ["crawl4ai-mcp"],
        "env": {
          "CRAWL4AI_BASE_URL": "http://crawl4ai:11235",
          "CRAWL4AI_API_TOKEN": "heretek-crawler-token"
        }
      }
    }
  }
  ```
* **Option 2: REST / HTTP API**
  Endpoint: `POST http://crawl4ai:11235/crawl`
  ```bash
  curl -s -X POST http://crawl4ai:11235/crawl \
    -H "Authorization: Bearer heretek-crawler-token" \
    -H "Content-Type: application/json" \
    -d '{
      "urls": ["https://news.ycombinator.com"],
      "priority": 10,
      "extraction_strategy": "markdown"
    }' | jq .
  ```

#### Security, Sandboxing & Resource Footprint
* **Resource Profile**: Idle: 80MB RAM, 0.02 CPU. Peak: 2.1GB RAM, 1.2 CPU. Shared memory (`/dev/shm`) allocated at 2GB to prevent Chromium crash loops during DOM tree virtualization.

---

### Service A.3: SearXNG
* **Service Identity**: SearXNG (`searxng/searxng`)
* **Repository**: [https://github.com/searxng/searxng](https://github.com/searxng/searxng)
* **Image Tag**: `searxng/searxng:2024.10.16-ac56c663b`
* **Core Value Proposition**: Commercial search APIs (Google Custom Search, Bing Web Search, Tavily, Brave) impose strict per-request billing, rate limits, and query logging. SearXNG aggregates 70+ search engines locally with zero tracking, rotating proxies, and structured JSON output. It gives agent fleets unlimited private web search capabilities without exposing API keys.
* **Target Roles**: All Roles (General Web Search, API Discovery, Error Message Resolution).

#### Docker Compose Service Block
```yaml
  searxng-redis:
    image: redis:7.4.1-alpine
    profiles: ["web-research"]
    restart: unless-stopped
    command: ["redis-server", "--save", "", "--appendonly", "no"]
    expose:
      - "6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "0.2"
    mem_limit: 256m

  searxng:
    image: searxng/searxng:2024.10.16-ac56c663b
    profiles: ["web-research"]
    restart: unless-stopped
    depends_on:
      - searxng-redis
    expose:
      - "8080"
    ports:
      - "127.0.0.1:8888:8080" # Loopback UI inspection
    environment:
      SEARXNG_BASE_URL: "http://searxng:8080/"
      SEARXNG_REDIS_URL: "redis://searxng-redis:6379/0"
      SEARXNG_SECRET: "${SEARXNG_SECRET:?SEARXNG_SECRET must be set in .env}"
    volumes:
      - ./docker/searxng/settings.yml:/etc/searxng/settings.yml:ro
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:8080/healthz || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "1.0"
    mem_limit: 1g
```

#### Agent Integration & Interface
* **Option 1: MCP Server (`@kevinwatt/mcp-server-searxng`)**
  ```json
  {
    "mcp": {
      "searxng": {
        "command": "npx",
        "args": ["-y", "@kevinwatt/mcp-server-searxng"],
        "env": {
          "SEARXNG_API_URL": "http://searxng:8080"
        }
      }
    }
  }
  ```
* **Option 2: REST / HTTP API**
  Endpoint: `GET http://searxng:8080/search?q={query}&format=json`
  ```bash
  curl -s -G "http://searxng:8080/search" \
    --data-urlencode "q=rust tokio actor pattern" \
    --data-urlencode "format=json" \
    --data-urlencode "categories=it" | jq '.results[] | {title, url, content}'
  ```

#### Security, Sandboxing & Resource Footprint
* **Resource Profile**: Idle: 65MB RAM, 0.01 CPU. Peak: 450MB RAM, 0.8 CPU.
* **Security Configuration**: Set `server.limiter: false` in `settings.yml` since incoming traffic originates solely from the internal `heretek` network, and enable `search.formats: [html, json]`.

---

### Service A.4: Gotenberg
* **Service Identity**: Gotenberg (`gotenberg/gotenberg`)
* **Repository**: [https://github.com/gotenberg/gotenberg](https://github.com/gotenberg/gotenberg)
* **Image Tag**: `gotenberg/gotenberg:8.15.0`
* **Core Value Proposition**: Autonomous agents frequently need to generate PDF reports, convert Markdown/HTML specs into formal documentation, or parse PDFs into images for visual regression testing. Gotenberg provides a stateless API wrapping Chromium, LibreOffice, and PDFtk, avoiding the need to install 800MB of font packages and office runtimes inside agent containers.
* **Target Roles**: Technical Documentation Lead, UI/UX Designer, Executive Reporter.

#### Docker Compose Service Block
```yaml
  gotenberg:
    image: gotenberg/gotenberg:8.15.0
    profiles: ["web-research", "qa-testing"]
    restart: unless-stopped
    expose:
      - "3000"
    command:
      - "gotenberg"
      - "--api-port=3000"
      - "--chromium-restart-after=30"
      - "--chromium-auto-start=true"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:3000/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "1.0"
    mem_limit: 1.5g
```

#### Agent Integration & Interface
* **REST API Execution**: Convert Markdown to PDF
  ```bash
  curl --request POST 'http://gotenberg:3000/forms/chromium/convert/markdown' \
    --form 'files=@index.html' \
    --form 'files=@report.md' \
    -o spec_report.pdf
  ```

---

## 2. Category B: Resilient & Stealth Browser Automation

### Service B.1: Browserless (Stealth Chromium)
* **Service Identity**: Browserless Chromium (`ghcr.io/browserless/chromium`)
* **Repository**: [https://github.com/browserless/browserless](https://github.com/browserless/browserless)
* **Image Tag**: `ghcr.io/browserless/chromium:v2.24.2`
* **Core Value Proposition**: Modern web targets employ Cloudflare, Datadome, and Akamai bot protections that instantly block default headless Puppeteer/Playwright instances. Browserless injects stealth evasions (evading `navigator.webdriver`, spoofing canvas/WebGL fingerprints, randomizing user agents) and manages persistent browser contexts. OpenCode agents connect over standard Chrome DevTools Protocol (CDP) or WebSocket endpoints without compiling Chromium locally.
* **Target Roles**: End-to-End Automation Engineer, Adversarial Red-Proof Tester, Web Scraper.

#### Docker Compose Service Block
```yaml
  browserless:
    image: ghcr.io/browserless/chromium:v2.24.2
    profiles: ["web-research", "qa-testing"]
    restart: unless-stopped
    expose:
      - "3000"
    ports:
      - "127.0.0.1:3003:3000" # Host inspection / live debugger view
    environment:
      CONCURRENT: "5"
      QUEUED: "10"
      TIMEOUT: "60000"
      TOKEN: "${BROWSERLESS_TOKEN:-heretek-stealth-token}"
      ENABLE_DEBUGGER: "true"
      DEFAULT_STEALTH: "true"
      DEFAULT_HEADLESS: "new"
      CHROME_REFRESH_TIME: "1800000" # Periodic GC
    shm_size: "2gb"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:3000/pressure || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "2.0"
    mem_limit: 3g
```

#### Agent Integration & Interface
* **Option 1: MCP Server (`@modelcontextprotocol/server-puppeteer`)**
  ```json
  {
    "mcp": {
      "puppeteer": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-puppeteer"],
        "env": {
          "PUPPETEER_BROWSER_WS_ENDPOINT": "ws://browserless:3000?token=heretek-stealth-token&stealth=true"
        }
      }
    }
  }
  ```
* **Option 2: Playwright Remote Connection (TypeScript / Node)**
  ```typescript
  import { chromium } from "playwright";
  const browser = await chromium.connectOverCDP(
    "ws://browserless:3000?token=heretek-stealth-token&stealth=true"
  );
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto("https://bot.sannysoft.com");
  await page.screenshot({ path: "stealth_audit.png", fullPage: true });
  await browser.close();
  ```
* **Option 3: HTTP Screenshot Endpoint**
  ```bash
  curl -s -X POST "http://browserless:3000/screenshot?token=heretek-stealth-token" \
    -H "Content-Type: application/json" \
    -d '{
      "url": "https://example.com",
      "options": { "fullPage": true, "type": "png" }
    }' --output screenshot.png
  ```

#### Security, Sandboxing & Resource Footprint
* **Resource Profile**: Idle: 180MB RAM, 0.05 CPU. Peak: 2.8GB RAM, 1.9 CPU.
* **Security Controls**: Authenticated via `TOKEN`. Container capabilities dropped (`CAP_SYS_ADMIN` avoided by utilizing Browserless user namespaces).

---

### Service B.2: mitmproxy Traffic Auditor
* **Service Identity**: mitmproxy (`mitmproxy/mitmproxy`)
* **Repository**: [https://github.com/mitmproxy/mitmproxy](https://github.com/mitmproxy/mitmproxy)
* **Image Tag**: `mitmproxy/mitmproxy:11.0.2`
* **Core Value Proposition**: In an autonomous organization, agents making unmonitored external HTTP calls present data exfiltration and credential leakage risks. Running mitmproxy as an audited outbound egress gateway enables automated logging of all agent HTTP/HTTPS payloads, inspection of API contracts, and cryptographic replay of third-party responses for determinism.
* **Target Roles**: Site Reliability Engineer, SRE / SecOps Lead, QA Contract Tester.

#### Docker Compose Service Block
```yaml
  mitmproxy:
    image: mitmproxy/mitmproxy:11.0.2
    profiles: ["devsec", "qa-testing"]
    restart: unless-stopped
    command: ["mitmweb", "--web-host", "0.0.0.0", "--web-port", "8081", "--set", "block_global=false"]
    expose:
      - "8080" # Proxy port
      - "8081" # Web UI
    ports:
      - "127.0.0.1:8081:8081" # Loopback web UI for flow inspection
    volumes:
      - mitmproxy-certs:/home/mitmproxy/.mitmproxy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:8081 || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "0.5"
    mem_limit: 512m
```

---

## 3. Category C: Defensive Binary Analysis, Decompilation & Reverse Engineering

### Service C.1: Headless Ghidra Server & MCP Bridge
* **Service Identity**: Headless Ghidra Bridge (`blacktop/ghidra`)
* **Repository**: [https://github.com/blacktop/docker-ghidra](https://github.com/blacktop/docker-ghidra) / [https://github.com/bethington/ghidra-mcp](https://github.com/bethington/ghidra-mcp)
* **Image Tag**: `blacktop/ghidra:11.2`
* **Core Value Proposition**: Ghidra is the premier NSA open-source SRE framework. Running Ghidra inside an agent container requires 1.5 GB of JVM dependencies and risks system lockup during intense decompilation passes. As an isolated sidecar, Ghidra executes headless batch scripts (`analyzeHeadless`), exports control-flow graphs, generates decompiled C code, and serves cross-reference queries over a lightweight RPC/MCP socket.
* **Target Roles**: Reverse Engineering Specialist, Binary Vulnerability Researcher, Firmware Security Auditor.

#### Docker Compose Service Block
```yaml
  ghidra:
    image: blacktop/ghidra:11.2
    profiles: ["devsec"]
    restart: unless-stopped
    expose:
      - "1337" # Headless bridge / GhidraMCP port
    environment:
      MAXMEM: "4G"
    volumes:
      - ./workspaces/binaries:/samples:ro
      - ghidra-projects:/ghidra/projects
      - ./docker/ghidra/scripts:/ghidra/scripts:ro
    entrypoint: ["/entrypoint.sh"]
    command: ["server"]
    healthcheck:
      test: ["CMD-SHELL", "pgrep -f ghidra || exit 1"]
      interval: 20s
      timeout: 5s
      retries: 3
      start_period: 30s
    networks:
      - heretek
    cpus: "2.0"
    mem_limit: 4g
```

#### Agent Integration & Interface
* **Option 1: MCP Server (`bethington/ghidra-mcp` or `suidpit/ghidra-mcp`)**
  ```json
  {
    "mcp": {
      "ghidra": {
        "command": "python3",
        "args": ["-m", "ghidra_mcp"],
        "env": {
          "GHIDRA_HOST": "ghidra",
          "GHIDRA_PORT": "1337"
        }
      }
    }
  }
  ```
* **Option 2: Headless CLI Script Execution via Docker Exec**
  OpenCode reverse engineering agents can trigger headless analysis passes:
  ```bash
  docker exec heretek-crew-ghidra-1 /ghidra/support/analyzeHeadless \
    /ghidra/projects default_proj \
    -import /samples/firmware.bin \
    -postScript /ghidra/scripts/DecompileAll.java /ghidra/projects/output.c
  ```

#### Security, Sandboxing & Resource Footprint
* **Resource Profile**: Idle: 350MB RAM (JVM baseline). Peak: 3.8GB RAM, 2.0 CPU during full binary decompilation passes.
* **Security Controls**: Mount target binaries volume as read-only (`:ro`). Ensure JVM process drops all root capabilities.

---

### Service C.2: Radare2 / r2mcp
* **Service Identity**: Radare2 (`radare/radare2`)
* **Repository**: [https://github.com/radareorg/radare2](https://github.com/radareorg/radare2)
* **Image Tag**: `radare/radare2:6.0.0`
* **Core Value Proposition**: While Ghidra provides deep decompilation, it has significant startup latency. Radare2 starts in milliseconds, making it optimal for rapid binary triage, string extraction, entropy scanning, ELF header inspection, and fast disassembling of specific functions.
* **Target Roles**: Binary Triage Specialist, C/C++ Systems Engineer, Exploit Mitigator.

#### Docker Compose Service Block
```yaml
  radare2:
    image: radare/radare2:6.0.0
    profiles: ["devsec"]
    restart: unless-stopped
    expose:
      - "9090"
    working_dir: /samples
    volumes:
      - ./workspaces/binaries:/samples:ro
    command: ["r2", "-qc=H 0.0.0.0:9090", "/samples/target.elf"]
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:9090/cmd/? || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "1.0"
    mem_limit: 1g
```

#### Agent Integration & Interface
* **Option 1: Official MCP Server (`radareorg/radare2-mcp`)**
  ```json
  {
    "mcp": {
      "r2mcp": {
        "command": "r2pm",
        "args": ["-r", "r2mcp", "--http", "http://radare2:9090"]
      }
    }
  }
  ```
* **Option 2: HTTP API via r2pipe web server**
  ```bash
  # Execute JSON disassembly command (pdfj)
  curl -s "http://radare2:9090/cmd/pdfj%20sym.main" | jq .
  ```

---

### Service C.3: REA (Reverse Engineer Anything) & OpenCode-REA
* **Service Identity**: REA MCP Bridge & Plugin (`morluto/rea` & `Heretek-AI/opencode-rea`)
* **Repository**: [https://github.com/morluto/rea](https://github.com/morluto/rea) / [https://github.com/Heretek-AI/opencode-rea](https://github.com/Heretek-AI/opencode-rea)
* **Core Value Proposition**: REA (Reverse Engineer Anything) exposes over 120 specialized reverse engineering tools bridging Ghidra, Binary Ninja, Radare2, and APK tools. Combined with `@heretek-ai/opencode-rea`, it enables OpenCode v2 agents to generate interactive control-flow graphs (CFGs), execute headless decompilation passes, trace data-flow cross references, and semantically rename opaque functions with zero hallucinations.
* **Target Roles**: Binary & Protocol Reverse Engineer (`binary-reverse-eng`), Firmware Security Analyst (`firmware-sec-analyst`).

#### Agent Integration via OpenCode v2 Plugin & MCP
In `/roles/binary-reverse-eng/opencode/opencode.json`:
```json
{
  "plugins": ["opencode-rea", "opencode-mem"],
  "mcp": {
    "servers": {
      "rea": {
        "type": "local",
        "command": ["npx", "-y", "@morluto/rea-mcp"],
        "env": {
          "GHIDRA_INSTALL_DIR": "/opt/ghidra"
        }
      }
    }
  }
}
```

---

## 4. Category D: Fast Codebase Search, Indexing & AST Analysis

### Service D.1: ast-grep
* **Service Identity**: ast-grep (`ast-grep`)
* **Repository**: [https://github.com/ast-grep/ast-grep](https://github.com/ast-grep/ast-grep)
* **Version**: `0.33.0` (Containerized via `mcp/ast-grep` or npm `@ast-grep/cli@0.33.0`)
* **Core Value Proposition**: Regular expressions are brittle for semantic code search (failing on whitespace variations, comments, and multi-line syntax). ast-grep parses code into concrete syntax trees (CST) across 20+ languages. Agents can find complex syntactic structures (e.g. `fn $NAME($$$ARGS) { await $EXPR; }`) and perform type-safe structural rewrites instantly without hallucinating regex lookarounds.
* **Target Roles**: Refactoring Architect, Code Reviewer, Static Analysis Specialist.

#### Agent Integration via MCP
In `opencode.json`:
```json
{
  "mcp": {
    "ast-grep": {
      "command": "npx",
      "args": ["-y", "@ast-grep/cli@0.33.0", "lsp", "--stdio"]
    }
  }
}
```
* **CLI Bridge Example**:
  ```bash
  ast-grep scan --pattern 'function $FUNC($$$ARGS) { console.log($$$A); }' --json /paperclip/workspaces/app
  ```

---

### Service D.2: Semgrep Local Analysis Engine
* **Service Identity**: Semgrep (`semgrep/semgrep`)
* **Repository**: [https://github.com/semgrep/semgrep](https://github.com/semgrep/semgrep)
* **Image Tag**: `semgrep/semgrep:1.97.0`
* **Core Value Proposition**: Semgrep enforces semantic security rulesets and architectural constraints locally. Running Semgrep as a shared analysis sidecar allows security and QA agents to mount repository checkouts, audit for OWASP vulnerabilities (SQL injection, unsafe deserialization, SSRF), and generate SARIF compliance reports without uploading code to third-party SaaS.
* **Target Roles**: Application Security Lead, QA Compliance Auditor, DevSecOps Lead.

#### Docker Compose Service Block
```yaml
  semgrep:
    image: semgrep/semgrep:1.97.0
    profiles: ["devsec", "qa-testing"]
    restart: unless-stopped
    expose:
      - "8000"
    volumes:
      - ./workspaces:/src:ro
      - semgrep-cache:/root/.cache/semgrep
    entrypoint: ["sleep", "infinity"] # Executed on-demand by agent runners
    networks:
      - heretek
    cpus: "2.0"
    mem_limit: 3g
```

#### Agent Integration & Interface
* **CLI Trigger**:
  ```bash
  docker exec heretek-crew-semgrep-1 semgrep scan \
    --config "p/security-audit" \
    --config "p/owasp-top-ten" \
    --json \
    --output /src/security_audit.json /src/repo
  ```

---

### Service D.3: Hound Code Search Engine
* **Service Identity**: Hound (`hound-search/hound`)
* **Repository**: [https://github.com/hound-search/hound](https://github.com/hound-search/hound)
* **Image Tag**: `ghcr.io/hound-search/hound:v0.6.0`
* **Core Value Proposition**: On multi-gigabyte codebases with dozens of microservices, `grep` or `find` over Docker volume mounts causes severe disk I/O bottlenecks. Hound indexes repositories into memory using trigrams, providing sub-millisecond regex search across millions of lines of code via a clean REST API.
* **Target Roles**: System Architect, Legacy Migration Engineer, Platform Lead.

#### Docker Compose Service Block
```yaml
  hound:
    image: ghcr.io/hound-search/hound:v0.6.0
    profiles: ["devsec", "web-research"]
    restart: unless-stopped
    expose:
      - "6080"
    ports:
      - "127.0.0.1:6080:6080"
    volumes:
      - ./docker/hound/config.json:/data/config.json:ro
      - ./workspaces:/workspaces:ro
      - hound-data:/data
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:6080/api/v1/healthz || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "1.0"
    mem_limit: 2g
```

#### REST Query Example:
```bash
curl -s "http://hound:6080/api/v1/search?q=class.*Handler&files=*.ts&repos=*" | jq .
```

---

## 5. Category E: Isolated Execution Sandboxes & Code Runners

### Service E.1: Isolated Docker Socket Proxy
* **Service Identity**: Docker Socket Proxy (`tecnativa/docker-socket-proxy`)
* **Repository**: [https://github.com/Tecnativa/docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy)
* **Image Tag**: `tecnativa/docker-socket-proxy:0.3.0`
* **Core Value Proposition**: Providing autonomous agents with raw `/var/run/docker.sock` access allows immediate root compromise of the host machine (e.g. `docker run -v /:/host alpine rm -rf /`). Docker Socket Proxy acts as a strict Layer 7 firewall for Docker's engine API, permitting container creation while blocking privileged flags, host mounts, network reconfiguration, and Swarm modifications.
* **Target Roles**: DevOps / Infrastructure Specialist, CI Pipeline Engineer, Test Runner.

#### Docker Compose Service Block
```yaml
  docker-socket-proxy:
    image: tecnativa/docker-socket-proxy:0.3.0
    profiles: ["core", "devsec"]
    restart: unless-stopped
    expose:
      - "2375"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      # Explicit API white-listing: Read operations & controlled container starts
      CONTAINERS: "1"
      IMAGES: "1"
      INFO: "1"
      VERSION: "1"
      POST: "1"
      # Strict blocks on dangerous primitives
      VOLUMES: "0"
      NETWORKS: "0"
      NODES: "0"
      SWARM: "0"
      SYSTEM: "0"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:2375/version || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "0.2"
    mem_limit: 128m
```

---

### Service E.2: Piston Code Execution Sandbox
* **Service Identity**: Piston (`engineer-man/piston`)
* **Repository**: [https://github.com/engineer-man/piston](https://github.com/engineer-man/piston)
* **Image Tag**: `ghcr.io/engineer-man/piston:v2.0.0`
* **Core Value Proposition**: When agents write and test code snippets (Python, Rust, C++, Go, JavaScript), executing them directly in the agent container risks infinite loops, fork bombs, and filesystem corruption. Piston runs untrusted code inside isolated cgroups with strictly enforced CPU time limits (default 3s), memory caps, and process caps.
* **Target Roles**: Programmer, QA Tester, Algorithm Specialist, Data Scientist.

#### Docker Compose Service Block
```yaml
  piston:
    image: ghcr.io/engineer-man/piston:v2.0.0
    profiles: ["qa-testing", "devsec"]
    restart: unless-stopped
    expose:
      - "2000"
    volumes:
      - piston-packages:/piston/packages
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:2000/api/v2/runtimes || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "2.0"
    mem_limit: 2g
```

#### REST Execution Example:
```bash
curl -s -X POST http://piston:2000/api/v2/execute \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "version": "3.10.0",
    "files": [{ "content": "import math\nprint(f\"Result: {math.sqrt(1764)}\")" }],
    "run_timeout": 3000
  }' | jq .
```

---

## 6. Category F: Agent Memory, Vector Stores & Knowledge Graphs

### Service F.1: Qdrant Vector Database
* **Service Identity**: Qdrant (`qdrant/qdrant`)
* **Repository**: [https://github.com/qdrant/qdrant](https://github.com/qdrant/qdrant)
* **Image Tag**: `qdrant/qdrant:v1.12.5`
* **Core Value Proposition**: OpenCode agents have finite context windows. Storing project documentation, architecture decisions, and historical bug fixes in Qdrant enables sub-10ms semantic retrieval across millions of chunked embeddings. Qdrant is written in Rust, offering low memory overhead and payload filtering.
* **Target Roles**: Memory Architect, Researcher, Technical PM, Lead Architect.

#### Docker Compose Service Block
```yaml
  qdrant:
    image: qdrant/qdrant:v1.12.5
    profiles: ["ai-gateway"]
    restart: unless-stopped
    expose:
      - "6333" # HTTP REST
      - "6334" # gRPC
    ports:
      - "127.0.0.1:6333:6333" # Web UI / Dashboard
    environment:
      QDRANT__SERVICE__ENABLE_TLS: "false"
      QDRANT__STORAGE__PERFORMANCE__MAX_SEARCH_THREADS: "4"
    volumes:
      - qdrant-storage:/qdrant/storage
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:6333/readyz || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "1.5"
    mem_limit: 2g
```

#### Agent Integration & Interface
* **Option 1: Official Qdrant MCP Server (`mcp-server-qdrant`)**
  ```json
  {
    "mcp": {
      "qdrant": {
        "command": "uvx",
        "args": ["mcp-server-qdrant"],
        "env": {
          "QDRANT_URL": "http://qdrant:6333",
          "COLLECTION_NAME": "agent_fleet_memory"
        }
      }
    }
  }
  ```

---

### Service F.2: Neo4j Graph Database
* **Service Identity**: Neo4j Community (`neo4j`)
* **Repository**: [https://github.com/neo4j/neo4j](https://github.com/neo4j/neo4j)
* **Image Tag**: `neo4j:5.26.0-community-bullseye`
* **Core Value Proposition**: Vector search finds semantically similar text, but fails to model structural relationships (e.g. "Which microservice imports this schema?" or "Who inherits from this abstract base class?"). Neo4j maintains codebase knowledge graphs, tracking call trees, module dependencies, and role permissions.
* **Target Roles**: System Architect, Codebase Memory Maintainer, Refactoring Lead.

#### Docker Compose Service Block
```yaml
  neo4j:
    image: neo4j:5.26.0-community-bullseye
    profiles: ["ai-gateway"]
    restart: unless-stopped
    expose:
      - "7474" # HTTP Browser
      - "7687" # Bolt protocol
    ports:
      - "127.0.0.1:7474:7474"
    environment:
      NEO4J_AUTH: "neo4j/${NEO4J_PASSWORD:?NEO4J_PASSWORD must be set in .env}"
      NEO4J_PLUGINS: '["apoc"]'
      server_memory_heap_initial__size: "512m"
      server_memory_heap_max__size: "1536m"
      server_memory_pagecache_size: "512m"
    volumes:
      - neo4j-data:/data
      - neo4j-logs:/logs
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:7474 || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 4
      start_period: 30s
    networks:
      - heretek
    cpus: "1.5"
    mem_limit: 2.5g
```

#### Agent Integration & Interface
* **Option 1: Official Neo4j MCP Server (`neo4j-mcp`)**
  ```json
  {
    "mcp": {
      "neo4j": {
        "command": "npx",
        "args": ["-y", "neo4j-mcp"],
        "env": {
          "NEO4J_URI": "bolt://neo4j:7687",
          "NEO4J_USERNAME": "neo4j",
          "NEO4J_PASSWORD": "${NEO4J_PASSWORD}"
        }
      }
    }
  }
  ```

---

## 7. Category G: LLM Gateways, Caching & Local Inference

### Service G.1: LiteLLM Proxy
* **Service Identity**: LiteLLM Proxy (`ghcr.io/berriai/litellm`)
* **Repository**: [https://github.com/BerriAI/litellm](https://github.com/BerriAI/litellm)
* **Image Tag**: `ghcr.io/berriai/litellm:v1.54.0`
* **Core Value Proposition**: When 50 autonomous agents invoke LLMs simultaneously, they risk hitting API rate limits, provider outages, and uncontrollable costs. LiteLLM acts as an OpenAI-compatible routing gateway supporting 100+ backends (Anthropic, OpenAI, Gemini, Bedrock, Ollama). It provides automatic fallback routing, virtual team API keys with hard spend caps, and token usage telemetry.
* **Target Roles**: All Agent Roles (Primary LLM Gateway for OpenCode).

#### Docker Compose Service Block
```yaml
  litellm:
    image: ghcr.io/berriai/litellm:v1.54.0
    profiles: ["ai-gateway"]
    restart: unless-stopped
    expose:
      - "4000"
    ports:
      - "127.0.0.1:4000:4000" # Admin dashboard
    volumes:
      - ./docker/litellm/config.yaml:/app/config.yaml:ro
    environment:
      LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY must be set in .env}"
      DATABASE_URL: "postgres://${POSTGRES_USER:-paperclip}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB:-paperclip}"
      STORE_MODEL_IN_DB: "True"
    command: ["--config", "/app/config.yaml", "--port", "4000", "--num_workers", "4"]
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:4000/health/readiness || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "1.0"
    mem_limit: 1.5g
```

#### Sample Configuration (`docker/litellm/config.yaml`):
```yaml
model_list:
  - model_name: claude-3-7-sonnet
    litellm_params:
      model: anthropic/claude-3-7-sonnet-20250219
      api_key: os.environ/ANTHROPIC_API_KEY
  - model_name: fallback-gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
router_settings:
  routing_strategy: usage-based-routing
  fallbacks: [{"claude-3-7-sonnet": ["fallback-gpt-4o"]}]
```

---

### Service G.2: Ollama Local Inference Server
* **Service Identity**: Ollama (`ollama/ollama`)
* **Repository**: [https://github.com/ollama/ollama](https://github.com/ollama/ollama)
* **Image Tag**: `ollama/ollama:0.5.4`
* **Core Value Proposition**: For routine tasks like text embedding generation, commit message formatting, and simple regex creation, calling commercial cloud models incurs unnecessary latency and cost. Ollama provides zero-cost local inference for models like `nomic-embed-text` and `qwen2.5-coder:7b`.
* **Target Roles**: Code Style Specialist, Git Automator, Local Embedding Engine.

#### Docker Compose Service Block
```yaml
  ollama:
    image: ollama/ollama:0.5.4
    profiles: ["ai-gateway"]
    restart: unless-stopped
    expose:
      - "11434"
    volumes:
      - ollama-models:/root/.ollama
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:11434/api/tags || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "4.0" # Utilize host CPU cores or configure GPU pass-through
    mem_limit: 8g
```

---

## 8. Category H: Developer Testing, Mocking & Observability

### Service H.1: Mailpit Mock SMTP Server
* **Service Identity**: Mailpit (`axllent/mailpit`)
* **Repository**: [https://github.com/axllent/mailpit](https://github.com/axllent/mailpit)
* **Image Tag**: `axllent/mailpit:v1.21.8`
* **Core Value Proposition**: When agents build and test user registration, password resets, or email alert pipelines, sending real emails risks spamming external users or getting domains blacklisted. Mailpit acts as a zero-configuration catch-all SMTP server with a REST API allowing test agents to retrieve, inspect, and verify message contents and HTML formatting automatically.
* **Target Roles**: Fullstack Programmer, QA Test Automation Specialist.

#### Docker Compose Service Block
```yaml
  mailpit:
    image: axllent/mailpit:v1.21.8
    profiles: ["qa-testing"]
    restart: unless-stopped
    expose:
      - "1025" # SMTP port
      - "8025" # Web UI & REST API
    ports:
      - "127.0.0.1:8025:8025" # Host web view
    environment:
      MP_MAX_MESSAGES: "5000"
      MP_DATABASE: "" # In-memory
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:8025/api/v1/messages || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "0.2"
    mem_limit: 256m
```

#### REST Verification Example:
```bash
# Agent verifies that a password reset email was dispatched with a token
curl -s "http://mailpit:8025/api/v1/messages" | jq '.messages[0] | {To, Subject, Snippet}'
```

---

### Service H.2: MinIO S3-Compatible Object Storage
* **Service Identity**: MinIO (`minio/minio`)
* **Repository**: [https://github.com/minio/minio](https://github.com/minio/minio)
* **Image Tag**: `minio/minio:RELEASE.2024-11-07T00-52-20Z`
* **Core Value Proposition**: Cloud-native software expects AWS S3 for hosting build artifacts, binary releases, screenshots, and logs. MinIO provides high-performance, S3 API-compatible local object storage without cloud costs or latency.
* **Target Roles**: Cloud Platform Specialist, Release Manager, CI/CD Automator.

#### Docker Compose Service Block
```yaml
  minio:
    image: minio/minio:RELEASE.2024-11-07T00-52-20Z
    profiles: ["qa-testing", "core"]
    restart: unless-stopped
    command: ["server", "/data", "--console-address", ":9001"]
    expose:
      - "9000" # S3 API
      - "9001" # Web Console
    ports:
      - "127.0.0.1:9001:9001"
    environment:
      MINIO_ROOT_USER: "${MINIO_ROOT_USER:-heretekadmin}"
      MINIO_ROOT_PASSWORD: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD must be set in .env}"
    volumes:
      - minio-data:/data
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:9000/minio/health/live || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "0.5"
    mem_limit: 1g
```

---

### Service H.3: WireMock API Mocking Engine
* **Service Identity**: WireMock (`wiremock/wiremock`)
* **Repository**: [https://github.com/wiremock/wiremock](https://github.com/wiremock/wiremock)
* **Image Tag**: `wiremock/wiremock:3.10.0-alpine`
* **Core Value Proposition**: Autonomous testing requires simulating payment gateways (Stripe), OAuth providers (GitHub/Google), and third-party webhooks with controlled delays and error codes (HTTP 429, 500). WireMock provides dynamic stubbing, stateful scenario simulation, and request verification via JSON APIs.
* **Target Roles**: API & Contract Testing Specialist, Backend Programmer.

#### Docker Compose Service Block
```yaml
  wiremock:
    image: wiremock/wiremock:3.10.0-alpine
    profiles: ["qa-testing"]
    restart: unless-stopped
    expose:
      - "8080"
    ports:
      - "127.0.0.1:8089:8080"
    volumes:
      - ./docker/wiremock/mappings:/home/wiremock/mappings
    command: ["--verbose", "--global-response-templating"]
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:8080/__admin/health || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "0.5"
    mem_limit: 512m
```

---

### Service H.4: OpenTelemetry Collector & Jaeger Tracing
* **Service Identity**: Jaeger All-In-One (`jaegertracing/all-in-one`) & OTel Collector (`otel/opentelemetry-collector-contrib`)
* **Repository**: [https://github.com/jaegertracing/jaeger](https://github.com/jaegertracing/jaeger)
* **Image Tag**: `jaegertracing/all-in-one:1.63.0`
* **Core Value Proposition**: When an autonomous agent delegates tasks across multiple subagents, diagnosing latency spikes or prompt loops is difficult without distributed tracing. Jaeger collects OpenTelemetry spans generated by Paperclip, LiteLLM, and OpenCode, providing a visual timeline of agent tool executions and subagent calls.
* **Target Roles**: Observability Engineer, Performance Profiler, Fleet Architect.

#### Docker Compose Service Block
```yaml
  jaeger:
    image: jaegertracing/all-in-one:1.63.0
    profiles: ["observability"]
    restart: unless-stopped
    expose:
      - "4317" # OTLP gRPC
      - "4318" # OTLP HTTP
      - "16686" # UI
    ports:
      - "127.0.0.1:16686:16686" # Web UI
    environment:
      COLLECTOR_OTLP_ENABLED: "true"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:16686 || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "0.5"
    mem_limit: 1g
```

---

## 9. Category I: Mobile Device & Emulation Testing

### Service I.1: Docker-Android Emulator & noVNC
* **Service Identity**: Docker-Android (`budtmo/docker-android`)
* **Repository**: [https://github.com/budtmo/docker-android](https://github.com/budtmo/docker-android)
* **Image Tag**: `budtmo/docker-android:emulator_14.0_v3.8.0-p1`
* **Core Value Proposition**: Testing native Android applications requires a full Android virtual device (AVD) running hardware acceleration (KVM). Bundling an emulator into an agent container is impossible due to KVM device requirements and X11/noVNC graphics stacks. `docker-android` provides an isolated, containerized Android 14.0 emulator exposing standard ADB on port 5555 and a noVNC web interface on port 6080.
* **Target Roles**: Mobile Android Specialist (`android-mobile-spec`), Mobile Web Engineer (`mobile-web-eng`), E2E Automation Engineer (`e2e-browser-qa`).

#### Docker Compose Service Block
```yaml
  docker-android:
    image: budtmo/docker-android:emulator_14.0_v3.8.0-p1
    profiles: ["mobile"]
    restart: unless-stopped
    privileged: true
    devices:
      - "/dev/kvm:/dev/kvm"
    expose:
      - "5555" # ADB bridge
      - "6080" # noVNC web view
    ports:
      - "127.0.0.1:5555:5555"
      - "127.0.0.1:6080:6080"
    environment:
      EMULATOR_DEVICE: "Samsung Galaxy S10"
      WEB_VNC: "true"
    volumes:
      - docker-android-data:/root
    healthcheck:
      test: ["CMD-SHELL", "adb devices | grep -q 'device' || exit 1"]
      interval: 20s
      timeout: 10s
      retries: 5
      start_period: 60s
    networks:
      - heretek
    cpus: "2.0"
    mem_limit: 4g
```

#### Agent Integration: Mobile-MCP & Google Artemis
Agents communicate with the containerized emulator via `mobile-next/mobile-mcp` and automate UI exploration with `google/artemis`:
1. **Mobile-MCP**: Provides MCP tools for UI hierarchy inspection, screen taps, text input, screenshot capture, and ADB shell commands.
2. **Google Artemis**: Automatic UI testing and exploration framework that uses reinforcement learning and heuristic graph exploration to discover crashes, ANRs, and edge cases.

---

## 10. Architecture & Composition Strategy

### 1. Compose Profiles Taxonomy
To ensure lean resource usage, services are segregated into logical Docker Compose profiles. The base stack (`postgres` and `paperclip`) runs under `default` (no profiles specified). Operators start additional capabilities on-demand:

| Profile Name | Included Supporting Services | Memory Budget (Idle / Peak) | Primary Use Case |
| :--- | :--- | :--- | :--- |
| **`default` / `core`** | `postgres`, `paperclip`, `docker-socket-proxy` | 1.2 GB / 4.5 GB | Standard agent workflow, local code editing, CLI tools |
| **`--profile web-research`** | `searxng`, `searxng-redis`, `firecrawl`, `firecrawl-redis`, `browserless`, `gotenberg` | 1.8 GB / 6.5 GB | Deep internet research, documentation extraction, web scraping |
| **`--profile devsec`** | `ghidra`, `radare2`, `semgrep`, `hound`, `docker-socket-proxy` | 2.5 GB / 8.0 GB | Binary reverse engineering, vulnerability audits, firmware triage |
| **`--profile mobile`** | `docker-android` | 1.5 GB / 4.0 GB | Native Android app testing, ADB bridge, Artemis UI exploration |
| **`--profile ai-gateway`** | `litellm`, `qdrant`, `neo4j`, `ollama` | 2.2 GB / 12.0 GB | Shared model routing, vector retrieval, codebase knowledge graph |
| **`--profile qa-testing`** | `piston`, `mailpit`, `wiremock`, `minio`, `browserless` | 1.5 GB / 5.5 GB | Unit/integration testing, mocking APIs, sandboxed scripts |
| **`--profile observability`**| `jaeger`, `otel-collector` | 0.8 GB / 2.0 GB | Telemetry, token usage tracking, distributed trace visualization |

---

### 2. OpenCode v2 Role-to-Sidecar Mapping Matrix

The following matrix cross-references the 9 functional departments and key specialist roles against the sidecars, protocols, and MCP modules they consume:

| Department / Role | Primary Sidecar Services | Integration Interface | Access Protocols & Ports |
| :--- | :--- | :--- | :--- |
| **Executive: System Architect** | `neo4j`, `hound`, `gotenberg` | `neo4j-mcp`, REST API | Bolt :7687, HTTP :6080, HTTP :3000 |
| **Executive: Tech Doc Lead** | `gotenberg`, `firecrawl`, `searxng` | `firecrawl-mcp`, REST | HTTP :3000, HTTP :3002, HTTP :8080 |
| **Web: UI/UX Designer** | `browserless`, `gotenberg` | `@modelcontextprotocol/server-puppeteer` | WS :3000 (CDP), HTTP :3000 |
| **Web: Performance Engineer** | `browserless`, `jaeger` | CDP, OTLP Tracing | WS :3000, gRPC :4317 |
| **Language: C/C++ Specialist** | `radare2`, `piston`, `hound` | `r2mcp`, REST API | HTTP :9090, HTTP :2000, HTTP :6080 |
| **Language: Rust Specialist** | `piston`, `ast-grep`, `qdrant` | `ast-grep` CLI, `qdrant-mcp` | HTTP :2000, HTTP :6333 |
| **Language: Android Specialist** | `docker-android` | `mobile-mcp`, ADB | TCP :5555, HTTP :6080 |
| **Platform: SRE / SecOps** | `mitmproxy`, `docker-socket-proxy`, `jaeger` | REST API, Docker Engine API | HTTP :8081, HTTP :2375, HTTP :16686 |
| **Platform: DBA Specialist** | `postgres`, `redis`, `qdrant` | Direct TCP client | TCP :5432, TCP :6379, HTTP :6333 |
| **QA: E2E Automation Eng** | `browserless`, `mailpit`, `wiremock` | Playwright CDP, REST | WS :3000, HTTP :8025, HTTP :8080 |
| **QA: Red-Proof Saboteur** | `piston`, `mitmproxy`, `browserless` | REST API, HTTP Proxy | HTTP :2000, HTTP :8080 |
| **DevSec: Reverse Engineer** | `ghidra`, `radare2` | `rea` MCP (`morluto/rea`), `opencode-rea`, `r2mcp` | TCP :1337, HTTP :9090 |
| **DevSec: Code Auditor** | `semgrep`, `ast-grep`, `hound` | CLI, `ast-grep-mcp` | Direct volume scan, HTTP :6080 |

---

## 11. Master `docker-compose.sidecars.yml`

This file is designed to be composed seamlessly with `docker-compose.yml`:
```bash
docker compose -f docker-compose.yml -f docker-compose.sidecars.yml --profile web-research --profile devsec up -d
```

```yaml
# Heretek-Crew: Master Supporting Software & Sidecars Specification
# Orchestrated alongside Paperclip and OpenCode v2 on the 'heretek' network.

version: "3.8"

services:
  # ============================================================================
  # CATEGORY A: WEB INGESTION, CRAWLING & SEARCH
  # ============================================================================
  searxng-redis:
    image: redis:7.4.1-alpine
    profiles: ["web-research"]
    restart: unless-stopped
    command: ["redis-server", "--save", "", "--appendonly", "no"]
    expose:
      - "6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "0.2"
    mem_limit: 256m

  searxng:
    image: searxng/searxng:2024.10.16-ac56c663b
    profiles: ["web-research"]
    restart: unless-stopped
    depends_on:
      - searxng-redis
    expose:
      - "8080"
    ports:
      - "127.0.0.1:8888:8080"
    environment:
      SEARXNG_BASE_URL: "http://searxng:8080/"
      SEARXNG_REDIS_URL: "redis://searxng-redis:6379/0"
      SEARXNG_SECRET: "${SEARXNG_SECRET:-dev_searxng_secret_key_heretek_crew_2026}"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:8080/healthz || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "1.0"
    mem_limit: 1g

  firecrawl-redis:
    image: redis:7.4.1-alpine
    profiles: ["web-research"]
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes", "--maxmemory", "512mb", "--maxmemory-policy", "noeviction"]
    expose:
      - "6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    volumes:
      - firecrawl-redis-data:/data
    networks:
      - heretek
    cpus: "0.5"
    mem_limit: 768m

  firecrawl:
    image: ghcr.io/mendableai/firecrawl:v1.17.2
    profiles: ["web-research"]
    restart: unless-stopped
    depends_on:
      firecrawl-redis:
        condition: service_healthy
      browserless:
        condition: service_healthy
    expose:
      - "3002"
    environment:
      PORT: "3002"
      REDIS_URL: "redis://firecrawl-redis:6379"
      USE_PUPPETEER_CACHE: "true"
      PUPPETEER_WS_ENDPOINT: "ws://browserless:3000"
      NUM_WORKERS_PER_QUEUE: "4"
      LOGGING_LEVEL: "warn"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:3002/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 20s
    networks:
      - heretek
    cpus: "1.5"
    mem_limit: 2g

  gotenberg:
    image: gotenberg/gotenberg:8.15.0
    profiles: ["web-research", "qa-testing"]
    restart: unless-stopped
    expose:
      - "3000"
    command:
      - "gotenberg"
      - "--api-port=3000"
      - "--chromium-restart-after=30"
      - "--chromium-auto-start=true"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:3000/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "1.0"
    mem_limit: 1.5g

  # ============================================================================
  # CATEGORY B: RESILIENT & STEALTH BROWSER AUTOMATION
  # ============================================================================
  browserless:
    image: ghcr.io/browserless/chromium:v2.24.2
    profiles: ["web-research", "qa-testing"]
    restart: unless-stopped
    expose:
      - "3000"
    ports:
      - "127.0.0.1:3003:3000"
    environment:
      CONCURRENT: "5"
      QUEUED: "10"
      TIMEOUT: "60000"
      TOKEN: "${BROWSERLESS_TOKEN:-heretek-stealth-token}"
      ENABLE_DEBUGGER: "true"
      DEFAULT_STEALTH: "true"
      DEFAULT_HEADLESS: "new"
      CHROME_REFRESH_TIME: "1800000"
    shm_size: "2gb"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:3000/pressure || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "2.0"
    mem_limit: 3g

  mitmproxy:
    image: mitmproxy/mitmproxy:11.0.2
    profiles: ["devsec", "qa-testing"]
    restart: unless-stopped
    command: ["mitmweb", "--web-host", "0.0.0.0", "--web-port", "8081", "--set", "block_global=false"]
    expose:
      - "8080"
      - "8081"
    ports:
      - "127.0.0.1:8081:8081"
    volumes:
      - mitmproxy-certs:/home/mitmproxy/.mitmproxy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:8081 || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "0.5"
    mem_limit: 512m

  # ============================================================================
  # CATEGORY C: DEFENSIVE BINARY ANALYSIS & REVERSE ENGINEERING
  # ============================================================================
  ghidra:
    image: blacktop/ghidra:11.2
    profiles: ["devsec"]
    restart: unless-stopped
    expose:
      - "1337"
    environment:
      MAXMEM: "4G"
    volumes:
      - ./workspaces/binaries:/samples:ro
      - ghidra-projects:/ghidra/projects
    entrypoint: ["/entrypoint.sh"]
    command: ["server"]
    healthcheck:
      test: ["CMD-SHELL", "pgrep -f ghidra || exit 1"]
      interval: 20s
      timeout: 5s
      retries: 3
      start_period: 30s
    networks:
      - heretek
    cpus: "2.0"
    mem_limit: 4g

  radare2:
    image: radare/radare2:6.0.0
    profiles: ["devsec"]
    restart: unless-stopped
    expose:
      - "9090"
    working_dir: /samples
    volumes:
      - ./workspaces/binaries:/samples:ro
    command: ["r2", "-qc=H 0.0.0.0:9090", "/samples"]
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:9090/cmd/? || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "1.0"
    mem_limit: 1g

  # ============================================================================
  # CATEGORY D: FAST CODEBASE SEARCH & AST ANALYSIS
  # ============================================================================
  hound:
    image: ghcr.io/hound-search/hound:v0.6.0
    profiles: ["devsec", "web-research"]
    restart: unless-stopped
    expose:
      - "6080"
    ports:
      - "127.0.0.1:6080:6080"
    volumes:
      - ./workspaces:/workspaces:ro
      - hound-data:/data
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:6080/api/v1/healthz || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "1.0"
    mem_limit: 2g

  semgrep:
    image: semgrep/semgrep:1.97.0
    profiles: ["devsec", "qa-testing"]
    restart: unless-stopped
    volumes:
      - ./workspaces:/src:ro
      - semgrep-cache:/root/.cache/semgrep
    entrypoint: ["sleep", "infinity"]
    networks:
      - heretek
    cpus: "2.0"
    mem_limit: 3g

  # ============================================================================
  # CATEGORY E: ISOLATED EXECUTION SANDBOXES
  # ============================================================================
  docker-socket-proxy:
    image: tecnativa/docker-socket-proxy:0.3.0
    profiles: ["core", "devsec"]
    restart: unless-stopped
    expose:
      - "2375"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      CONTAINERS: "1"
      IMAGES: "1"
      INFO: "1"
      VERSION: "1"
      POST: "1"
      VOLUMES: "0"
      NETWORKS: "0"
      NODES: "0"
      SWARM: "0"
      SYSTEM: "0"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:2375/version || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "0.2"
    mem_limit: 128m

  piston:
    image: ghcr.io/engineer-man/piston:v2.0.0
    profiles: ["qa-testing", "devsec"]
    restart: unless-stopped
    expose:
      - "2000"
    volumes:
      - piston-packages:/piston/packages
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:2000/api/v2/runtimes || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "2.0"
    mem_limit: 2g

  # ============================================================================
  # CATEGORY F: AGENT MEMORY, VECTOR STORES & KNOWLEDGE GRAPHS
  # ============================================================================
  qdrant:
    image: qdrant/qdrant:v1.12.5
    profiles: ["ai-gateway"]
    restart: unless-stopped
    expose:
      - "6333"
      - "6334"
    ports:
      - "127.0.0.1:6333:6333"
    environment:
      QDRANT__SERVICE__ENABLE_TLS: "false"
      QDRANT__STORAGE__PERFORMANCE__MAX_SEARCH_THREADS: "4"
    volumes:
      - qdrant-storage:/qdrant/storage
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:6333/readyz || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "1.5"
    mem_limit: 2g

  neo4j:
    image: neo4j:5.26.0-community-bullseye
    profiles: ["ai-gateway"]
    restart: unless-stopped
    expose:
      - "7474"
      - "7687"
    ports:
      - "127.0.0.1:7474:7474"
    environment:
      NEO4J_AUTH: "neo4j/${NEO4J_PASSWORD:-heretek_knowledge_graph_secret_2026}"
      NEO4J_PLUGINS: '["apoc"]'
      server_memory_heap_initial__size: "512m"
      server_memory_heap_max__size: "1536m"
      server_memory_pagecache_size: "512m"
    volumes:
      - neo4j-data:/data
      - neo4j-logs:/logs
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:7474 || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 4
      start_period: 30s
    networks:
      - heretek
    cpus: "1.5"
    mem_limit: 2.5g

  # ============================================================================
  # CATEGORY G: LLM GATEWAYS & CACHING
  # ============================================================================
  litellm:
    image: ghcr.io/berriai/litellm:v1.54.0
    profiles: ["ai-gateway"]
    restart: unless-stopped
    expose:
      - "4000"
    ports:
      - "127.0.0.1:4000:4000"
    environment:
      LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY:-sk-heretek-proxy-master-key}"
      DATABASE_URL: "postgres://${POSTGRES_USER:-paperclip}:${POSTGRES_PASSWORD:-paperclip}@postgres:5432/${POSTGRES_DB:-paperclip}"
      STORE_MODEL_IN_DB: "True"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:4000/health/readiness || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "1.0"
    mem_limit: 1.5g

  # ============================================================================
  # CATEGORY H: DEVELOPER TESTING, MOCKING & OBSERVABILITY
  # ============================================================================
  mailpit:
    image: axllent/mailpit:v1.21.8
    profiles: ["qa-testing"]
    restart: unless-stopped
    expose:
      - "1025"
      - "8025"
    ports:
      - "127.0.0.1:8025:8025"
    environment:
      MP_MAX_MESSAGES: "5000"
      MP_DATABASE: ""
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:8025/api/v1/messages || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "0.2"
    mem_limit: 256m

  minio:
    image: minio/minio:RELEASE.2024-11-07T00-52-20Z
    profiles: ["qa-testing", "core"]
    restart: unless-stopped
    command: ["server", "/data", "--console-address", ":9001"]
    expose:
      - "9000"
      - "9001"
    ports:
      - "127.0.0.1:9001:9001"
    environment:
      MINIO_ROOT_USER: "${MINIO_ROOT_USER:-heretekadmin}"
      MINIO_ROOT_PASSWORD: "${MINIO_ROOT_PASSWORD:-heretekminiopassword2026}"
    volumes:
      - minio-data:/data
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:9000/minio/health/live || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "0.5"
    mem_limit: 1g

  wiremock:
    image: wiremock/wiremock:3.10.0-alpine
    profiles: ["qa-testing"]
    restart: unless-stopped
    expose:
      - "8080"
    ports:
      - "127.0.0.1:8089:8080"
    command: ["--verbose", "--global-response-templating"]
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:8080/__admin/health || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 3
    networks:
      - heretek
    cpus: "0.5"
    mem_limit: 512m

  jaeger:
    image: jaegertracing/all-in-one:1.63.0
    profiles: ["observability"]
    restart: unless-stopped
    expose:
      - "4317"
      - "4318"
      - "16686"
    ports:
      - "127.0.0.1:16686:16686"
    environment:
      COLLECTOR_OTLP_ENABLED: "true"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:16686 || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 3
    networks:
      - heretek
    cpus: "0.5"
    mem_limit: 1g

  # ============================================================================
  # CATEGORY I: MOBILE DEVICE & EMULATION TESTING
  # ============================================================================
  docker-android:
    image: budtmo/docker-android:emulator_14.0_v3.8.0-p1
    profiles: ["mobile"]
    restart: unless-stopped
    privileged: true
    devices:
      - "/dev/kvm:/dev/kvm"
    expose:
      - "5555"
      - "6080"
    ports:
      - "127.0.0.1:5555:5555"
      - "127.0.0.1:6080:6080"
    environment:
      EMULATOR_DEVICE: "Samsung Galaxy S10"
      WEB_VNC: "true"
    volumes:
      - docker-android-data:/root
    healthcheck:
      test: ["CMD-SHELL", "adb devices | grep -q 'device' || exit 1"]
      interval: 20s
      timeout: 10s
      retries: 5
      start_period: 60s
    networks:
      - heretek
    cpus: "2.0"
    mem_limit: 4g

# ==============================================================================
# VOLUMES
# ==============================================================================
volumes:
  firecrawl-redis-data:
  mitmproxy-certs:
  ghidra-projects:
  hound-data:
  semgrep-cache:
  piston-packages:
  qdrant-storage:
  neo4j-data:
  neo4j-logs:
  minio-data:
  docker-android-data:

# ==============================================================================
# NETWORKS
# ==============================================================================
networks:
  heretek:
    external: true
```

---

## 12. Security Hardening & Isolation Best Practices

1. **Loopback Only (`127.0.0.1`) for Administrative Endpoints**:
   Services exposing management or browser UIs (Jaeger, Mailpit, SearXNG, WireMock, MinIO Console) are strictly mapped to `127.0.0.1:<port>`. They must never be published to `0.0.0.0` where they could be accessed over local LAN or public networks without authentication.
2. **Read-Only Root Filesystems & Capabilities Dropping**:
   For adversarial reverse engineering (Ghidra, Radare2) and code scanning (Semgrep), containers mount host workspaces as read-only (`:ro`). Containers drop all root capabilities (`cap_drop: ["ALL"]`) and add only required primitives (`NET_BIND_SERVICE`).
3. **Internal Network Segmentation**:
   Paperclip and the OpenCode v2 agent fleet share the single isolated `heretek` bridge network. Sidecars communicate over DNS aliases (e.g. `http://firecrawl:3002`, `bolt://neo4j:7687`), preventing container-to-host network leakage.
4. **Daemon Protection via Socket Proxy**:
   The `docker-socket-proxy` sidecar eliminates the catastrophic vulnerability of mounting `/var/run/docker.sock` into agent containers. All CI or test-spawn requests pass through the socket proxy with volume and network manipulation explicitly disabled.
