# OpenCode Ecosystem Mining Report: Recommendations for Heretek-Crew

**Date:** 2026-10-17 | **Investigator:** Lead Research & Tooling Engineer (OpenCode v2 autonomous investigation)
**Sources:** `references/awesome-opencode/` (136 plugin YAMLs in `data/plugins/`) + `references/awesome-opencode-techbuzzz/` (10 skills, `docs/mcp-quick-reference.md`, `docs/skills-quick-reference.md`, `configs/`, `agents/`)
**Target:** Heretek-Crew — Paperclip + OpenCode v2 (`@opencode/cli@2.0.32`), `@heretek-ai/opencode-harness@1.0.7`, `opencode-mem@2.31.3`, 50 fleet roles + 6 legacy roles (56 dirs in `roles/`), Qdrant/Neo4j/Jaeger/LiteLLM sidecars
**Method:** 6 sequential batches per `PROMPT_INVESTIGATE_AWESOME_OPENCODE.md`; every candidate YAML read in full. Key structural finding applies globally: **~130/136 plugin YAMLs are 4-line stubs (`name, repo, tagline, description` only)** — no `installation`, no version pin, no hook declaration. Only `flowdeck.yaml`, `tree-sitter-language-pack.yaml`, `crawlberg.yaml`, `opencode-telemetry.yaml` (and 1–2 others) carry `scope/tags/min_version/installation`. All install paths below are therefore **repo-URL-only until upstream READMEs are pinned** — nothing goes into `docker/Dockerfile` unpinned (zero-`:latest` rule).

---

## 1. Executive Summary & Top 5 High-Impact Adoptions

| # | Adoption | What it is | Target component | Effort / Risk |
|---|----------|-----------|------------------|---------------|
| 1 | **Tree-sitter Language Pack plugin** (`@xberg-io/opencode-tree-sitter-language-pack`) | Only orchestration/quality plugin with explicit npm package + v2 `plugin: [...]` install syntax; AST/symbol extraction for 300+ languages | `docker/Dockerfile` (pinned global install) + allow-list per role: `static-analysis-lead`, `binary-reverse-eng`, `vector-rag-spec`, `go-backend-eng` | Low. Pin npm + `tree-sitter-language-pack` CLI version, add per-role tool allows. No harness overlap. |
| 2 | **8 drop-in procedural skills** (`go-expert`, `security-audit`, `tdd`, `git-flow`, `code-review`, `tailwind-ui`, `typescript-astro`, `dotnet-expert`) | Single-file `SKILL.md`, valid frontmatter, zero network deps at load, 99–248 lines each | `roles/<role>/.opencode/skills/<skill>/SKILL.md` for 10+ roles (matrix in Batch 4) | Low. Pure copy + `smoke-test.sh --check-only`. `nextjs-dev` needs a frontmatter header; `nuxt-dev` (3061 lines) needs frontmatter + split before use — excluded from this wave. |
| 3 | **Secret-hygiene pair: Envsitter Guard + Log Sanitizer** | `envsitter-guard` (blocks `.env*` reads, fingerprint-only inspection) + `opencode-log-sanitizer` (redacts JWTs/bcrypt/base64 in pastes) | Fleet-wide plugin candidates via `docker/Dockerfile` + per-role `plugins` array; complements `.env`-in-`.gitignore` + `{env:VAR}` discipline | Medium. Both YAMLs are stubs with no v2 hook proof — verify hook names against `@opencode/cli@2.0.32` in staging before fleet rollout. |
| 4 | **Local-first cost telemetry: `opencode-telemetry`** (SQLite + `octm` CLI) | Only telemetry entry with `local-first` tags; per-session tokens/tool-calls/skills/cost, conductor+child chain rollups, no message bodies, zero cloud | Pilot on `observability-eng` + `exec-director`/`tpm-scrum-lead` (the only heartbeat roles); pairs with existing `jaeger:1.63.0` sidecar | Medium. Verify SQLite path under `/roles/<id>` isolation (no workspace pollution) and `octm` binary pin. Rejects cloud-exfil OTEL alternative for default fleet. |
| 5 | **Selective MCP expansion from verified quick-reference** (Context7 remote, gopls local, Postgres read-only — extend Playwright-per-agent + K8s-after-verify) | `mcp-quick-reference.md` gives 12 copy-paste configs with token costs (GitHub ~10–15k ⚠️, Context7 ~0.5–1k, Playwright ~1k, SQLite ~300); fleet already proves the pattern (`@upstash/context7-mcp@4.4.2`, `@modelcontextprotocol/server-postgres@0.6.2` + true read-only DB role, `codebase-memory-mcp@0.12.1`) | `roles/k8s-orchestrator` + `roles/cloud-platform-eng` (K8s MCP, after typosquat verify), `roles/e2e-browser-qa` (Playwright, disabled-global/enabled-per-agent), `roles/dba-specialist` (keep existing pinned Postgres, no change) | Low–Medium. Only adopt org-scoped packages (`@modelcontextprotocol/*`, `@playwright/mcp`, `@redis/*`, `@mongodb-js/*`); quarantine 5 unscoped names (`k8s-mcp`, `go-dev-mcp`, `firecrawl-mcp`, `opencode-mcp`, `opencode-litellm`) until resolved to exact scoped versions. |

**Explicit non-adoptions (highest-cost avoids):** full-fleet orchestrator plugins (FlowDeck, CrewBee, Ensemble, Swarm, Conclave, hiai, BMAD, Ralph-loop as fleet scheduler) — all duplicate Paperclip assignment/heartbeat/wave execution and would create dual-scheduler token waste; adopt at most as *process templates inside a single role*. Cloud OTEL exporter as fleet default — exfil-by-design; local SQLite telemetry first. Any `npx -y <unscoped-latest>` MCP — typosquat + `:latest` violation.

---

## 2. Batch-by-Batch Evaluation Matrix

### Batch 1: Multi-Agent & Orchestration

Sources: `data/plugins/` (15 files read in full) + techbuzzz README §Orchestration (8 rows, all links point at the aggregator — `data/plugins/*.yaml` `repo:` URLs are authoritative).

| Candidate (repo) | Verdict | Rationale | Target component |
|---|---|---|---|
| `@bluelovers/opencode-arise` (`bluelovers/opencode-arise`) — token-efficient parallel background orchestrator, per-agent model config | **ADAPT** | Closest fit to unattended `opencode run --session --auto` + shim (`--dir`/`--variant` folding). But stub YAML: no install string, no hook list, no v2 proof. Pilot as pattern, not fleet scheduler. | `exec-director` workflow template; verify `--auto`/cwd semantics in staging |
| `opencode-agent-identity` (`gotgenes/opencode-agent-identity`) — self-identity prompt injection + per-message attribution tool | **ADAPT** | Cheap attribution for multi-agent audit; prompt-injection + tool pattern is v2-plausible. No version field; attribution store must live under `/roles/<id>` (no repo pollution). | `exec-director` / `tpm-scrum-lead` review flow |
| FlowDeck (`DVNghiem/FlowDeck`) — 25 agents, 4-phase cycle, `.planning/STATE.md`, safety layer, 24 skills/17 commands; `min_version 1.0.0`, `curl\|bash` + `npx @dv.nghiem/flowdeck install` | **REJECT (as fleet)** / mine ideas | Only enriched orchestration YAML, but it's a parallel fleet: 25 agents vs our 50-role catalog, own state/memory/MCPs. Dual orchestration with Paperclip = scheduling + token duplication. Mine safety-layer concepts (edit gates, phase gating) into harness instead. | Ideas → `@heretek-ai/opencode-harness`; do not install |
| CrewBee (`CrewBeeLab/CrewBee`) — reusable agent teams, coding+review template | **REJECT** | Team-template concept already covered by `roles-catalog/` (9 departments) + Paperclip assignment. No install/v2 metadata. | — |
| OpenCode Ensemble (`hueyexe/opencode-ensemble`, npm `@hueyexe/opencode-ensemble`) — parallel agents, peer messaging, task board, worktree isolation, dashboard | **ADAPT (narrow)** | Worktree-isolation + task-board pieces are useful; full ensemble duplicates Paperclip. Evaluate only worktree/dashboard fragments for `git-drift-coord`. `cli-subagent-output` (`raisbecka/opencode-subagent-output`, missing from techbuzzz table — pipes subagent events to stdout) is the better observability pick for `opencode run` tracing. | `git-drift-coord` (worktree fragment); `exec-director` (subagent-output tracing) |
| OpenCode Swarm (`zaxbysauce/opencode-swarm`) / Swarm Plugin (`joelhooks/opencode-swarm-plugin`) — verification-gated swarms | **REJECT** | Two distinct swarm entries, both stubs, both duplicate verification already owned by `release-qa-officer` + `sabotage-qa-tester` + harness gates. | — |
| Open Conclave (`martinzokov/open-conclave`) — multi-agent debate + captain consensus | **REJECT** | Debate-until-consensus burns tokens on 50-role fleet with no evidence gate; no install/v2 data. | — |
| hiai-opencode (`HiAi-gg/hiai-opencode`) — 12-agent canonical model + bundled MCP/LSP/skills, todo-enforcer/ralph-loop | **REJECT** | Bundled MCP list (playwright, firecrawl, mempalace, …) conflicts with per-role least-privilege MCP allow-lists + token budgets; 12 agents vs 50-role catalog mismatch. | — |
| Background Agents (`kdcokenny/opencode-background-agents`) — async delegation + context persistence | **ADAPT** | Pattern-compatible with on-demand wake (48/50 roles `heartbeat.enabled:false`), but stub only — prove against shim streaming before use. | `exec-director` delegation pattern |
| opencode-bmad-workflow / open-dynamic-workflows / forloop-planner / opencode-plan-manager / subtask2 | **REJECT** | All stubs; BMAD/spec-pipeline concepts overlap Paperclip + `system-architect` planning; local-daemon (dynamic-workflows) and cloud-deploy (forloop) violate container/self-host invariants. | — |

Batch 1 answers: (1) arise = best spawning pattern, identity = best attribution, both need v2 proof; (2) no orchestrator integrates cleaner than Paperclip + `dispatch-pipeline` — all are parallel schedulers; (3) Ensemble task-board fragments + `cli-subagent-output` stdout tracing are the only messaging/assignment helps worth piloting.

### Batch 2: Memory, Context & Knowledge Graphs

Sources: `data/plugins/` (15 files, all read; 14× 4-line stubs, 1× 10-line `opencode-rag.yaml`). Schema (`data/schema.json`) requires only `name/repo/tagline/description` — **no backend/npm/hook/v2 fields exist**, so all backend notes below are description-inferred.

| Candidate (repo / backend) | Verdict | Rationale | Target component |
|---|---|---|---|
| Harness Memory (`smc2315/harness-memory`, sql.js WASM/SQLite, 73%-fewer-tokens claim) | **ADAPT** | Local-first + human-review gates fit self-hosted + PoLP, but auto-capture-from-tool-interactions must be scoped or it fights per-role deny tails. Name overlaps `@heretek-ai/opencode-harness` — confusion risk; evaluate as skill/memory pattern, not second harness. | `vector-rag-spec` evaluation vs Qdrant sidecar |
| Honcho (`plastic-labs/opencode-honcho`, cloud-or-self-hosted server) | **REJECT (default)** | Cloud dependency by default; fleet already runs `opencode-mem@2.31.3` (Turso/libSQL) + Qdrant `v1.12.5` + Neo4j `5.26.0` sidecars. Self-hosted Honcho only if `opencode-mem` proves insufficient. | — |
| Magic Context (`cortexkit/opencode-magic-context`, background compression) | **ADAPT** | Background historian/dreamer conflicts with on-demand ethos (no idle token waste); prompt-cache-safe claims need proof on our models. Pilot on one long-session role only. | `tech-docs-lead` pilot |
| Opencode Mem (`tickernelz/opencode-mem`, local vector DB) | **REJECT** | Name-collides with fleet-pinned `opencode-mem@2.31.3` (different project); adopting both guarantees confusion + dep conflict. | — |
| oc-mnemoria (`one-bit/oc-mnemoria`, Rust append-only binary, BM25+semantic, 7 tools + `/mn-*`) | **ADAPT** | Hive-mind shared memory is the only true multi-agent store here; Rust engine + CRC32 chains are credible. But binary format + custom tools need PoLP review (tool namespace bypasses `shell` denies — same caveat as `AGENTS.md` MCP-bypass note). | `vector-rag-spec` + `system-architect` shared-memory pilot |
| Simple Memory (`cnicolov/opencode-plugin-simple-memory`, git-backed) | **ADAPT** | Git-committable memory fits review culture, but memory commits inside workspaces risk repo pollution (`OPENCODE_DISABLE_PROJECT_CONFIG=true` invariant) — confine to `/roles/<id>` paths. | `git-drift-coord` convention pilot |
| Dynamic Context Pruning (`Tarquinen/opencode-dynamic-context-pruning`, ephemeral prune) | **ADOPT (after verify)** | Only pure token-saver with no storage side-effects; aligns with lean-context goal. Verify prune rules don't drop evidence harness needs. | Fleet-wide candidate, `tpm-scrum-lead` first |
| opencode-short-term-memory (`andrejtonev/opencode-short-term-memory`, session summarizer + prompt injection) | **ADAPT** | Helps long sessions/compactions; injection cadence must be tuned per role to avoid context bloat. | `exec-director`, `system-architect` |
| OpenCodeRAG (`MrDoe/OpenCodeRAG`, tree-sitter chunking 19 langs, LanceDB, Ollama/OpenAI, `index/query/status/clear` CLI, `chat.message` suggestions, watch mode) | **ADAPT (scoped)** | Only true vector-RAG entry; AST-aware chunking complements tree-sitter plugin (Batch 3). **Restrict watch/index to a single indexer role or sidecar** — per-agent watch mode violates on-demand policy. Embedding keys via runtime merge, never committed. Direct alternative to Qdrant sidecar for per-workspace search; run bake-off before committing. | `vector-rag-spec` bake-off: OpenCodeRAG (LanceDB local) vs Qdrant `v1.12.5` sidecar |
| OpenCode Claude Memory (`kuitos/opencode-claude-memory`, shared Markdown with Claude Code) | **REJECT** | Cross-tool Markdown sharing adds a second memory format with no fleet consumer. | — |
| Opencode Sessions (`malhashemi/opencode-sessions`, sparsest description) | **REJECT** | No functional detail; session management already owned by Paperclip/Postgres. | — |
| Worktree Memory Sync (`Edison-A-N/opencode-worktree-memory-sync`, copies `.opencode/memory/` into new worktrees, only-when-empty) | **ADOPT** | Tiny, safe, solves a real worktree-memory gap; only-when-empty semantics respect isolation. | `git-drift-coord` + `exec-director` worktree flow |
| Agent Memory (`joshuadavidthomas/opencode-agent-memory`, Letta-style blocks) | **ADAPT** | Self-editable blocks are elegant but self-edit + PoLP needs a write-scope audit. | Single-role pilot |
| With Context MCP (`boxpositron/with-context-mcp`, markdown-notes MCP) | **ADAPT** | MCP-notes fit per-role scoping; verify tool names vs MCP-namespace bypass caveat. | `tech-docs-lead` |
| Context Analysis (`IgorWarzocha/Opencode-Context-Analysis-Plugin`, token analysis only) | **REJECT (as memory)** | Observability, not memory — rerouted to Batch 6 telemetry. | — (see Batch 6) |

Batch 2 answers: (1) long-term options are Honcho (cloud — reject), opencode-mem-name-collision (reject), oc-mnemoria (pilot), Harness Memory (pilot), Simple Memory (convention pilot) — fleet incumbent `opencode-mem@2.31.3` stays; (2) Dynamic Context Pruning is the lean-context pick; (3) nothing plugs directly into Qdrant/Neo4j sidecars — OpenCodeRAG (LanceDB) is a *competitor*, not a connector; a Qdrant-native plugin remains a gap (build vs buy decision for `vector-rag-spec`).

### Batch 3: Code Quality, AST & Harnesses

Sources: `data/plugins/` (14 files, all read; 83 lines total; longest `tree-sitter-language-pack.yaml` 23 lines). Only 1/14 declares an npm package.

| Candidate | Verdict | Rationale | Target component |
|---|---|---|---|
| opencode-review (`sun-praise/opencode-review`) — idle-triggered staged-diff review, configurable dimensions/severity, auto-fix chain | **ADAPT** | Complements harness (which has no idle diff-reviewer or severity rubric). **Scope auto-fix OFF globally** — review-only roles first, respecting `fs:write` deny tails. Verify v2 idle/session hook + shim `--auto` interplay. | `static-analysis-lead`, `release-qa-officer` (review-only mode) |
| Tree-sitter Language Pack (`xberg-io/plugins`, npm `@xberg-io/opencode-tree-sitter-language-pack`, `plugin: [...]` syntax, `scope: [global, project]`) | **ADOPT** | Sole explicit-npm + explicit-v2-syntax entry; pure capability add (parse/symbols/imports, 300+ langs), zero harness overlap, clean per-role allow-listing. Pin npm + CLI versions (zero-`:latest`). | `docker/Dockerfile` + `static-analysis-lead`, `binary-reverse-eng` (pairs with radare2/Ghidra sidecars), `vector-rag-spec` (pairs with OpenCodeRAG chunking) |
| TypeUI (`bergside/typeui`) — design skills/prompts/layout guidance | **ADAPT** | Version-agnostic skills, no hook risk; evaluate against existing `design-system-eng` skills (`impeccable-taste`, `storybook-component-tokenization`) to avoid duplication. | `ui-ux-designer`, `design-system-eng` skill review |
| OpenCodeRAG (`MrDoe/OpenCodeRAG`) | **ADAPT (scoped)** | See Batch 2. Retrieval upgrade over `grep/glob/read`; watch mode confined to indexer role/sidecar; embedding secrets via runtime merge. | `vector-rag-spec` |
| Ralph Wiggum (`Th0rgal/opencode-ralph-wiggum`) — self-correcting loops | **ADAPT (as loop pattern only)** | Direct overlap with Paperclip orchestration + shim `--session/--auto` streaming if run as scheduler. Confine to *in-task iteration with fail-closed cap*; never a second orchestrator (idle-token + infinite-loop risk). | Single-role loop template, `programmer` |
| Semantic Anchors (`JensGrote/opencode-semantic-anchors`) — BLOCK/WARN contract enforcement, profiles, Zod YAML | **ADAPT** | Behavioral contracts (socratic/architecture gates) complement PoLP deny-tails + read-only PG/kube resource-layer scoping. **Dynamic role-switching breaks `XDG_CONFIG_HOME=/roles/<id>` isolation — disable that feature.** Test against prefix-match + MCP-bypass limitations. | `system-architect`, `appsec-engineer` |
| Opencode Hooks Plugin (`romain325/opencode-hooks-plugin`) — Claude-Code-hooks → OpenCode-hooks bridge | **ADAPT (high verification need)** | Adapter analogous to `scripts/opencode-shim.sh`; each bridged hook needs explicit allow-listing + `test-shim.sh`/`smoke-test.sh` parity. Verify v2 event mapping first. | Staging only |
| GoopSpec (`hffmnnj/opencode-goopspec`) — 5-phase spec workflow, 12 subagents, gates, wave commits | **ADAPT (as process template)** | Overlaps Paperclip + 50-role catalog if run as fleet; useful as `exec-director` contract-gate/deviation-rule template with memory under `/roles/<id>`. | `exec-director` process doc |
| OpenSpec (`Octane0411/opencode-plugin-openspec`) — architecture planning agent | **ADOPT (scoped)** | Single planner agent, no orchestration conflict; human/lead gate before execute. Verify agent frontmatter + `--model provider/model#variant` string. | `system-architect` |
| Plannotator (`backnotprop/plannotator`) — external plan-review UI + Obsidian/Bear export | **ADAPT** | Human-in-the-loop gate with no harness overlap; verify loopback binding + no secret exfiltration. | `exec-director` approval step |
| open-plan-annotator (`ndom91/open-plan-annotator`) — in-loop plan-mode interceptor, local browser annotate/approve | **ADAPT (staging first)** | Stronger integration than Plannotator but must not break `--auto` non-interactive runs or shim stdin/stdout streaming. Fully-local claim fits self-hosting — verify. | Staging, then `exec-director` |
| Opencode Roadmap (`IgorWarzocha/Opencode-Roadmap`) — strategic planning + coordination | **ADAPT (artifact-only)** | Confine to roadmap-doc generation in one role; scheduling stays with Paperclip + `tpm-scrum-lead` (3600s heartbeat). | `product-director`/`tpm-scrum-lead` |
| PR Auto-Signature (`arttttt/opencode-pr-signature`) — 90+ model signatures via GitHub MCP/git/gh | **REJECT (default)** | Provenance noise on atomic-commit history; Paperclip DB audit log already owns attribution. MCP path bypasses `shell` denies — needs `github_*` namespace constraint too. Scope to bot roles only if ever adopted. | — |
| Beads Plugin (`joshuadavidthomas/opencode-beads`, `/bd-*` for Yegge's beads tracker) | **ADAPT** | File-based issue graph conflicts with Paperclip/Postgres as system of record if run fleet-wide; fit is dev-role scratch tracking. Needs `bd` binary pinned + allow-listed. | `programmer` scratch tracking, Paperclip remains record |

Batch 3 answers: (1) community repair/lint plugins *complement* rather than replace `@heretek-ai/opencode-harness@1.0.7` — closest overlap (Ralph, GoopSpec, Roadmap, OpenSpec) should be absorbed as patterns, not parallel runners; (2) no dedicated test-generation plugin found — `tdd` skill (Batch 4) + existing `tester`/`release-qa-officer` toolchain remain the path; (3) `tree-sitter-language-pack` + `opencode-review` (review-only) + `semantic-anchors` (no role-switching) are the static-analysis upgrades.

### Batch 4: Procedural Skills Mining for the 50 Roles

Sources: all 10 `skills/*/SKILL.md` read in full (`wc -l` verified: 99–248 lines except `nuxt-dev` 3061). **No skill ships `scripts/`, `references/`, or `assets/`** — all guidance is inline. 8/10 have valid `name`+`description` frontmatter; 2 do not.

| Skill (lines) | Verdict | Mapped Heretek-Crew role(s) + exact target path |
|---|---|---|
| `code-review` (99) — severity-tiered review framework + report template, stack-agnostic, zero network | **ADOPT** | `roles/static-analysis-lead/.opencode/skills/code-review/SKILL.md`; also `roles/release-qa-officer/.opencode/skills/code-review/SKILL.md`, `roles/appsec-engineer/.opencode/skills/code-review/SKILL.md` |
| `dotnet-expert` (185, `.NET 8+`) — async/null-safety/records, Minimal API, EF Core N+1, Clean Architecture tree, xUnit+Testcontainers | **ADOPT** | Check fleet for .NET owner (no dedicated dotnet role in `roles/` listing — nearest: `roles/api-contract-tester/`, `roles/static-analysis-lead/`); place at `roles/api-contract-tester/.opencode/skills/dotnet-expert/SKILL.md` or hold for future dotnet role. No permission change needed (guidance-only). |
| `git-flow` (126) — Conventional Commits, branch naming, PR/Changelog templates | **ADOPT** | `roles/git-drift-coord/.opencode/skills/git-flow/SKILL.md`; reference for `roles/tpm-scrum-lead/.opencode/skills/git-flow/SKILL.md`. Align commit-type table with existing Conventional Commits usage before rollout. |
| `go-expert` (237, `Go 1.21+`) — error/context/interfaces/errgroup, chi handler, `cmd/internal/pkg` layout, table-driven tests, golangci-lint | **ADOPT** | `roles/go-backend-eng/.opencode/skills/go-expert/SKILL.md` (alongside existing `idiomatic-go-service-development/` — complementary, not replacement; keep both, go-expert as reference). Add `go vet*`? No — keep existing allow-list (`go build/test`, `golangci-lint`, `go mod`, `git status` + `shell *` deny) unchanged; skill is guidance-only. |
| `nextjs-dev` (113) — 9-section Next.js full-stack agent instructions, zero npm/curl commands | **ADAPT (add frontmatter)** | `roles/ts-node-fullstack/.opencode/skills/nextjs-dev/SKILL.md` + `roles/mobile-web-eng/.opencode/skills/nextjs-dev/SKILL.md` — after prepending `name: nextjs-dev` + trigger `description`. Content ready otherwise. |
| `nuxt-dev` (3061, ~121 KB, Nuxt 4/Vue 3.5/TS strict) — 21 sections, excellent but single-file context hog | **ADAPT (frontmatter + split)** | **Do not drop in.** Split into `SKILL.md` router + `references/` per concern (rendering, Nitro, Pinia, UI, testing, verification), then place at `roles/mobile-web-eng/.opencode/skills/nuxt-dev/` or `roles/ui-ux-designer/.opencode/skills/nuxt-dev/`. No fleet Vue/Nuxt owner today — hold split copy in staging until a consumer role confirms need. |
| `security-audit` (154) — OWASP Top 10 checklist (A08 numbering skipped — note), secret regexes, C#/Go/TS checks, risk-rated report template; only `npm audit`/`dotnet list`/`nancy` at agent-run time | **ADOPT** | `roles/appsec-engineer/.opencode/skills/security-audit/SKILL.md` (alongside existing `owasp-reachability-triage/`) + `roles/threat-modeler/.opencode/skills/security-audit/SKILL.md` + `roles/cloud-sec-auditor/.opencode/skills/security-audit/SKILL.md`. Optional: backfill A08 numbering. |
| `tailwind-ui` (248, v3/v4) — mobile-first, class dark-mode, v4 `@theme`, CVA Button/Card layouts, a11y checklist | **ADOPT** | `roles/ui-ux-designer/.opencode/skills/tailwind-ui/SKILL.md` + `roles/design-system-eng/.opencode/skills/tailwind-ui/SKILL.md` (check overlap with `impeccable-taste`/`storybook-component-tokenization` first) + `roles/mobile-web-eng/.opencode/skills/tailwind-ui/SKILL.md` |
| `tdd` (129) — Red-Green-Refactor cycle, C#/Go/TS `OrderService` templates, per-cycle checklist | **ADOPT** | `roles/tester/.opencode/skills/tdd/SKILL.md` (alongside existing `coverage-verification/`; legacy `bash`-dialect allow-list already covers `npm test/vitest/pytest/cargo test/go test` + `bash *` deny — no permission change) + `roles/release-qa-officer/.opencode/skills/tdd/SKILL.md`, `roles/api-contract-tester/.opencode/skills/tdd/SKILL.md` |
| `typescript-astro` (227, Astro 4+/5+) — strict TS, islands, content collections, SSR/SSG, SEO snippet, Lighthouse gate | **ADOPT** | `roles/ts-node-fullstack/.opencode/skills/typescript-astro/SKILL.md` + `roles/ui-ux-designer/.opencode/skills/typescript-astro/SKILL.md` |

Batch 4 answers: (1) `go-expert` is drop-in ready — keep alongside `idiomatic-go-service-development`, no permission change; (2) `security-audit` is drop-in ready for `appsec-engineer` + `threat-modeler` (+ `cloud-sec-auditor`), alongside `owasp-reachability-triage`; (3) `tdd` is drop-in ready for `tester` alongside `coverage-verification`; (4) `git-flow` is drop-in ready for `git-drift-coord`; (5) `tailwind-ui` + `typescript-astro` are drop-in ready for `ui-ux-designer` + `ts-node-fullstack` (+ `design-system-eng`/`mobile-web-eng` after overlap check); (6) `nextjs-dev` needs only a frontmatter header; `nuxt-dev` needs frontmatter + size split. All 8 ADOPT skills need **no shell-permission changes** (guidance-only, zero load-time network).

### Batch 5: MCP Servers & Tooling Infrastructure

Sources: `docs/mcp-quick-reference.md` (12 servers, full configs + token table), README MCP tables, `configs/` (4 example configs: starter/go/astro/dotnet), `data/plugins/{ejentum-mcp,with-context-mcp,crawlberg}.yaml`.

**Ranked recommendations (fleet `opencode.json` dialect: `mcp.servers` + pinned `npx -y pkg@version`; secrets via `{env:VAR}` or `${VAR}` runtime merge, never committed):**

| Rank | MCP server (package / transport) | Verdict | Target role file(s) |
|---|---|---|---|
| 1 | Context7 remote (`https://mcp.context7.com/mcp`, ~0.5–1k tokens) — already fleet-proven as `@upstash/context7-mcp@4.4.2` local in `go-backend-eng` | **ADOPT (standardize)** | Keep per-role; extend to `k8s-orchestrator`, `cloud-platform-eng`, `static-analysis-lead` where missing. Prefer remote URL form for new roles (less subprocess overhead). |
| 2 | gopls (`gopls mcp` local; needs `go install golang.org/x/tools/gopls@<pinned>`) | **ADOPT** | `roles/go-backend-eng/opencode/opencode.json` (+ `engine-systems-eng` if Go-adjacent). Requires Dockerfile layer pinning gopls version — new pin, verify before merge. |
| 3 | Postgres read-only (`@modelcontextprotocol/server-postgres@0.6.2` + `${POSTGRES_READONLY_URL}`) — already fleet-proven in `dba-specialist` with true read-only DB role (GRANTs, per charter §4) | **ADOPT (keep, no change)** | `roles/dba-specialist/opencode/opencode.json` as-is. Template for any new DB-touching role. Never widen to writer without DB-layer GRANT change. |
| 4 | Playwright (`@playwright/mcp`, ~1k tokens, disabled-global/enabled-per-agent) | **ADOPT (per-agent pattern)** | `roles/e2e-browser-qa/opencode/opencode.json` (`playwright_*` allow only there); complements `browserless:chromium:v2.24.2` sidecar. Follow `configs/opencode-astro.jsonc` pattern (`tools: {playwright_*: false}` global). |
| 5 | Filesystem / SQLite / Fetch / Puppeteer (`@modelcontextprotocol/server-*`, ~200–300 tokens) | **ADOPT (selective)** | SQLite/Fileops only where a role justifies local DB/file tools (`data-pipeline-eng`, `observability-eng`); Fetch/Puppeteer only for web-ingest roles (prefer `firecrawl:2.10.19` sidecar + SearXNG for bulk crawl). |
| 6 | Docker (`@docker/mcp`, local socket) | **ADAPT** | `roles/k8s-orchestrator` / `cloud-platform-eng` only, and only against `docker-socket-proxy:0.3.0` read-only posture (GET-only; POST/BUILD/EXEC/AUTH=0). Never raw `/var/run/docker.sock`. |
| 7 | Composio gateway (remote, `X-Composio-Api-Key: {env:...}`, ~500 meta-tool tokens) | **ADAPT** | Single-gateway alternative to N individual servers for integration-heavy roles; keeps per-turn token flat. Requires `COMPOSIO_API_KEY` runtime secret + toolset scoping (`X-MCP-Toolsets`). Pilot one role before fleet. |
| 8 | Sentry remote (OAuth) / GitHub remote (OAuth, **10–15k tokens ⚠️**) / Grep (`https://mcp.grep.app`) | **ADAPT (gated)** | Sentry → `sre-incident-eng`/`observability-eng` (OAuth via `opencode mcp auth`, disabled by default). GitHub → `pr-reviewer`-equivalent only (`github_*: false` global, per-agent allow per `configs/opencode-starter.jsonc`). Grep → code-search roles with global-disable default. |
| 9 | Redis (`@redis/mcp-redis`) / MongoDB (`@mongodb-js/mongodb-mcp`) / Supabase (`@supabase/mcp-server-supabase`) / Notion (`@notionhq/mcp` — confirm canonical name; README links `makenotion/notion-mcp-server`) / Slack (`@modelcontextprotocol/server-slack`) / Stagehand (`@browserbasehq/stagehand-mcp`) | **ADAPT (per need)** | Only where a role charter demands it (`cache-streaming-eng`→Redis, `data-pipeline-eng`→Mongo/Supabase, docs roles→Notion, `tpm-scrum-lead`→Slack/Linear). Each needs secret env (`REDIS_URL`, `SUPABASE_*`, `LINEAR_API_KEY`) via runtime merge. |
| 10 | Crawlberg (`@xberg-io/opencode-crawlberg` plugin + `crawlberg` CLI, `scope: [global, project]`) | **ADAPT** | Same vendor as tree-sitter pack; crawl/scrape/map→Markdown complements Firecrawl sidecar for agent-local fetch. Pin CLI version; compare against Firecrawl sidecar before fleet. |
| — | Ejentum (`ejentum/ejentum-mcp`: `harness_reasoning/code/anti_deception/memory` prompt-tools) / With-Context MCP (`boxpositron/with-context-mcp`: markdown notes) | **ADAPT (pilot)** | Ejentum → `system-architect` reasoning pilot; With-Context → `tech-docs-lead`. Both YAMLs lack command/transport — resolve install before use. |
| — | **Quarantine: `k8s-mcp`, `go-dev-mcp`, `firecrawl-mcp`, `opencode-mcp`, `opencode-litellm`** (all bare `npx -y <unscoped>`, no pin) | **REJECT until verified** | Do NOT add to any `opencode.json`. Resolve to exact scoped `@org/pkg@version` + hash, confirm registry ownership (typosquat risk), then re-propose. K8s need is real (`k8s-orchestrator`) — fill with verified `kubernetes-sigs` build, not bare `k8s-mcp`. Custom-builds (dotnet-mcp, Terraform, AWS bedrock, Azure) likewise need manual build + pin, not blind `npx`. |

Batch 5 answers: (1) Postgres → keep pinned `@modelcontextprotocol/server-postgres@0.6.2` + read-only GRANT role (proven); Redis → `@redis/mcp-redis` scoped-candidate for `cache-streaming-eng`; (2) K8s → real need, no verified package in source — bare `k8s-mcp` quarantined, build from `kubernetes-sigs` + pin; cloud (AWS/Azure/Terraform/Vercel/Cloudflare) → custom/remote, no copy-paste config in source; (3) Context7/Grep/DevDocs — Context7 verified (remote URL + fleet-local pin both good), Grep verified URL but keep globally disabled, DevDocs/Dash absent from source (gap).

### Batch 6: Security, Sandboxing & Telemetry

Sources: `data/plugins/` (15 files: 14 stubs + enriched `opencode-telemetry.yaml`) + techbuzzz README §Security (3 rows) + §Security Checklist (`{env:VAR}`, `opencode.jsonc.local` gitignore, Envsitter, skill-permission, audit-skills-for-network-calls).

| Candidate | Verdict | Rationale | Target component |
|---|---|---|---|
| Envsitter Guard (`boxpositron/envsitter-guard`) — `.env*` read/edit guard, fingerprint-only inspection | **ADAPT (verify hooks)** | Only true `.env` value-redaction guard; directly enforces secret hygiene + `.gitignore` discipline. Stub YAML — must prove v2 hook coverage (read/edit/tool-call) in staging. | Fleet-wide after staging; `appsec-engineer` + `cloud-sec-auditor` first |
| CC Safety Net (`kenryu42/claude-code-safety-net`) — destructive git/fs interceptor | **ADAPT (port check)** | Described as Claude Code plugin — OpenCode-v2 port unverified. If ported, it backstops prefix-match weakness (`git status; <payload>` matches `git status*`) documented in `AGENTS.md` §4. Never a substitute for deny tails + resource-layer GRANTs/kube RBAC. | Staging port; `git-drift-coord`, `sre-incident-eng` |
| Cupcake (`eqtylab/cupcake`, in `data/projects/`) — OPA/Rego policy layer, native OpenCode plugin claim | **ADAPT** | Only full policy engine; natural backstop for Safety Net + Envsitter. Needs Rego policy-as-code workflow (versioned policies, `--dry-run` parity per script standards) + v2 hook verification. Heaviest lift in batch. | `appsec-engineer` / `compliance-auditor` policy pilot |
| Opencode Log Sanitizer (`errhythm/opencode-log-sanitizer`) — redacts JWTs/bcrypt/base64/long strings in pastes | **ADOPT (after verify)** | Complements Envsitter (paste-hygiene vs file-guard) + saves tokens. Same v2-hook proof needed. | Fleet-wide candidate with Envsitter |
| Opencode Ignore (`lgladysz/opencode-ignore`) — pattern-based file exclusion | **ADOPT (scoped)** | Perimeter reduction, defense-in-depth with Envsitter (not secret-aware itself). Trivially scopeable per role. | Per-role `ignore` patterns, `dba-specialist`/`appsec-engineer` first |
| Shell Strategy (`JRedeker/opencode-shell-strategy`) — instruction file vs hanging interactive commands | **ADOPT** | Version-agnostic, zero hook risk; non-TTY hang avoidance helps unattended `--auto` runs. | Fleet instruction snippet / `sre-incident-eng` |
| Command Inject (`shihyuho/opencode-command-inject`) — auto-exposes Makefile/npm scripts/skills at startup | **REJECT (default)** | Expands command surface — inverse of least privilege; auto-exposed scripts must each be allow-listed anyway. Convenience ≠ security. | — |
| System Prompt Logger (`tlinhart/opencode-system-prompt-logger`) — logs system prompt pre-LLM | **ADAPT (treat logs as sensitive)** | Audit/forensics value, but logs may contain injected secrets — needs redaction + retention policy before use. Pair with Sanitizer. | `observability-eng` forensics pilot only |
| opencode-plugin-otel (`DEVtheOPS/opencode-plugin-otel`) — OTLP/gRPC export (Datadog/Honeycomb/Grafana), session/token/cost/tool/git signals | **ADAPT (opt-in only)** | Only cloud-export OTEL path; matches `jaeger:1.63.0` (`COLLECTOR_OTLP_ENABLED=true`, `observability` profile) + `litellm` gateway signals. Exfil-by-design — endpoint config audited, never fleet-default. Prefer local SQLite telemetry first. | `observability-eng` opt-in; Jaeger stays the default backend |
| Opencode Telemetry (`agostinilabsrl/opencode-telemetry`) — local SQLite ledger, chain rollups, `octm` CLI, no bodies, zero network | **ADAPT (pilot)** | Best fleet fit (Top-5 #4). Verify SQLite path isolation + `octm` pin + no `--auto`/shim interference. | `observability-eng` + `exec-director` pilot |
| Token Tracker (`eserete/opencode-token-tracker`) / Quota (`slkiser/opencode-quota`) / Usage Monitor (`Mark1708/opencode-usage-monitor`, OpenAI/Z.AI only) / Token Monitor (`Ainsley0917/opencode-token-monitor`, richest analytics) / Tokenscope (`ramtinJ95/opencode-tokenscope`, thinnest) / Throughput (`Howardzhangdqs/opencode-throughput`, only TTFT/TPS perf) / Context Analysis (`IgorWarzocha/...`, token analysis) | **ADAPT (pick ONE)** | Seven overlapping cost/toast/sidebar plugins — adopting several = duplicate instrumentation + toast spam. Pick one after bake-off: Token Monitor (analytics) vs Token Tracker (zero-config) vs Throughput (perf-only). Usage Monitor too narrow (2 providers). | Bake-off on `observability-eng`; single winner fleet-wide |

Batch 6 answers: (1) secret-masking = Envsitter Guard (files) + Log Sanitizer (pastes) — the pair to adopt; (2) telemetry = local SQLite plugin (default) + OTEL exporter (opt-in) both converge on existing Jaeger sidecar (`4317/4318` OTLP, `16686` UI, loopback-bound); (3) **no plugin provides true argv-level sandboxing** — Safety Net (command interceptor) + Cupcake (OPA/Rego) are gates, not sandboxes; the documented prefix-match + MCP-namespace bypass limitations stand. True containment remains Docker-side (socket proxy GET-only, `no-new-privileges`, profile-gated `devsec`/`mobile`, read-only mounts) + DB/kube resource-layer enforcement, not any catalog plugin.

---

## 3. Immediate Action Plan

Phased for least risk. Every step respects: `set -euo pipefail` + `shellcheck` for scripts, `--dry-run`/`--help` for state-changing scripts, `make test` + `bash scripts/smoke-test.sh --check-only` before commit, zero-`:latest`, deny-tail preservation (fleet `shell *` deny / legacy `bash *` deny — `smoke-test.sh` §3/§3b enforces), secrets via runtime env only.

### Phase A — Drop-in skills (no permission changes, no network at load)

Copy each source `SKILL.md` verbatim; target dirs use the fleet skill path `roles/<role>/.opencode/skills/<skill>/SKILL.md` (note: live `opencode.json` `skills` arrays variously point at `/roles/<id>/skills` while skills live under `.opencode/skills/` — confirm the loader resolution for each touched role with `smoke-test.sh --check-only` after copying; do not "fix" paths wholesale in this wave):

```bash
# 1. go-expert -> go-backend-eng (keeps existing idiomatic-go-service-development/)
mkdir -p roles/go-backend-eng/.opencode/skills/go-expert
cp references/awesome-opencode-techbuzzz/skills/go-expert/SKILL.md roles/go-backend-eng/.opencode/skills/go-expert/SKILL.md

# 2. security-audit -> appsec-engineer + threat-modeler (+ cloud-sec-auditor)
for r in appsec-engineer threat-modeler cloud-sec-auditor; do
  mkdir -p roles/$r/.opencode/skills/security-audit
  cp references/awesome-opencode-techbuzzz/skills/security-audit/SKILL.md roles/$r/.opencode/skills/security-audit/SKILL.md
done

# 3. tdd -> tester + release-qa-officer + api-contract-tester (alongside coverage-verification/)
for r in tester release-qa-officer api-contract-tester; do
  mkdir -p roles/$r/.opencode/skills/tdd
  cp references/awesome-opencode-techbuzzz/skills/tdd/SKILL.md roles/$r/.opencode/skills/tdd/SKILL.md
done

# 4. git-flow -> git-drift-coord (+ tpm-scrum-lead reference)
for r in git-drift-coord tpm-scrum-lead; do
  mkdir -p roles/$r/.opencode/skills/git-flow
  cp references/awesome-opencode-techbuzzz/skills/git-flow/SKILL.md roles/$r/.opencode/skills/git-flow/SKILL.md
done

# 5. tailwind-ui + typescript-astro -> ui-ux-designer + ts-node-fullstack (+ design-system-eng/mobile-web-eng after overlap check)
for r in ui-ux-designer ts-node-fullstack design-system-eng mobile-web-eng; do
  mkdir -p roles/$r/.opencode/skills/tailwind-ui roles/$r/.opencode/skills/typescript-astro
  cp references/awesome-opencode-techbuzzz/skills/tailwind-ui/SKILL.md roles/$r/.opencode/skills/tailwind-ui/SKILL.md
  cp references/awesome-opencode-techbuzzz/skills/typescript-astro/SKILL.md roles/$r/.opencode/skills/typescript-astro/SKILL.md
done

# 6. code-review -> static-analysis-lead + release-qa-officer + appsec-engineer
for r in static-analysis-lead release-qa-officer appsec-engineer; do
  mkdir -p roles/$r/.opencode/skills/code-review
  cp references/awesome-opencode-techbuzzz/skills/code-review/SKILL.md roles/$r/.opencode/skills/code-review/SKILL.md
done

# 7. dotnet-expert -> stage for api-contract-tester (no dedicated dotnet role; verify consumer first)
mkdir -p roles/api-contract-tester/.opencode/skills/dotnet-expert
cp references/awesome-opencode-techbuzzz/skills/dotnet-expert/SKILL.md roles/api-contract-tester/.opencode/skills/dotnet-expert/SKILL.md

# 8. nextjs-dev -> add missing frontmatter, then ts-node-fullstack + mobile-web-eng
# Prepend:
#   ---
#   name: nextjs-dev
#   description: Use when building with Next.js App/Pages Router: server/client boundaries, data caching, mutations, security, a11y, verification.
#   license: MIT
#   compatibility: opencode
#   ---
```

Then: `make test && bash scripts/smoke-test.sh --check-only`. `nuxt-dev` stays in staging (frontmatter + split into `SKILL.md` + `references/` before any role placement).

### Phase B — One pinned plugin in the image (Tree-sitter)

1. Resolve exact versions upstream: `npm view @xberg-io/opencode-tree-sitter-language-pack versions` + the `tree-sitter-language-pack` CLI release; choose exact pins (e.g. `@xberg-io/opencode-tree-sitter-language-pack@X.Y.Z`, CLI `vA.B.C`).
2. `docker/Dockerfile`: extend the pinned `ENV` block + global `npm install` with the new package; add `npm ls --global --depth=0` assertion; install the CLI binary pinned (same layer, version-asserted).
3. Per-role allow-list (example `static-analysis-lead`): add the plugin's tool-namespace allow + `tree-sitter*` shell allow **above** the terminal `shell *` deny; keep the deny tail last. Repeat for `binary-reverse-eng`, `vector-rag-spec`, `go-backend-eng` only.
4. `make build && make test && bash scripts/smoke-test.sh --check-only`.

### Phase C — Selective MCP additions (per-role `opencode.json`, never global-enable heavy servers)

- `go-backend-eng`: add `"gopls": {"type": "local", "command": ["gopls", "mcp"], "enabled": true}` once gopls is pinned in the image (Phase B step 1 pattern).
- `e2e-browser-qa`: add Playwright local MCP with `"enabled": false` globally + `"tools": {"playwright_*": false}` + per-agent allow for the e2e agent only (exact `configs/opencode-astro.jsonc` pattern).
- `sre-incident-eng` / `observability-eng`: Sentry remote + OAuth (`opencode mcp auth sentry`), `"enabled": false` default.
- `k8s-orchestrator` / `cloud-platform-eng`: **no MCP change this wave** — quarantined `k8s-mcp` must first resolve to a verified scoped build; Docker MCP only against `docker-socket-proxy` GET-only posture if piloted.
- `dba-specialist`: no change (pinned Postgres + read-only GRANT role stays the template).

### Phase D — Staging pilots (verify before fleet; each needs upstream README read + version pin + v2-hook proof vs `@opencode/cli@2.0.32` + shim `--auto` test)

1. Envsitter Guard + Log Sanitizer + Ignore (secret hygiene) → `appsec-engineer` first.
2. `opencode-telemetry` (SQLite) → `observability-eng` + `exec-director`; single token-plugin bake-off winner alongside.
3. `opencode-review` (review-only, auto-fix OFF) → `static-analysis-lead`.
4. OpenCodeRAG vs Qdrant bake-off → `vector-rag-spec` (watch mode OFF except indexer).
5. `opencode-arise` + `opencode-agent-identity` + `cli-subagent-output` → `exec-director` orchestration observability.
6. OTEL exporter (opt-in) → `observability-eng` → Jaeger `127.0.0.1:16686`.

### Explicitly deferred

FlowDeck/CrewBee/Ensemble/Swarm/Conclave/hiai/BMAD-as-fleet, Honcho-cloud, `opencode-mem`-name-collision plugin, PR Auto-Signature fleet-wide, Command Inject, quarantined unscoped MCPs, custom-build MCPs (dotnet/Terraform/AWS/Azure) without pins, `nuxt-dev` unsplit, any Compose sidecar addition (no new sidecar required — Qdrant, Neo4j, Jaeger, LiteLLM, Firecrawl, Browserless, Semgrep already cover the recommended backends).

### Verification checklist (close-out)

- [ ] `make test` (39/39 shim assertions) green
- [ ] `bash scripts/smoke-test.sh --check-only` green (deny tails §3/§3b, pins, no `:latest`)
- [ ] `shellcheck` clean on any touched script
- [ ] Per-touched-role `opencode.json` still ends in its dialect's deny tail; no dangling allow without consumer
- [ ] No secret committed (`.env` ignored, `{env:VAR}`/`${VAR}` only, `opencode.jsonc.local` pattern for local overrides)
- [ ] This report's Top-5 each has an owner role + next command (Phase A→D above)
