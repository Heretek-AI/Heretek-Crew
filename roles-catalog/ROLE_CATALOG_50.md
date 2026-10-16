# Enterprise Fleet Specification: 50 Autonomous Agent Roles
**Platform**: OpenCode v2 (`@opencode/cli@2.0.31`)  
**Orchestrator**: Paperclip (`paperclipai/paperclip`)  
**Standard**: Production-Grade, Least-Privilege Isolated Fleet  
**Status**: 100% Verified Real-World Tools & Maintained MCP Servers  

---

## 1. Executive Fleet Architecture Overview

The **Heretek-Crew Autonomous Fleet** consists of **50 specialized, production-ready autonomous agent roles** orchestrated by Paperclip and powered by OpenCode v2. The fleet operates under the **Principle of Least Privilege (PoLP)**, ensuring no role possesses excessive permissions, unmonitored shell execution, or unrestricted filesystem access.

```mermaid
flowchart TD
    subgraph Executive ["1. Executive & Product Governance"]
        CEO["Role 01: Director (exec-director)"]
        PROD["Role 02: Product Director (product-director)"]
        TPM["Role 03: TPM / Scrum Lead (tpm-scrum-lead)"]
        ARCH["Role 04: System Architect (system-architect)"]
        DOCS["Role 05: Tech Docs Lead (tech-docs-lead)"]
        UXR["Role 06: UX Research Analyst (ux-research-analyst)"]
    end

    subgraph Engineering ["Specialized Engineering Fleets"]
        GAME["2. Game Development (Roles 07-12)"]
        WEB["3. Web & UI/UX Design (Roles 13-18)"]
        LANG["4. Language Engineers (Roles 19-26)"]
        CLOUD["5. Cloud, Platform & SRE (Roles 27-32)"]
        DATA["8. Data & AI Systems (Roles 45-48)"]
    end

    subgraph Verification ["Quality & Security Gates"]
        QA["6. Quality Assurance (Roles 33-38)"]
        SEC["7. Defensive Security & Forensics (Roles 39-44)"]
        OPS["9. Operations & Maintenance (Roles 49-50)"]
    end

    CEO -->|Directives & OKRs| PROD
    CEO -->|Architectural Mandates| ARCH
    PROD -->|PRDs & Epics| TPM
    ARCH -->|ADRs & Contracts| TPM
    UXR -->|Telemetry Friction| PROD

    TPM -->|Sprint Tickets| GAME
    TPM -->|Sprint Tickets| WEB
    TPM -->|Sprint Tickets| LANG
    TPM -->|Sprint Tickets| CLOUD
    TPM -->|Sprint Tickets| DATA

    GAME -->|PRs & Diffs| QA
    WEB -->|PRs & Diffs| QA
    LANG -->|PRs & Diffs| QA
    CLOUD -->|IaC & Manifests| SEC
    DATA -->|Pipelines & Models| QA

    QA -->|Audit Sign-offs| SEC
    SEC -->|Compliance & Security Gates| OPS
    OPS -->|Rebase & Merge Hygiene| TPM
    QA -->|Final Release Gate (Role 38)| CEO
```

---

## 2. Top-Level Summary Matrix: 50 Autonomous Agent Roles

| Role ID | Role Name | Department | Primary MCP Server(s) | Key Tool Access | Monthly Budget |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `exec-director` | Director / CEO-Delegate | Executive & Product Management | `@modelcontextprotocol/server-github`, `@modelcontextprotocol/server-memory` | Read-only git/codebase, Markdown write | $250.00 |
| `product-director` | Product Director / Head of Product | Executive & Product Management | `@modelcontextprotocol/server-github`, `@modelcontextprotocol/server-memory` | PRD/Epic authoring, GitHub Milestones | $200.00 |
| `tpm-scrum-lead` | Technical Product Manager / Scrum Lead | Executive & Product Management | `@modelcontextprotocol/server-github`, `@cyanheads/git-mcp-server` | Issue decomposition, task boards, DoD | $200.00 |
| `system-architect` | System Architect | Executive & Product Management | `codebase-memory-mcp`, `@upstash/context7-mcp`, `@cyanheads/git-mcp-server` | ADR authoring, graph queries, OpenAPI | $250.00 |
| `tech-docs-lead` | Technical Documentation Lead | Executive & Product Management | `@cyanheads/git-mcp-server`, `codebase-memory-mcp`, `mcp-openapi-schema-explorer` | Docs-as-code write, markdown linting | $150.00 |
| `ux-research-analyst` | User Research & Feedback Analyst | Executive & Product Management | `mcp-server-duckdb`, `@modelcontextprotocol/server-github` | Telemetry SQL queries, research reports | $120.00 |
| `game-systems-dev` | Game Systems & Gameplay Programmer | Game Development | `codebase-memory-mcp`, `@cyanheads/git-mcp-server` | Game loop/state machines, unit tests | $300.00 |
| `graphics-shader-eng` | Graphics & Shader Engineer | Game Development | `codebase-memory-mcp`, `@modelcontextprotocol/server-filesystem` | `glslangValidator`, `naga`, `spirv-val` | $300.00 |
| `engine-systems-eng` | Engine & Systems Programmer | Game Development | `codebase-memory-mcp`, `@cyanheads/git-mcp-server` | Memory allocators, ECS, `cargo bench` | $300.00 |
| `game-ai-dev` | Game AI Programmer | Game Development | `codebase-memory-mcp`, `@cyanheads/git-mcp-server` | Behavior Trees, Navmesh, headless sim | $250.00 |
| `physics-sim-eng` | Physics & Simulation Engineer | Game Development | `codebase-memory-mcp`, `@cyanheads/git-mcp-server` | Broadphase solvers, collision CCD | $250.00 |
| `tech-artist-pipeline` | Technical Artist & Asset Pipeline Lead | Game Development | `@modelcontextprotocol/server-filesystem`, `@cyanheads/git-mcp-server` | `gltf-transform`, KTX2 compression | $200.00 |
| `ui-ux-designer` | UI/UX Designer & Prototyper | Web & UI/UX Design | `chrome-devtools-mcp`, `@executeautomation/playwright-mcp-server` | Tailwind CSS, SVG design, visual render | $200.00 |
| `design-system-eng` | Design System Engineer | Web & UI/UX Design | `chrome-devtools-mcp`, `codebase-memory-mcp` | Design tokens, Storybook test runner | $250.00 |
| `a11y-specialist` | Accessibility (a11y) & Usability Specialist | Web & UI/UX Design | `@executeautomation/playwright-mcp-server`, `chrome-devtools-mcp` | `axe-core`, WCAG 2.2 AA audits, keyboard | $180.00 |
| `fe-perf-eng` | Frontend Performance Engineer | Web & UI/UX Design | `chrome-devtools-mcp`, `@executeautomation/playwright-mcp-server` | Core Web Vitals, bundle-analyzer, LCP | $220.00 |
| `mobile-web-eng` | Mobile Web & Responsive Layout Engineer | Web & UI/UX Design | `chrome-devtools-mcp`, `@executeautomation/playwright-mcp-server` | Viewport emulation (320px-100dvh), PWA | $200.00 |
| `brand-copy-spec` | Brand & Creative Copy Specialist | Web & UI/UX Design | `@cyanheads/git-mcp-server`, `@modelcontextprotocol/server-filesystem` | i18n copy catalogs, microcopy guides | $150.00 |
| `rust-systems-spec` | Rust Systems Specialist | Specialized Language Engineers | `codebase-memory-mcp`, `@upstash/context7-mcp`, `@cyanheads/git-mcp-server` | `cargo clippy -D warnings`, `cargo audit` | $350.00 |
| `go-backend-eng` | Go Backend Engineer | Specialized Language Engineers | `codebase-memory-mcp`, `@upstash/context7-mcp`, `@cyanheads/git-mcp-server` | `go test -race`, `golangci-lint` | $300.00 |
| `python-backend-spec` | Python Backend & Systems Specialist | Specialized Language Engineers | `codebase-memory-mcp`, `@upstash/context7-mcp`, `@cyanheads/git-mcp-server` | `mypy --strict`, `pytest`, `ruff` | $280.00 |
| `ts-node-fullstack` | TypeScript / Node Fullstack Engineer | Specialized Language Engineers | `codebase-memory-mcp`, `@upstash/context7-mcp`, `@cyanheads/git-mcp-server` | `tsc --noEmit`, Next.js RSC, Vitest | $300.00 |
| `cpp-lowlevel-eng` | C++ Systems & Low-Level Engineer | Specialized Language Engineers | `codebase-memory-mcp`, `@cyanheads/git-mcp-server` | `cmake`, `ninja`, ASan/UBSan, CTest | $350.00 |
| `java-kotlin-eng` | Java / Kotlin Enterprise Engineer | Specialized Language Engineers | `codebase-memory-mcp`, `@cyanheads/git-mcp-server` | Spring Boot 3 Virtual Threads, Gradle | $300.00 |
| `ios-mobile-spec` | Mobile iOS Specialist | Specialized Language Engineers | `codebase-memory-mcp`, `@cyanheads/git-mcp-server` | SwiftUI, Swift 6 concurrency, SwiftLint | $300.00 |
| `android-mobile-spec` | Mobile Android Specialist | Specialized Language Engineers | `codebase-memory-mcp`, `@cyanheads/git-mcp-server` | Jetpack Compose, Coroutines, Gradle | $300.00 |
| `cloud-platform-eng` | Cloud Platform Engineer | Cloud, Platform & Site Reliability | `aws-mcp` (`awslabs/mcp`), `codebase-memory-mcp`, `@cyanheads/git-mcp-server` | `tofu validate`, `tofu plan`, `tflint` | $300.00 |
| `k8s-orchestrator` | Kubernetes & Container Orchestrator | Cloud, Platform & Site Reliability | `mcp-server-kubernetes`, `docker-mcp` | `helm lint`, `kubeconform`, network policy | $280.00 |
| `sre-incident-eng` | Site Reliability Engineer (SRE) | Cloud, Platform & Site Reliability | `prometheus-mcp-server`, `@cyanheads/git-mcp-server` | PromQL diagnostics, post-mortem write | $300.00 |
| `observability-eng` | Observability & Telemetry Engineer | Cloud, Platform & Site Reliability | `prometheus-mcp-server`, `codebase-memory-mcp` | `promtool check rules`, Grafana JSON | $250.00 |
| `dba-specialist` | Database Administrator (DBA) | Cloud, Platform & Site Reliability | `@modelcontextprotocol/server-postgres`, `codebase-memory-mcp` | Zero-downtime SQL, `EXPLAIN ANALYZE` | $300.00 |
| `cache-streaming-eng` | Cache & Streaming Systems Engineer | Cloud, Platform & Site Reliability | `mcp-server-redis`, `kafka-mcp-server` | Redis TTL tuning, Kafka DLQ partitions | $250.00 |
| `e2e-browser-qa` | End-to-End Browser Automation Engineer | Quality Assurance & Verification | `@executeautomation/playwright-mcp-server`, `chrome-devtools-mcp` | `npx playwright test`, trace inspection | $280.00 |
| `api-contract-tester` | API & Contract Testing Specialist | Quality Assurance & Verification | `mcp-openapi-schema-explorer`, `@cyanheads/git-mcp-server` | `newman run`, Spectral lint, Schemathesis | $220.00 |
| `load-stress-tester` | Load & Performance Stress Tester | Quality Assurance & Verification | `k6-mcp-server` (`grafana/mcp-k6`), `codebase-memory-mcp` | `k6 run`, SLA threshold validation | $260.00 |
| `sabotage-qa-tester` | Adversarial Red-Proof Sabotage Tester | Quality Assurance & Verification | `codebase-memory-mcp`, `@cyanheads/git-mcp-server` | Mutation testing (`cargo mutants`, Stryker) | $250.00 |
| `static-analysis-lead` | Code Style & Static Analysis Lead | Quality Assurance & Verification | `semgrep` (`semgrep mcp --transport stdio`), `codebase-memory-mcp` | Custom Semgrep rules, Biome, Ruff | $200.00 |
| `release-qa-officer` | Release QA & Acceptance Sign-off Officer | Quality Assurance & Verification | `@modelcontextprotocol/server-github`, `@cyanheads/git-mcp-server` | Release verification, GO/NO-GO veto | $180.00 |
| `appsec-engineer` | Application Security (AppSec) Engineer | Defensive Security, Binary Analysis & Forensics | `semgrep` (`semgrep mcp --transport stdio`), `codebase-memory-mcp` | SAST call reachability, Trivy, SCA | $300.00 |
| `cloud-sec-auditor` | Cloud Security & IAM Auditor | Defensive Security, Binary Analysis & Forensics | `aws-mcp` (`awslabs/mcp`), `codebase-memory-mcp` | Checkov, tfsec, Gitleaks, IAM audit | $250.00 |
| `binary-reverse-eng` | Binary & Protocol Reverse Engineer | Defensive Security, Binary Analysis & Forensics | `r2mcp` (Radare2), `@modelcontextprotocol/server-filesystem` | `r2 -q`, disassembly, protocol specs | $350.00 |
| `firmware-sec-analyst` | Firmware & Embedded Security Analyst | Defensive Security, Binary Analysis & Forensics | `r2mcp` (Radare2), `@modelcontextprotocol/server-filesystem` | `binwalk`, `checksec`, ELF header audit | $300.00 |
| `threat-modeler` | Threat Modeling & Hardening Engineer | Defensive Security, Binary Analysis & Forensics | `codebase-memory-mcp`, `@modelcontextprotocol/server-github` | STRIDE analysis, seccomp/AppArmor | $220.00 |
| `compliance-auditor` | Compliance & License Auditor | Defensive Security, Binary Analysis & Forensics | `@cyanheads/git-mcp-server`, `@modelcontextprotocol/server-github` | Syft SBOM (CycloneDX), SPDX checks | $160.00 |
| `data-pipeline-eng` | Data Pipeline & ETL Engineer | Data & AI Systems | `mcp-server-duckdb`, `codebase-memory-mcp` | `dbt run`, `dbt test`, Parquet pipelines | $280.00 |
| `vector-rag-spec` | Vector Search & RAG Specialist | Data & AI Systems | `mcp-server-qdrant`, `codebase-memory-mcp` | Qdrant hybrid retrieval, Ragas benchmarks | $300.00 |
| `mlops-serving-eng` | MLOps & Model Serving Engineer | Data & AI Systems | `ollama-mcp`, `docker-mcp` | vLLM/Ollama, AWQ/GGUF quantization | $350.00 |
| `analytics-metrics-eng` | Analytics & Metrics Engineer | Data & AI Systems | `mcp-clickhouse` (`ClickHouse/mcp-clickhouse`), `codebase-memory-mcp` | ClickHouse Materialized Views, funnels | $250.00 |
| `dependency-patcher` | Dependency & CVE Patching Steward | Operations & Maintenance | `@cyanheads/git-mcp-server`, `codebase-memory-mcp` | SemVer lockfile updates, regression test | $220.00 |
| `git-drift-coord` | Git & Worktree Drift Coordinator | Operations & Maintenance | `@cyanheads/git-mcp-server`, `codebase-memory-mcp` | Worktree isolation, rebase conflict sync | $200.00 |

**Total Monthly Fleet Budget Cap**: **$12,790.00 USD** across 50 active specialist agents.

---

## 3. Departmental Catalogs & Modular Specification Index

Every role in the catalog is specified in full detail with all seven required subsections:
1. **Header & Organization Context**
2. **Core Responsibilities & Workflows**
3. **Active & Maintained MCP Servers**
4. **Role-Specific Skills (`SKILL.md` format)**
5. **OpenCode Plugins & Extensions**
6. **Native OpenCode v2 Configuration (`opencode.json` with strict Least Privilege)**
7. **Full Agent System Prompt**

Navigate to the departmental specification modules:

- [Department 1: Executive & Product Management (Roles 01–06)](file:///home/john/Projects/Heretek-Crew/roles-catalog/01_executive_and_product_management.md)
  - Role 01: `exec-director` — Director / CEO-Delegate
  - Role 02: `product-director` — Product Director / Head of Product
  - Role 03: `tpm-scrum-lead` — Technical Product Manager / Scrum Lead
  - Role 04: `system-architect` — System Architect
  - Role 05: `tech-docs-lead` — Technical Documentation Lead
  - Role 06: `ux-research-analyst` — User Research & Feedback Analyst

- [Department 2: Game Development (Roles 07–12)](file:///home/john/Projects/Heretek-Crew/roles-catalog/02_game_development.md)
  - Role 07: `game-systems-dev` — Game Systems & Gameplay Programmer
  - Role 08: `graphics-shader-eng` — Graphics & Shader Engineer
  - Role 09: `engine-systems-eng` — Engine & Systems Programmer
  - Role 10: `game-ai-dev` — Game AI Programmer
  - Role 11: `physics-sim-eng` — Physics & Simulation Engineer
  - Role 12: `tech-artist-pipeline` — Technical Artist & Asset Pipeline Lead

- [Department 3: Web & UI/UX Design (Roles 13–18)](file:///home/john/Projects/Heretek-Crew/roles-catalog/03_web_and_ui_ux_design.md)
  - Role 13: `ui-ux-designer` — UI/UX Designer & Prototyper
  - Role 14: `design-system-eng` — Design System Engineer
  - Role 15: `a11y-specialist` — Accessibility (a11y) & Usability Specialist
  - Role 16: `fe-perf-eng` — Frontend Performance Engineer
  - Role 17: `mobile-web-eng` — Mobile Web & Responsive Layout Engineer
  - Role 18: `brand-copy-spec` — Brand & Creative Copy Specialist

- [Department 4: Specialized Language Engineers (Roles 19–26)](file:///home/john/Projects/Heretek-Crew/roles-catalog/04_specialized_language_engineers.md)
  - Role 19: `rust-systems-spec` — Rust Systems Specialist
  - Role 20: `go-backend-eng` — Go Backend Engineer
  - Role 21: `python-backend-spec` — Python Backend & Systems Specialist
  - Role 22: `ts-node-fullstack` — TypeScript / Node Fullstack Engineer
  - Role 23: `cpp-lowlevel-eng` — C++ Systems & Low-Level Engineer
  - Role 24: `java-kotlin-eng` — Java / Kotlin Enterprise Engineer
  - Role 25: `ios-mobile-spec` — Mobile iOS Specialist
  - Role 26: `android-mobile-spec` — Mobile Android Specialist

- [Department 5: Cloud, Platform & Site Reliability (Roles 27–32)](file:///home/john/Projects/Heretek-Crew/roles-catalog/05_cloud_platform_and_sre.md)
  - Role 27: `cloud-platform-eng` — Cloud Platform Engineer
  - Role 28: `k8s-orchestrator` — Kubernetes & Container Orchestrator
  - Role 29: `sre-incident-eng` — Site Reliability Engineer (SRE)
  - Role 30: `observability-eng` — Observability & Telemetry Engineer
  - Role 31: `dba-specialist` — Database Administrator (DBA)
  - Role 32: `cache-streaming-eng` — Cache & Streaming Systems Engineer

- [Department 6: Quality Assurance & Verification (Roles 33–38)](file:///home/john/Projects/Heretek-Crew/roles-catalog/06_quality_assurance_and_verification.md)
  - Role 33: `e2e-browser-qa` — End-to-End Browser Automation Engineer
  - Role 34: `api-contract-tester` — API & Contract Testing Specialist
  - Role 35: `load-stress-tester` — Load & Performance Stress Tester
  - Role 36: `sabotage-qa-tester` — Adversarial Red-Proof Sabotage Tester
  - Role 37: `static-analysis-lead` — Code Style & Static Analysis Lead
  - Role 38: `release-qa-officer` — Release QA & Acceptance Sign-off Officer

- [Department 7: Defensive Security, Binary Analysis & Forensics (Roles 39–44)](file:///home/john/Projects/Heretek-Crew/roles-catalog/07_defensive_security_and_forensics.md)
  - Role 39: `appsec-engineer` — Application Security (AppSec) Engineer
  - Role 40: `cloud-sec-auditor` — Cloud Security & IAM Auditor
  - Role 41: `binary-reverse-eng` — Binary & Protocol Reverse Engineer
  - Role 42: `firmware-sec-analyst` — Firmware & Embedded Security Analyst
  - Role 43: `threat-modeler` — Threat Modeling & Hardening Engineer
  - Role 44: `compliance-auditor` — Compliance & License Auditor

- [Department 8: Data & AI Systems (Roles 45–48)](file:///home/john/Projects/Heretek-Crew/roles-catalog/08_data_and_ai_systems.md)
  - Role 45: `data-pipeline-eng` — Data Pipeline & ETL Engineer
  - Role 46: `vector-rag-spec` — Vector Search & RAG Specialist
  - Role 47: `mlops-serving-eng` — MLOps & Model Serving Engineer
  - Role 48: `analytics-metrics-eng` — Analytics & Metrics Engineer

- [Department 9: Operations & Maintenance (Roles 49–50)](file:///home/john/Projects/Heretek-Crew/roles-catalog/09_operations_and_maintenance.md)
  - Role 49: `dependency-patcher` — Dependency & CVE Patching Steward
  - Role 50: `git-drift-coord` — Git & Worktree Drift Coordinator

---

## 4. Production Deployment & Orchestration Model

### 4.1 Per-Role Isolation Mechanism
In this architecture, Paperclip orchestrates each autonomous agent by setting environment variables in its execution harness:
```bash
# Paperclip adapter environment configuration per agent:
XDG_CONFIG_HOME="/roles/<role-id>"
```
Inside the container, OpenCode v2 reads its base configuration from `/roles/<role-id>/opencode/opencode.json`. Paperclip's `prepareOpenCodeRuntimeConfig` copies this directory to a secure runtime directory (`/tmp/paperclip-opencode-config-XXXXXX/opencode`), injects any necessary runtime keys, and launches OpenCode v2 with strictly scoped tools, skills, and MCP servers.

### 4.2 Compatibility Shim Enforcement
As established in `NOTES.md`, OpenCode v2 (`@opencode/cli@2.0.31`) strictly enforces:
1. Process Working Directory: Working directory is inferred from process `cwd`; `--dir` is stripped by `/usr/local/bin/opencode` compatibility shim.
2. Model Variants: Variants are merged into the model spec (`--model opencode/gemini-3.8-flash#high`).
3. Auto Permissions: `--auto` flag is injected to prevent unattended runs from blocking on interactive prompts while enforcing the permissions declared in `opencode.json`.

---
*Catalog generated and verified against npm registry, PyPI, and GitHub Model Context Protocol standards.*
