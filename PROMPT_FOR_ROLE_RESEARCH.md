# Master Research & Specification Prompt: 50 Autonomous Agent Roles

You are an expert Autonomous Agent Architect and Technical Researcher. Your mission is to research, design, and thoroughly specify a comprehensive company catalog of **50 distinct, production-ready specialist agent roles** for an enterprise fleet running on **OpenCode v2** orchestrated by **Paperclip**.

All specifications must be grounded in **active, real-world, maintained tools** (verified via web search, npm registry, PyPI, and GitHub). Do not invent fictitious MCP packages or plugins.

---

## 1. Catalog Architecture & Domain Distribution (50 Roles)

Distribute the 50 roles across these 9 core functional departments:

1. **Executive & Product Management (6 roles)**:
   - Director / CEO-delegate (Strategic planning, company goals, executive approval)
   - Product Director / Head of Product (Roadmap, milestone management)
   - Technical Product Manager / Scrum Lead (Sprint decomposition, acceptance criteria)
   - System Architect (Cross-repository design, architectural decision records - ADRs)
   - Technical Documentation Lead (Docs-as-code, API specifications, runbooks)
   - User Research & Feedback Analyst (Telemetry analysis, user feedback triage)

2. **Game Development (6 roles)**:
   - Game Systems & Gameplay Programmer (Game loops, mechanics, state machines)
   - Graphics & Shader Engineer (GLSL/HLSL, WebGPU/Vulkan rendering, shader optimization)
   - Engine & Systems Programmer (Memory management, asset pipelines, entity-component systems)
   - Game AI Programmer (Behavior trees, navmeshes, state graphs)
   - Physics & Simulation Engineer (Collision detection, rigid bodies, solvers)
   - Technical Artist & Asset Pipeline Lead (Asset conversions, model validation, rig inspection)

3. **Web & UI/UX Design (6 roles)**:
   - UI/UX Designer & Prototyper (Wireframing, SVG design, Tailwind/CSS layouts)
   - Design System Engineer (Component libraries, token management, Storybook)
   - Accessibility (a11y) & Usability Specialist (WCAG compliance, screen reader audits)
   - Frontend Performance Engineer (Core Web Vitals, bundle analysis, SSR/hydration profiling)
   - Mobile Web & Responsive Layout Engineer (Touch gestures, viewport adaptation)
   - Brand & Creative Copy Specialist (Typography, visual tone, microcopy)

4. **Specialized Language Engineers (8 roles)**:
   - Rust Systems Specialist (Memory safety, async/tokio, cargo ecosystems, unsafe audits)
   - Go Backend Engineer (Microservices, gRPC, concurrency, goroutines)
   - Python Backend & Systems Specialist (FastAPI/Django, typing, asyncio, PyPI tooling)
   - TypeScript / Node Fullstack Engineer (Next.js/React, TypeScript strictness, Node/Bun)
   - C++ Systems & Low-Level Engineer (Modern C++20/23, CMake, memory profiling)
   - Java / Kotlin Enterprise Engineer (Spring Boot, JVM tuning, Gradle/Maven)
   - Mobile iOS Specialist (Swift, SwiftUI, Xcode build pipelines)
   - Mobile Android Specialist (Kotlin, Jetpack Compose, Gradle Android)

5. **Cloud, Platform & Site Reliability (6 roles)**:
   - Cloud Platform Engineer (Terraform/OpenTofu, AWS/GCP/Azure infrastructure)
   - Kubernetes & Container Orchestrator (Helm, K8s manifests, pod security policies)
   - Site Reliability Engineer (SRE) (Incident remediation, alerting, service health)
   - Observability & Telemetry Engineer (Prometheus, OpenTelemetry, Grafana dashboards)
   - Database Administrator (PostgreSQL tuning, indexing, schema migrations, backup verify)
   - Cache & Streaming Systems Engineer (Redis, Kafka/NATS, message queues)

6. **Quality Assurance & Verification (6 roles)**:
   - End-to-End Browser Automation Engineer (Playwright test suites, visual regressions)
   - API & Contract Testing Specialist (Postman/Newman, OpenAPI validation, mock servers)
   - Load & Performance Stress Tester (k6, Locust, throughput benchmarks)
   - Adversarial Red-Proof Sabotage Tester (Deliberate fault injection, regression proofing)
   - Code Style & Static Analysis Lead (ESLint, Biome, Ruff, Clippy, Semgrep rulesets)
   - Release QA & Acceptance Sign-off Officer (Release verification checklists, staging sign-offs)

7. **Defensive Security, Binary Analysis & Forensics (6 roles)**:
   - Application Security (AppSec) Engineer (SAST/DAST, dependency audits, OWASP triage)
   - Cloud Security & IAM Auditor (Least-privilege policy verification, secret scanning)
   - Binary & Protocol Reverse Engineer (Disassembly inspection, protocol reverse engineering, network packet analysis, Ghidra/radare2 defensive triage)
   - Firmware & Embedded Security Analyst (ELF/binary header inspection, defensive symbol auditing, memory safety analysis)
   - Threat Modeling & Hardening Engineer (STRIDE modeling, attack-surface reduction, container hardening)
   - Compliance & License Auditor (SPDX checks, license compliance, regulatory requirements)

8. **Data & AI Systems (4 roles)**:
   - Data Pipeline & ETL Engineer (DuckDB, dbt, parquet data processing)
   - Vector Search & RAG Specialist (Embedding indexing, vector stores, semantic retrieval)
   - MLOps & Model Serving Engineer (vLLM/Ollama deployment, model quantization, inference benchmarking)
   - Analytics & Metrics Engineer (ClickHouse, analytics pipelines, business metrics)

9. **Operations & Maintenance (2 roles)**:
   - Dependency & CVE Patching Steward (Dependabot-style updates, lockfile upgrades, migration testing)
   - Git & Worktree Drift Coordinator (Branch hygiene, worktree orchestration, merge conflict resolution)

---

## 2. Rigorous Specification Standard (Per Role)

For **EACH** of the 50 roles, deliver a complete, copy-paste-ready specification containing all seven of the following subsections:

### 1. Header & Organization Context
- **Title & Department**
- **Seniority & Reporting Chain** (Who assigns tasks to this role; who this role reports to)
- **Delegation Triggers** (When this role executes directly vs. when it creates or delegates sub-tasks to other roles)
- **Monthly Budget & Wake Policy** (Budget cap in USD; wake on mention/assignment vs. timer schedule)

### 2. Core Responsibilities & Workflows
- Primary technical responsibilities.
- Daily input artifacts (e.g. issues, design tokens, pull requests) and expected output deliverables (code, PRs, audit logs, test reports).

### 3. Active & Maintained MCP Servers
- List 1–3 specific, currently maintained Model Context Protocol (MCP) servers relevant to this role.
- Provide:
  - Official Package or Repository name (e.g., `@modelcontextprotocol/server-postgres`, `playwright-mcp`, `@cyanheads/git-mcp-server`, `codebase-memory-mcp`, `docker-mcp`, `ghidra-mcp`).
  - Transport type (`stdio` or `sse`) and execution command.
  - Required environment variables or configuration keys.

### 4. Role-Specific Skills
- Specific skill definitions (`SKILL.md` format):
  - Skill name and trigger description.
  - Step-by-step procedural rules the agent executes when the skill is active.

### 5. OpenCode Plugins & Extensions
- OpenCode plugins or CLI extensions relevant to the domain (e.g. `opencode-mem`, linters, or specialized language toolchains).

### 6. Native OpenCode v2 Configuration (`opencode.json`)
- Native v2 JSON block for `roles/<role>/opencode/opencode.json`:
  - `permissions`: Strict ordered array of permissions according to the **Principle of Least Privilege** (e.g. read-only roles must deny filesystem write/shell; execution roles allow specific commands).
  - `skills`: Skill directory paths.
  - `mcp`: Exact configuration for the role's MCP servers.

### 7. Full Agent System Prompt
- An exhaustive, production-grade prompt instructing the agent:
  - Identity, tone, and operational boundaries.
  - Strict Rules & Non-Negotiables (e.g., Zero-Stubs policy, defensive focus, verification requirements).
  - Step-by-step methodology for executing assigned tickets.
  - Handoff and completion protocol (reporting deliverables back to Paperclip).

---

## 3. Execution & Output Instructions

1. **Verify Real Packages**: Use search tools to verify real npm packages, PyPI libraries, and MCP servers before listing them.
2. **Strict Least-Privilege**: Enforce appropriate security boundaries. Executive, PM, and Auditor roles must NOT have blanket shell execution or destructive edit tools.
3. **Structured Delivery**: Save the complete specification report in a master document `roles-catalog/ROLE_CATALOG_50.md` (or modular role files in `roles-catalog/` with a master index).
4. **Summary Matrix**: Include a top-level Markdown summary table with Columns: `Role ID`, `Role Name`, `Department`, `Primary MCP Server(s)`, `Key Tool Access`, `Monthly Budget`.
