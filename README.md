# Heretek-Crew — Paperclip + OpenCode v2 Agent Fleet

Self-hosted Docker Compose stack where [Paperclip](https://github.com/paperclipai/paperclip)
orchestrates a company-style fleet of **OpenCode v2** agents: a Director, a PM,
and four specialists (Programmer, Tester, QA, Designer) operating as
"Acme Autonomous Corp".

All versions are pinned — never `latest` (see [Version upgrades](#version-upgrades)).

| Component | Pin | Where |
|---|---|---|
| Node base image | `node:24-trixie-slim` | `docker/Dockerfile` (inherited from official Paperclip base) |
| PostgreSQL | `postgres:17-alpine` | `docker-compose.yml` |
| OpenCode CLI | `@opencode/cli@2.0.31` | `docker/Dockerfile` (`OPENCODE_CLI_VERSION`) |
| OpenCode client SDK | `@opencode/client@2.0.31` | `docker/Dockerfile` (`OPENCODE_CLIENT_VERSION`) |
| Reverse proxy (optional) | `caddy:2.11.7-alpine` | `docker-compose.yml` |
| Mesh sidecar (optional) | `tailscale/tailscale:v1.104.1` | `docker-compose.yml` |
| QA/Designer browser MCP | `@playwright/mcp@0.0.83` | `roles/qa`, `roles/designer` `opencode.json` |

Paperclip source: extended from the official build in `/tmp/paperclip`
(`paperclipai/paperclip`) — we layer on top of it, we do not fork it.

## Architecture

```mermaid
graph TD
    Human([Human board]) -->|HTTPS / Tailscale| Proxy
    Human -->|http://127.0.0.1:3100| Paperclip

    subgraph Host / Docker network `heretek` - private by default
        Proxy{Caddy reverse proxy<br/>profile: proxy<br/>+ Tailscale sidecar<br/>profile: tailscale}
        Proxy -->|paperclip:3100| Paperclip

        subgraph Paperclip container - user `node` UID 1000
            Server[Paperclip server + UI<br/>PORT 3100]
            Shim[opencode shim<br/>/usr/local/bin/opencode]
            RealBin[real OpenCode v2 CLI<br/>/usr/local/bin/opencode-bin<br/>@opencode/cli@2.0.31]
            Server -->|spawn `opencode run --format json`<br/>cwd = agent workspace| Shim
            Shim -->|strips `--dir`<br/>merges `--variant` into `--model#variant`<br/>injects `--auto`| RealBin
        end

        Server -->|DATABASE_URL<br/>postgres:5432| Postgres[(PostgreSQL 17<br/>volume pgdata)]
        Server -->|reads company / agents / runs| Postgres

        RolesDir([./roles - mounted ro at /roles<br/>per-role opencode.json])
        Server -->|agent env XDG_CONFIG_HOME=/roles/role<br/>copied to temp runtime config| RolesDir
        RealBin -->|loads merged role config| RolesDir

        Workspaces([./workspaces - mounted at<br/>/paperclip/workspaces<br/>agent checkouts])
        RealBin -->|edits / runs in| Workspaces
    end

    EnvFile[.env - secrets, never baked into image] -.->|POSTGRES_PASSWORD<br/>BETTER_AUTH_SECRET<br/>API keys| Paperclip
    EnvFile -.-> Postgres
```

How a run flows:

1. The board (or a heartbeat) assigns a ticket to an agent. Paperclip's
   `opencode-local` adapter spawns `opencode run --format json …` with the
   agent workspace as the process working directory.
2. The call lands on the **compatibility shim** (`scripts/opencode-shim.sh`,
   installed as `/usr/local/bin/opencode`), which translates the two v1-only
   flags Paperclip still emits and injects `--auto`, then `exec`s the real
   OpenCode v2 binary (`/usr/local/bin/opencode-bin`).
3. OpenCode loads the agent's **role config**: Paperclip copies
   `$XDG_CONFIG_HOME/opencode` (i.e. `/roles/<role>/opencode`) into a temp
   runtime dir, merges runtime providers/permissions, and points OpenCode at
   it — so every role gets isolated tools, MCPs, and skills.
4. JSONL output (`step_start` / `tool_use` / `step_finish` / `text`) streams
   back to Paperclip for transcript, **token/cost accounting**, and session
   resume via `--session`.

## Quickstart

Prerequisites: Docker with the Compose plugin, `make`, `curl`, `python3`.

```bash
# 1. Configure secrets (never commit .env; never bake keys into images)
cp .env.example .env
# Edit .env: set POSTGRES_PASSWORD, BETTER_AUTH_SECRET,
# PAPERCLIP_TOOL_ACTION_SIGNING_SECRET, and at least one model API key.
# Generate secrets with:  openssl rand -base64 48

# 2. Build the official Paperclip base once, then our wave layer on top
docker build -t paperclip:official-local /tmp/paperclip
make build

# 3. Start the stack (postgres + paperclip, UI/API on 127.0.0.1:3100)
make up

# 4. Seed "Acme Autonomous Corp" + the 6-agent fleet (idempotent)
make seed

# 5. Verify (static checks; live checks run when the stack is up)
make test
```

Open the UI at `http://127.0.0.1:3100`. Follow logs with `make logs`.
Remote access: `docker compose --profile proxy up -d` (Caddy + automatic TLS,
set `PROXY_DOMAIN`), or `docker compose --profile tailscale up -d`
(private mesh; set `TS_AUTHKEY`).

## Operations (`make`)

| Target | What it does |
|---|---|
| `make build` | Build the Paperclip + OpenCode v2 image (`docker compose build`) |
| `make up` | Start the stack detached |
| `make down` | Stop the stack (named volumes keep all data) |
| `make logs` | Follow `paperclip` service logs |
| `make seed` | Seed company + fleet (safe to re-run; patches org-chart/budget drift) |
| `make generate-roles` | Scaffold the 50-agent fleet on disk (`roles/<role-id>/`, idempotent) |
| `make seed-50` | Seed the 50-agent fleet (safe to re-run; patches org-chart/budget drift) |
| `make backup` | `pg_dump` → `backups/backup-YYYYMMDD-HHMMSS.sql.gz`, keeps newest 14 |
| `make restore FILE=backups/…` | Confirm-then-restore a dump (`ON_ERROR_STOP=1`, fail-closed) |
| `make test` | Smoke test: `--check-only` static suite, or full live suite when up |

Backups live in `backups/` (git-ignored). Retention is configurable via
`BACKUP_DIR` / `BACKUP_RETENTION_COUNT` env vars. Restore is destructive by
design (dumps use `--clean`) and requires typing the database name unless
called with `--yes`.

Smoke test modes (`scripts/smoke-test.sh --help` documents both):

- `--check-only`: no server, daemon, or secrets needed. Checks repo files,
  `docker compose config`, role JSON validity + pins, seed dry-run, shim
  translation matrix, file-creation simulation, `--session` support. Used by
  `make test` in CI gates.
- live (default): everything above plus `pg_isready`, HTTP health at
  `http://127.0.0.1:3100`, and — with `PAPERCLIP_TOKEN` set — a real ticket
  round-trip: assign "Create hello.txt with today's date" to an agent, wait
  for run completion, verify transcript + token/cost accounting + workspace
  file, post a follow-up comment to confirm `--session` resumption.

## Roles

Six roles ship under `roles/<role>/`, each with `AGENTS.md` (charter, chain of
command, delegation triggers) and `opencode/opencode.json` (v2-native
permissions, skills, MCPs):

| Role | Paperclip role | Reports to | Tools | Heartbeat |
|---|---|---|---|---|
| `director` | ceo | human board | read-only (no edit/write/bash) | 30 min |
| `pm` | pm | Director | read-only triage | 1 h |
| `programmer` | engineer | PM | full (edit/shell/git) | on-demand |
| `tester` | engineer | PM | test files + test runners only | on-demand |
| `qa` | qa | PM | read + bash + Playwright MCP | on-demand |
| `designer` | designer | PM | read + webfetch + Playwright MCP | on-demand |

Org chart: Director → PM → {Programmer, Tester, QA, Designer}. Only Director
and PM have timer heartbeats; everyone wakes on assignment and on mention.
Monthly budgets: $100 Director, $50 others (see `BUDGET_*` in
`scripts/seed-company.sh`).

### Add a new role (or modify one)

1. Copy an existing role as a template:
   `cp -r roles/programmer roles/sre` (or `roles/qa` for a read-biased role).
2. Edit `roles/sre/opencode/opencode.json`: set `model`, least-privilege
   `permissions` (deny `edit`/`write`/`bash` you don't need), `skills`, and any
   `mcp` servers (pin versions, never `latest`).
3. Write `roles/sre/AGENTS.md`: identity/scope, who it reports to, who it may
   delegate to, delegation triggers, non-negotiables, completion protocol.
4. Wire it into `scripts/seed-company.sh`: extend `ROLE_LIST` and the
   `role_*()` metadata helpers (Paperclip role enum, display name, model,
   budget, timer, `reportsTo` wiring in both dry-run placeholders and pass 2).
5. Validate without a server:
   `./scripts/seed-company.sh --dry-run` and
   `./scripts/smoke-test.sh --check-only` (add the role to the smoke test's
   role loop so it stays covered).

Per-role isolation needs no image rebuild: `./roles` is mounted read-only at
`/roles` and each agent's adapter config sets `env.XDG_CONFIG_HOME` to
`/roles/<role>`. Re-seed (or update the agent in the UI) to pick up changes.

### Swap models per role

Three levels, cheapest first:

1. **Per role file** — edit the `"model": "provider/model"` string in
   `roles/<role>/opencode/opencode.json` (e.g. `"model": "opencode/gemini-3.8-flash"`),
   then re-seed or update the agent. Variants use the v2 suffix form:
   `"provider/model#variant"` (the shim also auto-merges Paperclip's legacy
   `--variant` flag into this form).
2. **At seed time** — `MODEL_DEFAULT=… MODEL_DIRECTOR=… MODEL_PM=… ./scripts/seed-company.sh`
   overrides the adapter `model` for all / director / PM agents without
   touching role files.
3. **Credentials** — provider keys come from `.env`
   (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, …); they are injected at runtime,
   never baked into the image.

## 50-agent fleet (`roles-catalog/` → `roles/` → Paperclip)

Beyond the 6-role prototype above, the repo ships a full **50-specialist
enterprise fleet** specified in `roles-catalog/ROLE_CATALOG_50.md` (plus
department modules `01_*.md` … `09_*.md`) and scaffolded on disk under
`roles/<role-id>/`. Each fleet role carries the same four artifacts as the
prototype roles: `AGENTS.md`, `opencode/opencode.json`,
`.opencode/agents/<role-id>.md`, and skill packs under
`.opencode/skills/*/SKILL.md`. The 6 prototype roles remain in place and stay
covered by the smoke test (which discovers roles dynamically).

### Department breakdown (9 departments, 50 roles)

| Dept | Module | Roles | Count |
|---|---|---|---|
| 1. Executive & Product Management | `01_executive_and_product_management.md` | `exec-director`, `product-director`, `tpm-scrum-lead`, `system-architect`, `tech-docs-lead`, `ux-research-analyst` | 6 |
| 2. Game Development | `02_game_development.md` | `game-systems-dev`, `graphics-shader-eng`, `engine-systems-eng`, `game-ai-dev`, `physics-sim-eng`, `tech-artist-pipeline` | 6 |
| 3. Web & UI/UX Design | `03_web_and_ui_ux_design.md` | `ui-ux-designer`, `design-system-eng`, `a11y-specialist`, `fe-perf-eng`, `mobile-web-eng`, `brand-copy-spec` | 6 |
| 4. Specialized Language Engineers | `04_specialized_language_engineers.md` | `rust-systems-spec`, `go-backend-eng`, `python-backend-spec`, `ts-node-fullstack`, `cpp-lowlevel-eng`, `java-kotlin-eng`, `ios-mobile-spec`, `android-mobile-spec` | 8 |
| 5. Cloud, Platform & SRE | `05_cloud_platform_and_sre.md` | `cloud-platform-eng`, `k8s-orchestrator`, `sre-incident-eng`, `observability-eng`, `dba-specialist`, `cache-streaming-eng` | 6 |
| 6. Quality Assurance & Verification | `06_quality_assurance_and_verification.md` | `e2e-browser-qa`, `api-contract-tester`, `load-stress-tester`, `sabotage-qa-tester`, `static-analysis-lead`, `release-qa-officer` | 6 |
| 7. Defensive Security & Forensics | `07_defensive_security_and_forensics.md` | `appsec-engineer`, `cloud-sec-auditor`, `binary-reverse-eng`, `firmware-sec-analyst`, `threat-modeler`, `compliance-auditor` | 6 |
| 8. Data & AI Systems | `08_data_and_ai_systems.md` | `data-pipeline-eng`, `vector-rag-spec`, `mlops-serving-eng`, `analytics-metrics-eng` | 4 |
| 9. Operations & Maintenance | `09_operations_and_maintenance.md` | `dependency-patcher`, `git-drift-coord` | 2 |

Notable specialist wiring (see the catalog for the full spec):
`android-mobile-spec` drives `mobile-mcp` (`@mobile-next/mobile-mcp@0.1.2`)
against a `docker-android` emulator over ADB (`127.0.0.1:5555`);
`binary-reverse-eng` pairs `morluto/rea` + `r2mcp` (Radare2) with the
`opencode-rea` plugin for evidence-based decompilation.

### Seeding the fleet

```bash
# 1. Scaffold (or re-scaffold) all 50 role directories from the catalog
make generate-roles            # python3 scripts/generate-50-roles.py (idempotent)

# 2. Preview exactly what would be POSTed — no network calls
bash scripts/seed-50-fleet.sh --dry-run   # 1 company + 50 agent payloads

# 3. Seed "Heretek Autonomous Fleet" + 50 agents into Paperclip (idempotent)
make seed-50                   # bash scripts/seed-50-fleet.sh
```

Model overrides: `MODEL_DEFAULT=…` re-targets all 50 agents,
`MODEL_COORDINATOR=…` re-targets the three coordination roles
(`exec-director`, `tpm-scrum-lead`, `system-architect`); heartbeat
intervals via `TIMER_EXEC_SEC` / `TIMER_TPM_SEC` (defaults 1800 / 3600).

**Budget note — known $90 catalog discrepancy.** The catalog's documented
fleet cap is **$12,790.00 USD** (1,279,000 cents), but the authoritative
verbatim per-role values sum to **$12,700.00 USD** (1,270,000 cents) — a
$90.00 gap. The seeder uses the per-role catalog values verbatim, prints
the computed total, and emits a `WARNING` on mismatch; it never invents
budgets to force the total. The smoke test asserts this handling
(51 payloads + budget total + `WARNING`) so the discrepancy stays visible
until the catalog is amended.

### How Paperclip routes tasks to on-demand specialists

- **Isolation** — every agent is seeded with
  `adapterConfig.env.XDG_CONFIG_HOME=/roles/<role-id>`, so Paperclip's
  `prepareOpenCodeRuntimeConfig` copies that role's `opencode.json` into a
  temp runtime dir, merges credentials/permissions, and hands it to
  OpenCode v2. No image rebuild is needed to change a role: edit
  `roles/<role-id>/`, re-run `make generate-roles` if the change belongs
  in the generator, and re-seed.
- **On-demand wake** — 48 of the 50 roles are seeded with
  `heartbeat.enabled: false, intervalSec: 0, wakeOnAssignment: true,
  wakeOnMention: true`: they consume no idle tokens and wake only when a
  ticket is assigned or they are `@mentioned`. Only `exec-director`
  (1800 s) and `tpm-scrum-lead` (3600 s) run recurring heartbeats.
- **Hierarchy (`reportsTo`)** — `exec-director` answers to the human
  board; `product-director` and `system-architect` report to
  `exec-director`; `tpm-scrum-lead`, `tech-docs-lead`, and
  `ux-research-analyst` report to `product-director`. Game, Web/Design,
  Language, QA, and Ops roles report to `tpm-scrum-lead`; Cloud/SRE,
  Security/Forensics, and Data/AI roles report to `system-architect`.
  Seeding is two-pass (ensure agents, then PATCH `reportsTo` + budgets on
  drift), so `make seed-50` is safe to re-run and heals org-chart drift.

## Version upgrades

| What | Current | Where to change | Notes |
|---|---|---|---|
| OpenCode CLI/client | `2.0.31` | `docker/Dockerfile` `ENV OPENCODE_CLI_VERSION` / `OPENCODE_CLIENT_VERSION` | Bump together; re-run shim + smoke tests (`--dir`/`--variant`/`--auto` behavior may change upstream) |
| Node base | `node:24-trixie-slim` | inherited from official base rebuilt from `/tmp/paperclip` | Rebuild `paperclip:official-local` first |
| PostgreSQL | `postgres:17-alpine` | `docker-compose.yml` `postgres.image` | `make backup` before major bumps; PG data volume may need `pg_upgrade`/dump-restore |
| Caddy | `caddy:2.11.7-alpine` | `docker-compose.yml` `caddy.image` | proxy profile only |
| Tailscale | `tailscale/tailscale:v1.104.1` | `docker-compose.yml` `tailscale.image` | tailscale profile only |
| Playwright MCP | `@playwright/mcp@0.0.83` | `roles/qa`, `roles/designer` `opencode.json` | keep QA/Designer in sync |

After any bump: `make build && make up && make test` (live), plus
`scripts/test-shim.sh` for the shim matrix.

## Security model

**Why `dangerouslySkipPermissions` is `true` for every agent.**
OpenCode v2 non-interactive runs reject tool-approval prompts
(`"This non-interactive run cannot ask the user for permission…"`) unless the
run passes `--auto` or carries an allow-all permissions array. Paperclip drives
agents unattended — there is no human at the approval prompt at 3 AM — so both
are set: every seeded agent has `dangerouslySkipPermissions: true`, the role
configs carry explicit `permissions` arrays, and the shim injects `--auto`.
Read-scoped roles (Director, PM, QA, Designer, Tester-outside-tests) additionally
`deny` `edit`/`write`/`bash` at the OpenCode layer, so even an auto-approved
run cannot write where its role forbids.

**How container isolation compensates.** Auto-approve is only safe inside a
sandbox; this stack provides it:

- **Private networking by default** — the UI/API binds `127.0.0.1:3100`;
  Postgres exposes no host ports at all. Remote access is opt-in via the
  `proxy` (Caddy/TLS) or `tailscale` profiles.
- **Non-root execution** — the Paperclip server and every agent child process
  run as `node` (UID 1000): the entrypoint repairs `/paperclip` ownership as
  root, then `exec gosu node`. (Deliberately no `USER node` in our layer —
  that would silently disable the ownership repair and break first boot.)
- **Restricted volumes** — `./roles` is mounted `:ro`; only
  `./workspaces` and the `paperclip-data` volume are writable, so a rogue run
  cannot rewrite its own role config or escape the data dir.
- **Resource ceilings** — `cpus: 2.0`, `mem_limit: 4g`, `pids_limit: 2048`
  stop a fork-bombing or runaway fleet from starving the host; `tini` reaps
  zombie agent/tool descendants.
- **No baked secrets** — API keys and signing secrets live only in `.env`
  (git-ignored, documented in `.env.example`); images carry versions, not
  credentials. Backups contain database bytes only and stay in git-ignored
  `backups/`.
- **Fail-closed scripts** — seed, backup, restore, and smoke scripts abort on
  unhealthy dependencies, refuse to guess (restore requires `FILE=` plus typed
  confirmation), and restore with `ON_ERROR_STOP=1`.

## Layout

```
docker-compose.yml        postgres + paperclip (+ optional caddy/tailscale profiles)
docker/Dockerfile         official-base extension: OpenCode v2 + shim, pinned
.env.example              secrets template (copy to .env, never commit .env)
Makefile                  build/up/down/logs/seed/backup/restore/test
scripts/
  opencode-shim.sh        v1→v2 CLI translation (--dir/--variant/--auto)
  seed-company.sh         idempotent company + 6-agent seeder (supports --dry-run)
  generate-50-roles.py    50-role disk scaffolding generator (roles/<role-id>/)
  seed-50-fleet.sh        idempotent 50-agent fleet seeder (supports --dry-run)
  backup-db.sh            timestamped pg_dump + retention
  restore-db.sh           confirmed, fail-closed restore
  smoke-test.sh           --check-only static suite + live ticket round-trip
  test-shim.sh            shim unit matrix (wave 1)
roles/<role>/            AGENTS.md charter + opencode/opencode.json v2 config
workspaces/               agent checkouts (host-visible, backup-friendly)
backups/                  timestamped dumps (git-ignored)
```

Design notes, verified upstream facts, and the wave-by-wave execution log live
in [`NOTES.md`](NOTES.md).
