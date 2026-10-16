# CLAUDE.md — Claude Code Instructions for Heretek-Crew

This file provides instructions and guidelines for Claude Code (`claude`) when working in `/home/john/Projects/Heretek-Crew`.

---

## 1. Build, Test & Verification Commands

```bash
# Unit & Shim Tests (mandatory before any commit)
bash scripts/test-shim.sh           # 28/28 assertions must pass
make test                           # Aliased to test-shim.sh

# Repository Static Smoke Tests
bash scripts/smoke-test.sh --check-only   # 48+ assertions (config, pins, roles, payloads)

# Shell script syntax & linting
shellcheck scripts/*.sh             # Must pass with 0 errors/warnings

# Docker Compose validation
BETTER_AUTH_SECRET=dummy POSTGRES_PASSWORD=dummy docker compose config
BETTER_AUTH_SECRET=dummy POSTGRES_PASSWORD=dummy docker compose -f docker-compose.yml -f docker-compose.sidecars.yml config

# Fleet Seeding Dry-Runs (validates generated JSON against Paperclip schema)
bash scripts/seed-company.sh --dry-run
bash scripts/seed-50-fleet.sh --dry-run

# Running the Stack
make build                          # Build Paperclip + OpenCode v2 image
make up                             # Start stack bound to 127.0.0.1:3100
make down                           # Tear down stack
make logs                           # Tail Paperclip logs
```

---

## 2. Architecture & Critical Invariants

1. **Paperclip + OpenCode v2 Integration**:
   - Paperclip spawns `opencode run --format json`.
   - OpenCode v2 removed `--dir` and `--variant`; requires `--auto` for non-interactive runs.
   - The compatibility shim (`scripts/opencode-shim.sh`) intercepts `run` and adapts arguments before delegating to `@opencode/cli@2.0.31`.
2. **Per-Role Isolation**:
   - Paperclip enforces `OPENCODE_DISABLE_PROJECT_CONFIG=true`.
   - Each agent must specify `adapterConfig.env.XDG_CONFIG_HOME = "/roles/<role-id>"`.
   - Paperclip copies `/roles/<role-id>/opencode/opencode.json` into a temporary runtime directory.
3. **Strict Version Pinning (Zero `:latest` Tags)**:
   - Node: `node:24-trixie-slim`
   - Postgres: `postgres:17-alpine`
   - OpenCode CLI & Client: `@opencode/cli@2.0.31`, `@opencode/client@2.0.31`
   - Caddy: `caddy:2.11.7-alpine`
   - Tailscale: `tailscale:v1.104.1`
   - Android Emulator: `budtmo/docker-android:emulator_14.0_v3.8.0-p1`
4. **On-Demand Execution**:
   - Workers: `heartbeat.enabled: false`, `intervalSec: 0`, `wakeOnAssignment: true`, `wakeOnMention: true`.
   - Coordinators: `exec-director` (1800s), `tpm-scrum-lead` (3600s).

---

## 3. Code & Operational Standards

- **Zero Stubs**: No placeholder functions, no dummy returns, no swallowed errors (`catch {}` or `|| true`).
- **Fail Closed**: In every `opencode.json`, explicit allow rules must precede `{ "action": "shell", "resource": "*", "effect": "deny" }`.
- **Bash Scripts**: Use `set -euo pipefail`. Implement `--dry-run` and `--help` for any provisioning scripts.
- **Security**: Never expose ports to `0.0.0.0` without proxy/auth. Internal network only (`heretek`). Secrets stay in `.env` (git-ignored).
- **Refer to Master Docs**:
  - Decision Log: [`NOTES.md`](file:///home/john/Projects/Heretek-Crew/NOTES.md)
  - 50-Role Specification: [`roles-catalog/ROLE_CATALOG_50.md`](file:///home/john/Projects/Heretek-Crew/roles-catalog/ROLE_CATALOG_50.md)
  - Sidecar Catalog: [`SUPPORTING_SERVICES.md`](file:///home/john/Projects/Heretek-Crew/SUPPORTING_SERVICES.md)
