# AGENTS.md — Heretek-Crew Repository Guide for Autonomous Agents

Welcome to **Heretek-Crew**. This repository contains a production-grade, self-hosted Docker Compose stack running **Paperclip** (`paperclipai/paperclip`) as the orchestrator and WebUI for an enterprise fleet of **OpenCode v2** (`@opencode/cli@2.0.31`) autonomous agents.

Any AI coding assistant, autonomous agent, or paired developer working on this codebase MUST adhere strictly to the rules, invariants, and operational procedures outlined below.

---

## 1. Project Overview & Architecture

### Core Tech Stack
- **Orchestrator**: Paperclip (Node.js 24, TypeScript, Fastify/Prisma backend, Vite/React WebUI).
- **Agent Runtime**: OpenCode v2 (`@opencode/cli@2.0.31` + `@opencode/client@2.0.31`).
- **Database**: PostgreSQL 17 (`postgres:17-alpine`) with healthcheck and backup automation.
- **Compatibility Layer**: Custom POSIX shell shim (`scripts/opencode-shim.sh`) installed at `/usr/local/bin/opencode` in the container.
- **Network & Ingress**: Isolated user-defined bridge network (`heretek`), loopback-bound ports (`127.0.0.1:3100`), optional Caddy TLS reverse proxy (`--profile proxy`), and Tailscale mesh sidecar (`--profile tailscale`).
- **Fleet Scope**: 50 specialist roles organized into 9 departments (`roles-catalog/`), supported by on-demand sidecar containers (`docker-compose.sidecars.yml`).

### Architectural Invariants
1. **Per-Role Isolation via `XDG_CONFIG_HOME`**:
   - Paperclip sets `OPENCODE_DISABLE_PROJECT_CONFIG=true` at runtime to prevent repository workspace git pollution.
   - Each agent is configured with `adapterConfig.env.XDG_CONFIG_HOME = "/roles/<role-id>"`.
   - Paperclip's `prepareOpenCodeRuntimeConfig` copies `/roles/<role-id>/opencode/opencode.json` into a temporary directory, merges runtime credentials and permissions, and passes it to OpenCode v2.
2. **OpenCode v2 Breaking Changes Addressed by the Shim**:
   - `opencode run` in v2 removed `--dir` (runs in process `cwd`) and `--variant` (encoded as `--model provider/model#variant`).
   - Non-interactive unattended runs require `--auto` to avoid interactive permission blocks.
   - `scripts/opencode-shim.sh` intercepts `opencode run`, strips `--dir`, folds `--variant`, injects `--auto`, and passes `--session`, stdin, and stdout streaming verbatim.
3. **On-Demand Execution (No Idle Token Waste)**:
   - 48 of the 50 roles run with `heartbeat.enabled: false`, `intervalSec: 0`, and wake only on assignment or `@mention`.
   - Only `exec-director` (1800s) and `tpm-scrum-lead` (3600s) have scheduled recurring heartbeats.
4. **Strict Version Pinning (Zero `:latest` Tags)**:
   - Every Docker image, npm package, pip package, and system binary must be pinned to an exact version.

---

## 2. Directory Layout & Organization

```
.
├── docker-compose.yml              # Primary Compose stack (Postgres + Paperclip + Caddy + Tailscale)
├── docker-compose.sidecars.yml     # Modular sidecars (Ghidra, REA, Browserless, Android, Qdrant, etc.)
├── docker/
│   └── Dockerfile                  # Production container extending /tmp/paperclip + OpenCode v2
├── roles/                          # Concrete per-role runtime directories
│   ├── <role-id>/
│   │   ├── opencode/opencode.json  # Native OpenCode v2 config (least privilege, MCP, skills)
│   │   ├── AGENTS.md               # Per-role boundaries and operational protocol
│   │   └── .opencode/
│   │       ├── agents/<role>.md    # Agent system prompt
│   │       └── skills/*/SKILL.md   # Procedural skills
├── roles-catalog/                  # Master specification for 50 roles across 9 departments
│   ├── ROLE_CATALOG_50.md          # Fleet overview, matrix, and budget allocation
│   └── 01_*.md ... 09_*.md         # Departmental specifications
├── scripts/
│   ├── opencode-shim.sh            # Production CLI shim
│   ├── test-shim.sh                # 28-assertion unit test suite for the shim
│   ├── seed-company.sh             # 6-agent bootstrap seeding script
│   ├── seed-50-fleet.sh            # 50-agent fleet seeding script
│   ├── generate-50-roles.py        # 50-role disk scaffolding generator
│   ├── smoke-test.sh               # Static and end-to-end integration test runner
│   ├── backup-db.sh                # Automated PostgreSQL timestamped backup
│   └── restore-db.sh               # Fail-closed PostgreSQL restoration
├── Makefile                        # Operational command runner
├── SUPPORTING_SERVICES.md          # Architectural catalog for sidecar services
├── NOTES.md                        # Living decision log and verified facts
└── README.md                       # Master documentation & Mermaid topology
```

---

## 3. Standard Operational Commands

Always use the `Makefile` or explicit scripts. Never construct ad-hoc commands that bypass validation.

```bash
# Verification & Testing (run before committing any changes)
make test                           # Runs unit shim tests (28/28 assertions)
bash scripts/smoke-test.sh --check-only   # 48+ static verification assertions

# Environment Initialization
cp .env.example .env                # Generate secret tokens: openssl rand -hex 32

# Build & Lifecycle
make build                          # Build Paperclip + OpenCode v2 container image
make up                             # Start stack in background (127.0.0.1:3100)
make down                           # Stop stack
make logs                           # Follow Paperclip logs

# Database Operations
make backup                         # Generate timestamped dump in backups/
make restore FILE=backups/<file>.sql.gz  # Restore database with confirmation prompt

# Fleet Seeding
make seed                           # Seed initial 6 core agents
bash scripts/seed-company.sh --dry-run   # Validate payloads without network calls
bash scripts/seed-50-fleet.sh --dry-run  # Validate 50-agent payloads (51 documents)

# Sidecar Services
docker compose -f docker-compose.yml -f docker-compose.sidecars.yml --profile web-research up -d
docker compose -f docker-compose.yml -f docker-compose.sidecars.yml --profile devsec up -d
docker compose -f docker-compose.yml -f docker-compose.sidecars.yml --profile mobile up -d
```

---

## 4. Coding & Modification Standards

When modifying this repository, follow these non-negotiable rules:

1. **Zero-Stub Policy**:
   - Never write placeholder comments (`// TODO: implement later`), dummy return values (`return true`), empty catch blocks (`catch {}`), or fake mock responses.
   - All scripts and configuration files must be completely functional and fail-closed.
2. **Least Privilege (PoLP)**:
   - In all `opencode.json` files, permissions must explicitly allow only the specific commands needed for that role, ending with:
     ```json
     { "action": "shell", "resource": "*", "effect": "deny" }
     ```
3. **No Unpinned Versions**:
   - Forbidden: `:latest`, `@latest`, unversioned package installations.
4. **Shell Script Standards**:
   - Every bash script must begin with `set -euo pipefail`.
   - All scripts must pass `shellcheck` with zero warnings.
   - All scripts modifying state must support `--dry-run` and `--help`.
5. **Secret Hygiene**:
   - Never commit API keys, database passwords, or auth secrets.
   - Keep `.env` strictly in `.gitignore`.
