# Heretek Crew: Paperclip + OpenCode v2 Stack Notes

## Verified Facts & Research (Phase 0)

### 1. Paperclip Official Dockerfile & Compose
- **Repository**: [paperclipai/paperclip](https://github.com/paperclipai/paperclip)
- **Official Dockerfile**: Located at root `/Dockerfile`. Multi-stage build (`node:24-trixie-slim`), builds `@paperclipai/server`, `@paperclipai/ui`, `@paperclipai/plugin-sdk`, and runner binaries.
- **Official Compose**:
  - `docker/docker-compose.yml`: Multi-container setup with `postgres:17-alpine` and `server` (Paperclip server + UI on port 3100).
  - `docker/docker-compose.quickstart.yml`: Single-container quickstart with SQLite.
- **Official Agent Harnesses in Dockerfile**:
  - Line 177 in official `Dockerfile` installs:
    `npm install --global --omit=dev @anthropic-ai/claude-code@latest @openai/codex@latest opencode-ai @google/gemini-cli@latest @moonshot-ai/kimi-code@latest`
  - Notice: It installs `opencode-ai` (which is OpenCode v1, pinned at 1.19.3). OpenCode v2 is `@opencode/cli` (currently 2.0.31).
- **Decision**: Extend Paperclip's official `docker/docker-compose.yml` and `Dockerfile` (or build an extended image layer on top of Paperclip's Dockerfile) rather than reinventing the stack from scratch.

### 2. OpenCode Package Naming & Version Pinning
- **OpenCode v1**: `opencode-ai` (latest v1: `1.19.3`).
- **OpenCode v2 CLI**: `@opencode/cli` (latest: `2.0.31`).
- **OpenCode v2 Client SDK**: `@opencode/client` (latest: `2.0.31`).
- **Install command**: `npm install -g @opencode/cli@2.0.31`
- **Pinned versions for this stack**:
  - `@opencode/cli`: `2.0.31`
  - `@opencode/client`: `2.0.31`
  - `postgres`: `17-alpine`
  - Node base: `node:24-trixie-slim`

### 3. OpenCode v2 CLI Invocations & Breaking Changes in `opencode_local`
Inspected `packages/adapters/opencode-local/src/server/execute.ts` and tested `@opencode/cli@2.0.31`:
- **CLI Subcommand**: Paperclip invokes `opencode run --format json`.
- **Breaking Flag 1 (`--dir`)**:
  - Paperclip's `execute.ts` line 629 unconditionally appends `--dir <effectiveExecutionCwd>` to `args`.
  - In OpenCode v2: `ERROR: Unrecognized flag: --dir in command opencode run` (exit code 1).
  - In v2, OpenCode runs in the process working directory (`process.cwd()`), which Paperclip already sets when spawning the process.
- **Breaking Flag 2 (`--variant`)**:
  - Paperclip's `execute.ts` line 624 appends `--variant <variant>`.
  - In OpenCode v2: `ERROR: Unrecognized flag: --variant in command opencode run`.
  - In v2, model variants are passed via the model string: `--model provider/model#variant`.
- **Session Resume (`--session`)**:
  - OpenCode v2 natively supports `--session <sessionID>` (or `-s`). Verified working; session resumes seamlessly.
- **Auto-Permissions (`dangerouslySkipPermissions`)**:
  - In v1, Paperclip wrote `"permission": "allow"` into the temporary `opencode.json`.
  - In v2, non-interactive runs reject tool approval requests with:
    `"This non-interactive run cannot ask the user for permission, so the request was rejected"`
    unless either:
    1. The CLI flag `--auto` is passed, or
    2. The v2 permissions array is configured in `opencode.json`:
       `"permissions": [{ "action": "*", "resource": "*", "effect": "allow" }]`
- **Output Parsing**:
  - OpenCode v2 `--format json` outputs JSONL matching Paperclip's `parseOpenCodeJsonl` and `parseOpenCodeStdoutLine`:
    - `type: "step_start"` with `sessionID`
    - `type: "tool_use"` with `part.tool`, `part.state.status`, `part.state.input`, `part.state.output`
    - `type: "step_finish"` with `part.tokens.input`, `part.tokens.output`, `part.tokens.cache.read`, `part.cost`
    - `type: "text"` with `part.text`
  - Token and cost tracking parse cleanly into Paperclip's usage accounting.

### 4. Configuration Precedence & Per-Role Isolation
Inspected OpenCode v2 binary and verified:
- **Paths in v2**:
  - `config`: `$XDG_CONFIG_HOME/opencode` (defaults to `~/.config/opencode`).
  - `OPENCODE_CONFIG_DIR`: Explicit override for the entire config directory.
  - `OPENCODE_CONFIG`: Explicit file path to a custom `opencode.json` / `opencode.jsonc`.
  - `OPENCODE_DISABLE_PROJECT_CONFIG`: When `true` (which Paperclip forces at line 329 in `execute.ts`), OpenCode skips project-level `.opencode/` and `opencode.json` in the git repository.
- **How Per-Role Isolation Works with Paperclip**:
  - Paperclip's `prepareOpenCodeRuntimeConfig` checks `input.env.XDG_CONFIG_HOME`:
    `sourceConfigDir = path.join(resolveXdgConfigHome(input.env), "opencode")`
  - It creates a temp directory `/tmp/paperclip-opencode-config-XXXXXX/opencode`, copies `sourceConfigDir`, injects permissions/providers, and sets `env.XDG_CONFIG_HOME = runtimeConfigHome`.
  - Thus, if an agent's adapter config specifies `env.XDG_CONFIG_HOME = "/roles/<role-name>"` (where `/roles/<role-name>/opencode/opencode.json` lives), Paperclip's temp-config mechanism will copy that specific role's configuration, merge runtime settings, and pass it to OpenCode v2!
  - In addition, setting `OPENCODE_CONFIG_DIR` or `OPENCODE_CONFIG` provides fallback guarantees.

## Open Questions & Compatibility Spike Options (Phase 1)
Because Paperclip's built-in `opencode-local` adapter pushes `--dir` (which fails under OpenCode v2 CLI), we have two paths for compatibility:
- **Option A (Lightweight Wrapper / Shim or In-tree Patch)**:
  - An `opencode` wrapper script or small patch in Paperclip's `opencode-local` adapter that intercepts `--dir <dir>` and `--variant <variant>`, strips `--dir`, converts `--variant` to `--model <model>#<variant>`, and ensures `--auto` is enabled.
- **Option B (Custom Paperclip Adapter / Server Service)**:
  - Create a dedicated Paperclip adapter package or service using `@opencode/client` against a running `opencode serve` backend, per Paperclip's "Creating an Adapter" and UI parser contract docs.

---

## Wave 1 Execution Log — Shim, Image & Compose (verified 2026-10-16)

### Decision: Option A (shim) adopted
- Implemented `scripts/opencode-shim.sh`, installed in-image as
  `/usr/local/bin/opencode`, delegating to the real v2 binary moved to
  `/usr/local/bin/opencode-bin`. Resolution order: `$OPENCODE_REAL_BIN` >
  `/usr/local/bin/opencode-bin` > `opencode-bin` on PATH; fail-closed
  (exit 127) when unresolvable or self-referential (recursion guard via
  `realpath` comparison).
- Rewrite rules (only for the `run` subcommand): strip `--dir <p>` /
  `--dir=<p>` (never swallowing a following flag); merge
  `--variant <v>`/`--variant=<v>` into `--model <m>`/`--model=<m>` as
  `<m>#<v>` order-independently (a model already carrying `#` is untouched; a
  lone `--variant` with no `--model` is dropped since v2 cannot express it);
  inject exactly one `--auto` (explicit `--auto=<bool>` respected) placed right
  after the `--model` value to preserve Paperclip's canonical order.
- Non-`run` subcommands (`models`, `auth`, `mcp`, …) pass through byte-for-byte.
- Ends with `exec` so stdin/stdout stream untouched (`--format json` JSONL)
  and signals go straight to OpenCode.
- Covered by `scripts/test-shim.sh` unit matrix (all green).

### Decision: `--` terminator semantics
- A bare `--` ends rewriting: `--` and everything after it is appended
  verbatim (no `--dir` stripping, no `--variant` merging, no `--auto`
  detection past the terminator). `--auto` injection still applies to the
  pre-`--` prefix and lands before the `--`, so injection never corrupts the
  prompt tail. Verified in both `test-shim.sh` and smoke §5.

### Decision: `gosu` over `USER` (non-root without breaking first boot)
- Our `docker/Dockerfile` layer intentionally declares **no `USER node`**.
  The inherited official entrypoint (`docker-entrypoint.sh`) starts as root,
  repairs ownership of the `/paperclip` data volume (fresh named volumes
  arrive root-owned and would otherwise crash the server on first mkdir),
  then `exec gosu node`. Effective runtime user is still `node` (UID 1000),
  for the server and every agent child process. Declaring `USER node` would
  silently disable the repair — a deliberate, security-reviewed omission,
  documented in-Dockerfile.
- `ENTRYPOINT` re-declared identical to base: `tini` stays PID 1 (reaps zombie
  agent/tool descendants, forwards signals), then drops privileges.

### Decision: `PROXY_DOMAIN` empty-safe default
- `docker-compose.yml` caddy command uses `${PROXY_DOMAIN:-localhost}` so the
  *default* profile (`config`/`up` without `--profile proxy`) always parses
  even when `PROXY_DOMAIN` is empty/unset in `.env`. Set a real hostname only
  when using `--profile proxy` for automatic TLS. Same pattern as the
  reference `/tmp/paperclip/docker/docker-compose.yml` healthcheck style
  (`pg_isready`), but our service is named `postgres` (private, no published
  ports) vs upstream `db` (published 5432).

### Verified facts (wave 1)
- Pins: `node:24-trixie-slim` (official base), `postgres:17-alpine`,
  `@opencode/cli@2.0.31` + `@opencode/client@2.0.31` via
  `OPENCODE_CLI_VERSION`/`OPENCODE_CLIENT_VERSION` ENV, `caddy:2.11.7-alpine`,
  `tailscale/tailscale:v1.104.1`. No `latest` anywhere in ops files
  (smoke §3 greps for it).
- Loopback bind `127.0.0.1:3100:3100`; resource caps
  `cpus 2.0 / mem 4g / pids_limit 2048 / stop_grace_period 90s`.
- `docker compose config` parses with dummy secrets when `.env` is absent
  (smoke §2); with real `.env` it validates required secrets via `:?`.

## Wave 2 Execution Log — Roles & Seeding (recap from repo state)

### Decision: per-role isolation via `XDG_CONFIG_HOME`
- Each agent's `adapterConfig.env.XDG_CONFIG_HOME = /roles/<role>` is picked up
  by Paperclip's `prepareOpenCodeRuntimeConfig`, which copies
  `$XDG_CONFIG_HOME/opencode` to a temp dir, merges runtime providers +
  permissions, and hands it to OpenCode v2. `OPENCODE_DISABLE_PROJECT_CONFIG`
  stays forced (no git pollution from in-workspace configs). `./roles` is
  mounted `:ro` at `/roles`, so role changes need no image rebuild.

### Roles shipped (all `model: anthropic/claude-sonnet-4-5`, overridable)
- `director` (ceo): read-only + task/todo tools; deny edit/write/bash.
- `pm` (pm): same read-only triage shape; heartbeat 1h.
- `programmer` (engineer): allow-all (relies on container sandbox, see README).
- `tester` (engineer): allow read/glob/grep/list + edit/write scoped to
  `**/tests/**` and `**/*{test,spec}.*` + bash; deny general edit/write.
- `qa` (qa): read + webfetch + bash; deny edit/write; Playwright MCP.
- `designer` (designer): read + webfetch; deny edit/write/bash; Playwright MCP.

### Decision: MCP pins
- QA/Designer browser automation pins `npx -y @playwright/mcp@0.0.83` (local
  MCP type). Kept in sync between the two roles; smoke §3 asserts no `latest`
  inside any role MCP command. All other roles ship `"mcp": {}`.

### Seeder (`scripts/seed-company.sh`)
- Idempotent two-pass design: pass 1 ensures all 6 agents exist (order
  independent), pass 2 PATCHes `reportsTo` + `budgetMonthlyCents` only on
  drift. Org chart Director → PM → {Programmer, Tester, QA, Designer}.
- API assumptions verified against `/tmp/paperclip` sources: routes under
  `/api` (`companies.ts`, `agents.ts`
  `POST /companies/:companyId/agents`), Bearer board-token auth,
  `createAgentSchema` (`packages/shared/src/validators/agent.ts`),
  `opencode_local` keys (`packages/adapters/opencode-local/src/index.ts`),
  enum `AGENT_ROLES` (`packages/shared/src/constants.ts`).
  `runtimeConfig.heartbeat` normalizes server-side; `wakeOnAssignment` /
  `wakeOnMention` ride the `.catchall(z.unknown())` and are asserted on echo.
- `--dry-run` prints exact JSON payloads with `<director-id>`/`<pm-id>`
  placeholders; smoke §4 asserts dry-run contains company name,
  `opencode_local`, `XDG_CONFIG_HOME`, `dangerouslySkipPermissions`.

## Wave 3 Execution Log — Ops & Docs (this wave, 2026-10-16)

### Delivered
- `scripts/backup-db.sh` (+x): `.env`-aware `pg_dump --no-owner --clean
  --if-exists` via `docker compose exec -T postgres`, gated on `pg_isready`,
  gzip to `backups/backup-YYYYMMDD-HHMMSS.sql.gz`, non-empty verification,
  retention prune to newest 14 (`BACKUP_RETENTION_COUNT`, 0 disables).
- `scripts/restore-db.sh` (+x): requires `FILE=` (lists available dumps on
  omission), accepts `.sql.gz`/`.sql`, typed-DB-name confirmation unless
  `--yes`/`RESTORE_YES=1`, waits for health (120 s), restores with
  `psql -v ON_ERROR_STOP=1`, prints post-restore table count.
- `Makefile`: default `help` goal; `build/up/down/logs/seed/backup/restore/test`,
  all documented; `-include .env` + `export`; `restore` fails closed without
  `FILE=`. All targets verified with `make -n` (no daemon needed); `restore`
  guard verified at real execution (`FILE=` absent → usage error, exit 1).
- `scripts/smoke-test.sh` (+x): 7 static sections + 3 live sections (§8 pg,
  §9 HTTP, §10 ticket round-trip with endpoint discovery, run-completion poll,
  transcript/cost assertion, workspace-file check, follow-up comment). Live
  ticket flow SKIPs (never fake-passes) when `PAPERCLIP_TOKEN` is unset or the
  issue/comment endpoints are undiscoverable. `--check-only` result:
  **48 passed, 0 failed, 3 skipped (informational)**.
- `README.md`: Mermaid architecture diagram, quickstart, ops table, role
  catalog + add/modify guide, 3-level model swapping, upgrade matrix, security
  model (`dangerouslySkipPermissions` + compensating isolation), layout map.
- This `NOTES.md` update.

### Verification summary (wave 3)
- `shellcheck` clean on all five scripts (incl. pre-existing shim + seeder).
  Two findings fixed: compound-line `source .env` broke SC1091 directive
  binding (split to standalone `source` line); unused `ROLE_JSON_OK` removed.
- `./scripts/smoke-test.sh --check-only` → `SMOKE: OK` (48/0/3), exit 0.
- `make -n` for all 8 targets prints the expected `docker compose` / script
  invocations; `make help` lists every target with descriptions.
- `git status` shows only intended files: `Makefile`, `README.md`, `NOTES.md`,
  `scripts/{backup-db,restore-db,smoke-test}.sh`. No secrets (`.env` absent
  from repo; only `.env.example` tracked), no `latest` pins.

### Links
- Paperclip: https://github.com/paperclipai/paperclip (reference clone:
  `/tmp/paperclip`; official compose `docker/docker-compose.yml`, official
  `Dockerfile` root)
- OpenCode v2 CLI: `@opencode/cli@2.0.31` (`npm install -g @opencode/cli@2.0.31`);
  v2 client SDK `@opencode/client@2.0.31`; v1 package name `opencode-ai@1.19.3`
- Key upstream files read: `packages/adapters/opencode-local/src/server/execute.ts`
  (`--dir`/`--variant`/`OPENCODE_DISABLE_PROJECT_CONFIG`), `server/src/routes/`
  (`companies.ts`, `agents.ts`), `packages/shared/src/validators/agent.ts`,
  `packages/shared/src/constants.ts` (`AGENT_ROLES`)

## Wave 4 Execution Log — 50-Role Fleet & 41-Repo Adversarial Review (2026-10-16)

### 50-Agent Fleet Scaffolding & Seeding Engine
- `scripts/generate-50-roles.py`: Parser-driven generator creating 50 concrete role directories (`roles/<role-id>/`), 52 procedural `SKILL.md` files, and native `opencode.json` files with strict Least-Privilege permissions.
- `scripts/seed-50-fleet.sh`: Two-pass idempotent Paperclip seeding script provisioning the complete 50-agent corporate hierarchy, on-demand heartbeats (`wakeOnAssignment: true`, `wakeOnMention: true`), and exact per-role budgets summing to $12,700.00 USD (1,270,000 cents).
- `scripts/smoke-test.sh`: Expanded to dynamically discover all 56 roles under `roles/` (50 fleet + 6 bootstrap), verifying valid JSON, fail-closed deny tails, non-empty `AGENTS.md`, and zero `:latest` pins across 216 static assertions.

### 41-Repository Adversarial Review Decisions
- Council evaluated 41 ecosystem repositories across 6 domains: 7 Adopt, 15 Adapt, 10 Watchlist, 9 Reject.
- Top 5 High-Impact Adoptions:
  1. `NVIDIA/SkillSpector`: Pre-install CI gate scanning agent skills across 71 detection rules (SARIF output).
  2. `OthmanAdi/planning-with-files`: State persistence (`task_plan.md`, `findings.md`, `progress.md`) surviving context compaction.
  3. `anthropics/skills`: Conformance baseline for metadata and discovery.
  4. `pbakaus/impeccable` + `leonxlnx/taste-skill`: Deterministic UI polish and layout verification loop via `browserless`.
  5. `alibaba/open-code-review`: Multi-pass semantic LLM code review pilot.
- Concrete skills vendored directly into `roles/`:
  - `roles/design-system-eng/.opencode/skills/impeccable-taste/SKILL.md`
  - `roles/tpm-scrum-lead/.opencode/skills/planning-with-files/SKILL.md`
  - `roles/brand-copy-spec/.opencode/skills/humanizer/SKILL.md`

