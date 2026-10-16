# Master Prompt for OpenCode v2: 50-Agent Fleet Scaffolding & Seeding

**Role**: Senior Distributed Systems Engineer & OpenCode v2 Systems Architect  
**Task**: Scaffold the complete 50-agent enterprise fleet on disk (`roles/<role-id>/`) and implement the automated Paperclip seeding engine (`scripts/seed-50-fleet.sh`) based on the master specifications in `roles-catalog/`.  
**Repository**: `/home/john/Projects/Heretek-Crew`  
**Execution Mode**: Zero-Stub, Full-Production, Triad-Verifiable Code.

---

## 1. Architectural Mission & Context

You are tasked with expanding the Heretek-Crew agent repository from the initial 6-role prototype to the complete **50-specialist autonomous enterprise fleet** running under **OpenCode v2** (`@opencode/cli@2.0.31`) and orchestrated by **Paperclip** (`paperclipai/paperclip`).

### Established Architectural Guarantees
1. **Per-Role Configuration Isolation**:
   - Paperclip sets `OPENCODE_DISABLE_PROJECT_CONFIG=true` at runtime to prevent workspace git pollution.
   - Setting `adapterConfig.env.XDG_CONFIG_HOME = "/roles/<role-id>"` in each agent's definition instructs Paperclip's `prepareOpenCodeRuntimeConfig` to copy `/roles/<role-id>/opencode/opencode.json` into a temporary runtime directory, inject runtime provider credentials and permissions, and pass the isolated directory to OpenCode v2.
2. **OpenCode v2 CLI Compatibility Shim**:
   - The container runs `scripts/opencode-shim.sh` (tested with 28/28 assertions passing). It strips `--dir`, maps `--variant` into `--model <provider>/<model>#<variant>`, and injects `--auto` to avoid interactive permission blocks.
3. **On-Demand Execution (No Idle Drain)**:
   - 48 of the 50 roles are strictly **on-demand workers** (`heartbeat.enabled: false`, `intervalSec: 0`, `wakeOnAssignment: true`, `wakeOnMention: true`, `maxConcurrentRuns: 1`). They wake only when a ticket is assigned to them or their username is `@mentioned`.
   - Only 2 coordination roles run recurring heartbeats:
     - `exec-director` (Role 01): 1800s (30 minutes)
     - `tpm-scrum-lead` (Role 03): 3600s (1 hour)
4. **Fleet Budget Allocation**:
   - Total Monthly Fleet Budget: **$12,790.00 USD** (1,279,000 cents) across all 50 roles. Each agent has an exact monthly budget cap defined in cents (`budgetMonthlyCents`).

---

## 2. Master Specification Source of Truth

The entire catalog of 50 roles is fully authored and verified in the repository under `roles-catalog/`:
- **Master Catalog & Summary Matrix**: [`roles-catalog/ROLE_CATALOG_50.md`](file:///home/john/Projects/Heretek-Crew/roles-catalog/ROLE_CATALOG_50.md)
- **Department 1 (Roles 01–06)**: [`roles-catalog/01_executive_and_product_management.md`](file:///home/john/Projects/Heretek-Crew/roles-catalog/01_executive_and_product_management.md)
- **Department 2 (Roles 07–12)**: [`roles-catalog/02_game_development.md`](file:///home/john/Projects/Heretek-Crew/roles-catalog/02_game_development.md)
- **Department 3 (Roles 13–18)**: [`roles-catalog/03_web_and_ui_ux_design.md`](file:///home/john/Projects/Heretek-Crew/roles-catalog/03_web_and_ui_ux_design.md)
- **Department 4 (Roles 19–26)**: [`roles-catalog/04_specialized_language_engineers.md`](file:///home/john/Projects/Heretek-Crew/roles-catalog/04_specialized_language_engineers.md)
- **Department 5 (Roles 27–32)**: [`roles-catalog/05_cloud_platform_and_sre.md`](file:///home/john/Projects/Heretek-Crew/roles-catalog/05_cloud_platform_and_sre.md)
- **Department 6 (Roles 33–38)**: [`roles-catalog/06_quality_assurance_and_verification.md`](file:///home/john/Projects/Heretek-Crew/roles-catalog/06_quality_assurance_and_verification.md)
- **Department 7 (Roles 39–44)**: [`roles-catalog/07_defensive_security_and_forensics.md`](file:///home/john/Projects/Heretek-Crew/roles-catalog/07_defensive_security_and_forensics.md)
- **Department 8 (Roles 45–48)**: [`roles-catalog/08_data_and_ai_systems.md`](file:///home/john/Projects/Heretek-Crew/roles-catalog/08_data_and_ai_systems.md)
- **Department 9 (Roles 49–50)**: [`roles-catalog/09_operations_and_maintenance.md`](file:///home/john/Projects/Heretek-Crew/roles-catalog/09_operations_and_maintenance.md)

### Specific High-Value Tool Requirements (Strictly Maintained)
- **Role 26 (`android-mobile-spec`)**:
  - Primary MCP: `mobile-next/mobile-mcp` (stdio: `npx -y @mobile-next/mobile-mcp@0.1.2`)
  - Integration: `budtmo/docker-android` emulator over ADB (`127.0.0.1:5555`)
  - Skills: `android-compose-architecture`, `artemis-android-ui-exploration` (`google/artemis`)
- **Role 41 (`binary-reverse-eng`)**:
  - Primary MCP: `morluto/rea` (stdio: `npx -y @morluto/rea-mcp` with 120+ RE tools) and `r2mcp` (Radare2)
  - Plugin: `opencode-rea` (`@heretek-ai/opencode-rea`)
  - Skills: `r2-disassembly-analysis`, `rea-evidence-based-decompilation`
  - Integration: Headless Ghidra decompilation passes and symbol renaming

---

## 3. Concrete Deliverables to Implement

### Deliverable 1: Scaffolding Generator Script (`scripts/generate-50-roles.py`)
Because creating 50 roles × 4 files = 200 files manually is prone to truncation and syntax errors, author an executable Python 3 script `scripts/generate-50-roles.py` that parses the specifications from `roles-catalog/*.md` (or encodes the catalog data structure cleanly) and generates the full directory hierarchy under `roles/<role-id>/`:

For each role `<role-id>` (01 to 50):
```
roles/<role-id>/
├── AGENTS.md
├── opencode/
│   └── opencode.json
└── .opencode/
    ├── agents/
    │   └── <role-id>.md
    └── skills/
        └── <skill-name>/
            └── SKILL.md
```

#### File Requirements:
1. **`roles/<role-id>/opencode/opencode.json`**:
   - Must be valid JSON matching OpenCode v2 schema (`"$schema": "https://opencode.ai/config.json"`).
   - Must contain a valid default model (e.g. `"model": "anthropic/claude-sonnet-4-5"`).
   - Strict Least-Privilege `permissions` array (specific shell commands allowed, fallback `{ "action": "shell", "resource": "*", "effect": "deny" }`).
   - Active `skills` array referencing the role's skills.
   - Pinned `mcp.servers` or `mcp` object with real npm/uvx packages (never `:latest`).
   - Enabled `plugins` (e.g. `opencode-mem`, `opencode-rea`).
2. **`roles/<role-id>/AGENTS.md`**:
   - Complete role identity, department, and operational boundaries.
   - Chain of command: Reports to, delegates to, handoff destinations.
   - Specific step-by-step per-ticket workflow.
   - Strict Non-Negotiables & Zero-Stub Policy.
   - Completion protocol and quality gate criteria.
3. **`roles/<role-id>/.opencode/agents/<role-id>.md`**:
   - Frontmatter (`name`, `description`).
   - Full operational system prompt conforming to the catalog spec.
4. **`roles/<role-id>/.opencode/skills/<skill-name>/SKILL.md`**:
   - Frontmatter (`name`, `description`).
   - Step-by-step procedural instructions with exact commands, verification steps, and expected outputs.

---

### Deliverable 2: Complete Fleet Seeding Script (`scripts/seed-50-fleet.sh`)
Build an idempotent, production-grade bash + Python script `scripts/seed-50-fleet.sh` that provisions the entire 50-agent fleet into Paperclip.

#### Features Required:
1. **CLI Flags**:
   - `--dry-run`: Print the exact JSON payloads (1 company + 50 agents) to stdout without making network calls.
   - `--help` / `-h`: Comprehensive usage guide, environment variable list, and org hierarchy summary.
2. **Environment Configuration**:
   - `PAPERCLIP_URL`: Default `http://127.0.0.1:3100`
   - `PAPERCLIP_TOKEN`: Board API key (falls back to `ADMIN_API_KEY`)
   - `COMPANY_NAME`: Default `"Heretek Autonomous Fleet"`
   - `MODEL_DEFAULT`: Default `"anthropic/claude-sonnet-4-5"`
   - Model overrides by tier/department if specified.
3. **Paperclip Data Mapping**:
   - **`role`**: Map each specialist role to a valid Paperclip enum value (`ceo|cto|cmo|cfo|security|engineer|designer|pm|qa|devops|researcher|general`).
   - **`adapterType`**: Always `"opencode_local"`.
   - **`adapterConfig`**:
     ```json
     {
       "model": "<MODEL>",
       "env": {
         "XDG_CONFIG_HOME": "/roles/<role-id>"
       },
       "dangerouslySkipPermissions": true
     }
     ```
   - **`budgetMonthlyCents`**: Exact integer cents from the catalog (e.g. $250.00 -> 25000, $350.00 -> 35000). Total fleet budget must equal **1,279,000 cents** ($12,790.00 USD).
   - **`runtimeConfig.heartbeat`**:
     - `exec-director`: `enabled: true`, `intervalSec: 1800`, `maxConcurrentRuns: 1`, `wakeOnAssignment: true`, `wakeOnMention: true`
     - `tpm-scrum-lead`: `enabled: true`, `intervalSec: 3600`, `maxConcurrentRuns: 1`, `wakeOnAssignment: true`, `wakeOnMention: true`
     - All other 48 roles: `enabled: false`, `intervalSec: 0`, `maxConcurrentRuns: 1`, `wakeOnAssignment: true`, `wakeOnMention: true`
   - **`reportsTo`**: Agent UUID mapping enforcing the org hierarchy:
     - `exec-director`: `null` (reports to Board/Human)
     - `product-director` & `system-architect`: report to `exec-director`
     - `tpm-scrum-lead`, `tech-docs-lead`, `ux-research-analyst`: report to `product-director`
     - Department 2 (Game Dev, Roles 07–12): report to `tpm-scrum-lead`
     - Department 3 (Web/Design, Roles 13–18): report to `tpm-scrum-lead`
     - Department 4 (Language Engineers, Roles 19–26): report to `tpm-scrum-lead`
     - Department 5 (Cloud/SRE, Roles 27–32): report to `system-architect` (or `tpm-scrum-lead`)
     - Department 6 (QA, Roles 33–38): report to `tpm-scrum-lead` (with `release-qa-officer` acting as sign-off gate)
     - Department 7 (Security/Forensics, Roles 39–44): report to `system-architect`
     - Department 8 (Data/AI, Roles 45–48): report to `system-architect`
     - Department 9 (Ops/Maintenance, Roles 49–50): report to `tpm-scrum-lead`
4. **Idempotency**:
   - Check if the company already exists; reuse ID if found.
   - For each agent, query `/api/companies/:companyId/agents`; if an agent with that name already exists, report as existing (or update) rather than creating duplicate agents.

---

### Deliverable 3: Ops & Verification Updates

1. **Update `scripts/smoke-test.sh`**:
   - Update Section 3 of `smoke-test.sh` so that it validates all role directories present under `roles/` (or all 50 roles dynamically):
     - Every `roles/<role>/opencode/opencode.json` must be valid JSON with valid model, permissions, and non-empty rules.
     - Verify no `:latest` tags appear in any role MCP configuration.
     - Check that `AGENTS.md` and `.opencode/agents/<role>.md` exist and are non-empty.
2. **Update `Makefile`**:
   - Add target `generate-roles`: Runs `python3 scripts/generate-50-roles.py`.
   - Add target `seed-50`: Runs `bash scripts/seed-50-fleet.sh`.
   - Update `help` documentation.
3. **Update `README.md`**:
   - Document the 50-agent fleet structure, department breakdown, seeding instructions, and how Paperclip routes tasks to on-demand specialists.

---

## 4. Execution Step-by-Step Plan

Execute in this order:
1. **Phase 1: Generator Script & Execution**:
   - Write `scripts/generate-50-roles.py`.
   - Run `python3 scripts/generate-50-roles.py`.
   - Verify that 50 directories exist under `roles/` with all required files.
2. **Phase 2: Fleet Seeding Engine**:
   - Write `scripts/seed-50-fleet.sh`.
   - Make it executable (`chmod +x scripts/seed-50-fleet.sh`).
   - Run `bash scripts/seed-50-fleet.sh --dry-run` and verify that exactly 51 JSON payloads (1 company + 50 agents) are emitted cleanly.
   - Verify total budget calculation matches $12,790.00 (1,279,000 cents).
3. **Phase 3: Ops Integration & Smoke Verification**:
   - Update `scripts/smoke-test.sh` and `Makefile`.
   - Run `bash scripts/test-shim.sh` (must maintain 28/28 pass).
   - Run `bash scripts/smoke-test.sh --check-only` (must pass all static checks).
   - Run `shellcheck` on all modified or created shell scripts.

---

## 5. Non-Negotiables & Quality Standards

- **Zero Stubs**: No placeholder functions, no empty mocks, no `TODO: add later`. Every skill must contain concrete procedural steps.
- **Fail Closed**: In every `opencode.json`, ensure permissions restrict shell commands to specific binaries needed by that role, ending with `{ "action": "shell", "resource": "*", "effect": "deny" }`.
- **Pin Every Version**: No `:latest` anywhere in Dockerfile, Compose, MCP commands, or packages.
- **Idempotency**: All seeding scripts must be safe to run repeatedly without creating duplicates.
