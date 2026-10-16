# Master Fleet & Architecture Audit Prompt

**Role**: Principal Systems Architect & Autonomous Agent Fleet Auditor  
**Task**: Conduct a comprehensive architectural, security, and operational audit of the Heretek-Crew codebase (`/home/john/Projects/Heretek-Crew`) against its original requirements and design specifications.  
**Prompt Intent**: *"This is what the original project was, did we build it right, are there areas we can improve?"*

---

## 1. Original Project Goals & Ground Rules

### Primary Objectives
1. **Self-Hosted Orchestration**: Run **Paperclip** (`paperclipai/paperclip`) in Docker Compose as the central orchestrator and WebUI for an enterprise fleet of autonomous agents.
2. **OpenCode v2 Fleet**: Power all agents using **OpenCode v2** (`@opencode/cli@2.0.31`), addressing all v2 breaking changes without hacking or destabilizing Paperclip core.
3. **On-Demand Execution**: Agents must NOT run 24/7 in expensive idle loops; they must sleep until woken on-demand by ticket assignment or `@mention` in Paperclip.
4. **Per-Role Isolation**: Each agent must have its OWN tools, MCP servers, skills, and permissions without leaking configurations into Git workspaces or colliding with other roles.
5. **Observability & Accounting**: Full visibility from the Paperclip UI (session resumption, execution logs, token usage, and cost tracking).
6. **Ground Rules**:
   - Zero `:latest` tags; every image, binary, and package pinned to an exact version.
   - Non-root container execution with loopback-bound ports (`127.0.0.1`) and internal networks.
   - Strict Zero-Stub policy (no fake mocks, no `TODO` stubs, fail-closed error handling).
   - Documented in `NOTES.md` and verifiable via automated smoke tests.

---

## 2. Audit Review Checklist

Perform a methodical, evidence-based review across the following 6 core dimensions:

### Dimension A: Architectural Conformance & OpenCode v2 Compatibility
- [ ] **CLI Compatibility Shim** (`scripts/opencode-shim.sh`):
  - Does the shim properly strip `--dir` and merge `--variant` into `--model provider/model#variant`?
  - Does it inject `--auto` to prevent interactive permission blocks in unattended runs?
  - Does it preserve `--session` for resume, maintain `--` argument boundaries, and correctly stream JSONL stdin/stdout?
  - Do all 28 unit tests pass in `scripts/test-shim.sh`?
- [ ] **Runtime Config Isolation**:
  - Is `XDG_CONFIG_HOME = "/roles/<role-id>"` properly passed to Paperclip agents?
  - Does Paperclip successfully copy and merge `/roles/<role-id>/opencode/opencode.json` without workspace pollution?
- [ ] **Docker Architecture** (`docker/Dockerfile` and `docker-compose.yml`):
  - Does the container image build cleanly on top of `node:24-trixie-slim` and Paperclip assets?
  - Are permissions properly initialized without breaking non-root execution (`node` UID 1000)?

### Dimension B: Security, Sandboxing & Least Privilege
- [ ] **Least Privilege Matrix**:
  - Does every `roles/<role>/opencode/opencode.json` restrict shell execution to specific binaries and end with a catch-all deny rule (`{ "action": "shell", "resource": "*", "effect": "deny" }`)?
  - Are read-only roles (e.g. Director, Tech Docs Lead, Static Analysis Lead) prevented from executing arbitrary shell commands or code modifications?
- [ ] **Network & Secret Exposure**:
  - Are all ports bound strictly to `127.0.0.1`?
  - Is the `heretek` Docker network isolated?
  - Are `.env` secrets excluded from version control and Docker images?
  - Is Docker daemon access guarded via `docker-socket-proxy` rather than exposing raw `/var/run/docker.sock`?

### Dimension C: Fleet Organization & Org Hierarchy
- [ ] **50-Role Specification** (`roles-catalog/`):
  - Is the organization chart coherent across all 9 departments (Executive, Game Dev, Web, Languages, Cloud, QA, Security, Data, Ops)?
  - Are all reporting lines and delegation chains unambiguous?
  - Are all MCP servers real, maintained, and pinned to verified npm/uvx packages (e.g. `mobile-mcp`, `rea`, `ast-grep`, `semgrep`, `r2mcp`)?
  - Does the total monthly budget equal the designated cap ($12,790.00 USD / 1,279,000 cents)?
- [ ] **Wake Policy**:
  - Are 48/50 roles verified to be on-demand (`intervalSec: 0`, `heartbeat.enabled: false`, `wakeOnAssignment: true`, `wakeOnMention: true`)?
  - Are heartbeats confined exclusively to `exec-director` (1800s) and `tpm-scrum-lead` (3600s)?

### Dimension D: Supporting Software & Sidecars (`docker-compose.sidecars.yml`)
- [ ] **Service Modularity**:
  - Are sidecars properly organized into compose profiles (`web-research`, `devsec`, `mobile`, `ai-gateway`, `qa-testing`, `observability`)?
  - Do sidecar services include healthchecks, resource limits (`cpus`, `mem_limit`), and persistent named volumes?
  - Does `docker-android` correctly bind KVM hardware acceleration (`/dev/kvm`), ADB (:5555), and noVNC (:6080)?
  - Does `morluto/rea` and `Heretek-AI/opencode-rea` integrate with Ghidra and Radare2 for binary reverse engineering?

### Dimension E: Operational Rigor & Automation
- [ ] **Operations Tooling** (`Makefile`, `scripts/`):
  - Does `scripts/seed-50-fleet.sh` support `--dry-run` and idempotent provisioning?
  - Do `scripts/backup-db.sh` and `scripts/restore-db.sh` handle PostgreSQL dumps safely with confirmation prompts?
  - Does `scripts/smoke-test.sh --check-only` pass with zero failures?

---

## 3. Deliverables Expected from the Audit

Produce an **Audit & Optimization Report** organized into:

1. **Executive Verdict**:
   - `VERDICT: PASS / PASS WITH ADVISORIES / FAIL`.
   - Summary of compliance against the original goals.
2. **Detailed Findings by Category**:
   - Strengths & verified architectural achievements.
   - Any identified edge cases, potential bottlenecks, or security caveats.
3. **High-Leverage Areas for Improvement**:
   - **Cost & Model Routing**: Opportunities for dynamic model tiering (e.g., routing triage tickets to light models and complex refactoring to frontier models).
   - **Cold-Start Optimization**: Strategies for pre-warming Node/Python environments or sharing read-only package caches.
   - **Distributed Observability**: Enhancing OpenTelemetry trace propagation from Paperclip task dispatch down into OpenCode v2 execution steps.
   - **Adversarial Resilience**: Expanding the `sabotage-qa-tester` mutation testing suites against agent PRs.
