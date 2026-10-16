# Master Implementation Prompt for OpenCode v2

You are tasked with implementing the complete, self-hosted Docker Compose stack for **Paperclip** (`paperclipai/paperclip`) orchestrating a company-style fleet of **OpenCode v2** agents in this repository (`/home/john/Projects/Heretek-Crew`).

Read this entire prompt and the existing `NOTES.md` before executing any commands or writing code.

---

## 1. Ground Rules & Version Pinning
1. **Never use `latest` tags**:
   - Node: `node:24-trixie-slim`
   - Postgres: `postgres:17-alpine`
   - OpenCode CLI: `@opencode/cli@2.0.31`
   - OpenCode Client SDK: `@opencode/client@2.0.31`
   - Paperclip source: Extend from `/tmp/paperclip` (already cloned from `paperclipai/paperclip`).
2. **Security & Isolation**:
   - Internal network only by default; bind ports to `127.0.0.1:3100`.
   - Never bake secrets or API keys into Docker images. Use `.env` with a complete `.env.example`.
   - All services must run as non-root (`node` UID 1000 in Paperclip container).
   - Enforce resource limits (`mem_limit`, `cpus`, `pids_limit: 2048`) on containers.
3. **Documentation**:
   - Maintain and update `NOTES.md` with verified facts, design decisions, and doc links.
   - Deliver a comprehensive `README.md` with a Mermaid architecture diagram, operational runbooks, role configuration guide, model swapping instructions, and security isolation explanations.

---

## 2. Verified Technical Facts & Breaking Changes (Phase 0 Findings)
Keep these critical facts in mind:
1. **Paperclip's built-in `opencode_local` adapter**:
   - Spawns `opencode run --format json`.
   - In OpenCode v1, `--dir <path>` and `--variant <variant>` were valid CLI flags.
   - **Breaking in OpenCode v2**: `@opencode/cli` rejects `--dir` with `ERROR: Unrecognized flag: --dir in command opencode run`. In v2, OpenCode runs in the process working directory (`process.cwd()`), which Paperclip already sets.
   - **Breaking in OpenCode v2**: `@opencode/cli` rejects `--variant <variant>`. In v2, variants are passed via `--model provider/model#variant`.
   - **Permissions in Unattended Runs**: Paperclip writes `"permission": "allow"` into the temp `opencode.json`. OpenCode v2 non-interactive runs reject tool execution unless either `--auto` is passed on the CLI or `"permissions": [{"action": "*", "resource": "*", "effect": "allow"}]` is present.
   - **Session Resume**: OpenCode v2 natively supports `--session <id>` (or `-s`).
   - **Output Format**: OpenCode v2 `--format json` emits JSONL with `step_start`, `tool_use`, `step_finish` (with token usage and cost accounting), and `text` parts that match Paperclip's parser.
2. **The OpenCode Compatibility Shim**:
   - Place a wrapper script at `/usr/local/bin/opencode` (or intercept the command in Paperclip's PATH) that calls the real `@opencode/cli` binary (`/usr/local/bin/opencode-bin` or global node package).
   - The shim must:
     - Detect `run` subcommand.
     - Strip `--dir <dir>` and `--dir=<dir>` (the process `cwd` is already in the target workspace).
     - Translate `--variant <variant>` by appending `#<variant>` to the preceding or succeeding `--model` argument.
     - Ensure `--auto` is added to `opencode run` if not already present.
     - Pass all other arguments, global flags, and subcommands (`models`, `debug`, `auth`, etc.) directly to the real OpenCode binary.
3. **Per-Role Configuration Isolation**:
   - Paperclip forces `OPENCODE_DISABLE_PROJECT_CONFIG=true` at run time, disabling in-workspace `.opencode/` and `opencode.json` files to prevent git pollution.
   - Paperclip's `prepareOpenCodeRuntimeConfig` checks `agent.env.XDG_CONFIG_HOME` first. It copies `$XDG_CONFIG_HOME/opencode` to a temporary directory `/tmp/paperclip-opencode-config-XXXXXX/opencode`, merges runtime providers and permissions, and passes the temporary `XDG_CONFIG_HOME` to OpenCode.
   - Therefore, to give each agent its own isolated tools, MCP servers, plugins, and skills:
     - Store each role's configuration in `roles/<role>/opencode/opencode.json`.
     - In each Paperclip agent's adapter config `env`, specify `"XDG_CONFIG_HOME": "/roles/<role>"`.
     - OpenCode v2 will load that role's `opencode.json` merged with Paperclip's runtime overrides.

---

## 3. Tasks to Implement

### Task 1: OpenCode v2 CLI Compatibility Shim
- Create an executable wrapper `scripts/opencode-shim.sh` (which installs to `/usr/local/bin/opencode` in Docker).
- Handles:
  - Transparent pass-through for subcommands: `models`, `debug`, `auth`, `mcp`, etc.
  - For `run`:
    - Filters out `--dir <path>` and `--dir=<path>`.
    - Merges `--variant <var>` into `--model <provider>/<model>#<var>`.
    - Injects `--auto` to avoid interactive permission blocking.
    - Preserves stdin piping and stdout streaming (`--format json`).
- Test the shim locally with tests verifying:
  - `opencode models` passes through.
  - `opencode run --format json --dir /tmp --model opencode/gemini-3.8-flash --variant high "prompt"` correctly translates to `opencode-real run --format json --model opencode/gemini-3.8-flash#high --auto "prompt"`.

### Task 2: Dockerfile & Docker Compose Architecture
- **`docker/Dockerfile`**:
  - Extend Paperclip's official build (copy or reference `/tmp/paperclip` build stages).
  - Base: `node:24-trixie-slim`.
  - Install pinned OpenCode v2: `npm install -g @opencode/cli@2.0.31 @opencode/client@2.0.31`.
  - Install base development tools: `git`, `curl`, `jq`, `tini`, `ripgrep`, `python3`, `ca-certificates`.
  - Copy and install the OpenCode compatibility shim as `/usr/local/bin/opencode`, moving the actual node binary to `/usr/local/bin/opencode-cli` or similar.
  - Run as non-root user `node` (UID 1000). Ensure `/paperclip`, `/roles`, `/workspaces` have appropriate permissions.
- **`docker-compose.yml`**:
  - Services:
    1. `postgres`: Image `postgres:17-alpine`. Healthcheck with `pg_isready`. Named volume `pgdata`.
    2. `paperclip`: Built from `docker/Dockerfile`. Environment: `DATABASE_URL`, `PORT=3100`, `SERVE_UI=true`, `PAPERCLIP_DEPLOYMENT_MODE=authenticated`, `PAPERCLIP_DEPLOYMENT_EXPOSURE=private`, `BETTER_AUTH_SECRET`, `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET`. Ports: `127.0.0.1:3100:3100`. Volumes:
       - `paperclip-data:/paperclip`
       - `./roles:/roles:ro`
       - `./workspaces:/paperclip/workspaces`
    3. `caddy` (optional profile `--profile proxy`): Reverse proxy with automatic TLS. Bound to 80/443.
    4. `tailscale` (optional profile `--profile tailscale`): Sidecar container for private mesh network access.
  - Resource limits: `cpus: "2.0"`, `mem_limit: 4g`, `pids_limit: 2048` for Paperclip.
- **`.env.example` & `.env`**:
  - Generate template with required secrets: `BETTER_AUTH_SECRET`, `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET`, `POSTGRES_PASSWORD`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, etc.

### Task 3: Specialist Roles Definition (`roles/`)
Create `roles/<role>/` for the 6 roles:
1. `director` (CEO equivalent):
   - Scope: High-level goals, company direction, architectural decisions, delegations to PM.
   - `roles/director/opencode/opencode.json`: Planning, read/markdown tools, NO code execution or filesystem write MCPs.
   - `AGENTS.md`: Outlines executive responsibilities, delegation chain (delegates only to PM).
2. `pm` (Product Manager):
   - Scope: Task decomposition, issue triage, assigning specifications to programmers and QA.
   - `roles/pm/opencode/opencode.json`: Issue triage tools, status query skills, no direct code execution MCPs.
   - `AGENTS.md`: Outlines task breakdown and delegation rules.
3. `programmer` (Software Engineer):
   - Scope: Feature development, bug fixes, refactoring, writing unit tests.
   - `roles/programmer/opencode/opencode.json`: Edit, shell, git, language tools (LSP/linters).
   - `AGENTS.md`: Outlines coding standards, zero-stub policy, requirement to submit work for QA review.
4. `tester` (Automated & Unit Tester):
   - Scope: Writing test suites, running unit/integration tests, verifying test coverage.
   - `roles/tester/opencode/opencode.json`: Shell (test runners: `npm test`, `vitest`, `pytest`, `cargo test`), read/edit for test files.
   - `AGENTS.md`: Outlines testing requirements.
5. `qa` (Quality Assurance):
   - Scope: End-to-end verification, browser testing (Playwright), red-proof verification.
   - `roles/qa/opencode/opencode.json`: Browser/Playwright tools, shell for acceptance scripts, strictly read-only on production source.
   - `AGENTS.md`: Outlines acceptance criteria, verification reports.
6. `designer` (UI/UX Designer):
   - Scope: UI components, styling, wireframes, design critique.
   - `roles/designer/opencode/opencode.json`: Browser/screenshot tools, SVG/CSS inspection tools.
   - `AGENTS.md`: Outlines design guidelines.

Each role directory must contain:
- `opencode/opencode.json` (v2 native schema with `permissions`, `skills`, `mcp`).
- `.opencode/agents/` and `.opencode/skills/` with specialized instructions.
- `AGENTS.md` specifying role responsibilities, chain of command, and delegation triggers.

### Task 4: Company & Fleet Seeding Automation
- Create `scripts/seed-company.sh` (or TypeScript automation using Paperclip's CLI/API):
  - Initializes the company ("Acme Autonomous Corp").
  - Seeds the 6 agents:
    - Director (CEO, reports to human board).
    - PM (reports to Director).
    - Programmer, Tester, QA, Designer (all report to PM).
  - Configures for each agent:
    - Adapter: `opencode_local`.
    - Model: Configured via environment (e.g. `opencode-go/muse-spark-1.3-contributor` or `opencode/gemini-3.8-flash` or `anthropic/claude-sonnet-4-5`).
    - `env.XDG_CONFIG_HOME`: `/roles/<role-name>`.
    - `dangerouslySkipPermissions`: `true`.
    - Heartbeats:
      - Wake on assignment: `true`.
      - Wake on mention: `true`.
      - Timer: `false` (disabled for all except Director and PM, which get a modest 30m/1h interval if configured).
    - Monthly budget limit per agent (e.g. $100 for Director, $50 for others).

### Task 5: Backup, Restore & Operations (`Makefile`)
- Create `scripts/backup-db.sh` and `scripts/restore-db.sh` for PostgreSQL backups with timestamps.
- Create `Makefile` with clean, documented targets:
  - `make build`: Build the Paperclip + OpenCode v2 Docker image.
  - `make up`: Start the stack in background.
  - `make down`: Stop the stack.
  - `make logs`: Follow logs of paperclip service.
  - `make seed`: Run the company and fleet seeding script.
  - `make backup`: Create a database dump in `backups/`.
  - `make restore FILE=backups/...`: Restore a database dump.
  - `make test`: Run the end-to-end smoke test.

### Task 6: End-to-End Compatibility & Smoke Test
- Create `scripts/smoke-test.sh`:
  - Verifies PostgreSQL health.
  - Verifies Paperclip web server responds at `http://127.0.0.1:3100`.
  - Creates a test ticket assigned to an agent ("Create hello.txt with today's date").
  - Triggers agent wake on assignment.
  - Verifies run completion, transcript in UI, token/cost tracking, and file creation in the workspace.
  - Posts a follow-up comment on the issue and confirms session resumption via `--session`.

### Task 7: Documentation & `NOTES.md`
- **`README.md`**:
  - Architecture diagram (Mermaid) showing Paperclip, PostgreSQL, OpenCode v2 shim, role isolation via `XDG_CONFIG_HOME`, workspaces, and optional reverse proxy.
  - Step-by-step Quickstart (`cp .env.example .env`, `make build`, `make up`, `make seed`).
  - How to add a new role or modify existing roles.
  - How to swap models per role.
  - How to upgrade pinned package and image versions.
  - Security model: Why `dangerouslySkipPermissions` is required for unattended multi-agent execution, and how container isolation (non-root, restricted volumes, pids limits, private networking) compensates for it.
- **`NOTES.md`**: Keep updated with all execution steps, verified facts, and design notes.

---

## 4. Deliverables Checklist
Before finishing, verify that:
- [ ] Paperclip builds and runs using extended official Docker assets.
- [ ] All versions are pinned (`@opencode/cli@2.0.31`, `postgres:17-alpine`, `node:24-trixie-slim`).
- [ ] The OpenCode v2 CLI shim resolves `--dir`, `--variant`, and `--auto` cleanly.
- [ ] `roles/` contains all 6 roles with native v2 configs, role MCPs, and `AGENTS.md`.
- [ ] `scripts/seed-company.sh` creates the company and 6 agents with proper org chart, budgets, and on-demand heartbeats.
- [ ] `Makefile` targets (`up`, `down`, `logs`, `backup`, `restore`, `test`) work reliably.
- [ ] `scripts/smoke-test.sh` passes end-to-end.
- [ ] `README.md` and `NOTES.md` are complete and accurate.
