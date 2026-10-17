# Heretek-Crew Research Expansion Report
## Multi-Subagent Ecosystem Investigation — 8 Tracks, Synthesis & 30-Day Roadmap

**Date:** 2026-10-17
**Source prompt:** `PROMPT_SUBAGENT_RESEARCH_EXPANSION.md`
**Fleet baseline verified:** 50 roles in `roles/` (9 departments, `roles-catalog/`), OpenCode v2 `@opencode/cli@2.0.32`, Paperclip + Postgres 17, `scripts/opencode-shim.sh`
**Method:** 7 parallel research subagents (Tracks 1–7) with live `webfetch`/GitHub API/shallow clones to `/tmp/opencode/*` + local grounding (`roles/*/opencode/opencode.json`, `AGENTS.md`, `SUPPORTING_SERVICES.md`). This file is Track 8 synthesis.

---

## Table of Contents

1. [Executive Scorecard & Key Recommendations](#1-executive-scorecard--key-recommendations)
2. [Track 1 — Claude Plugins vs OpenCode Interop](#2-track-1--claude-plugins-vs-opencode-interop-awesome-claude-plugins)
3. [Track 2 — Agent Methodology & Harness OS](#3-track-2--agent-methodology--harness-os-ecc--superpowers)
4. [Track 3 — GitHub Ecosystem Mining (7 domains)](#4-track-3--github-ecosystem-mining-across-7-strategic-domains)
5. [Track 4 — OpenCode Best Practices](#5-track-4--opencode-best-practices--real-world-configurations)
6. [Track 5 — Can Anything Replace Paperclip?](#6-track-5--the-orchestrator-battle--can-anything-replace-paperclip)
7. [Track 6 — Architecture Translation (claude-code-best-practice)](#7-track-6--architecture-translation-claude-code-best-practice)
8. [Track 7 — Cyber Defense & New Roles](#8-track-7--cyber-defense-skills--new-security-roles-anthropic-cybersecurity-skills)
9. [30-Day Evolutionary Roadmap](#9-the-30-day-heretek-crew-evolutionary-roadmap)
10. [Appendices — Snippets, Tables, Guardrails](#10-appendices)

---

## 1. Executive Scorecard & Key Recommendations

### 1.1 One-paragraph verdict

**Stay with Paperclip. Patch the adapter. Vendor procedures, not platforms.** No evaluated orchestrator replaces Paperclip's company layer (tickets + locks + heartbeat + budgets + approvals + PG + WebUI + multi-org = 38/40 vs 17–23/40 for all alternatives). No plugin repo is OpenCode-native — all value ports as `SKILL.md`/agent/command content, plus 2–3 real MCP servers. The highest-ROI moves are: (a) Superpowers TDD/debugging skills into every implementer role, (b) Cognee memory layer on top of existing Qdrant+Neo4j, (c) codebase-memory-mcp + Serena to close the symbol/call-graph gap, (d) `ecc-agentshield` as CI audit gate, (e) `small_model` + loop/context guards + `.env` deny audit in the 50 `opencode.json` files, (f) 5 new security roles led by `ai-red-teamer`, (g) Spec-Kit + OpenSpec as CI-enforced spec gates.

### 1.2 Scorecard (Track → Recommendation → Effort → Impact)

| Track | Recommendation | Effort | Impact | Priority |
|---|---|---|---|---|
| 1 — awesome-claude-plugins | Port TOP 5 (connect-apps, security-sweep, codebase-graph, test-writer-fixer/pr-review/ship, AgentLint); ignore hype tier | S (0.5d/role) | M–H | P1 |
| 2 — ECC | Adopt ideas + `ecc-agentshield@1.6.0` CI gate; do NOT install `ecc-universal` (311 skills blow context) | S | M | P1 |
| 2 — Superpowers | Vendor 2–4 skills/role (TDD + systematic-debugging everywhere; brainstorming/writing-plans for director/architect) | S–M | **H** | **P0** |
| 3 — SDD | Spec-Kit (governance skeleton) + OpenSpec (per-role authoring UX) + `spec-gate.sh` in CI | M | H | P1 |
| 3 — Memory | **Cognee-first** on existing Qdrant+Neo4j; Mem0 OSS pilot in parallel; reject Zep Cloud (egress) | M | H | P1 |
| 3 — Code-intel | `DeusData/codebase-memory-mcp` (primary) + `oraios/serena` (safe-edit) + `code-review-graph` (review blast-radius); keep ast-grep/Semgrep/Qdrant | M | **H** | **P0** |
| 3 — Web | Keep Firecrawl+Crawl4AI+SearXNG+Browserless; add `browser-use` self-host core + swap puppeteer → `microsoft/playwright-mcp` | M | M | P2 |
| 3 — Automation | Windmill (script-workflows) + n8n (guarded sidecar); pilot Temporal only if saga pain materializes | M | M | P2 |
| 4 — Config | Add `small_model` (haiku), `steps`/doom-loop cap, MCP `timeout`, `compaction.prune`, `.env` deny; dialect-translation doc | S | H (cost+reliability) | **P0** |
| 5 — Orchestrator | **STAY WITH PAPERCLIP**, harden adapter (Phases 0–3); custom daemon only as tracked contingency | S–M | H (avoids 6–12mo rewrite) | **P0 decision** |
| 6 — best-practice | Frontmatter upgrade (50 roles), 3-file skill split, command layer, `fleet-hooks.sh`, ≤200-line memory hygiene | M | H | P1 |
| 7 — Cyber skills | Inject 10–20 skills into each of 6 existing security roles; create 5 new roles (R1 ai-red-teamer first) | M | H | P1 |

### 1.3 Top 10 actionable decisions (if you read nothing else)

1. **Paperclip stays.** Score 38/40; OpenRig 23, Temporal 21, OpenHands 23, CrewAI/AutoGen/LangGraph 19, custom daemon 17. Patch, don't migrate (§6).
2. **Superpowers TDD everywhere.** Iron Law (no production code without watched-fail test) + systematic-debugging directly enforce the zero-stub policy (§3).
3. **Cognee for memory.** Only candidate that leverages Qdrant+Neo4j instead of duplicating them (§4.3).
4. **codebase-memory-mcp + Serena.** Closes the biggest capability hole (symbol/call-graph + safe LSP edit), 70–99% exploration-token reduction (§4.7).
5. **Spec-Kit + OpenSpec gates.** Formalize the PRD→ADR→Decompose pipeline the fleet spec already assumes (§4.1).
6. **`small_model` + `steps` + `compaction.prune` + MCP `timeout`.** Largest cost/reliability lever; 50/50 roles currently Sonnet-only with zero guards (§5).
7. **`ecc-agentshield@1.6.0` CI gate.** Audit scanner (not sandbox) for prompts/hooks/MCP/secrets per role (§3).
8. **`ai-red-teamer` new role first.** 14-skill AI-security domain has zero coverage despite running a 50-agent AI fleet (§8).
9. **Port 5 plugin picks, reject hype.** connect-apps, security-sweep, codebase-graph, test/ship workflow, AgentLint; ignore image/piano/personality plugins (§2).
10. **Fix the `skills` path discrepancy.** `opencode.json` declares `/roles/<id>/skills` but files live at `.opencode/skills/` — verify what `prepareOpenCodeRuntimeConfig` actually honors before vendoring or new skills silently won't load (§3, §10.5).

---

## 2. Track 1 — Claude Plugins vs OpenCode Interop (`composio-community/awesome-claude-plugins`)

**Repo:** https://github.com/composio-community/awesome-claude-plugins (1.9k★, 662 forks, verified 2026-10-17). **Clone verified** to `/tmp/opencode/awesome-claude-plugins`. **Local grounding:** `roles/` = 50 dirs; sample `roles/static-analysis-lead/opencode/opencode.json` uses `mcp.servers = {name: {type:"local", command:[...]}}` stdio format.

### 2.1 Category inventory (README + `marketplace.json` + disk)

| Category | Plugins on disk | Notes |
|---|---|---|
| Integrations | `connect-apps`, ext `kaggle-skill` | Only native MCP bridge in repo |
| Frontend & Design | `frontend-design`, `artifacts-builder`, `theme-factory`, `canvas-design`, `senior-frontend`, `frontend-developer` | All SKILL.md/agent-prompt only, no MCP |
| Git & Version Control | `commit`, `create-pr`, `pr-review`, `changelog-generator`, `ship` | `ship` largest (491-line `ship.md` + CI-review + Railway/Vercel deploy) |
| Code Quality & Testing | `code-review`, `test-writer-fixer`, `debugger`, `bug-fix`, ext `AgentLint` | Prompt/agent only |
| Backend & Architecture | `backend-architect`, `mcp-builder`, ext `maestro-orchestrate` | `mcp-builder` is meta-skill for authoring MCP servers |
| DevOps & Performance | `perf`, `audit-project`, ext `MyVibe`, `aws-cost-saver`, `Manifest` | `perf` = 8 SKILLs (baseline/benchmark/analyzer); `audit-project`/`ship` share `lib/` (validator, schemas, repo-map) |
| Documentation & Security | `documentation-generator`, `security-guidance`, ext `security-sweep`, `asqav-claude-code` | `security-guidance` = hooks-only (`hooks.json` + `security_reminder_hook.py`) |
| Developer Productivity | `developer-growth-analysis`, `skill-bus`, ext `CCHub`, `context-mode`, `codebase-graph`, `agntk`, `backlog` | `skill-bus` = hooks + dispatcher |
| Companion/Image/Video | ext only: `claude-familiar`, `nano-banana`, `taisly-agent-kit` | Hype tier, ignore for fleet |

Plugin format (verified): `plugin-name/.claude-plugin/plugin.json` + `skills/*/SKILL.md` | `commands/*.md` | `agents/*.md` | `hooks/hooks.json`. **Claude-Code native, not OpenCode native.** No `.mcp.json`/`opencode.json` found (`find -iname "*mcp*" -o -iname "*opencode*"` returns only `mcp-builder` itself). Port = copy SKILL.md/agent md into `/roles/<id>/.opencode/skills/` or `agents/`, translate `commands/*.md` to OpenCode commands; only MCP-backed items need `mcp.servers` entries.

### 2.2 OpenCode/MCP compatibility

**Natively MCP-backed (load via `opencode.json` `mcp.servers`):**

| Plugin | Mechanism | OpenCode path |
|---|---|---|
| `connect-apps` (`connect-apps/commands/setup.md`) | Writes `~/.mcp.json` → `{"connect-apps": {"type":"http","url":"https://connect.composio.dev/mcp","headers":{...}}}` via Composio gateway (1000+ apps) | `{"type":"remote","url":"https://connect.composio.dev/mcp","headers":{"x-consumer-api-key":"${COMPOSIO_API_KEY}"}}` — inject via Paperclip `adapterConfig.env`, never commit key |
| ext `codebase-graph` (https://github.com/Phoenixrr2113/codebase-graph) | Real MCP server, npm `@agntk/codegraph-mcp` (tree-sitter + FalkorDB; tools `analyze`/`search`/`knowledge`/`codebase`/`query`) | `"codegraph": {"type":"local","command":["npx","-y","@agntk/codegraph-mcp@<pin>"]}` — pin version |
| ext `backlog` (https://github.com/backloghq/backlog) | 24 MCP tools, TS, event-sourced task store | Local `npx`/`node` server entry per its README |
| `mcp-builder` (`mcp-builder/skills/mcp-builder/SKILL.md`, 126 lines) | Not a server; skill teaching FastMCP (Python)/TS-SDK authoring | Copy SKILL.md into role skills dir; no `mcp.servers` entry |

**Prompt-only, trivially portable (no MCP):** `frontend-design`, `senior-frontend`, `test-writer-fixer`, `code-review`/`commit`/`create-pr`/`pr-review`/`changelog-generator` (thin `commands/*.md` over `git`/`gh`), `security-guidance` (hooks → port to OpenCode hooks), `security-sweep` ext (SKILL.md + `patterns.md` regex, `allowed-tools: Read,Grep,Glob,Bash,Agent`). Zero reference MCP servers.

### 2.3 Sentry/GitHub/Linear/Supabase/Vercel/Stagehand verdict

**None are first-class plugins in this repo** (README + marketplace.json + `ls`: no sentry/linear/supabase/vercel/stagehand dirs). What exists: GitHub via `connect-apps` (Composio) + `gh`-based commands (`ship`, `create-pr`, `pr-review`); Vercel only as deploy target inside `ship/commands/ship-deployment.md`. Sentry/Linear/Supabase/Stagehand: **absent** — route through `connect-apps` gateway or official MCP servers added directly to `opencode.json`; do not expect them from this repo.

### 2.4 TOP 5 high-leverage picks

**1. `connect-apps` — Composio MCP gateway.** https://github.com/composio-community/awesome-claude-plugins/tree/master/connect-apps — single endpoint proxying 1000+ apps (Gmail/Slack/GitHub/Notion/Linear per composio.dev/tools) with OAuth + audit logs. MCP: YES native. Roles: `exec-director`, `tpm-scrum-lead`, `product-director`.
```json
"mcp": { "servers": { "connect-apps": { "type": "remote", "url": "https://connect.composio.dev/mcp", "headers": { "x-consumer-api-key": "${COMPOSIO_API_KEY}" } } } }
```

**2. `security-sweep` (ext) — OWASP scanner skill.** https://github.com/Onome-AJ/security-sweep-plugin — SKILL.md-driven scan (secrets/injection/auth/config/deps/AI/mobile/data), OWASP Top 10 2025 + Mobile 2024 + LLM 2025; framework-aware triage. MCP: N/A (Read/Grep/Glob/Bash only). Roles: `appsec-engineer`, `threat-modeler`, `cloud-sec-auditor`. Copy `skills/security-sweep/{SKILL.md,patterns.md}`; back with PoLP `semgrep --config*`, `gitleaks detect*` + deny tail.

**3. `codebase-graph` (ext) — code-knowledge-graph MCP.** https://github.com/Phoenixrr2113/codebase-graph (npm `@agntk/codegraph-mcp`) — tree-sitter (42 langs) → FalkorDB; tools `codebase/configure+reindex`, `search`, `analyze` (impact/cycles/dead-code/coupling), `query` (read-only Cypher), `knowledge`. Roles: `system-architect`, `static-analysis-lead`, `vector-rag-spec`.
```json
"mcp": { "servers": { "codegraph": { "type": "local", "command": ["npx", "-y", "@agntk/codegraph-mcp@0.1.0"], "env": { "CODEGRAPH_DATA_DIR": "/roles/system-architect/.codegraph", "CODEGRAPH_EMBEDDING_PROVIDER": "none" } } } }
```

**4. `test-writer-fixer` + `pr-review`/`ship` — test & ship workflow.** `.../tree/master/test-writer-fixer`, `.../tree/master/pr-review`, `.../tree/master/ship` — test agent (write/run/fix Jest/Vitest/Pytest) + 6-lens PR review template + `/ship` commit→CI-monitor→deploy (`gh`, Railway/Vercel). Roles: `release-qa-officer`, `git-drift-coord`, `e2e-browser-qa`. Permissions: allow `git diff*|git log*|gh pr*|npm test*|pytest*`, deny tail intact.

**5. `AgentLint` (ext) — harness linter.** https://github.com/0xmariowong/AgentLint (npm `agentlint-ai`) — 51 deterministic checks over AGENTS.md/CLAUDE.md/CI/hooks/`.gitignore`; catches 40K truncation, SHA-unpinned Actions, `.env` leaks. CLI, not MCP. Roles: `system-architect`, `static-analysis-lead` (fleet-wide audits).
```json
"permissions": [{"action":"shell","resource":"npx -y agentlint-ai@<pin> check*","effect":"allow"},{"action":"shell","resource":"*","effect":"deny"}]
```

**Porting rule (all):** Claude `--plugin-dir`/`plugin.json` do not transfer; transfer the *content* (SKILL.md/agent/commands/hooks). Pin every npm/pkg version, inject secrets via env, keep the deny-all `shell` tail per `AGENTS.md` §4.

---

## 3. Track 2 — Agent Methodology & Harness OS (ECC + Superpowers)

Sources: live `webfetch` of both repos + shallow clones at `/tmp/opencode/ECC` and `/tmp/opencode/superpowers`; local `roles/`, `roles/system-architect/AGENTS.md`, `roles/system-architect/opencode/opencode.json`, `scripts/opencode-shim.sh`. Versions verified 2026-10-17: `ecc-universal@2.2.3`, `ecc-agentshield@1.6.0`.

### 3.1 ECC (`affaan-m/ECC`, v2.2.3, MIT)

Curated distribution: one canonical content tree (`skills/` ×311, `agents/` ×71, `commands/` ×97 legacy shims, `rules/`, `hooks/`, `workflows/`, `mcp-configs/`) + manifest-driven installer (`ecc-universal` npm package, `scripts/ecc.js` + `install.sh`) projecting into each harness's native layout. Harness coverage explicitly tiered (README "Pick one path only"): **native plugin path** = Claude Code (`ecc@ecc` marketplace), Codex, Qoder, Kimi Code; **managed adapters (second tier)** = `cursor, antigravity, gemini, opencode, codebuddy, joycode, qwen, zed, hermes, openclaw` via `ecc install --target <harness>`. **OpenCode is second-tier**, not on the guided `install --guided` path (currently Claude/Codex/Kimi only).

The OpenCode adapter is real: `.opencode/opencode.json` (default `build` primary agent, `planner`/`architect` subagents with `write:false`, `instructions` pinning `skills/tdd-workflow`, `security-review`, `verification-loop`, `skills.paths: ["../skills"]`), `.opencode/plugins/ecc-hooks.ts`, `.opencode/tools/*.ts` (security-audit, run-tests, lint-check, check-coverage, changed-files), tests (`opencode-tools.test.js`, `opencode-plugin-hooks.test.js`, `opencode-config.test.js`).

Management mechanism worth stealing: **selective-install manifests** — `config/install-profiles.json`, `install-components.json`, `install-modules.json`, `context-profiles/`, `context-packs/` driving `ecc install --profile minimal|core|standard|full --target X`, plus `consult` (NL→component recommendation), `catalog`, `doctor --target X`. Rules distributed as **opt-in packs** (`rules/common` + one language pack) because Claude plugins cannot ship rules — precedent directly relevant to §7.

**`ecc-agentshield` verdict: audit scanner, NOT a sandbox.** `ecc-agentshield@1.6.0` = static scanner (`agentshield scan --path .` or `/security-scan`) auditing prompts, hooks, MCP config, permissions, secrets, agent files; plus GateGuard (destructive-shell gating) and supply-chain IOC scanner in CI. It **cannot enforce OpenCode `opencode.json` permissions at runtime** and does not replace the deny-tail, MCP resource-layer GRANTs, or container isolation. **Concrete adoption:** pin `ecc-agentshield@1.6.0`, review the binary once, add `agentshield scan --path roles/<role-id>` as a new `smoke-test.sh` section (fail on secrets in skills, over-broad `shell` allows, unknown MCP commands). Low cost, real value — call it auditing, never sandboxing.

**Capability maps + token optimization: partially portable.** ECC has the pieces (`skills/product-capability/`, `consult`, `catalog`, `install-components.json`, `project-stack-mappings.json`) but they map *harness→components*, not *ticket→fleet-role*. Do not import; copy the **pattern**: a `consult`-like NL→role/skill router could live in `exec-director`. Token doctrine ports directly (`docs/token-optimization.md` + `skills/context-budget/` + `skills/strategic-compact/` + `skills/token-budget-advisor/`): cheap-model subagents (Haiku-class explorers; Sonnet-class ~80%), bounded audits, 50-entry caps — but the knobs are Claude-Code-specific (`CLAUDE_CODE_EFFORT_LEVEL`, `CLAUDE_CODE_SUBAGENT_MODEL`). Heretek equivalent: per-role model selection in `roles-catalog/` budgets + bounded-audit procedure for observability roles. Do not copy env-var settings.

### 3.2 Superpowers (`obra/superpowers`, MIT, 15 skills)

**Native OpenCode support: yes, and clean.** OpenCode is first-class (`docs/README.opencode.md`, `.opencode/INSTALL.md`): V2 (≥2.0.4) plugin entry `"plugins": ["superpowers@git+https://github.com/obra/superpowers.git"]`, dual V1/V2 loader in `.opencode/plugins/superpowers.js` (V2 `setup()` registers skills via `ctx.skill.transform()`, bootstrap via `ctx.session.hook("context")`), zero dependencies. Heretek runs `@opencode/cli@2.0.32` — compatible. V2 skill priority = project > personal > Superpowers, so fleet project skills override on collision (use distinct names regardless).

**The methodology (the actual asset)** — seven-step chain: `brainstorming` (chunked spec elicitation, "one question per message") → `using-git-worktrees` (isolation-first) → `writing-plans` (tasks sized to one test cycle + one reviewer gate; header mandates `subagent-driven-development` or `executing-plans`; plans under `docs/superpowers/plans/`) → `subagent-driven-development` (fresh implementer subagent per task → spec+quality review per task → ≤5 fix rounds → whole-branch final review; "rulings, not stalls") or `executing-plans` (cheap inline variant, one final review) → `test-driven-development` (**Iron Law**: no production code without a watched-fail test; violators delete, not adapt) → `requesting-code-review` (SHA-pinned reviewer template) → `finishing-a-development-branch` (verify → merge/PR/keep/discard → cleanup). Support: `systematic-debugging` (no fixes without root-cause Phase 1), `verification-before-completion`, `dispatching-parallel-agents`, `receiving-code-review`.

**Importable into `roles/`? Yes — as procedure library, not driver.** Format matches exactly (`SKILL.md` frontmatter `name:` + one-line `description:` + markdown body = local `roles/system-architect/.opencode/skills/madr-architecture-decision/SKILL.md` convention). Three impedance mismatches to adapt: (1) interactive-partner assumption (`brainstorming` dialogue) fits only human-facing roles; (2) worktree/branch freedom vs per-role confined `fs:write` scopes ("fail closed, do not work around the denial"); (3) subagents-vs-fleet: **roles ARE the subagents; Paperclip/`exec-director` is the dispatcher** — map to `executing-plans` *within* a role or `dispatching-parallel-agents` fan-out *at* `exec-director`/`tpm-scrum-lead`.

| Role(s) | Skills to vendor | Why |
|---|---|---|
| `product-director` | `brainstorming`, `writing-plans` | Chunked elicitation → phased PRDs/epics (`epic-roadmap-authoring` stays the output format) |
| `system-architect` | `writing-plans` | Binds ADRs to bite-sized test-gated tasks |
| `python-backend-spec`, `ts-node-fullstack`, `go-backend-eng`, `cpp-lowlevel-eng`, `rust-systems-spec`, `java-kotlin-eng` | `test-driven-development`, `systematic-debugging` | Iron-law TDD + no-fix-without-root-cause enforce zero-stub policy |
| `api-contract-tester`, `e2e-browser-qa`, `release-qa-officer`, `sabotage-qa-tester` | `verification-before-completion`, `requesting-code-review` | Evidence-before-done matches QA gates |
| `exec-director`, `tpm-scrum-lead` | `dispatching-parallel-agents`, `finishing-a-development-branch` (decision table only) | Fan-out pattern + merge/PR/keep/discard matrix minus git commands outside allowed lists |

**Concrete import steps:**
```bash
for r in python-backend-spec ts-node-fullstack go-backend-eng; do
  mkdir -p roles/$r/.opencode/skills/test-driven-development
  cp /tmp/opencode/superpowers/skills/test-driven-development/SKILL.md \
     roles/$r/.opencode/skills/test-driven-development/SKILL.md
done
```
Register in `roles/<id>/AGENTS.md` §5 (`- test-driven-development — RED-GREEN-REFACTOR iron law. (procedure: .opencode/skills/test-driven-development/SKILL.md)`), ensure verification commands are in `opencode.json` `permissions` (skills are decorative if tests can't run), add one Per-Ticket Workflow line (§7): "Execute implementation steps under `.opencode/skills/test-driven-development/SKILL.md`; no production code without a watched-fail test." Pin at a commit SHA (`superpowers@git+https://github.com/obra/superpowers.git#<sha>`), keep per-role copies (no shared symlinks — confined write scopes + per-role review), extend `smoke-test.sh` to assert `SKILL.md` frontmatter (`name`/`description`).

### 3.3 Bottom-line verdicts

- **ECC:** adopt *ideas and one tool* — selective-install manifests + `doctor`/ownership pattern; `ecc-agentshield@1.6.0` pinned CI gate; token doctrine translated to per-role tiers. Do **not** install `ecc-universal` into role `XDG_CONFIG_HOME`s (311 skills blow context + collide with least-privilege scoping; OpenCode adapter second-tier anyway).
- **Superpowers:** adopt *procedures* — 2–4 skills/role per table above. Highest ROI: `test-driven-development` + `systematic-debugging` for implementers; `brainstorming`/`writing-plans` for `product-director`/`system-architect`.

---

## 4. Track 3 — GitHub Ecosystem Mining Across 7 Strategic Domains

**Method:** GitHub REST `search/repositories` + `repos/:owner/:repo` (stars/description/pushed_at, 2026-10-17) + trend validation + `SUPPORTING_SERVICES.md` incumbent stack. Star counts API-verified 2026-10-17 unless marked `~`.
**Incumbent stack (authoritative):** Firecrawl 2.10.19 + Crawl4AI 0.9.4 + SearXNG + Browserless `chromium:v2.24.2`; ast-grep 0.33.0 + Semgrep 1.97.0 + Hound v6.0.0; Qdrant v1.12.5 + Neo4j 5.26-community + `mcp-server-qdrant`/`neo4j-mcp` + `opencode-mem`-class session plugin + Ollama 0.5.4-spec; LiteLLM v1.54.0 gateway; Ghidra 11.2 + REA bridge.

### 4.1 Spec-driven development

| Repo | Stars | Verdict | Integrate? |
|---|---|---|---|
| `github/spec-kit` — SDD toolkit (specify/plan/tasks) | 141,576 | Most production-hardened; GitHub-official, harness-neutral, active 2026-10-16. Maps 1:1 to PRD→ADR→decompose | **Y — primary** |
| `Fission-AI/OpenSpec` — SDD for AI assistants (`openspec/` proposals) | 72,173 | Lightest agent-native loop; topic page #1 for `spec-driven-development` (2,530 repos) | **Y — complementary** |
| `gsd-build/get-shit-done` — meta-prompting + context-engineering SDD | 64,285 | Powerful but stale (pushed 2026-05-31), Claude-Code-coupled, fragmented successor (`open-gsd/gsd-core` 10.6k★) | N (watch) |
| `bmad-code-org/BMAD-METHOD` — Agile AI-Driven Development | 54,239 | Richest agent-role pack but heaviest ceremony; slowest time-to-first-diff | N (borrow roles only) |
| `gotalab/cc-sdd` / `spec-kitty/spec-kitty` — minimal SDD / governance SDD | 3.7k / 1.7k | Niche: best OpenCode-compatible minimal harness / charter governance | Fallback |

External comparisons converge: **Spec-Kit = governance, OpenSpec = velocity, BMAD = theatre.** Adopt **Spec-Kit as enforcement skeleton** (`constitution.md` + `specify`/`plan`/`tasks` gates — fail merge if `specs/` deltas missing) and **OpenSpec `change-id` proposal flow as per-role authoring UX** (researcher writes proposal, `exec-director` approves, `tpm` decomposes). Integration: `scripts/spec-gate.sh` checking `openspec/changes/<id>/{proposal,tasks}.md` + spec-kit `tasks.md` checkboxes, wired into `smoke-test.sh`; pin `github/spec-kit` digest as submodule; expose both slash-commands via `opencode.json` skills.

### 4.2 `claude-code` domain (harness/skills/plugins)

| Repo | Stars | Verdict | Integrate? |
|---|---|---|---|
| `obra/superpowers` | 300,763 | Largest skills-methodology repo; harness-agnostic markdown ports directly to `.opencode/skills/` | **Y — primary** |
| `anthropics/skills` — official Agent Skills repo | 181,632 | Canonical skill spec + reference skills; forward-compat guarantee | **Y — pin spec** |
| `anthropics/claude-code` — terminal agentic coding tool | 151,277 | Reference harness, not self-hostable fleet runtime; CLI-parity testing only | N (parity-test) |
| `modelcontextprotocol/servers` — reference MCP servers | 91,317 | Upstream source for puppeteer/fetch/memory servers the stack already wraps | Y (vendor from) |
| `wshubson/agents` — multi-harness plugin marketplace (Claude/Codex/Cursor/OpenCode/Copilot) | 40,934 | Best cross-harness skill pack; pushed 2026-10-15. Ideal donor for role `SKILL.md` | **Y — donor** |

Do not chase Claude-Code-as-runtime. Treat `anthropics/skills` as the **skill-format standard**, bulk-import `superpowers` + selected `wshubson/agents` role packs into `roles/<id>/.opencode/skills/`, gated by PoLP review. Sketch: `scripts/sync-skills.sh --pin obra/superpowers@<sha>` → copy allow-listed `SKILL.md` → `smoke-test.sh` asserts no `shell:*` beyond role allow-list.

### 4.3 Long-term memory (deep dive vs Qdrant/Neo4j/opencode-mem incumbent)

Incumbent = Qdrant (dense vectors) + Neo4j (relationship graph) + `opencode-mem`-class session plugin (local, file/SQLite-backed). Missing: **extraction/retrieval layer** (fact extraction, entity resolution, temporal decay, conflict merge).

| Repo | Stars | Verdict | Integrate? |
|---|---|---|---|
| `mem0ai/mem0` — Memory Layer for AI agents | 67,322 | Most production-hardened; hosted + OSS, Qdrant/Postgres backends; best docs/ops. Active 2026-10-16 | **Y — pilot** |
| `topoteretes/cognee` — OSS AI memory, ECL + small-model friendly | 32,417 | **Best self-host fit:** builds entity/temporal KG **on top of existing Qdrant+Neo4j** instead of replacing them; `pip install cognee`, no SaaS | **Y — primary self-host** |
| `letta-ai/letta` (ex-MemGPT) — stateful agents, self-editing archival memory | 25,168 | Architecturally unique but heaviest (stateful server, manual archival search); overkill per-role | N (borrow block-memory pattern) |
| `getzep/zep` — temporal KG memory (Graphiti) | 4,963 (+ cloud) | Technically excellent temporal graph, but production path pushes to Zep Cloud = data-egress + cost conflict | N |
| `memodb-io/memobase` — user-profile LTM | 2,932 | Narrow (chatbot profiles), stale (Jan 2026) | N |

2026 roundups agree: **Mem0 = facts store (fast, best eval harness), Zep = temporal graph (accurate, SaaS gravity), Letta = agent memory OS (powerful, heavy), Cognee = ECL middleware (cheapest self-host, reuses infra).** Cognee persists into the *existing* Qdrant collections + Neo4j graph, preserving sidecar topology and zero-egress posture. Mem0 is the right second bet only if hosted fallback is ever acceptable (OSS server behind `docker-socket-proxy` with `MEM0_QDRANT_URL=http://qdrant:6333`).
**Integration sketch (Cognee-first):** new sidecar `cognee:0.x-pinned` (or pip lib inside `memory-bridge`) wired `COGNEE_VECTOR_DB=qdrant:6333`, `COGNEE_GRAPH_DB=bolt://neo4j:7687`; roles call `POST /memories` / `GET /search` via MCP wrapper; nightly `scripts/memory-decay.sh` prunes stale edges. Decision gate = LOCOMO-style recall eval on fleet runbooks.

### 4.4 AI agents (frameworks/orchestration)

| Repo | Stars | Verdict | Integrate? |
|---|---|---|---|
| `langchain-ai/langchain` | 147,952 | Ubiquitous but sprawling; LangGraph subset is the durable part; heavy deps conflict with pinned-lean images | N (patterns only) |
| `microsoft/autogen` | 61,440 | Best conversation/topology primitives (round-robin, reflection) | N (pattern donor) |
| `crewAIInc/crewAI` | 59,778 | Closest analog to 50-role fleet (roles/handoffs/tasks); but Paperclip already *is* the orchestrator — adoption duplicates it | N (steal role-task schema) |
| `FlowiseAI/Flowise` | 55,509 | Useful for non-eng TPM sketching, but visual-runner + Node baggage; stale (Aug 2026) | N |
| `HKUDS/nanobot` — ultra-light self-hosted agent + WebUI + MCP + memory | 49,100 | Lightest credible alternative harness; sidecar experiment only, not fleet replacement | Watch |
| `langchain-ai/langgraph` / `huggingface/smolagents` / `pydantic/pydantic-ai` | 43.4k / 29.9k / 20.7k | LangGraph = durable-workflow gold; smolagents = code-first minimalism; pydantic-ai = typed best-practice | **Y — LangGraph patterns only** |

No new orchestrator — Paperclip+OpenCode v2 already occupy that slot. **LangGraph as design donor**: model TPM decomposition/retries/fan-out as durable graphs executed by Paperclip assignments. Optionally trial `nanobot` as single `devsec`-profile sandbox for untrusted experiments.

### 4.5 Web scrapers (LLM-ready ingestion)

| Repo | Stars | Verdict | Integrate? |
|---|---|---|---|
| `firecrawl/firecrawl` | 192,252 | Already composed (5-container `web-research` block). Category king; keep | **Y — incumbent** |
| `browser-use/browser-use` — AI browser agents + stealth cloud | 118,232 | Agentic browsing (goal→actions: form-filling, paginated flows) beyond scraping; self-hostable Playwright core complements Browserless | **Y — add self-host core** |
| `unclecode/crawl4ai` | 85,679 | Already composed; best structured extraction. Keep | **Y — incumbent** |
| `microsoft/playwright-mcp` — official Playwright MCP | 38,253 | Canonical CDP bridge; cleaner than bespoke puppeteer wrappers for Browserless endpoint | **Y — swap-in** |
| `ScrapeGraphAI/Scrapegraph-ai` | 31,828 | Prompt-driven extraction: flexible but nondeterministic + token-hungry vs Crawl4AI schemas | N |
| `jina-ai/reader` / `exa-labs/exa-mcp-server` | 12.1k / 5.1k | Excellent SaaS search/reader, but external-egress violates self-host/loopback posture | N |

Two surgical upgrades: (1) `browser-use` self-host core as `web-research` sidecar for agentic multi-step retrieval into the Firecrawl pipeline; (2) replace `@modelcontextprotocol/server-puppeteer` with `microsoft/playwright-mcp` pointed at `ws://browserless:3000?stealth=true`. Sketch: pinned `browser-use` container, `BROWSER_USE_CDP_URL` env, MCP tool `browser_agent_goal` allow-listed per researcher role; SSRF guard via Firecrawl URL validation + mitmproxy egress logging.

### 4.6 Workflow automation (durable execution)

| Repo | Stars | Verdict | Integrate? |
|---|---|---|---|
| `n8n-io/n8n` — fair-code automation, 400+ integrations, AI nodes | 207,733 | Category king for human-readable automations (backup ROT, digests, webhook intake). Fair-code, self-host compatible | **Y — guarded sidecar** |
| `temporalio/temporal` — durable execution | 23,761 | Gold standard for long-running sagas (seed-50, restore-db, multi-hour decompositions) with replay/timeout semantics Paperclip lacks. Heaviest addition | **Y — pilot for sagas** |
| `windmill-labs/windmill` — scripts→workflows/UIs, fastest engine | 18,207 | Best script-native fit (Python/TS/Go/Bash first-class); ideal home for `scripts/*.sh` as versioned workflows | **Y — script runner** |
| `hatchet-dev/hatchet` | 8,132 | Well-designed but subscale vs the three above | N |

Adopt **Windmill for script-workflows + n8n for integration-automations**, pilot **Temporal only if saga-replay pain materializes**. Sketch: `windmill` sidecar importing `scripts/backup-db.sh`, `seed-50-fleet.sh --dry-run`, `smoke-test.sh --check-only` as versioned steps with audit logs; `n8n` loopback-only (`127.0.0.1:5678`) for scheduled digests and WireMock/Mailpit hooks, MCP-gated to `tpm-scrum-lead`/`exec-director`; both behind `docker-socket-proxy` allow-list, no privileged flags.

### 4.7 Code intelligence (deep dive vs ast-grep/Hound/Semgrep incumbent)

Incumbent = ast-grep 0.33.0 (structural search/rewrite, 20+ langs) + Hound trigram search + Semgrep 1.97.0 (security rules) + shared-volume checkouts. Missing: **persistent symbol graph, call-graph tracing, cross-file definition resolution** — vectors find similar text; they don't answer "who calls this" or "who implements this interface."

| Repo | Stars | Verdict | Integrate? |
|---|---|---|---|
| `DeusData/codebase-memory-mcp` — C/tree-sitter KG MCP, 162 langs, ms indexing, sub-ms queries, ~99% fewer tokens | 46,728 | Best throughput-per-watt: native C + SQLite graph, persistent across sessions | **Y — primary** |
| `continuedev/continue` — OSS coding agent + code-intel context engine | 36,234 | Mature embeddings+symbol hybrid; heavyweight as full agent, good indexing reference | N (reference) |
| `tirth8205/code-review-graph` — local-first code graph, benchmarked context reduction | 32,206 | Strongest review-specific graph (impact/blast-radius); Python, auditable. Pairs with codebase-memory (index vs review) | **Y — review sidecar** |
| `oraios/serena` — MCP toolkit, semantic retrieval + editing (LSP-backed) | 30,336 | Best *editing* semantics (rename/move with LSP safety) where codebase-memory is read-optimized. Complementary | **Y — editing complement** |
| `ast-grep/ast-grep` (incumbent) | 16,252 | Keep: unbeatable structural rewrite/lint; no persistent graph, no overlap conflict | **Y — keep** |
| `Graphify-Labs/graphify` | ~127k★ (topic-inflated, verify) | Deterministic-AST pitch, but star count looks farmed, evals thin | Watch (re-eval Q1) |

2026 MCP code-intel comparisons agree: **tree-sitter graph indexers cut exploration tokens 70–99%** vs grep/embedding-only retrieval. None replace ast-grep (rewrite), Semgrep (security rules), or Qdrant (semantic doc search) — they sit **between** them as the structural layer, persisting to SQLite/volumes shared with downstream QA/Refactorer roles.
**Integration sketch:** sidecar `codebase-memory` (`devsec` profile, pinned image, `./workspaces:/src:ro` + `codegraph-data` volume) exposing MCP `resolve_symbol`/`call_graph`/`dependents`; `serena` scoped to programmer/refactorer roles for LSP edits; `code-review-graph` in QA pipeline (`semgrep scan` → graph blast-radius → SARIF). Benchmark context-reduction on fleet monorepo before promoting to `core`; preserve read-only mounts and deny-tails.

### 4.8 Cross-cutting standouts (if forced to 3)

1. **`topoteretes/cognee` (memory)** — only candidate that *leverages* Qdrant+Neo4j instead of duplicating them.
2. **`DeusData/codebase-memory-mcp` + `oraios/serena` (code-intel)** — closes the biggest capability hole with measured token savings.
3. **`github/spec-kit` + `Fission-AI/OpenSpec` (SDD)** — formalizes PRD→ADR→Decompose with CI-enforceable gates.

All preserve invariants: pinned digests (no `:latest`), loopback-only UIs, `*_PASSWORD` via `.env`, `--dry-run`/`--help` on new scripts, `shellcheck`-clean, PoLP MCP gating with terminal `deny` tails, no SaaS-egress additions.

---

## 5. Track 4 — OpenCode Best Practices & Real-World Configurations

Verified against live docs (`opencode.ai/docs/{config,permissions,models,mcp-servers,agents,skills,policies}`).

### 5.1 Upstream canonical facts

- **Config format:** JSON/JSONC, `$schema: https://opencode.ai/config.json`. Sources **merge** in precedence: remote `.well-known/opencode` → global `~/.config/opencode/opencode.json` → `OPENCODE_CONFIG` → project `opencode.json` → `.opencode/` dirs → `OPENCODE_CONFIG_CONTENT` → managed (`/etc/opencode/`, MDM).
- **Model selection:** `--model/-m` > config `model` > last-used > internal priority. Format `provider/model` (e.g. `anthropic/claude-sonnet-4-5`). **No native `fallback` chain in core config** — tiering/failover via plugins (oh-my-openagent `model_fallback`), OpenCode Zen routing, or LiteLLM proxy.
- **`small_model`:** separate cheap model for title/summary/compaction; defaults to cheap same-provider model else main model.
- **Variants:** `model#variant` (`--model x/y#high`). Built-ins: Anthropic `high`/`max`, OpenAI `none/minimal/low/medium/high/xhigh`, Google `low/high`. Custom variants definable; `variant_cycle` keybind switches.
- **Permissions (modern key: singular `permission`):** `tool → allow|ask|deny`, or per-pattern object (`bash: {"*":"ask","git *":"allow","rm *":"deny"}`). **Last matching rule wins** — `"*"` first, specifics after. Defaults: mostly `allow`; `doom_loop` + `external_directory` default `ask`; `read` allows all except `*.env` denied by default. `--auto` auto-approves anything not explicitly `deny`.
- **Agents:** `agent.<name> = {description, mode: primary|subagent|all, model, prompt, temperature, steps (max iterations/cost cap), permission (agent wins over global), hidden, color}`. Built-ins: `build` (full), `plan` (edit/bash ask), `general`/`explore`/`scout`, hidden `compaction`/`title`/`summary`.
- **MCP:** `mcp.<name> = {type: local|remote, command[], environment/env, cwd, enabled, timeout (default 5000ms)}` or `{type: remote, url, headers, oauth, enabled, timeout}`. Tools namespaced `server_tool`; gate via `tools: {"my-mcp*": false}` + per-agent re-enable. Docs warn: MCP servers (esp. GitHub) inflate context fast.
- **Skills:** `SKILL.md` discovery (`.opencode/skills/`, `~/.config/opencode/skills/`, `.claude/skills/`, `.agents/skills/`); frontmatter requires `name` (match dirname, `^[a-z0-9]+(-[a-z0-9]+)*$`) + `description` (1–1024 chars). Gated by `permission.skill`; `skill:false` disables.
- **Cost/context knobs:** `compaction: {auto, prune, reserved}`, `snapshot` (disable for huge repos), `watcher.ignore`, `instructions[]`, `experimental.policies` (replaces `disabled_providers`), `{env:VAR}`/`{file:path}` substitution.

### 5.2 Config pattern table (community + enterprise consensus)

| Pattern | Production form | Seen in |
|---|---|---|
| Global vs project split | Global: providers, `model`, `small_model`, timeouts. Project (checked-in): least-privilege `permission`, `agent`, `mcp`, `instructions` | docs precedence; `share your opencode.json` threads |
| Read-only agents | `plan`/`explore`/`review`: `edit: deny`, `bash: {"*":"ask","git diff*":"allow"}` | docs/agents; security-auditor pattern |
| Bash prefix allowlist | `bash: {"*":"ask","git *":"allow","npm *":"allow","rm *":"deny"}`, narrow `edit` paths | docs/permissions |
| Deny tail | Broad deny first, specific allows after (last-match-wins) | docs rule-order |
| MCP scoping | `tools: {"mymcp_*": false}` globally, enable per-agent; `timeout`, `enabled:false` opt-in; secrets via `{env:...}` | docs/mcp-servers |
| Model tiering | `model` = Sonnet-class for build; per-agent `plan: haiku`, title/summary haiku; failover via oh-my-openagent/Zen/LiteLLM, **not** core | tiered-architecture guides |
| Cache/token optimisation | `setCacheKey: true`, `small_model` for chores, `compaction: {auto:true,prune:true,reserved:10000}`, minimal MCP, `snapshot:false` on monorepos | docs config + compaction |
| Version pinning | `npx -y pkg@x.y.z`, `uvx pkg==x.y.z` in MCP commands | all community examples; Heretek already compliant |
| Enterprise lockdown | Managed config (`/etc/opencode/`, MDM), `experimental.policies` provider allowlist, `external_directory` scoping | docs managed-settings + policies |

### 5.3 Operational trap → defense matrix

| # | Trap | Symptom | Standard defense | Heretek status |
|---|---|---|---|---|
| T1 | Permission hang (headless) | `opencode run` blocks on approval, Paperclip timeout | `--auto` + explicit `deny` (auto approves only non-denied) | ✅ COVERED — shim injects `--auto` exactly once |
| T2 | Infinite retry / doom loop | Same tool ×N, token burn | `permission.doom_loop: ask/deny` + per-agent `steps` cap | ❌ GAP — no `doom_loop`, no `steps` in 50 roles |
| T3 | Prefix-match shell bypass | `git status; <payload>` matches `git status*` | Fail-closed deny tail **plus** resource-layer enforcement | ✅ COVERED & DOCUMENTED — `AGENTS.md` §2 names this |
| T4 | MCP bypasses shell denies | `psql*` shell-deny but `postgres_*` MCP still writes | Per-namespace MCP deny tails + true read-only creds (DB GRANTs, read-only kubeconfig) | ✅ AHEAD — dba/k8s roles do both |
| T5 | Context exhaustion | GitHub MCP / too many servers blow context | Minimal MCP per role, `timeout`, `compaction.prune`, `small_model`, `snapshot:false` | ⚠️ PARTIAL — minimal-MCP good, zero `compaction`/`small_model`/`snapshot`/`timeout` |
| T6 | Secret leakage via read | Agent reads `.env` | Upstream default denies `*.env`; explicit `read: {"*.env":"deny"}` | ⚠️ UNVERIFIED — fleet `fs:read **` roles (dba, k8s) have no `.env` deny; rests on mount scoping |
| T7 | Model deprecation breakage | `ProviderModelNotFoundError` after rename | Pin `provider/model`, `opencode models` verify | ✅ COVERED — all 50 pin `anthropic/claude-sonnet-4-5`; shim folds `--variant` |
| T8 | Stale provider-package cache | `AI_APICallError` after provider change | `rm -rf ~/.cache/opencode`, restart | ➖ Runbook note; container rebuild clears |
| T9 | Config-precedence surprise | Project re-enables globally-denied provider | Global policy wins for `experimental.policies` | ✅ COVERED — `OPENCODE_DISABLE_PROJECT_CONFIG=true` + XDG isolation |
| T10 | Unbounded agent cost | No iteration cap, Sonnet for trivia | `steps` cap + `small_model` (haiku) | ❌ GAP — no `steps`, no `small_model`; all 50 incl. `exec-director` run Sonnet-4-5 |

### 5.4 Recommended template (upstream-native; fleet-dialect translation below)

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-5",
  "small_model": "anthropic/claude-haiku-4-5",
  "provider": { "anthropic": { "options": { "timeout": 300000, "chunkTimeout": 900000, "setCacheKey": true } } },
  "compaction": { "auto": true, "prune": true, "reserved": 10000 },
  "permission": {
    "edit": { "*": "deny", "deploy/**": "allow" },
    "bash": { "*": "ask", "git status*": "allow", "git diff*": "allow", "helm lint*": "allow", "rm *": "deny" },
    "read": { "*": "allow", "*.env": "deny", "*.env.*": "deny" },
    "doom_loop": "ask", "external_directory": "ask", "skill": { "*": "allow" }
  },
  "agent": { "plan": { "mode": "primary", "model": "anthropic/claude-haiku-4-5", "temperature": 0.1, "permission": { "edit": "deny", "bash": "deny" } } },
  "mcp": { "postgres": { "type": "local", "command": ["npx", "-y", "@modelcontextprotocol/server-postgres@0.6.2", "{env:POSTGRES_READONLY_URL}"], "enabled": true, "timeout": 5000 } },
  "tools": { "postgres_*": false },
  "instructions": ["AGENTS.md"],
  "experimental": { "policies": [
    { "effect": "deny", "action": "provider.use", "resource": "*" },
    { "effect": "allow", "action": "provider.use", "resource": "anthropic" }
  ]}
}
```

Fleet-dialect translation (Paperclip adapter consumes `permissions[]` not `permission{}`): keep existing `permissions` arrays + deny tails, add missing semantic guards at the enforcing layer — `doom_loop`/iteration caps in orchestrator or `steps`-equivalent, `small_model` routing in `prepareOpenCodeRuntimeConfig`, MCP `timeout` passthrough.

### 5.5 Gap analysis vs Heretek (fleet-wide grep over all 50 `roles/*/opencode/opencode.json`)

**Strengths (keep):** 50/50 valid `provider/model`, pinned MCP versions, terminal `shell * deny` enforced by smoke-test §3/§3b, per-namespace MCP deny tails, `fs:write * deny` on all 50, read-only resource layer, `--auto` injection, XDG isolation. Stricter than most community configs sampled.
**Gaps (value-ordered):** (1) Dialect divergence — 0/50 use upstream `permission`/`agent`/`tools` keys; recommend dialect-translation table + conformance test. (2) No cost tiering — 50/50 Sonnet-4-5, zero `small_model`. (3) No loop/context guards — zero `compaction`/`prune`/`snapshot`/`steps`/`doom_loop`/`timeout`. (4) No provider hardening — zero `provider.options`/`policies`. (5) `.env` read path unverified — add explicit deny or document mount guarantee. (6) Non-portable `skills` path (`/roles/<id>/skills` absolute, valid only under `XDG_CONFIG_HOME` mount).

---

## 6. Track 5 — The Orchestrator Battle: Can Anything Replace Paperclip?

**Verdict: No. Patch, don't migrate. Score: Paperclip 38/40 vs next-best 23/40.**

### 6.1 Fair baseline: what Paperclip actually is

Source: `paperclipai/paperclip` — 103k★, 17.3k forks, MIT, Node 24 + React + Fastify/Prisma + embedded/self-hosted Postgres 17, `npx paperclipai@latest onboard`. Full control plane, not a wrapper: CLI/TUI/MCP → Hono/Fastify server (Identity | Tasks | Heartbeat | Governance | OrgChart | Workspaces | Plugins | Budgets | Routines | Secrets | Activity | Portability) → Claude Code | Codex | Cursor | Gemini | OpenCode | Pi | Hermes | OpenClaw | HTTP bots.

Relevant subsystems for the 50-role fleet: **heartbeat execution** (DB-backed wakeup queue with coalescing, budget checks, workspace resolution, secret injection, skill loading, adapter invocation; 48/50 Heretek roles on-demand `heartbeat.enabled:false` = 1:1 match; bounded recovery + human-escalation); **work system** (issues with company/project/goal/parent links, atomic checkout + execution locks, blocker deps, comments/docs/attachments/work-products, inbox, revisioned plans, anchored feedback); **governance** (approval gates, board workflows, execution policies, pause/reassign/terminate, connection-action approvals, config revision + rollback, org-scoped access); **budget & cost** (token/cost rollup by company/agent/project/goal/issue/provider/model; scoped policies with warnings + hard stops; honestly-documented caveat: enforcement uses *recorded* spend, in-flight lag possible — harden this, no competitor does it better); **routines/schedules** (cron + webhook + API, concurrency/catch-up; each run = tracked issue + assignee wake); **state durability** (everything in PG + local/S3 file store; reboot-safe); **multi-org + portability** (one deployment, N companies; `companies.sh` export/import with secret scrubbing); **plugins/MCP gateway** (out-of-process workers, capability-gated host services, governed MCP gateway + connected apps); **ops** (pinnable Docker + Tailscale/LAN binds, mobile-ready UI + Agent Chat, OTel/Sentry opt-in). Maturity: 5,334 commits, 2,700+ merged PRs; Memory/Knowledge + Agent Chat 🟡 (closing the gaps a replacement would promise). Thesis: *"If OpenClaw is an employee, Paperclip is the company."*

### 6.2 Alternatives evaluated

**A. OpenRig (`mvschwarz/openrig`, 7.6k★, Apache-2.0, `@openrig/cli` + Node 22/24 + tmux + SQLite + Hono daemon).** Closest cousin. `RigSpec` YAML (pods/members/edges/continuity/culture), `rig up` (tmux + multi-harness + readiness), `rig send/broadcast/chatroom`, `rig grow/shrink/launch`, `rig down --snapshot`, `rig discover/adopt`, seat = stable role/address, snapshot/restore, TUI topology, MCP tools, RigBundle archive. **Fatal gaps: single-host tmux-local.** No PG fleet store (SQLite `~/.openrig`), no org chart, no tickets with locks/blockers, no budgets, no multi-org, no approval board, no routines engine, no manager WebUI (React in maintenance; TUI primary). Permission model = launch flags + native harness rules, explicitly not a sandbox. 112 open issues, single-maintainer bus factor. "OpenCode-Rig" = re-building tickets/budgets/governance/PG/WebUI from zero.

**B. Temporal.io / Cadence — durable substrate, not orchestrator.** Event-sourced history + replay; worker crash → replay reconstructs state; MCP-ized primitives give retries + audit replay. Limits: 51k events/50MB history, 2MB payload; self-host needs tuned PG/Cassandra + shards + cache tuning. Superb durability primitive, **zero company semantics** (no tickets/org/budgets/approvals/skills/routines UI/adapters/manager UI). Adoption = generic engine + 6-month build bill + second stateful system to operate. Correct use: steal the *idea* (append-only run log + idempotent resume), not the server.

**C. OpenHands (ex-OpenDevin, v1.27.1).** Loop: stateless Agent → Actions → Conversation EventLog → Workspace (local/Docker/remote) → Observation; LiteLLM routing; microagents/skills, stuck detection, VSCode-in-sandbox, Agent Server REST. Best-in-class *coding-agent sandbox*, **wrong layer**: no org chart, budget hard-stops, heartbeat fleet, multi-org. Multi-agent = containers on one host, not per-role XDG-isolated fleet. Evaluate as *execution backend* (like E2B/Daytona/Modal), not replacement.

**D. CrewAI / AutoGen (AG2) / LangGraph — Python frameworks.** LangGraph (StateGraph + checkpointing + DeltaChannel, per-node timeouts/fallbacks, HITL interrupts, LangSmith; ~62% complex-task benches, v1.0) is the production winner; CrewAI (role-based Crews + `@start/@listen/@router` Flows; 2–3 days to demo, ~54%, fragile delegation) is the closest fleet analog; AutoGen/AG2 (60k★ legacy, now maintenance-mode) is do-not-start-new. All are *libraries for one team's logic*, not deployable products (no server/PG/WebUI/heartbeat/budgets/RBAC/routines/mobile). Heretek would still need to build Paperclip around them. LangGraph + LangSmith defensible *inside* a custom daemon or single specialist role only.

**E. Custom minimalist event daemon (Go/TS + SQLite/NATS + git worktrees + CLI + TUI).** Appealing: single binary, NATS `task.claimed/completed/agent.heartbeat`, SQLite event log, worktree-per-run, `heretek up/ps/send/down`, TUI dashboard. Honest cost: re-implementing Paperclip's 12 subsystems = **6–12 eng-months minimum before parity** + perpetual maintenance, SQLite→PG migration, NATS ops, worktree GC, TUI polish, audit/compliance — all already maintained by Paperclip's team. Justified only if Paperclip goes unpatchable or commercially hostile — neither true (MIT, self-hosted, no account, Docker-supported, active). Tracked contingency only.

### 6.3 Comparison matrix (1–5; 5 = best)

| Criterion | Paperclip | OpenRig | Temporal/Cadence | OpenHands | CrewAI/AutoGen/LangGraph | Custom Daemon |
|---|---|---|---|---|---|---|
| Autonomy throughput (50-role, unattended) | **5** | 3 | 3 | 3 | 3 | 2 |
| Event-driven IPC | **5** | 4 | 5 | 3 | 3 | 4 |
| State durability | **5** | 3 | **5** | 4 | 3 | 3 |
| Budget/policy enforcement | **5** | 1 | 1 | 1 | 1 | 1 |
| Web UI (manager/phone) | **5** | 2 | 2 | 3 | 1 | 1 |
| Maturity | **5** | 3 | 5 | 4 | 4 | 1 |
| Self-host cost (low = 5) | **5** | 4 | 2 | 3 | 4 | 2 |
| Heretek fit (OpenCode v2, 50 roles, shim, PoLP) | **5** | 3 | 2 | 2 | 2 | 3 |
| **Total /40** | **38** | **23** | **21** | **23** | **19** | **17** |

### 6.4 Unequivocal recommendation + migration blueprint (Stay + Harden)

**STAY WITH PAPERCLIP. Patch the adapter. Do not migrate. Do not build.** Borrow, don't switch: OpenRig seat/RigSpec vocabulary as *naming + codegen* (generate `rig.yaml` views from `roles-catalog/`); Temporal idempotency/replay *pattern* (append-only `run_events` + resume tokens); LangGraph *inside* one role if ever needed; OpenHands/E2B as sandbox *backend* via Paperclip's sandbox-provider hook.

- **Phase 0 — Pin + verify (days, zero risk).** `docker/Dockerfile`: pin `paperclip@<exact>` + `@opencode/cli@2.0.32` + `@opencode/client@2.0.32`; `docker-compose.yml`: pin `postgres:17-alpine` digest; `make test` + `test-shim.sh` (39 asserts) + `smoke-test.sh --check-only` green pre/post every change.
- **Phase 1 — Adapter hardening (1–2 wks).** `opencode-shim.sh`: keep intercepting `opencode run` (strip `--dir` → `cwd`, fold `--variant` → `--model provider/model#variant`, inject `--auto`, passthrough `--session`/stdio); add `--dry-run` argv echo + `--help`; `shellcheck` clean; log resolved model + session id for budget attribution. `roles/*/opencode/opencode.json`: keep single-dialect `shell`-allows ending in deny; enforce `OPENCODE_DISABLE_PROJECT_CONFIG=true` + `XDG_CONFIG_HOME=/roles/<id>` via `adapterConfig.env` + smoke check failing closed if missing. `seed-50-fleet.sh`: `--dry-run` diff vs `roles-catalog/*.md` + live PG; fail on count ≠ 50 or `bash`-dialect remnants.
- **Phase 2 — Durability + budget without Temporal (2–4 wks).** PG: add `run_events (id, run_id, seq, type, payload JSONB, ts)` append-only + `runs (id, issue_id, agent_id, status, resume_token, attempt)`; heartbeat writes `claimed/started/progress/completed/failed` in same txn → crash resume = `SELECT … WHERE status IN ('claimed','started')` + idempotent retry with `resume_token`. Budgets: keep recorded-spend enforcer; add pre-claim guard (`SELECT sum(cost) … FOR UPDATE` + in-memory in-flight ledger in heartbeat worker) to close in-flight lag; threshold webhooks to alerts channel; `make backup/restore` cron + monthly staging-restore test. Governance: encode Track 3 approval gates as Paperclip execution policies; keep MCP shell denies + true read-only PG GRANTs / read-only kube ClusterRole.
- **Phase 3 — OpenRig-inspired ergonomics without leaving Paperclip (2 wks, optional).** Codegen `rig.yaml` *views* from `roles-catalog/` (`scripts/generate-rigspec.py`: pods = departments, seats = roles, edges = reporting, culture = `AGENTS.md`); read-only projection, PG remains source of truth. Seat addressing (`role@department`) as display alias. `herdr|cmux` attach for live tmux debug only.
- **Phase 4 — Contingency trigger (tracked, not staffed).** Build Go/TS + NATS + PG daemon only if: Paperclip archived >6mo, license leaves MIT, or OpenCode adapter unshimmable across two majors. Reuse Phase 2 schema + Phase 1 role JSONs as seed.
- **Risks:** shim drift on OpenCode v3 → pin + contract test on `run --help`; budget-lag overspend → Phase 2 pre-claim guard; prefix-bypass → allows-as-hints + resource-layer GRANTs; MCP bypass → per-namespace MCP deny tails once runtime publishes tool-name contract; single-PG fate-sharing → timestamped dumps + tested restore.

---

## 7. Track 6 — Architecture Translation (`shanraisshan/claude-code-best-practice`)

**Source:** `shanraisshan/claude-code-best-practice` (~67.7k★, commit `fe29cd1`, Oct 17 2026), shallow-cloned to `/tmp/opencode/claude-code-best-practice`. Repo is a *reference implementation*: `CLAUDE.md` + `.claude/` + `best-practice/` + `implementation/` + `orchestration-workflow/` + `reports/` + `agent-teams/`. Grounded against `appsec-engineer` (agent md, `AGENTS.md`, `opencode.json`, skills `owasp-reachability-triage`/`security-audit`/`code-review`).

### 7.1 Actual contents (verified via `find .claude -type f`)

No naive agents/commands/skills triad — real inventory: **Agents (6):** `weather-agent`, `time-agent-pkt`, `development-workflows-research-agent`, `presentation-claude-code`, `presentation-claude-gemini`, `presentation-vibe-coding`. **Commands (2):** `weather-orchestrator`, `time-command` (+ team twin `time-orchestrator.md`). **Skills (8):** `weather-fetcher`, `weather-svg-creator` (+`reference.md`/`examples.md`), `time-skill`, `agent-browser`, `presentation/{vibe-to-agentic-framework, presentation-structure, presentation-styling}`. **Hooks:** `.claude/hooks/scripts/hooks.py` (single Python dispatcher, ~33 events: `PreToolUse…Stop/SubagentStart/SubagentStop/PreCompact/PostCompact/SessionStart/SessionEnd/Setup/PermissionRequest/PermissionDenied/TeammateIdle/TaskCreated/TaskCompleted/ConfigChange/CwdChanged/DirectoryAdded/FileChanged/WorktreeCreate/WorktreeRemove/Elicitation…`), `config/hooks-config.json` (+ `.local.json` override) with per-event `disable*` flags + 33 sound folders, wired in `.claude/settings.json`. **Memory:** root `CLAUDE.md` (~120 lines, under the repo's own ≤200-line rule) + `.claude/rules/presentation.md` + `.claude/rules/markdown-docs.md` (both `paths:` frontmatter = lazy-load) + `best-practice/claude-memory.md` (ancestor-UP vs descendant-DOWN/lazy vs sibling-never) + `reports/claude-agent-memory.md` (`memory: user|project|local`). **Orchestration demo:** `orchestration-workflow/orchestration-workflow.md` — **Command → Agent (preloaded skill) → Skill**: `/weather-orchestrator` (model `haiku`) asks C/F via `AskUserQuestion`, calls `Agent(subagent_type="weather-agent")`, then `Skill(skill="weather-svg-creator")`. `weather-agent` (model `sonnet`, tools `Read,Skill`, `maxTurns: 5`, `memory: project`) preloads `weather-fetcher` (`user-invocable: false`, `allowed-tools: WebFetch(*)`). `agent-teams/agent-teams-prompt.md` = 3-teammate parallel variant agreeing on `{time, timezone, formatted}` data contract via shared task list. **Frontmatter taxonomies** (`best-practice/claude-subagents|commands|skills.md`, v2.1.300): 16 subagent / 20 command / 20 skill fields — incl. `effort`, `isolation: worktree`, `context: fork` + `agent` + `background`, `initialPrompt`, `when_to_use`, `paths`, `metadata/license/compatibility`, per-scope `hooks`.

### 7.2 Claude Code → OpenCode v2 mapping (1:1)

OpenCode equivalents verified against Heretek (`roles/*/opencode/opencode.json`: `$schema, model, permissions, skills, plugins, mcp`; agents at `.opencode/agents/<role>.md` with bare `name/description`; skills at `.opencode/skills/<name>/SKILL.md`):

| Claude Code path | OpenCode v2 equivalent | Heretek action |
|---|---|---|
| `.claude/agents/*.md` (16-field frontmatter) | `roles/<id>/.opencode/agents/<id>.md` + fleet `opencode.json` (`model`, `permissions`, `mcp`) | Port allowed fields; move the rest. `name/description/model` direct. `tools/allowedTools` → `permissions[]` allows; `disallowedTools` → explicit `deny` tail (already enforced). `skills:` → `skills[]`. `maxTurns` → Paperclip adapter. `memory: project` → `opencode-mem` + `codebase-memory-mcp`. `isolation: worktree` → `opencode worktree_*`/shim `--dir`. `color/background/effort/permissionMode` → drop or Paperclip metadata. Never copy `Bash(*)` allowlists — translate to least-privilege `shell` prefixes |
| `.claude/commands/*.md` (`/weather-orchestrator`) | OpenCode custom command (`.opencode/commands/*.md`) or Paperclip ticket template | Port almost verbatim: keep **Execution Contract / fail-closed guardrail** ("forbidden from fetching yourself; if Agent unavailable, stop"). `AskUserQuestion/Agent/Skill` → `question`/subagent-spawn/skill-invoke. `model: haiku` → cheap pin per command. Add step 0 (restate ticket + acceptance) + final step (verification evidence + handoff) |
| `.claude/skills/*/SKILL.md` (preloaded vs directly-invoked) | `.opencode/skills/*/SKILL.md` (already this layout) | Adopt both patterns: `user-invocable: false` → internal procedures (e.g. `owasp-reachability-triage`); invocable → analyst skills. Adopt 3-file shape (`SKILL.md` + `reference.md` templates + `examples.md` I/O pairs) — Heretek skills today are single-file checklists. Copy `when_to_use/argument-hint/paths/allowed-tools` into `description` + frontmatter |
| `.claude/hooks/` + `settings.json: hooks` | OpenCode events/hooks + `scripts/*.sh` | Port dispatcher pattern: one script, per-event config with `disable*` flags, `*.local.json` override. Map `PreToolUse/PostToolUse/Stop/SubagentStart/SubagentStop/SessionStart/SessionEnd/PreCompact` to OpenCode equivalents; keep `disableAllHooks` hatch. Sound hooks → log/audit hooks headless |
| `CLAUDE.md` (+ ancestor/descendant rules) | `AGENTS.md` (+ root + per-role) | Direct port of memory doctrine: root = fleet invariants (zero-stub, fail-closed, PoLP, pinned versions); `roles/<id>/AGENTS.md` = role charter (§1–10 incl. per-ticket sequence); skills = lazy-loaded procedure. Enforce ≤200 lines per memory file |
| `.mcp.json` + `settings.json: permissions.allow/ask/deny` | `opencode.json: {mcp, permissions[]}` | `playwright/context7/deepwiki` → per-role MCP (`semgrep`, `codebase-memory-mcp`, pinned). `allow` → `allow`; `ask` (`rm/npm/docker/kubectl…`) → omit (= denied by tail) or explicit `deny`; empty `deny: []` (repo) → **invert**: every Heretek file must end in deny-all |
| `agent-teams/` parallel build | Paperclip multi-role assignment / `tpm-scrum-lead` fan-out | Reuse data-contract pattern: teammates agree on `{time,timezone,formatted}` → Heretek roles agree on advisory schema (`SEC-<id>.md`: finding, reachability, CVSS, patch) before parallel SAST/SCA/triage |
| `reports/*`, `tips/*`, `implementation/*`, RPI/cross-model workflows | `roles-catalog/`, `NOTES.md`, `SUPPORTING_SERVICES.md`, per-role skills | `Research→Plan→Execute→Review→Ship` + human-gated task lists → `AGENTS.md` §7 mandatory sequence + §9 quality gates |

### 7.3 Subagent prompt uplift — can it improve the 50 role prompts? Yes

**Before (current `appsec-engineer.md`, ~25 lines):** identity + 4 strict rules + 4-step methodology/handoff + runtime binding. No frontmatter triggers, no tool contract, no fail-closed delegation guard, no output schema, no self-check.
**After (ported pattern — apply fleet-wide):**

```md
---
name: appsec-engineer
description: PROACTIVELY use for SAST triage, OWASP Top-10 review, SCA reachability, crypto audits. Use when a PR touches auth, crypto, input handling, or dependencies.
model: anthropic/claude-sonnet-4-5
color: red
maxTurns: 30
skills:
  - owasp-reachability-triage   # preloaded: procedure, NOT optional reference
tools:
  - Read
  - Skill
  - semgrep_*
  - codebase-memory_*
permissionMode: default
memory: project
---
# Application Security Engineer
You are the AppSec Engineer (role 39/50). Tone: vigilant, evidence-demanding, risk-calibrated.
## Execution contract (non-negotiable)
You MUST complete every ticket by running `.opencode/skills/owasp-reachability-triage/SKILL.md` step by step. You are forbidden from: asserting exploitability without a `trace_path` call-graph; writing outside `docs/security/advisories/**`; skipping verification (`semgrep scan*`, `trivy fs*`, `git status*` all exit 0). If a tool is denied, stop and hand off — do not work around the denial.
## Workflow — Ingest → Trace → Score → Advise → Hand off
1. Restate ticket objective + acceptance criteria. 2. Scan. 3. Trace reachability (CONFIRMED vs LOW/MITIGATED). 4. CVSS 3.1. 5. Write `SEC-<id>.md` (finding/reachability/CVSS/patch). 6. Report to `system-architect`, assign fix via `tpm-scrum-lead`, block `release-qa-officer` on High/Critical.
## Output schema … ## Self-check … (no TODOs/dummies/swallowed errors; fail closed)
```

Borrowed mechanics: `PROACTIVELY` trigger + `skills:` preload, Execution Contract/fail-closed guard, `maxTurns/memory/color` bounding, scope isolation ("ONLY edits X, never Y").

**Heretek actions (Track 6):** (1) Frontmatter upgrade (50 roles): `PROACTIVELY` descriptions, `skills:`, `maxTurns`, `memory: project`, narrow `tools:`. (2) Skill split: single-file → `SKILL.md` + `reference.md` + `examples.md`. (3) Command layer: `.opencode/commands/<workflow>.md` orchestrators (e.g. `/security-sweep`) reusing the weather-orchestrator contract. (4) Hooks port: `scripts/fleet-hooks.sh` + per-role hook config with `disable*` flags + `.local` override. (5) Memory hygiene: ≤200-line charters + lazy-loaded skills; root `AGENTS.md` only always-loaded file.

---

## 8. Track 7 — Cyber Defense Skills & New Security Roles (`mukul975/Anthropic-Cybersecurity-Skills`)

**Source:** https://github.com/mukul975/Anthropic-Cybersecurity-Skills — verified via webfetch + sparse clone to `/tmp/opencode/cyber-skills` (818 skill dirs, `ls skills | wc -l`; 39 MB tree, 9.1 MB `.git`). README badge claims 818; About box says "817" (stale copy, trust 818). **License: Apache-2.0 at root AND `license: Apache-2.0` in all 818 SKILL.md frontmatters** (`grep -h "^license:" | uniq -c` = 818×). Commercially injectable, attribution required. Upstream: 34.6k★, 4.2k forks, `.claude-plugin` + `npx skills add` distribution.

### 8.1 Domain coverage (actual vs README)

README advertises "34/29 domains" (inconsistent copy). Ground truth from `grep -h "^subdomain:" skills/*/SKILL.md`: **46 distinct `subdomain:` values** (near-duplicate labels). Heavy hitters:

| # | Subdomain | n | # | Subdomain | n |
|---|---|---|---|---|---|
| 1 | cloud-security | 66 | 12 | security-operations | 28 |
| 2 | threat-hunting | 58 | 13 | ot-ics-security | 28 |
| 3 | threat-intelligence | 52 | 14 | api-security | 28 |
| 4 | network-security | 43 | 15 | incident-response | 26 |
| 5 | web-application-security | 42 | 16 | vulnerability-management | 25 |
| 6 | digital-forensics | 41 | 17 | penetration-testing | 21 |
| 7 | malware-analysis | 39 | 18 | devsecops | 18 |
| 8 | identity-access-management | 37 | 19 | zero-trust-architecture | 17 |
| 9 | soc-operations | 35 | 20 | endpoint-security | 17 |
| 10 | red-teaming | 33 | 21 | cryptography | 16 |
| 11 | container-security | 33 | 22 | phishing-defense | 15 |

Long tail: ai-security 14, ransomware-defense 13, mobile-security 13, compliance-governance 10, supply-chain-security 8, threat-detection 7, deception-technology 6, hardware-firmware-security **4**, application-security 4, wireless 2–3, blockchain 2. Duplicates inflating 34→46: `red-team` (2) vs `red-teaming` (33), `firmware-security`/`firmware-analysis`/`hardware-firmware-security`, `identity-and-access-management` (2) vs `identity-access-management` (37), `ot-security` (1) vs `ot-ics-security` (28). **Normalize to one canonical list on ingest; treat 46 as ~34 real domains.** Framework mappings: ATT&CK **805/818**, NIST CSF 2.0 **804/818**, D3FEND 139, AI RMF 97, F3 (Fight Fraud v1.1, Apr 2026) 94, ATLAS 93. `mappings/` has `attack-navigator-layer.json` (Navigator v4.5, ATT&CK Enterprise v14 — lags README's v19.1 claim; re-validate technique IDs on ingest), `mitre-attack/`, `nist-csf/`, `owasp/`. ATT&CK tactic coverage strongest in Initial Access (467), PrivEsc (464), Persistence (444), Stealth (442) — **offense-heavy**, matters for PoLP scoping.

### 8.2 Skill format (Heretek-compatible)

Per skill: `skills/<kebab-name>/SKILL.md + SKILL.es.md + LICENSE + references/ + scripts/ (+ assets/)`. Frontmatter: `name` (kebab ≤64ch), `description` (keyword-rich), `domain: cybersecurity`, `subdomain:`, `tags: [...]`, `version`, `author: mahipal`, `license: Apache-2.0`, plus selective `nist_csf`, `mitre_attack`, `atlas_techniques`, `d3fend_techniques`, `nist_ai_rmf`, `mitre_f3`. Body: `## When to Use / Prerequisites / Workflow / Verification` (canonical; red-team adds Objectives/ATT&CK/Tools/Detection+OPSEC/Validation; compliance uses Key Concepts/Tools/Scenarios/Output). Runner must tolerate optional sections; enforce only When-to-Use + Workflow + Verification. **Cost:** ~30 tokens frontmatter scan, 500–2,000 full load; 818 × 30 ≈ 25k tokens/full pass; per-role injection 10–25 skills keeps dirs lean. **Injection mechanics (local ground truth):** `opencode.json` declares `"skills": ["/roles/<id>/skills"]` but files live at `roles/<id>/.opencode/skills/<skill>/SKILL.md` (verified `appsec-engineer/.opencode/skills/{code-review, owasp-reachability-triage, security-audit}`) — vendor upstream skills into `.opencode/skills/<name>/SKILL.md` verbatim (keep LICENSE + frontmatter), add `references/` + `scripts/agent.py` helpers only where shell allowlist permits, list in `AGENTS.md` §5. No schema change. Skills are data, not packages — satisfies no-`:latest` rule.

### 8.3 Per-role injection tables (6 existing roles)

Convention: upstream `skills/<name>/SKILL.md` → `roles/<role>/.opencode/skills/<name>/SKILL.md`. 10–20 skills/role. Offensive (red-team/pentest) skills go **only** to `sabotage-qa-tester` + proposed AI Red-Teamer, never defensive auditors (PoLP + RoE).

**`appsec-engineer`** (has `owasp-reachability-triage`; tools `semgrep scan*`, `trivy fs*`): Web AppSec 42 (`exploiting-insecure-deserialization`, `exploiting-jwt-algorithm-confusion-attack`, `implementing-jwt-signing-and-verification`, `integrating-dast-with-owasp-zap-in-pipeline`); API Security 28 (`conducting-api-security-testing`, `performing-api-fuzzing-with-restler`, `implementing-api-schema-validation-security`, `detecting-shadow-api-endpoints`, `performing-api-rate-limiting-bypass`, `testing-websocket-api-security`); Supply-chain 8 (`detecting-typosquatting-packages`, `detecting-typosquatting-packages-in-npm-pypi`, `analyzing-supply-chain-malware-artifacts`, `generating-and-analyzing-sboms`); Crypto 16 (`migrating-to-post-quantum-cryptography`, TLS ×6, `configuring-hsm-for-key-storage`). Uplift: SAST-only → auth/session/deserialization + API-first + malicious-package detection; fills zero-crypto gap.

**`threat-modeler`** (has `stride-threat-modeling`; no shell — evidence-review only): second `threat-model` skill + `analyzing-cyber-kill-chain`, `analyzing-apt-group-with-mitre-navigator`, `mapping-attack-paths-with-bloodhound-ce`; `emulating-cloud-attacks-with-stratus-red-team` (read plan, don't execute), `auditing-kubernetes-rbac-privilege-escalation`; `auditing-mcp-servers-for-tool-poisoning`, `securing-agentic-ai-tool-invocation` (covers MCP tool-poisoning — #1 threat to Heretek's own fleet; evidence-review compatible). Uplift: STRIDE-only → STRIDE + kill-chain + ATT&CK Navigator + attack-path + cloud/K8s + AI attack surface.

**`cloud-sec-auditor`** (has `iam-least-privilege-audit`; `checkov -d*`, `tfsec*`, `gitleaks detect*`; `aws_run*` denied, read-only creds): Cloud 66 (`auditing-aws-s3-bucket-permissions`, `auditing-azure-active-directory-configuration`, `auditing-gcp-iam-permissions`, `auditing-cloud-with-cis-benchmarks`, `detecting-aws-cloudtrail-anomalies`, `detecting-aws-guardduty-findings-automation`, `analyzing-azure-activity-logs-for-threats`, `detecting-s3-data-exfiltration-attempts`); IAM 37+ (`detecting-aws-iam-privilege-escalation`, `performing-aws-privilege-escalation-assessment`, `building-identity-federation-with-saml-azure-ad`, Entra ×5); Secrets (`detecting-aws-credential-exposure-with-trufflehog`, `detecting-compromised-cloud-credentials`, `analyzing-cloud-storage-access-patterns`). Uplift: AWS-only → multi-cloud + CIS pass/fail bar + escalation assessment + runtime compromise detection.

**`firmware-sec-analyst`** (has `firmware-extraction-and-hardening-audit`; `readelf/objdump/checksec/binwalk`): ~9 of ~11 HW skills (`performing-firmware-extraction-with-binwalk`, `performing-firmware-malware-analysis`, `auditing-uefi-firmware-with-chipsec`, `analyzing-uefi-bootkit-persistence`, `detecting-secure-boot-bypass`, `validating-tpm-measured-boot-attestation`, `analyzing-bootkit-and-rootkit-samples`, `hunting-bootkits-in-efi-system-partition`, `performing-plc-firmware-security-analysis`); ELF crossover (`analyzing-linux-elf-malware` — static+dynamic, x86_64+ARM, container-targeted; `analyzing-linux-kernel-rootkits`). Uplift: fills UEFI/TPM/secure-boot gaps + embedded-Linux/ARM IoT coverage.

**`binary-reverse-eng`** (has r2 + REA skills; `r2`, `rabin2`, `strings`, `tshark`; REA 120+ tools via `@morluto/rea-mcp`): Malware RE 39 (`analyzing-linux-elf-malware`, `analyzing-golang-malware-with-ghidra`, `analyzing-macro-malware-in-office-documents`, `analyzing-malicious-pdf-with-peepdf`, `analyzing-heap-spray-exploitation`, `analyzing-malware-sandbox-evasion-techniques`, `analyzing-malware-persistence-with-autoruns`, `analyzing-cobalt-strike-beacon-configuration`, `analyzing-command-and-control-communication`); Mobile (`analyzing-android-malware-with-apktool`, `analyzing-ios-app-security-with-objection`); Memory forensics (`performing-memory-forensics-with-volatility3` ×5, `analyzing-network-traffic-of-malware`). Uplift: protocol-RE → full malware triage bench + mobile + PCAP/memory correlation.

**`sabotage-qa-tester`** (has `adversarial-mutation-sabotage`; piston sandbox only — **sole role cleared for offensive skills**): `performing-purple-team-atomic-testing`, `performing-purple-team-exercise`; C2 emulation (`building-red-team-c2-infrastructure-with-havoc`/`operating-havoc-c2`, `building-c2-infrastructure-with-sliver-framework`/`operating-sliver-c2`, `hunting-for-cobalt-strike-beacons`, `analyzing-cobaltstrike-malleable-c2-profiles` — constrain to piston/ephemeral lab, document RoE in skill header); Phishing sim (`performing-red-team-phishing-with-gophish`, `conducting-spearphishing-simulation-campaign`, `conducting-social-engineering-penetration-test`); Ransomware/OT tabletop (`performing-ransomware-tabletop-exercise`, `building-soc-playbook-for-ransomware`, `implementing-ot-incident-response-playbook` — cross-feeds proposed Incident Commander).

### 8.4 Proposed NEW elite specialist roles (5)

All follow fleet contract: on-demand wake, `XDG_CONFIG_HOME=/roles/<id>`, `opencode.json` ending `shell * deny`, writes confined to one `docs/` subtree, pinned MCP. Department: new **Offensive & Resilience Operations** carved from `07_defensive_security_and_forensics` (else bloats to 11) — except Fraud Officer (sits with `compliance-auditor`).

**R1. `ai-red-teamer` — Adversarial AI / LLM Red-Team Operator (MISSING, highest priority).** Mission: own 14-skill `ai-security` domain with zero coverage despite 50-agent AI fleet; red-team fleet agents, RAG pipelines (`vector-rag-spec`), shipped LLM features. Bundle (11, all verified): `red-teaming-llms-with-garak`, `orchestrating-llm-attacks-with-pyrit`, `continuous-llm-red-teaming-with-promptfoo`, `detecting-ai-model-prompt-injection-attacks`, `detecting-indirect-prompt-injection`, `testing-prompt-injection-in-rag-pipelines`, `testing-for-system-prompt-leakage`, `defending-llms-with-guardrails`, `implementing-llm-guardrails-for-security`, `auditing-mcp-servers-for-tool-poisoning`, `securing-agentic-ai-tool-invocation` (+ ATLAS 93 + AI RMF 97 mappings). Config: `fs:write docs/security/ai-redteam/**`; `shell`: `garak*`, `pyrit*`, `promptfoo*`, `git status*` + deny tail; MCP `codebase-memory-mcp@0.12.1` only; model Sonnet-4-5. Metrics: injection-suite pass rate per skill change; leaked prompts 0/quarter; bypass rate down; ATLAS coverage/release.

**R2. `incident-commander` — DFIR / Breach Response Commander (MISSING).** Mission: own `incident-response` (26) + `digital-forensics` (41) + `soc-operations` (35) orchestration — containment, timelines, comms (auditors exist; nobody runs a breach). Bundle (14): `containing-active-breach`, `building-incident-response-playbook`, `building-soc-escalation-matrix`, `building-soc-metrics-and-kpi-tracking`, `conducting-cloud-incident-response`, `conducting-malware-incident-response`, `conducting-phishing-incident-response`, `building-detection-rules-with-sigma`, `building-super-timelines-with-plaso`, `performing-timeline-reconstruction-with-plaso`, `generating-forensic-timelines-with-hayabusa`, `performing-memory-forensics-with-volatility3`, `analyzing-disk-image-with-autopsy`, `performing-soc-tabletop-exercise`. Config: `fs:write docs/security/incident/**`; `shell`: `plaso*`, `hayabusa*`, `volatility*`, `git status*` + deny. Metrics: quarterly tabletops; MTTR on sims; timeline completeness; playbook ATT&CK coverage ≥12/15.

**R3. `cloud-iam-forensic-auditor` — Cloud IAM Forensic / Blast-Radius Auditor (split from `cloud-sec-auditor`).** Mission: old role does static IaC posture; new role does **runtime** forensics (stolen keys, lateral movement, exfiltration). Bundle (12): `detecting-aws-iam-privilege-escalation`, `detecting-azure-lateral-movement`, `detecting-azure-service-principal-abuse`, `detecting-compromised-cloud-credentials`, `detecting-cloud-threats-with-guardduty`, `detecting-cryptomining-in-cloud`, `analyzing-cloud-storage-access-patterns`, `analyzing-azure-activity-logs-for-threats`, `analyzing-kubernetes-audit-logs`, `auditing-kubernetes-rbac-privilege-escalation`, `detecting-container-escape` (defensive use), `building-cloud-siem-with-sentinel`. Config: mirror `cloud-sec-auditor` (read-only `aws-mcp@1.0.2`, `aws_list*/aws_select*` allow, `aws_run*/aws_*` deny) + `fs:write docs/security/cloud-forensics/**` + `kubectl auth can-i*`/`get*` read-only. Metrics: escalation paths/account; MTTD on key-compromise sims; GuardDuty closure rate.

**R4. `fraud-abuse-officer` — Cyber-Fraud & Abuse Officer (MISSING; F3 is 2026-new).** Mission: own MITRE F3 (94 fraud skills) + `phishing-defense` (15) + `deception` (6) — BEC, APP fraud, mule layering, honeytokens (zero coverage today). Bundle (12): `detecting-business-email-compromise`, `analyzing-email-headers-for-phishing-investigation`, `implementing-soar-playbook-for-phishing`, `building-phishing-reporting-button-workflow`, F3-mapped fraud skills (filter `mitre_f3:` frontmatter, ~94), `implementing-honeytokens-for-breach-detection`, `deploying-cloud-deception-with-decoy-resources`, `detecting-qr-code-phishing-with-email-security`. Config: `fs:write docs/security/fraud/**`; evidence-review like `threat-modeler` (minimal shell) + deny. Metrics: BEC sim catch rate; honeytoken trips/quarter; F3 coverage map; report-to-triage SLA.

**R5. `supply-chain-crypto-steward` — Supply-Chain & Cryptography Steward (force-multiplier).** Mission: fuse thinnest defensive domains — supply-chain (8) + crypto (16) + SBOM — homeless between `compliance-auditor` and `appsec-engineer`. Bundle (10–12): `generating-and-analyzing-sboms`, `analyzing-sbom-for-supply-chain-vulnerabilities`, `detecting-supply-chain-attacks-in-ci-cd`, `detecting-typosquatting-packages-in-npm-pypi`, `hunting-for-supply-chain-compromise`, `implementing-sigstore-for-software-signing`, `implementing-supply-chain-security-with-in-toto`, `migrating-to-post-quantum-cryptography`, `implementing-api-key-security-controls`, `configuring-hsm-for-key-storage` (+ TLS skills). Config: `fs:write docs/compliance/supply-chain/** + sbom/**`; `shell`: `syft*`, `cosign*`, `openssl*`, `git status*` + deny. Metrics: SBOM freshness; Sigstore coverage →100%; PQC inventory complete; typosquat feed in CI.

**Cross-cutting risks:** offensive-skill containment (~200+ dual-use: DPAPI/Mimikatz/Kerberoasting/C2) — inject red-team-labeled skills **only** into `sabotage-qa-tester` + `ai-red-teamer`, retain upstream Legal Notice header; all others get `detecting-*`/`hunting-*`/`containing-*` variants; add `smoke-test.sh` assertion (no `skills/red-teaming/*` outside those two). Subdomain normalization required (46→~34). ATT&CK version skew (README v19.1 vs Navigator layer v14 — re-validate with `mitreattack-python`). Effort: ~0.5d/role for 6 injections; 1–2d each for R1–R5; R1 first, then R2, R4.

---

## 9. The 30-Day Heretek-Crew Evolutionary Roadmap

### Phase A — Immediate (Days 1–7): stop the bleeding, bank the cheap wins

| Day | Action | Owner role(s) | Done when |
|---|---|---|---|
| 1 | Pin + verify (Phase 0 §6.4): Dockerfile pins, PG digest, `make test` (39/39) + `smoke-test.sh --check-only` green | `system-architect`, `sre-incident-eng` | Green baseline committed |
| 1–2 | Fix `skills` path discrepancy (§10.5): verify what `prepareOpenCodeRuntimeConfig` honors; align `opencode.json` `skills` or file locations | `system-architect` | Conformance test proves skills load |
| 2–3 | Config hardening P0 (§5): add `small_model: haiku` routing, per-agent `steps`/iteration cap + `doom_loop` guard, MCP `timeout: 5000`, `compaction.prune`, explicit `*.env` deny (or documented mount guarantee) | `system-architect` + Paperclip adapter owner | Grep proves 0 roles missing guards; cost dashboard shows title/summary on haiku |
| 2–4 | Vendor Superpowers TDD + systematic-debugging to all implementer roles; brainstorming/writing-plans to `product-director`/`system-architect` (§3.2) | `product-director`, `system-architect` | `smoke-test.sh` asserts `SKILL.md` frontmatter; per-ticket workflow lines added |
| 3–4 | Role prompt frontmatter uplift pilot (5 roles: `appsec-engineer`, `system-architect`, `python-backend-spec`, `tpm-scrum-lead`, `exec-director`) per §7.3 template | `system-architect` | Before/after review shows triggers + contracts + schemas |
| 4–5 | Port Track 1 quick wins: `security-sweep` → `appsec-engineer`; `test-writer-fixer` → QA roles; `AgentLint` fleet audit; `connect-apps` gated remote MCP for 3 director roles | `appsec-engineer`, `release-qa-officer`, `exec-director` | Skills copied, permissions allow-listed, deny tails intact, smoke green |
| 5–7 | Add `ecc-agentshield@1.6.0` CI gate (`agentshield scan --path roles/<id>`) + `spec-gate.sh` skeleton (Spec-Kit `constitution.md` + OpenSpec `changes/<id>/`) | `static-analysis-lead`, `system-architect` | New `smoke-test.sh` sections fail on secrets/over-broad allows/missing specs |
| 7 | `.env` read-path audit (§5 T6) + offensive-skill containment assertion (no `red-teaming/*` outside 2 roles) | `dba-specialist`, `k8s-orchestrator`, `sabotage-qa-tester` | Audit doc committed; smoke assertions green |

### Phase B — Medium-Term (Days 8–20): structural capability

| Days | Action | Owner | Done when |
|---|---|---|---|
| 8–11 | Code-intel sidecar: `codebase-memory-mcp` (`devsec` profile, `:ro` mounts + data volume) + `serena` scoped to programmer/refactorer + `code-review-graph` in QA pipeline; benchmark context-reduction before `core` promotion | `system-architect`, `static-analysis-lead` | `resolve_symbol`/`call_graph` live via MCP; benchmark shows 70%+ token cut on sample tasks |
| 10–13 | Memory plane: Cognee sidecar (`COGNEE_VECTOR_DB=qdrant:6333`, `COGNEE_GRAPH_DB=bolt://neo4j:7687`) + MCP wrapper + nightly `memory-decay.sh`; Mem0 OSS pilot on one role; LOCOMO-style recall eval gate | `vector-rag-spec`, `dba-specialist` | Roles read/write memories via MCP; eval picks winner; no SaaS egress |
| 12–14 | Cyber injection wave 1: `appsec-engineer`, `threat-modeler`, `cloud-sec-auditor` (10–20 skills each per §8.3) + ATT&CK ID re-validation (`mitreattack-python`, v14→v19.1 renames) | `appsec-engineer`, `threat-modeler`, `cloud-sec-auditor` | Skills vendored verbatim + LICENSE; `AGENTS.md` §5 entries; smoke green |
| 13–15 | Cyber injection wave 2: `firmware-sec-analyst`, `binary-reverse-eng`, `sabotage-qa-tester` (sandbox RoE headers on C2 skills) | same + `sabotage-qa-tester` | Same gates + RoE headers present |
| 14–16 | New roles R1 (`ai-red-teamer`) + R2 (`incident-commander`): charter + `opencode.json` + Paperclip seed + `roles-catalog` entries | `system-architect`, `exec-director` | `ls roles` = 52; seed dry-run diff clean; smoke §3/§3b deny tails pass |
| 15–18 | Command + hooks layer (§7): `.opencode/commands/<workflow>.md` orchestrators (e.g. `/security-sweep`) + `scripts/fleet-hooks.sh` dispatcher with `disable*` flags + `.local` override; 3-file skill split pilot (SKILL + reference + examples) on 3 roles | `system-architect`, `tpm-scrum-lead` | Commands invocable; hooks log audit events headless; skill split reviewed |
| 16–20 | Paperclip Phase 2 (§6.4): `run_events` append-only + `runs` resume tokens; pre-claim budget guard (close in-flight lag); threshold webhooks; monthly staging-restore test | Paperclip/DBA owner + `sre-incident-eng` | Crash-resume demo passes; overspend sim blocked pre-claim; restore test logged |
| 18–20 | SDD enforcement live: `spec-gate.sh` blocking merges without `specs/` deltas; `sync-skills.sh --pin` for `superpowers` + `wshubson/agents` donors | `tpm-scrum-lead`, `system-architect` | CI red on spec-less PR (verified with fixture); skill sync reproducible at SHA |

### Phase C — Long-Term (Days 21–30): new roles, automation, ergonomics

| Days | Action | Owner | Done when |
|---|---|---|---|
| 21–24 | New roles R3 (`cloud-iam-forensic-auditor`), R4 (`fraud-abuse-officer`), R5 (`supply-chain-crypto-steward`): charters + configs + seeds; carve **Offensive & Resilience Operations** department (R4 stays with compliance) | `system-architect`, `exec-director` | `ls roles` = 55; `roles-catalog` + `generate-50-roles.py` successor updated; smoke green |
| 22–25 | Automation sidecars: Windmill (import `backup-db.sh`, `seed-*-fleet.sh --dry-run`, `smoke-test.sh --check-only` as versioned steps) + n8n loopback-only (`127.0.0.1:5678`) for digests/hooks, MCP-gated to `tpm`/`exec-director` | `sre-incident-eng`, `tpm-scrum-lead` | Scripts runnable as audited workflows; no privileged flags; socket-proxy allow-list |
| 24–26 | Web upgrades: `browser-use` self-host core in `web-research` profile; puppeteer → `microsoft/playwright-mcp` at `ws://browserless:3000?stealth=true`; SSRF guard + egress logging | Research roles owner | Agentic retrieval demo (login/pagination → Markdown); MCP swap without regression |
| 25–27 | `rig.yaml` read-only projection (`scripts/generate-rigspec.py`: pods = departments, seats = roles, edges = reporting, culture = `AGENTS.md`); seat aliases (`role@department`) in logs/UI | `system-architect` | Generated views diff-clean vs `roles-catalog/`; PG remains source of truth |
| 27–28 | Memory hygiene enforcement: ≤200-line charters fleet-wide; lazy-load audit (root `AGENTS.md` only always-loaded); `anthropics/skills` spec pin recorded | `tech-docs-lead`, `system-architect` | Linter (AgentLint + line-count) green fleet-wide |
| 28–30 | Full-fleet rehearsal: seed dry-run + smoke + Agentshield + spec-gate + backup/restore staging test + budget pre-claim sim + recall eval (Cognee vs Mem0 decision) + context-reduction benchmark sign-off | `exec-director`, `tpm-scrum-lead`, `sre-incident-eng` | Go/no-go report; decisions + evidence appended to `NOTES.md`; roadmap v2 cut |

**Explicit non-goals (30d):** no Paperclip migration, no Temporal cluster, no `ecc-universal` install, no SaaS memory/search egress, no unpinned `:latest`, no offensive skills outside the 2 cleared roles.

---

## 10. Appendices

### 10.1 Dockerfile lines (pins — adapt to actual `docker/Dockerfile`)

```dockerfile
# Orchestrator + agent runtime — exact pins, never :latest
ARG PAPERCLIP_VERSION=0.9.31
ARG OPENCODE_CLI_VERSION=2.0.32
ARG OPENCODE_CLIENT_VERSION=2.0.32
FROM paperclipai/paperclip:${PAPERCLIP_VERSION} AS paperclip
RUN npm install -g @opencode/cli@${OPENCODE_CLI_VERSION} @opencode/client@${OPENCODE_CLIENT_VERSION} \
 && npm ls -g --depth=0 \
 && opencode --version
# MCP servers pinned at role level (examples — keep in opencode.json, not here):
#   npx -y @modelcontextprotocol/server-postgres@0.6.2
#   npx -y @agntk/codegraph-mcp@0.1.0
#   uvx semgrep==1.97.0 / ruff==0.8.4 (per SUPPORTING_SERVICES.md)
```

`docker-compose.yml`: `postgres:17-alpine` → pin digest (`postgres:17-alpine@sha256:<digest>`); sidecars: `qdrant:v1.12.5`, `neo4j:5.26-community`, `browserless/chromium:v2.24.2`, `cognee:0.x-pinned`, `windmill:…-pinned`, `n8n:…-pinned` — all digest-pinned; loopback binds (`127.0.0.1:3100`, `127.0.0.1:5678`); secrets via `.env` (`.gitignore`d).

### 10.2 `opencode.json` hardening patch (Paperclip dialect — apply per role)

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-5",
  "small_model": "anthropic/claude-haiku-4-5",
  "compaction": { "auto": true, "prune": true, "reserved": 10000 },
  "permissions": [
    { "action": "shell", "resource": "git status*", "effect": "allow" },
    { "action": "shell", "resource": "git diff*", "effect": "allow" },
    { "action": "shell", "resource": "semgrep scan*", "effect": "allow" },
    { "action": "shell", "resource": "npx -y agentlint-ai@1.4.0 check*", "effect": "allow" },
    { "action": "shell", "resource": "*", "effect": "deny" }
  ],
  "mcp": {
    "codegraph": { "type": "local", "command": ["npx", "-y", "@agntk/codegraph-mcp@0.1.0"], "timeout": 5000 },
    "postgres-ro": { "type": "local", "command": ["npx", "-y", "@modelcontextprotocol/server-postgres@0.6.2", "{env:POSTGRES_READONLY_URL}"], "timeout": 5000 }
  },
  "tools": { "postgres_*": false },
  "instructions": ["AGENTS.md"]
}
```
Plus orchestrator-side: `steps`/iteration cap + `doom_loop: ask` equivalent in `prepareOpenCodeRuntimeConfig`/heartbeat worker; `read: {"*.env": "deny"}` semantics or documented mount guarantee (T6); `experimental.policies` provider allowlist if adapter passes it through.

### 10.3 Role → skill mapping master table (new injections only)

| Role | Source pack | Skills (count) | Procedure file target |
|---|---|---|---|
| all implementers (`python-backend-spec`, `ts-node-fullstack`, `go-backend-eng`, `cpp-lowlevel-eng`, `rust-systems-spec`, `java-kotlin-eng`) | Superpowers | `test-driven-development`, `systematic-debugging` (2) | `roles/<id>/.opencode/skills/<name>/SKILL.md` |
| `product-director` | Superpowers | `brainstorming`, `writing-plans` (2) | same |
| `system-architect` | Superpowers + AgentLint + codebase-graph | `writing-plans`, `agentlint-check`, `codegraph-workflow` (3) | same |
| `api-contract-tester`, `e2e-browser-qa`, `release-qa-officer`, `sabotage-qa-tester` | Superpowers + test-writer-fixer | `verification-before-completion`, `requesting-code-review`, `test-writer-fixer` (3) | same |
| `exec-director`, `tpm-scrum-lead` | Superpowers + connect-apps | `dispatching-parallel-agents`, `finishing-a-development-branch`, `connect-apps-use` (3) | same + gated remote MCP |
| `appsec-engineer` | Cyber (web/API/supply/crypto) + security-sweep | ~14 + `security-sweep` | same |
| `threat-modeler` | Cyber (modeling/cloud/AI) | ~8 | same (evidence-review, no shell) |
| `cloud-sec-auditor` | Cyber (cloud/IAM/secrets) | ~14 | same (read-only creds) |
| `firmware-sec-analyst` | Cyber (firmware/ELF) | ~11 | same |
| `binary-reverse-eng` | Cyber (malware/mobile/memory) | ~13 | same (+ REA bridge) |
| `sabotage-qa-tester` | Cyber (purple/C2/phishing/tabletop, sandboxed) | ~10 | same (piston only, RoE headers) |
| `ai-red-teamer` (NEW R1) | Cyber ai-security (11) | §8.4 | new role dir + charter |
| `incident-commander` (NEW R2) | Cyber IR/forensics/SOC (14) | §8.4 | new role dir + charter |
| `cloud-iam-forensic-auditor` (NEW R3) | Cyber cloud-forensics (12) | §8.4 | new role dir + charter |
| `fraud-abuse-officer` (NEW R4) | Cyber F3/phishing/deception (12) | §8.4 | new role dir + charter |
| `supply-chain-crypto-steward` (NEW R5) | Cyber supply-chain/crypto (10–12) | §8.4 | new role dir + charter |

### 10.4 Per-Ticket Workflow addition (paste into each touched `AGENTS.md` §7)

```md
- Execute implementation steps under the vendored procedure skill(s) listed in §5 (e.g. `.opencode/skills/test-driven-development/SKILL.md`); no production code without a watched-fail test. TDD violations are deleted, not adapted.
- For security findings write `SEC-<id>.md` (finding/reachability-trace/CVSS-3.1/patch) under the role's advisory dir; reachability MUST cite a `call_graph`/`trace_path` result; High/Critical blocks `release-qa-officer`.
- If any required tool is denied, stop and hand off via Paperclip assignment — do not work around the denial (fail closed).
```

### 10.5 Known discrepancy to fix first (load-bearing)

`roles/<id>/opencode/opencode.json` declares `"skills": ["/roles/<id>/skills"]` but on-disk skills live at `roles/<id>/.opencode/skills/<skill>/SKILL.md` (verified for `appsec-engineer`, `system-architect`). Before any vendoring wave, confirm which path `prepareOpenCodeRuntimeConfig` actually copies/honors; align config or locations and add a conformance test (skill file exists AND is referenced AND loads in a dry-run session). Otherwise all injected skills silently won't load.

### 10.6 Shell verification log (this synthesis)

- `ls roles | wc -l` = **50**; `ls *.md` confirms prompt + supporting docs present.
- Subagent clones verified: `awesome-claude-plugins` (25 plugin dirs + `marketplace.json`), `ECC` (`.opencode/opencode.json` + `ecc-hooks.ts` + `tools/*.ts` + `install-profiles.json`), `superpowers` (15 skills incl. `test-driven-development`, `subagent-driven-development`), `claude-code-best-practice` (`weather-orchestrator`, `weather-agent`, `hooks.py` ~33 events, `CLAUDE.md` ~120 lines), `Anthropic-Cybersecurity-Skills` (818 skill dirs, 39 MB tree, Apache-2.0 ×818, 46 `subdomain:` values).
- Versions verified 2026-10-17: `ecc-universal@2.2.3`, `ecc-agentshield@1.6.0`, `@opencode/cli@2.0.32`; star counts via GitHub REST `search/repositories` + `repos/:owner/:repo` per-track.
- Hypotheses killed: (a) "awesome-claude-plugins is OpenCode-native" — false, Claude-Code native, content portable; (b) "ecc-agentshield is a sandbox" — false, audit scanner; (c) "Paperclip replaceable by OpenRig/Temporal/OpenHands" — false on company-layer scoring (38 vs ≤23); (d) "Zep Cloud for memory" — rejected on egress; (e) "BMAD/GSD wholesale" — rejected on ceremony/staleness, borrow personas only.

### 10.7 Sources (primary; per-track reports hold full API/diff evidence)

- https://github.com/composio-community/awesome-claude-plugins (+ `connect-apps`, `codebase-graph`, `security-sweep`, `AgentLint`, `backlog`)
- https://github.com/affaan-m/ECC (+ `ecc-universal`, `ecc-agentshield`) · https://github.com/obra/superpowers
- https://github.com/github/spec-kit · https://github.com/Fission-AI/OpenSpec · https://github.com/bmad-code-org/BMAD-METHOD · https://github.com/mem0ai/mem0 · https://github.com/topoteretes/cognee · https://github.com/letta-ai/letta · https://github.com/getzep/zep · https://github.com/DeusData/codebase-memory-mcp · https://github.com/oraios/serena · https://github.com/tirth8205/code-review-graph · https://github.com/firecrawl/firecrawl · https://github.com/browser-use/browser-use · https://github.com/unclecode/crawl4ai · https://github.com/microsoft/playwright-mcp · https://github.com/n8n-io/n8n · https://github.com/temporalio/temporal · https://github.com/windmill-labs/windmill · https://github.com/langchain-ai/langgraph
- https://github.com/shanraisshan/claude-code-best-practice · https://github.com/mukul975/Anthropic-Cybersecurity-Skills · https://github.com/mvschwarz/openrig · https://github.com/paperclipai/paperclip · https://opencode.ai/docs/ (+ config/permissions/models/mcp-servers/agents/skills/policies)
- Local: `AGENTS.md`, `SUPPORTING_SERVICES.md`, `roles-catalog/`, `scripts/opencode-shim.sh`, `scripts/test-shim.sh`, `scripts/smoke-test.sh`, `NOTES.md`, `REMEDIATION_LOG.md`

---

*End of report. Next action: execute Roadmap Phase A Day 1 (pin + verify + skills-path fix) and record evidence in `NOTES.md`.*
