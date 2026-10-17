# Heretek Ecosystem Integration Plan — Sovereign Architecture Blueprint

**Author:** Subagent 6 (Master Synthesis) · **Date:** 2026-10-17 · **Workspace:** `/home/john/Projects/Heretek-Crew`
**Sources:** S1–S5 investigation reports + direct verification reads (see §5).
**Companion repos (all under `references/`):** `agency-control-plane`, `epistemic-factory` (v3.0.0),
`heretek-context-router`, `heretek-devcontainers`. Current production stack: Paperclip + OpenCode v2
(`@opencode/cli@2.0.32`) + PostgreSQL 17 + `scripts/opencode-shim.sh` + `docker-compose.sidecars.yml`.

---

## 1. Comparative Landscape Analysis: Heretek's 4 Companion Repos vs External Tools

### 1.1 Fleet / harness layer (Heretek: agency-control-plane)

| System | Execution model | Merge / queue | Review gate | Verdict for Heretek |
|---|---|---|---|---|
| **agency-control-plane** (`references/agency-control-plane/`) | OpenCode v2 worker servers in isolated git worktrees, one long-lived Director session, pure scheduler DAG (`dispatcher/src/scheduler.ts`), crash-safe 2-phase worktrees + base-pinning + salvage refs (`dispatcher/src/worktrees.ts`), Ed25519 ticket-bound approvals (`dispatcher/src/approval-tickets.ts`, `human-key.ts`), 5-pillar WebUI (`web/`) | `landing.ts` merge barrier (fast-forward only) — **implemented but `landTask()` NEVER CALLED** (S3) | Ed25519 signature from pinned human key required before land; approval routes 503 fail-closed without key | **Adopt as the sovereign orchestrator (Wave 4).** Fix the landing call-site first; it is the single load-bearing gap. |
| Paperclip (current prod) | Persistent agents on shared checkouts, `XDG_CONFIG_HOME=/roles/<id>` isolation, shim-mediated `opencode run` | No merge queue; human merges | Deployment auth + signed tool actions | **Retire after Wave 4.** Keep as the stable production plane during Waves 1–3. |
| Superset (`superset` in S1) | Worktree-per-task + human per-diff review, no queue | None (direct review) | Human per-diff | Borrow the per-diff review discipline; not a queue solution. |
| Gas Town | Bors-style bisecting Refinery merge queue + patrols | Strongest external queue design | Patrol + bisect | **Design reference for the landing barrier** (bisect on red), but the stack is too heavy to adopt wholesale. Do not import Gas Town; port the bisect idea into `landing.ts` later. |
| Symphony | Ticket-daemon intake, per-ticket clones + `bwrap`, OpenCode V2 runner, max ~5 parallel | Daemon intake | Ticket-scoped | Validates the ticket→worktree→runner shape we already have. Concurrency ceiling (~5) matches our `--fleet-cap 4` default; keep 4 until NATS + Postgres evidence supports raising. |
| OpenHands | Container-per-session + EventStream | None (no fleet layer) | None at fleet scope | Reject as orchestrator. Containers-per-session is the wrong primitive for trusted code — worktrees are cheaper and diff-native. Reserve containers for untrusted code (devsec/mobile segments). |
| OMO / Sisyphus plugins | `@oracle` / `@librarian` roles, `work-with-pr` + `smart-rebase` + `worktree-isolation` | Smart-rebase | Role-based | **Immediate tactical borrowing (Wave 3):** copy `smart-rebase` semantics into worker instructions and `worktree-isolation` defaults into `es init` scaffolding. |
| SWE-AF | Semantic merger pattern | Semantic merge | — | Notable only for the semantic-merger idea; park until post-Wave-4. |

**Consensus primitive (S1, verified against `agency-control-plane/dispatcher/src/worktrees.ts` file list):**
one worktree + one branch per writer; containers only for untrusted code.

### 1.2 Gateway / routing / cache layer (Heretek: heretek-context-router + devcontainers core)

| Concern | External reference | Heretek answer | Status |
|---|---|---|---|
| MCP routing + policy | AgentGateway v1.6.0: MCP routing + CEL `mcpAuthorization` + per-target isolation | `heretek-devcontainers/compose/core.yml`: `ghcr.io/agentgateway/agentgateway:v1.6.0` + `nats:2.15.1-alpine`; `heretek-context-router` lazy broker (3 meta-tools `mcp_search_tools` / `mcp_inspect_schema` / `mcp_call_tool`, ~240 tokens vs 262,500 baseline) | **Verified pins match (S2/S5).** AgentGateway CEL is the real boundary; broker gates are cost-control only. |
| LLM gateway + failover | LiteLLM (current prod `docker-compose.sidecars.yml:541-563`, `ghcr.io/berriai/litellm@sha256:eb14f07d…`, tag `main-v1.54.0`) | Bifrost v2.3.0 (`ghcr.io/maximhq/bifrost:v2.3.0` in `compose/core.yml`): virtual keys + budgets + fallbacks map 1:1 from LiteLLM; 3-tier failover; semantic-cache plugin (`cache_tool_call_responses:false`) | **Do NOT cut over on vendor perf claims.** S2 flags 11µs / 50×-vs-LiteLLM as UNVERIFIED — repro with own load test before replacing LiteLLM. Run both behind AgentGateway in Wave 1, shadow-compare, then decide. |
| Secret vault | AgentGateway AES-256 vault | **NOT a verified primitive (S2).** Buy or build separately; do not assume AgentGateway covers vault. Secrets stay in `.env` + `0600` key files until a vault decision lands. | Gap — see risk register R-4. |
| Prompt / prefix caching | Anthropic 5-min/1-h tiers, reads at 0.10×; ordering tools→system→docs→history→query; ProjectDiscovery case 7%→84% hit, −59% cost (S2) | `heretek-context-router/src/prefix-builder`: L1 frozen invariant + L2 shared-context frozen, breakpoints `[B1,B2]`; L1+L2 byte-identical across roles for KV-cache stability; `src/skills` SHA-256 tree hash + lock v3 + `timingSafeEqual` | **Adopt (Wave 2).** Concrete win, no gateway dependency. |
| Memory / vector plane | Qdrant, Neo4j (current sidecars `docker-compose.sidecars.yml:474-536`) | heretek-devcontainers has **no memory-plane equivalent** (S5: qdrant/neo4j dropped with no equivalent) | Gap — see R-5. Keep current Qdrant/Neo4j sidecars until a disposition lands. |

### 1.3 Quality-gate layer (Heretek: epistemic-factory v3.0.0)

| Concern | External reference | Heretek answer | Status |
|---|---|---|---|
| Mutation testing | Stryker (`high:80 low:60 break:null` defaults) | `epistemic-factory` textual mutation engine, threshold **0.85**, CLI `es gate-mutation --dir <dir> --files <csv> -- <testCmd…>` (`packages/cli/src/bin.ts`) | **Adopt the gate, adjust the ramp:** S2 recommends PR-scoped incremental gate `break:60` ratcheting to 80 rather than enforcing 0.85 on day one. Wire `es gate-mutation` into task worktrees (Wave 3) with `--files` scoped to the PR diff; ratchet 60→80→85. No Stryker adapter exists — do not promise one. |
| Survivor feedback | MutGen loop 53%→89.5% kill rate (S2) | Feed `es gate-mutation` survivors back into the worker prompt as new kill-targets (manual loop first, automate post-Wave-3) | Process adoption, no code needed. |
| TDD red/green enforcement | — | `epistemic-factory` 8-stage machine `IDLE→GRILL→RESEARCH→SPEC→BUILD_TDD_RED→BUILD_TDD_GREEN→GATE_MUTATION→QA_DUAL_EVAL→DONE (+HALTED)`, TDD manifest lock (added files = tampering), dual-QA diversity guards, hash recompute + signature + manifest-lock (`packages/core`, `packages/cli`, `packages/epistemic-verifier-mcp`) | **Adopt (Wave 3).** Strongest verification story of the four repos. |
| Evidence integrity | — | Verifier MCP stdio server, 4 tools (`cache_source` / `verify_quote` / `locate_quote` / `audit_markdown`), NFKC folds, dual-bound HMAC cache | **Adopt (Wave 3).** Workers cannot forge evidence; low-friction stdio entry (`packages/epistemic-verifier-mcp`). |

### 1.4 Sandbox / sidecar layer (Heretek: heretek-devcontainers)

Current prod (`docker-compose.sidecars.yml`, verified by read: 822 lines, services `searxng`, `firecrawl`
stack, `gotenberg:8.37.0`, `browserless`, `mitmproxy`, `ghidra:11.2`, `radare2` digest-pinned, `hound`,
`semgrep:1.181.0`, `docker-socket-proxy:0.3.0`, `piston` digest-pinned, `qdrant:v1.19.2`, `neo4j:5.26.32`,
`litellm` digest-pinned, `mailpit:v1.21.8`, `minio` quay tag, `wiremock:3.10.0-alpine`,
`jaeger:2.22.0`, `docker-android:emulator_14.0_v3.8.0-p1`, `local-ci-runner`, isolated
`heretek-devsec` / `heretek-mobile` nets) vs `heretek-devcontainers` (`docker-compose.yml` root with
`include:` of `compose/core.yml` + `profile-appsec/android/game/research`; verified service→image map
in §7). Upgrade deltas per S5: `litellm`→bifrost+gateway, MCP env→lazy broker, `firecrawl`→`crawl4ai:0.9.5`,
formalized RE/mobile/game MCP bridges, uniform hardening. **Dropped with no equivalent and needing a
disposition decision:** qdrant/neo4j, piston, wiremock/mailpit/minio, gotenberg, browserless, jaeger.
Default disposition: **keep the current sidecars file authoritative** until each dropped service gets an
explicit keep/replace/retire row in the risk register (R-5).

---

## 2. The Unified 4-Phase Factory Mapping

One mission flows through exactly four phases. Each phase names its owning subsystem, entry points,
and acceptance artifact. No phase is optional; `HALTED` is a terminal state from any phase.

### Phase 1 — Inception: Socratic Director + Epistemic Research Cache

| Slot | Subsystem | Concrete entry point |
|---|---|---|
| Agency / decomposition intake | agency-control-plane Director | `dispatcher/src/director.ts` — one long-lived OpenCode session (`--director-agent director`), Zod-strict fenced ` ```tasks ` blocks; unknown fields / bad deps create nothing |
| Research evidence | epistemic-factory stages `GRILL→RESEARCH→SPEC` | `es init`, `es status`, `es audit-research`, `es approve` in `packages/cli/src/bin.ts`; verifier MCP `cache_source` / `verify_quote` / `locate_quote` / `audit_markdown` in `packages/epistemic-verifier-mcp` |

Flow: Director grills the human (Socratic loop) → `RESEARCH` fills the epistemic cache (every quote
dual-bound HMAC, NFKC-normalized) → `SPEC` freezes the frontier. Artifact: signed `SPEC` approval
(`.factory/approvals/SPEC-<runId>.json`, sealed Ed25519 key via `es key seal`, passphrase via
`--passphrase` or `ES_PASSPHRASE`, never on disk). WAIVER records exist but are **unenforced**
(S4) — treat any WAIVER as `HALTED` until enforcement lands (R-2).

### Phase 2 — Decomposition: Pure Scheduler DAG with Path-Overlap Serialization

Owner: `agency-control-plane/dispatcher/src/scheduler.ts` (pure: `all_success` / `one_success`,
fleet caps, path-overlap). Verified PASS per S3.

Rules:
- `task.expert` MUST be a valid 50-role id (Wave 4 mapping, §3); generic `taskPrompt` without an
  expert is rejected at intake (closes S3 blocker #1).
- Path-overlap serializes tasks touching the same `paths[]`; disjoint paths run parallel up to
  `--fleet-cap 4` (default in `dispatcher/src/main.ts` header + README `bun run dispatcher` flags).
- Per-expert caps ride alongside the global cap (e.g. `dba-specialist` max 1 concurrent migration
  task; see §3).
- `worktrees.ts` crash-safe 2-phase creation + base-pinning + salvage refs stay exactly as-is (PASS,
  do not refactor).

Artifact: scheduler-admitted DAG with pinned base commit per task.

### Phase 3 — Execution Triad (runs inside each task worktree)

Three mechanisms run together on every task; a task passes Phase 3 only when all three are green.

**(a) OpenCode v2 worker worktrees (agency-control-plane).**
`dispatcher/src/worker-launcher.ts` + `worker-session.ts` spawn `opencode serve --port 0
--hostname 127.0.0.1` per task in its worktree (`--worker-cmd` default; verified in README flags
table). Keep `scripts/opencode-shim.sh` semantics for any `opencode run` compat path (strip `--dir`,
fold `--variant` into `--model#variant`, inject `--auto` once — `scripts/opencode-shim.sh:22-48`).

**(b) TDD Red/Green gates + mutation testing (epistemic-factory).**
Inside the task worktree: `es init --dir <worktree>` → `BUILD_TDD_RED` (failing tests first,
manifest-locked) → `BUILD_TDD_GREEN` → `es gate-mutation --dir <worktree> --files <pr-diff-csv> --
<testCmd>` at the ratcheting threshold (§1.3). Added-files-outside-manifest = tampering → `HALTED`.

**(c) Lazy meta-tool routing + prefix caching (heretek-context-router) + devcontainer sidecars
(heretek-devcontainers).**
Worker `opencode.json` registers exactly one MCP server, the lazy broker (`heretek-lazy-broker`
stdio; `configs/opencode.base.json` shape: `mcp.servers.heretek-lazy-broker = { type:"local",
command:["heretek-lazy-broker"], environment:{ HERETEK_GATEWAY_URL } }`), exposing only the 3
meta-tools (~240 tokens). System prompt = `assemblePrefixCachedPrompt({ role, workspaceRoot,
activeProfile })` from `@heretek-ai/heretek-context-router/src/index.ts` (L1+L2 frozen,
`cacheBreakpoints` placed as provider breakpoints). Specialist tool traffic routes broker →
AgentGateway (`http://127.0.0.1:3000`) → devcontainer sidecars (Core always; appsec/android/game/
research on demand via `box-ctl` / `docker compose --profile`).

### Phase 4 — Integration & Gate: Ed25519 Cryptographic Approval + Fast-Forward Merge Barrier

| Slot | Subsystem | Concrete entry point |
|---|---|---|
| Approval | agency-control-plane + epistemic-factory shared key format | `dispatcher/src/approval-tickets.ts` + `human-key.ts` (ticket binding + `subjectHash` + audit chain); key files `human.key.enc` (scrypt + AES-256-GCM, `0600`) + `human.pub`; `es approve` records at `.factory/approvals/<STAGE>-<runId>.json`. One keypair serves both (`--human-pub /path/to/human.pub` flag verified in README). |
| Merge barrier | agency-control-plane | `dispatcher/src/landing.ts` — fast-forward-only land onto `fleet/integration/<mission>`. **Currently dead code (`landTask()` never called → approved tasks never merge, worktrees leak).** Wave 4 wires it: approval-present → `landTask()` → branch delete + worktree cleanup. Later enhancement: Gas-Town-style bisect on red. |

Artifact: signed, landed commit on `fleet/integration/<mission>` + `audit.jsonl` chain entry +
SQLite board row (`dispatcher.db`, WAL, `busy_timeout=15000`).

---

## 3. The 50-Role Fleet Ingestion

Current state (verified: `ls roles/ | wc -l` = **50**; sample read
`roles/api-contract-tester/opencode/opencode.json`): each role owns `opencode/opencode.json`
(least-privilege `fs:read`/`fs:write`/`shell`/MCP allows + terminal `* deny` tail — sample shows
terminal deny; full 50-file deny-tail audit is `make test` / `smoke-test.sh §3` scope) and
`AGENTS.md` boundaries. Paperclip injects them via `adapterConfig.env.XDG_CONFIG_HOME=/roles/<id>`
plus `OPENCODE_DISABLE_PROJECT_CONFIG=true` (`docker-compose.yml:87-91`, `AGENTS.md §1`).

### 3.1 Mapping table (mechanical, no exceptions)

| agency-control-plane concept | 50-role source of truth | Rule |
|---|---|---|
| `task.expert` | `roles/<role-id>/` directory name | Intake validates membership in the 50-set; unknown expert → card rejected with chat-visible error. |
| Worker system prompt | `roles/<id>/.opencode/agents/<role>.md` + `roles/<id>/AGENTS.md` | Launcher concatenates agent md + `AGENTS.md` boundary section, then appends the Phase-3 prefix-cache L3/L4 (role + task) layers. L1/L2 frozen bytes untouched. |
| `XDG_CONFIG_HOME` | `/roles/<id>` (container path; host `./roles:/roles:ro` mount per `docker-compose.yml:124`) | Dispatcher sets `XDG_CONFIG_HOME=/roles/<expert>` on every worker spawn. `OPENCODE_DISABLE_PROJECT_CONFIG=true` inherited. |
| `opencode.json` merge | `roles/<id>/opencode/opencode.json` + runtime overlay | Same merge Paperclip's `prepareOpenCodeRuntimeConfig` performs today: role file as base, runtime credentials/permissions overlaid, lazy-broker MCP server entry injected (Wave 2), never replacing the terminal deny tail. |
| Per-expert caps | `dispatcher/src/limits.ts` + new `roles-caps.json` | Global `--fleet-cap 4` stays; add per-expert ceiling map (default 1 for migration-capable roles, 2 otherwise; `exec-director`/`tpm-scrum-lead` heartbeat roles never take worker tasks). |
| Owned paths | role file's `fs:write` allow list | Scheduler path-overlap uses the union of `task.paths[]` and the expert's `fs:write` allows; writes outside owned paths → worker permission denial (fail-closed), recorded as task failure, not retried. |
| Heartbeat roles | `exec-director` (1800s), `tpm-scrum-lead` (3600s) | Only these two keep scheduled cadence; all other 48 remain wake-on-assignment (`AGENTS.md §1`, invariant 3 preserved). |

### 3.2 Sensitive-role hardening (already in prod — must survive migration)

- `dba-specialist`: Postgres MCP connects ONLY through `POSTGRES_READONLY_URL` (`paperclip_reader`,
  `docker-compose.yml:104`); seed gate rejects superuser URLs. agency-control-plane must import this
  gate verbatim: worker env for `dba-specialist` tasks gets the read-only URL and no other
  `POSTGRES_*`. (`roles/dba-specialist/` dir verified present.)
- `k8s-orchestrator`: read-only kubeconfig bind (`${KUBECONFIG_READONLY_PATH}:…:ro`,
  `docker-compose.yml:132`); context bound to a read-only ClusterRole. Same import rule.
  (`roles/k8s-orchestrator/` dir verified present.)
- Shell-prefix and MCP-namespace bypass limits (`AGENTS.md §4` known limitations) carry over
  unchanged: prefix patterns are hints, CEL/MCP boundaries + DB/kube RBAC are the real enforcement.

---

## 4. Step-by-Step Transition & Migration Plan

Principle: Paperclip stays the production plane through Waves 1–3. agency-control-plane only takes
over intake+dispatch in Wave 4 after its three blockers are closed. Each wave ends with a
-mechanical acceptance command; do not start the next wave on red.

### Wave 1 — Deploy Sidecar Foundation (heretek-devcontainers Core Profile)

Goal: Bifrost + AgentGateway + NATS running beside the current stack.

1. `cd references/heretek-devcontainers && bun install --frozen-lockfile --ignore-scripts` (Bun 1.4.2).
2. `make images` (resolves every pinned remote image; needs network).
3. `docker compose --profile core up -d` → expect `bifrost` (internal `:8080`),
   `agentgateway` (`127.0.0.1:3000`), `nats` (`:4222`/`:8222`).
4. Shadow-compare Bifrost vs LiteLLM (`docker-compose.sidecars.yml:541-563` stays live): mirror a
   day of prod prompts, diff latency/cost/quality. **Cutover requires own numbers** (rebuts
   UNVERIFIED vendor 11µs/50× claims — R-6).
5. Write AgentGateway CEL `mcpAuthorization` policy: admin-only `mdb`/`gui` paths (S5), per-target
   isolation on. Broker gates stay cost-control; CEL is the boundary.
6. Accept: `bash scripts/accept/wave-1.sh` (devcontainers) + `docker compose config` green on every
   profile combo + current `make test` still 39/39 in Heretek-Crew root.

### Wave 2 — Mount heretek-context-router Lazy Broker & Prompt Cache into OpenCode v2

Goal: every worker prompt cheaper and every worker tool-list under 500 tokens.

1. `cd references/heretek-context-router && bun install && bun run check && bun test && make accept`
   (waves 1–3 scripts, stop at first failure).
2. `bun link` (puts `heretek-lazy-broker` on `~/.bun/bin`); bake the broker bin into
   `docker/Dockerfile` beside `opencode-bin` + `scripts/opencode-shim.sh` so Paperclip-spawned
   workers resolve it.
3. Register in role configs: merge `configs/opencode.base.json`'s single
   `mcp.servers.heretek-lazy-broker` entry into all 50 `roles/*/opencode/opencode.json` via a
   script (idempotent, preserves terminal deny tail; assert with `smoke-test.sh §3` after).
   Env: `HERETEK_GATEWAY_URL=http://127.0.0.1:3000`.
4. Switch worker system prompts to `assemblePrefixCachedPrompt({ role:<id>,
   workspaceRoot:/paperclip/workspaces/<checkout>, activeProfile })`; verify L1+L2 frozen bytes
   identical across 6+ roles (cache-breakpoint test in router suite).
5. Fix S5 spec drift before prod: reconcile `session_affinity` spec vs implementation, confirm
   broker bind-paths, decide searxng-brokered-vs-direct (S5 open items — default: keep searxng
   direct until brokered path is accept-tested).
6. Accept: prompt-token benchmark (target ≤500 upfront, prefix hit-rate improvement logged) +
   `make test` + `smoke-test.sh --check-only` green.

### Wave 3 — Run epistemic-factory Gates in Task Worktrees

Goal: TDD + mutation + evidence integrity enforced on live Paperclip-dispatched work.

1. `cd references/epistemic-factory && bun install && bun test && bun run check &&
   bash scripts/accept/wave-1.sh && bash scripts/accept/wave-2.sh && bash scripts/accept/wave-3.sh`
   (expect 140/141; the 1 failure is the env-sensitive `bwrap-in-tmpdir` case — S4).
2. Vendor the CLI + verifier MCP into the Paperclip image (`docker/Dockerfile`): `bun ./packages/cli/src/bin.ts`
   as `es` on PATH; `packages/epistemic-verifier-mcp` as an MCP stdio entry workers can reach but
   cannot forge (evidence writes go to `.factory/`, workers hold no signing key).
3. Pilot on 5 roles (§8 checklist): worker instruction patch — `es init --dir <worktree>` at task
   start; RED before GREEN (manifest lock on); `es gate-mutation --dir <worktree> --files <diff-csv>
   -- <role-test-cmd>` with `break:60` initial threshold, ratchet 60→80→85 on consecutive green weeks.
4. Adopt OMO/Sisyphus tactics now: `smart-rebase` semantics in worker instructions,
   `worktree-isolation` defaults in `es init` scaffolding.
5. Sandbox note: `bwrap --ro-bind` covers build sandboxing; **mutation currently runs unsandboxed
   (S4)** — run Wave-3 mutation inside the existing `local-ci-runner`/quarantined path or a
   one-shot `bwrap` until the factory sandboxes it (R-3).
6. Accept: 5-role pilot ships ≥1 gated task each with `.factory/approvals/` + mutation report +
   `audit_markdown` clean; spend ledger reviewed (self-reported, no default ceiling — set per-task
   caps in dispatcher flags, R-3).

### Wave 4 — Launch agency-control-plane Daemon & WebUI, Migrating Off Paperclip

Preconditions (the three S3 blockers, all MUST close first):
- (a) Role-home injection: `task.expert=<role-id>` validation + agent-md/skills + `XDG_CONFIG_HOME`
    + `opencode.json` merge + per-expert caps + owned paths (§3.1). No generic-`taskPrompt` tasks.
- (b) Landing wired: approval-present → `landTask()` (`dispatcher/src/landing.ts`) → FF-merge to
    `fleet/integration/<mission>` → branch/worktree cleanup. Prove with a 2-task E2E (disjoint paths
    parallel, overlapping paths serialized) ending on `fleet/integration/<mission>`.
- (c) Parity + pins: Postgres/Caddy/Tailscale/sidecar essentials re-declared for the daemon plane
    (or daemon runs inside the same compose net reusing `docker-compose.yml` services); floating
    ranges (`zod^`, `react^`, `@types/bun@latest`) pinned exact; `bun install` +
    `make check`/`make accept` green (34-pass/7-fail baseline is missing-`node_modules`, S3).

Launch sequence:
1. `cd references/agency-control-plane && bun install --frozen-lockfile --ignore-scripts &&
   bun run build:web && bun run dispatcher -- --repo /paperclip/workspaces/<pilot> --port 7600`
   (loopback only; `--fleet-cap 4`; `--human-pub` pointing at the shared `human.pub`).
2. `bun run keygen -- --out ~/.local/state/agency-control-plane` once (or reuse the es-core key —
   same format, verified in README); `0600` on `human.key.enc`.
3. Dual-run: Paperclip keeps prod intake; control-plane takesglow pilot missions only. NATS
   (`NATS_URL`) mirroring on for event audit.
4. Cutover: migrate heartbeat roles last (`exec-director`, `tpm-scrum-lead`); freeze Paperclip seed
   (`scripts/seed-50-fleet.sh --dry-run` stays as the fleet manifest source until the daemon owns it).
5. Accept: `make check` + `make accept` in agency-control-plane; E2E land proof; `audit.jsonl`
   chain verifies (`human-key.ts` verify path); Paperclip decommission decision recorded in `NOTES.md`.

---

## 5. Verification Status Table

| # | Claim | Method | Status |
|---|---|---|---|
| V-1 | `references/` contains exactly `agency-control-plane`, `epistemic-factory`, `heretek-context-router`, `heretek-devcontainers` (+2 awesome-* dirs) | `read references/` | ✅ VERIFIED |
| V-2 | agency-control-plane README flags (`--repo`, `--state-dir`, `--port 7600`, `--fleet-cap 4`, `--human-pub`, `NATS_URL`, `opencode serve --port 0`) | `head -60 README.md` | ✅ VERIFIED |
| V-3 | Dispatcher source files (`scheduler.ts`, `worktrees.ts`, `landing.ts`, `approval-tickets.ts`, `human-key.ts`, `director.ts`, `worker-launcher.ts`, …) | `ls dispatcher/src` | ✅ VERIFIED |
| V-4 | epistemic-factory v3.0.0 rewrite notice, `es` CLI reference, `gate-mutation` 85% threshold text | `head -60 README.md` + `grep bin.ts` | ✅ VERIFIED |
| V-5 | Context-router lazy broker (3 meta-tools, ~240 tokens), prefix-cache L1/L2 frozen, `configs/opencode.base.json` shape | `head -60 README.md` + `ls src/` | ✅ VERIFIED |
| V-6 | Devcontainers Core pins `bifrost:v2.3.0`, `agentgateway:v1.6.0`, `nats:2.15.1-alpine`; research `crawl4ai:0.9.5`; `include:` root | `head -60 README.md` + `grep compose/*.yml` | ✅ VERIFIED |
| V-7 | Heretek-Crew prod: `postgres:17-alpine`, `@opencode/cli@2.0.32`, shim rules, `XDG_CONFIG_HOME`, sidecar service list (searxng/firecrawl/gotenberg/browserless/ghidra/qdrant/neo4j/litellm/…) | `read docker-compose.yml`, `docker-compose.sidecars.yml` (822 lines), `opencode-shim.sh:22-53` | ✅ VERIFIED |
| V-8 | `roles/` count = 50; `dba-specialist` + `k8s-orchestrator` present; sample `opencode.json` least-privilege + deny tail | `ls roles \| wc -l`, sample `cat` + `tail` | ✅ VERIFIED |
| V-9 | S1 external claims (Superset/Gas Town/Symphony/OpenHands/OMO/SWE-AF version specifics, queue semantics) | No network reads performed | ⚠️ UNVERIFIED — taken from S1 on trust; re-verify before citing versions externally |
| V-10 | S2 vendor numbers (Bifrost 11µs/50×, Anthropic cache pricing tiers, MutGen 53→89.5%, ProjectDiscovery 7%→84%/−59%) | No live repro | ⚠️ UNVERIFIED — do not use for cutover decisions; repro in Wave 1 |
| V-11 | S3 test counts (34/7), S4 (140/1), shim 39/39, smoke-test 48+ assertions | Reported, not re-run (no `bun install`/test runs in this synthesis) | ⚠️ UNVERIFIED — first milestone re-runs them (§8) |
| V-12 | Full 50-file deny-tail + `shell`-prefix audit | Sample only (1 role) | ⚠️ UNVERIFIED — `smoke-test.sh §3` owns the complete audit |

---

## 6. Gap / Risk Register

| ID | Sev | Gap / Risk | Mitigation (concrete) |
|---|---|---|---|
| R-1 | **P0 / BLOCKER** | `landTask()` never called — approved work never merges, worktrees leak (S3) | Wave 4 precondition (b): wire approval→`landTask()`→cleanup; prove 2-task E2E before any cutover. |
| R-2 | **P0 / BLOCKER** | No 50-role home in agency-control-plane (generic `taskPrompt`, no `opencode.json`/`XDG` injection) (S3) | Wave 4 precondition (a): implement §3.1 mapping; reject expert-less tasks at intake. |
| R-3 | P0 | Trust-root + sandbox holes: `.factory/` writability = evidence trust root; WAIVER signable but unenforced; mutation unsandboxed; spend ledger self-reported, no ceiling (S4) | Treat WAIVER as `HALTED`; run Wave-3 mutation inside quarantined runner/`bwrap`; set per-task spend caps in dispatcher flags; chmod/`chattr` + ownership hardening on `.factory/` before pilot. |
| R-4 | P1 | No verified secret vault; AgentGateway AES-256 vault unverified (S2); auth-bypass via direct gateway key; emulator privilege; `session_affinity` drift; searxng-not-brokered (S5) | Keep `.env` + `0600` keys; rotate gateway keys per-profile; never co-schedule `mobile` + `devsec` (existing Makefile guard); fix affinity drift + bind-paths in Wave 2 step 5. |
| R-5 | P1 | Dropped sidecars with no equivalent: qdrant/neo4j (memory plane — no replacement at all), piston, wiremock/mailpit/minio, gotenberg, browserless, jaeger (S5) | Default KEEP on current `docker-compose.sidecars.yml`; per-service keep/replace/retire decision logged in `NOTES.md` before any removal. Memory plane is the hardest gap — do not retire Qdrant/Neo4j without a successor design. |
| R-6 | P1 | Floating deps (`zod^`, `react^`, `@types/bun@latest`) + unverified vendor perf (Bifrost) + missing Postgres/Caddy/Tailscale parity in control-plane (S3) | Wave 4 precondition (c): pin exact, repro perf, re-declare infra parity. Zero-`:latest` policy (`AGENTS.md §4`) applies to all new pins. |
| R-7 | P2 | Tier-failover display-grade; WebUI 5-pillar conditional; `firecrawl`→`crawl4ai` migration unproven; `mcp-proxy` 0.13.0 wrapping for every MCP bridge | Shadow-run + accept scripts per wave; `firecrawl` stays live until `crawl4ai:0.9.5` proves parity on real crawls. |

---

## 7. Pinned-Version Table (verified pins only — no `:latest` anywhere)

| Component | Pin | Source file |
|---|---|---|
| OpenCode CLI/client | `@opencode/cli@2.0.32` + `@opencode/client@2.0.32` | `docker-compose.yml:15-16`, `AGENTS.md §1` |
| Postgres / Caddy / Tailscale | `postgres:17-alpine`, `caddy:2.11.7-alpine`, `tailscale/tailscale:v1.104.1` | `docker-compose.yml:13-14,22,165,211` |
| Sidecars (current) | `redis:7.4.11-alpine`, `rabbitmq:4.3.6-management-alpine`, `firecrawl:2.10.19` (+2 digest-pinned images), `gotenberg:8.37.0`, `chromium:v2.24.2`, `mitmproxy:11.0.2`, `ghidra:11.2`, `hound`+`radare2`+`semgrep:1.181.0`+`piston` digest pins, `qdrant:v1.19.2`, `neo4j:5.26.32-community-trixie`, litellm `main-v1.54.0` digest, `mailpit:v1.21.8`, minio `RELEASE.2024-11-07T00-52-20Z`, `wiremock:3.10.0-alpine`, `jaeger:2.22.0`, `docker-android:emulator_14.0_v3.8.0-p1`, `catthehacker/ubuntu:act-22.04` | `docker-compose.sidecars.yml` (full read) |
| Devcontainers Core | `ghcr.io/maximhq/bifrost:v2.3.0`, `ghcr.io/agentgateway/agentgateway:v1.6.0`, `nats:2.15.1-alpine` | `references/heretek-devcontainers/compose/core.yml` (grep-verified) |
| Devcontainers specialist | `searxng:2026.10.16-0ce72dd2c`, `crawl4ai:0.9.5`, `budtmo/docker-android:emulator_14.0_v3.8.0-p1`, `localhost/heretek/{ghidra-mcp:6.0.0, radare2-mcp:1.9.0, rea-mcp:6.5.0, mdb-mcp:0.2.0-5d03b25, adb-mcp:0.23.0, maestro-mcp:2.11.0, godot-mcp:3.1.0, blender-mcp:0.11.1, computer-use-linux:0.7.17}`, `mcp-proxy:0.13.0` | `compose/profile-*.yml` + README image table (README-verified) |
| Runtimes | Bun 1.4.2 (control-plane README), Bun ≥1.1 (factory README), Node 24 (Paperclip base) | Companion READMEs + `docker-compose.yml:14` |
| Mutation gate | Factory textual engine threshold **0.85**; rollout ramp `break:60→80→85` (Stryker defaults `high:80 low:60 break:null` as reference) | `packages/cli/src/bin.ts` + S2 |

---

## 8. First-Milestone Checklist (concrete commands, in order)

Pilot roles (cover contracts, data, infra, direction, process): `api-contract-tester`,
`dba-specialist`, `k8s-orchestrator`, `exec-director`, `tpm-scrum-lead`.

```sh
# 0. Baseline: prove the tree is green before touching anything.
cd /home/john/Projects/Heretek-Crew
make test                                   # shim suite, expect 39/39
bash scripts/smoke-test.sh --check-only     # static assertions
bash scripts/seed-50-fleet.sh --dry-run     # fleet manifest validates, no network

# 1. Companion test baselines (record pass/fail; do not fix here, file gaps).
cd references/agency-control-plane && bun install --frozen-lockfile --ignore-scripts && make check
cd ../epistemic-factory && bun install && bun test && bun run check
cd ../heretek-context-router && bun install && bun run check && bun test && make accept
cd ../heretek-devcontainers && bun install --frozen-lockfile --ignore-scripts && make images

# 2. Wave 1 up.
cd ../heretek-devcontainers && docker compose --profile core up -d
docker compose --profile core ps          # bifrost + agentgateway + nats healthy

# 3. Wave 2 link (after Wave-1 accept green).
cd ../heretek-context-router && bun link  # heretek-lazy-broker on ~/.bun/bin

# 4. Wave 3 pilot (after Wave-2 accept green; Paperclip still prod).
# For each pilot role: dispatch 1 task, require es RED→GREEN→gate-mutation(break:60)
# + verifier audit_markdown clean + .factory/approvals present.

# 5. Wave 4 gate (after R-1/R-2/R-6 closed): 2-task E2E landing on fleet/integration/<mission>.
cd ../agency-control-plane && bun run build:web \
  && bun run dispatcher -- --repo /paperclip/workspaces/<pilot> --port 7600 --fleet-cap 4
```

Done = all five steps green with artifacts (mutation reports, `audit.jsonl` chain, landed branch)
linked from `NOTES.md`. Paperclip decommission is a separate, later decision — never part of this milestone.
