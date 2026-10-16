# GEMINI.md — Gemini & Antigravity Agent Guidelines for Heretek-Crew

This file provides system context, architectural guidelines, and tool preferences for Gemini CLI and Antigravity agents working in `/home/john/Projects/Heretek-Crew`.

---

## 1. Primary Directives & Code Discovery

### Knowledge Graph Priority (`codebase-memory-mcp`)
When navigating or discovering code within this codebase:
1. **Always prefer MCP graph tools over grep/glob/file-search**:
   - `search_graph`: Find functions, classes, routes, variables by pattern.
   - `trace_path`: Trace who calls a function or what it calls.
   - `get_code_snippet`: Read specific function/class source code.
   - `query_graph`: Execute Cypher queries for complex dependencies.
   - `get_architecture`: High-level project summary.
2. **Fall back to grep/glob only for**:
   - Searching for string literals, error messages, config values.
   - Inspecting non-code files (Dockerfiles, shell scripts, Compose YAML, markdown specs).
   - When MCP tools return insufficient results.

---

## 2. Core Architecture & Operating Invariants

- **Orchestration**: Paperclip (`paperclipai/paperclip`) running in Docker on `127.0.0.1:3100`.
- **Runtime**: OpenCode v2 (`@opencode/cli@2.0.31`) invoked by Paperclip's `opencode_local` adapter.
- **CLI Translation Shim**: `scripts/opencode-shim.sh` intercepts `opencode run`, strips `--dir`, maps `--variant`, and injects `--auto`.
- **Per-Role Config Isolation**: Each agent's runtime environment is defined in `roles/<role-id>/opencode/opencode.json` and mounted via `XDG_CONFIG_HOME = "/roles/<role-id>"`.
- **Wake Strategy**: 48/50 roles are strictly on-demand (`heartbeat.enabled: false`, `intervalSec: 0`, `wakeOnAssignment: true`, `wakeOnMention: true`). Only `exec-director` (1800s) and `tpm-scrum-lead` (3600s) have recurring timers.
- **Budget Control**: Fleet budget cap is $12,790.00 USD/mo (1,279,000 cents) across 50 specialist roles.

---

## 3. Essential Verification Commands

Always run these verification commands before presenting changes or completing a task:

```bash
# 1. Run the compatibility shim test suite (28 assertions)
bash scripts/test-shim.sh

# 2. Run repository static validation (48+ assertions)
bash scripts/smoke-test.sh --check-only

# 3. Lint shell scripts
shellcheck scripts/*.sh

# 4. Validate Docker Compose configurations
BETTER_AUTH_SECRET=dummy POSTGRES_PASSWORD=dummy docker compose config
BETTER_AUTH_SECRET=dummy POSTGRES_PASSWORD=dummy docker compose -f docker-compose.yml -f docker-compose.sidecars.yml config

# 5. Verify seeding payloads in dry-run mode
bash scripts/seed-company.sh --dry-run
bash scripts/seed-50-fleet.sh --dry-run
```

---

## 4. Engineering Standards & Quality Gates

1. **Zero-Stub Policy**: No placeholder functions, no empty mocks, no `TODO` comments in place of real implementations.
2. **Strict Version Pinning**: Never use `:latest` or unpinned packages. Pinned versions:
   - Node: `node:24-trixie-slim`
   - Postgres: `postgres:17-alpine`
   - CLI/SDK: `@opencode/cli@2.0.31`, `@opencode/client@2.0.31`
   - Playwright MCP: `@playwright/mcp@0.0.83`
   - Android Emulator: `budtmo/docker-android:emulator_14.0_v3.8.0-p1`
   - Caddy: `caddy:2.11.7-alpine`, Tailscale: `tailscale:v1.104.1`
3. **Fail-Closed Permissions**: All role `opencode.json` files must end with `{ "action": "shell", "resource": "*", "effect": "deny" }`.
4. **Documentation Sync**: Any changes to roles, sidecars, or environment variables must be documented in [`roles-catalog/ROLE_CATALOG_50.md`](file:///home/john/Projects/Heretek-Crew/roles-catalog/ROLE_CATALOG_50.md), [`SUPPORTING_SERVICES.md`](file:///home/john/Projects/Heretek-Crew/SUPPORTING_SERVICES.md), and [`NOTES.md`](file:///home/john/Projects/Heretek-Crew/NOTES.md).
