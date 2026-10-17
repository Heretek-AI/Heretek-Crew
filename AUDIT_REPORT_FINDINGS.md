# Adversarial Three-Subagent Fleet & Architecture Audit — Findings

**Target:** `/home/john/Projects/Heretek-Crew`
**Date:** 2026-10-17 | **Prompt:** `PROMPT_ADVERSARIAL_FLEET_AUDIT.md` (11 domains)
**Formation:** Alpha (Runtime & Functionality) + Beta (Version Modernity) + Gamma (Security/Sandbox)
**Rule:** Tests were NOT trusted. Every verdict below rests on file reads, shell probes, and registry checks — not on `test-shim.sh` / `smoke-test.sh` exit codes.
**Controller spot-verification (2026-10-17):** `ls roles/ | wc -l` = 51; 51/51 `opencode.json` end with `{shell,*,deny}` as last entry; 51/51 declare scoped `@heretek-ai/opencode-harness`; `FLEET_BUDGET_CAP_CENTS=1300000`; socket-proxy `tecnativa/docker-socket-proxy:0.3.0` with `POST/BUILD/EXEC/VOLUMES/NETWORKS=0`; `dispatch-pipeline.sh` contains zero `curl`/`/api/` calls by design.
**Supersedes:** prior `AUDIT_REPORT_FINDINGS.md` (2026-10-16). Resolved since then: bare `plugins:["opencode-harness"]` (now scoped 51/51), 6 legacy `bash`-dialect roles (deleted), gotenberg/rabbitmq/redis/semgrep/qdrant/jaeger bumps. New findings below replace stale prompt baselines — the prompt's Domain 11 version table itself is outdated (lists searxng 2024.10.16, firecrawl 2.10.19-mutable, gotenberg 8.15.0, browserless v2.18.0, radare2 5.9.8, semgrep 1.96.0, piston v2.0.0, litellm v1.52.16, qdrant v1.12.1, neo4j 5.26.0, ollama 0.4.4, mailpit v1.21.4, minio 2024-11-07, jaeger 1.62.0, mitmproxy 11.0.1, socket-proxy 0.1.1 — most already rotated in-tree; do not re-file those as defects).

---

## P0 / Critical (broken execution, fatal security, defunct registry)

### P0-1. Harness 1.0.7 DIES on load under `@opencode/cli@2.0.32` — all 51 roles' `harness_*` surface is dead (Claims 4.1–4.3 broken in function, true in config)
- **Files:** `docker/Dockerfile:33-53`; all 51 `roles/*/opencode/opencode.json` (`plugins`, `harness_*` allows).
- **Claim:** Domain 4 provides FNV-1a `file_hash_edit`, AST transforms, blast-radius, doom-loop breakers.
- **Proof:** Beta verified config true (51/51 scoped plugin + ≥1 `harness_*` allow) but `docker/Dockerfile:36-53` documents 1.0.7 dies on load (empty-string `directory` → `resolveHarnessOptions({rootDir:""})` throws; every harness tool reads "not available"), fix unlanded, publish gate designed to FAIL until bump. Prior audit proved live: fixture `opencode run` replied "tool `file_hash_read` is not available", debug log `Die(Error: opencode-harness: rootDir must be a non-empty string)`. Controller confirms pins still `@opencode/cli@2.0.32` + `harness@1.0.7` in-tree.
- **Command:** `grep -n "opencode-harness\|rootDir\|Die" docker/Dockerfile; grep -l "heretek-ai/opencode-harness" roles/*/opencode/opencode.json | wc -l` → 51.
- **Fix (fail-closed, upstream + repo gate):**
```diff
- inferredRoot = ctx?.directory ?? ctx?.worktree ?? ctx?.location?.directory ?? ctx?.location?.worktree ?? process.cwd()
+ const pick = (v) => (typeof v === "string" && v.trim() !== "" ? v : undefined);
+ inferredRoot = pick(ctx?.directory) ?? pick(ctx?.worktree) ?? pick(ctx?.location?.directory) ?? pick(ctx?.location?.worktree) ?? process.cwd()
```
Then bump harness pin, add publish-gate live test asserting a harness tool call succeeds (not just `npm ls`), re-run live `run` visibility check.

### P0-2. Claim 3.3 FALSE — "read-only" roles hold 4 file-mutating harness tools (universal read-only bypass)
- **Files:** all 51 `roles/*/opencode/opencode.json` (e.g. `roles/exec-director/opencode/opencode.json:142-161`).
- **Claim:** Domain 3 Claim 3.3 — executive/PM/docs/auditing roles cannot execute code modification.
- **Proof:** Gamma + controller: `exec-director` scopes `fs:write` to docs + `fs:write * deny`, but allows with `resource:"*"` the mutating `harness_file_hash_edit`, `harness_ast_structural_rewrite`, `harness_rename_symbol`, `harness_checkpoint_rollback`. Affected: `exec-director`, `product-director`, `threat-modeler`, `compliance-auditor`, `tech-docs-lead`, `ux-research-analyst`. `smoke-test.sh` asserts harness uniformity, not least-privilege; nothing proves harness consults `fs:write` scoping.
- **Command:** `grep -rn "harness_file_hash_edit\|harness_ast_structural_rewrite\|harness_rename_symbol\|harness_checkpoint_rollback" roles/exec-director/opencode/opencode.json`
- **Fix (fail-closed):** strip the 4 from every read-only-charter role; replace with denies:
```json
{ "action": "harness_file_hash_edit", "resource": "*", "effect": "deny" },
{ "action": "harness_ast_structural_rewrite", "resource": "*", "effect": "deny" },
{ "action": "harness_rename_symbol", "resource": "*", "effect": "deny" },
{ "action": "harness_checkpoint_rollback", "resource": "*", "effect": "deny" }
```
Add smoke assertion: role without non-docs `fs:write` allow MUST NOT allow those 4. Retract Claim 3.3 until landed (blocked on P0-1 for live verify).

### P0-3. XDG isolates config only — all agents share one UID/filesystem/env (Claim 3.1 overstated)
- **Files:** `docker-compose.yml:100-130` (single `paperclip` container), `docker/Dockerfile:90-95` (children UID 1000), `scripts/seed-50-fleet.sh:435` (`XDG_CONFIG_HOME=/roles/<id>`).
- **Claim:** Domain 3 Claim 3.1 "per-role isolation … without modifying workspace git".
- **Proof (Gamma):** one UID, one mount ns, one RW `/paperclip/workspaces`, one RO kubeconfig mount. 48/51 roles hold `fs:read **` allow; no `fs:read` deny covers `secrets/`, `*.kubeconfig`, `*token*`. `docker-compose.yml:86-117` puts superuser `DATABASE_URL` (embedded `POSTGRES_PASSWORD`), `GITHUB_TOKEN`, 11 provider keys into server env; scrub code lives in `/tmp/paperclip` upstream (outside repo, commit unrecorded — `docker/Dockerfile:21` `PAPERCLIP_SOURCE_COMMIT=<paste-…-here>`). Dba `shell psql* deny` moot if child inherits superuser URL.
- **Command:** `grep -n "DATABASE_URL\|GITHUB_TOKEN\|XDG_CONFIG_HOME" docker-compose.yml scripts/seed-50-fleet.sh | head`
- **Fix:** (a) mount kubeconfig only into k8s-orchestrator runtime (or FD-passed MCP env); (b) live canary test — plant canary `opencode.json`+`.opencode/` in scratch workspace, run one agent turn, assert ignored; assert child env lacks `DATABASE_URL`/`POSTGRES_PASSWORD`/`BETTER_AUTH_SECRET`/provider keys; (c) add `fs:read` denies for `**/secrets/**`, `**/kubeconfig*`, `**/*.pem`, `**/id_rsa*` above allows. Label 3.1 "config-advice, live-unverified" until canary passes.

### P0-4. Piston on shared `heretek` net = unauthenticated RCE-as-a-service reachable from any agent container
- **Files:** `docker-compose.sidecars.yml:509-549` (piston `expose:2000`, shared `heretek` net, no auth env); `:859-863` (paperclip bridges all nets).
- **Proof (Gamma):** `curl http://piston:2000/api/v2/execute` executes arbitrary code by design; sabotage-qa-tester allow `curl -s -X POST http://piston:2000/api/v2/execute*` proves intended reachability. Upstream OSS has no auth knob. Any shell-prefix bypass (P1-1) or SSRF anywhere on shared net reaches it. Ghidra `:1337`/radare2 `:9090` correctly segmented to `heretek-devsec` but paperclip-as-bridge residual remains (admitted in-file).
- **Command:** `grep -n "piston\|expose\|networks" docker-compose.sidecars.yml | sed -n '1,40p'`
- **Fix:** move piston to isolated net (paperclip-only access like devsec); front `:2000/:9090/:1337` with shared-secret sidecar proxy / per-request tokens mounted only into needing roles; never co-schedule devsec with untrusted workloads (enforce in Makefile guard, not comments).

---

## P1 / High (deprecated, escape vectors, drift, false claims)

### P1-1. Shell allows are prefix-patterns, not a sandbox — `;`/`$()`/`||` bypass assumed unproven (Claim 3.2 overstated)
- **Files:** all 51 `roles/*/opencode/opencode.json` (233 `shell` entries; e.g. `roles/sabotage-qa-tester/opencode/opencode.json:73-78`, `roles/dependency-patcher/opencode/opencode.json:103-113`).
- **Proof (Gamma):** deny tail `{shell,*,deny}` verified last-entry 51/51 (controller `python3` JSON parse), but enforcer (upstream OpenCode v2 `@opencode/cli@2.0.32` + Paperclip `opencode-local` adapter, `/tmp/paperclip` outside repo) semantics unpinned; `AGENTS.md §4` concedes prefix-match (`git status; <payload>` matches if prefix-based). `npm install*`/`go get*` fetch arbitrary code inside an "allowed" prefix. `smoke-test.sh §3` checks JSON shapes only — never executes a denial.
- **Command:** `grep -rhoE '"resource": "[^"]*"' roles/*/opencode/opencode.json | sort | uniq -c | sort -rn | head -30`
- **Fix:** record enforcer semantics + version; run live probes through a real agent turn and record: `git status; id`, `git status$(id)`, `git status||id`, `npm test -- --unknown-flag`; if prefix-based, replace with argv-aware exec or signed gated actions; narrow `adb connect*` to host allowlist; never cite `smoke §3` as enforcement proof.

### P1-2. MCP namespaces bypass shell denies — structurally open where deny tails missing
- **Files:** `roles/k8s-orchestrator/opencode/opencode.json:19-28`, `roles/dba-specialist/opencode/opencode.json:14-15`, plus `playwright_*`/`chrome-devtools_*`/`mobile_*`/`r2_*`/`redis_*`/`qdrant_*` wildcards fleet-wide.
- **Proof (Gamma):** k8s `deny shell kubectl apply*/delete*` but `allow kubernetes_kubectl_get*` + `deny kubernetes_*` — safe only under deny-override semantics (unproven). Dba `deny shell psql*` but `allow postgres_query*` — safe only with DB-layer read-only role (verify live). `mobile_*`, `r2_*`, `playwright_*`, `chrome-devtools_*` have no per-namespace deny tails. MCP `filesystem_read*` may resolve paths differently from `fs:read` denies.
- **Fix:** constrain at resource layer (read-only Postgres GRANTs, read-only ClusterRole — verify live); add per-namespace MCP deny tails everywhere (extend existing docker/k8s/filesystem/git/harness pattern to playwright/chrome/mobile/r2/redis/kafka/qdrant); front piston/r2/ghidra with secret proxy.

### P1-3. Docker-socket-proxy GET-recon open to whole shared net; mandate version stale
- **Files:** `docker-compose.sidecars.yml:462-507` (`tecnativa/docker-socket-proxy:0.3.0`, mandate says `0.1.1`).
- **Proof:** env `CONTAINERS/IMAGES/INFO/VERSION=1`, `POST/BUILD/EXEC/VOLUMES/NETWORKS=0` (controller verified) — creation/exec blocked at proxy ✅, `local-ci-runner` correctly has no socket mount + `DOCKER_HOST=tcp://docker-socket-proxy:2375` + ro checkouts. Residual: `expose:2375` unauthenticated GET lets any heretek container list images/containers (`docker inspect` leaks env/secrets in layers). Every future sidecar on `heretek` inherits this.
- **Fix:** move proxy+runner to dedicated `heretek-ci` net (paperclip-only bridge) or source-IP allowlist; never publish `:2375`; never weaken POST/BUILD/EXEC; update audit prompt version to `0.3.0`.

### P1-4. Ports: one intentional all-interfaces binding (caddy 80/443, guard is Makefile-only) + firecrawl unauth SSRF on loopback
- **Files:** `docker-compose.yml:97-98` (paperclip `127.0.0.1:3100` ✅), `:227-229` (caddy `80:80,443:443` bare ⚠️, profile-gated), sidecars 14× `127.0.0.1:` ✅ (`:8888,:3002,:3003,:8081,:6081,:6333,:7474,:4000,:8025,:9001,:8089,:16686,:5555,:6080`); `sidecars.yml:191` firecrawl `HOST:0.0.0.0` container-internal behind loopback-publish + `USE_DB_AUTHENTICATION:false` (`:208`).
- **Proof (Gamma):** `guard-proxy` (`Makefile:48-61`) refuses non-`private` exposure, but raw `docker compose --profile proxy up` bypasses it — nothing technical stops internet-facing auth surface. Firecrawl `:3002` fetches arbitrary URLs with no credential = SSRF primitive for anyone with host-loopback access.
- **Fix:** compose-level refusal unless `PAPERCLIP_DEPLOYMENT_EXPOSURE=private` + non-placeholder secret; set firecrawl `USE_DB_AUTHENTICATION=true` + provisioned secret; extend smoke port assertions to all 14 loopback binds.

### P1-5. Secret hygiene: no committed secrets, but server-side env exposure real + isolation live-unverified
- **Files:** `docker-compose.yml:111` (`DATABASE_URL` embeds superuser password), `:138-148` (10+ provider keys into server env), `scripts/seed-50-fleet.sh:107,192` (`Bearer` curl, no `set -x`/echo ✅), `docker-compose.yml:170` (kubeconfig bind visible to whole server UID).
- **Proof (Gamma):** `git ls-files | grep -E "^\.env$"` empty ✅; `secrets/` only `.gitkeep` ✅; `smoke §4` greps rendered payloads, not upstream inheritance scrubbing. `OPENCODE_GO_API_KEY→OPENCODE_API_KEY` auto-export (`opencode-shim.sh:73-76`) spreads keys. Kubeconfig containment = read-only ClusterRole + `fs:read` denies (present, but order vs `**` unproven — see P1-6).
- **Fix:** move `DATABASE_URL` to password-file/secret-mount; keep only `POSTGRES_READONLY_URL` agent-reachable; require explicit opt-in for GO-key fallback (no silent export); land kubeconfig FD plan; add `set +x` + Bearer masking in seed script; run canary + `id -u==1000` live gates.

### P1-6. `fs:read` `.env` denies ordered AFTER `fs:read **` allow — dead under first-match semantics
- **Files:** every role file (e.g. `roles/exec-director`, `roles/dba-specialist`): `fs:read **` allow first, four `.env` denies ~10 entries later. `fs:write * deny` correctly last.
- **Proof (Gamma):** if first-match-wins, `**` matches `.env` before deny consulted → 48 `**`-reader roles read any workspace `.env`. Neither semantics pinned/documented/live-tested.
- **Fix:** move all `fs:read … deny` ABOVE any `fs:read … allow` in every role + generator `scripts/generate-50-roles.py`; add live negative test (`read .env` must be denied).

### P1-7. Dispatch pipeline claims vs reality (Claims 7.1, 7.2 false as stated; implementation honest)
- **File:** `scripts/dispatch-pipeline.sh:4-17` (header admits provisioner-tracer), `:132`, `:182-184`.
- **Proof (Alpha):** `grep -n "curl\|PAPERCLIP_URL\|/api/\|poll" scripts/dispatch-pipeline.sh` → header lines only stating it does NOT call the API. Execute mode provisions only phase 3 (worktree + `task_plan.md`); phases 1/2/4/5 print MANUAL lines; phase 6 never merges. Controller: `grep -c` = 1 (header comment). Prior report's `exit 1` claim needs re-check — current header frames non-zero as intentional tracer signal; either way happy-path CI gating is misleading.
- **Fix:** rewrite prompt Claims 7.1/7.2 as provisioner-tracer (promote header into docs), or implement `--fail`-checked Paperclip ticket transitions `todo→in_progress→in_review→done`; make execute mode exit 0 on successful provisioning; fix dry-run "Emitted PRD task" wording (nothing emitted).

### P1-8. Domain 8 claims contradict remediated implementation (Claims 8.1, 8.2 false as stated; code is GOOD)
- **Files:** `docker-compose.sidecars.yml:486-498` (`POST/BUILD/EXEC/VOLUMES/NETWORKS=0`, only `CONTAINERS/IMAGES/INFO/VERSION=1`), `:826` (`ghcr.io/catthehacker/ubuntu:act-22.04`, `sleep infinity`, `DOCKER_HOST=tcp://docker-socket-proxy:2375`).
- **Proof (Alpha):** proxy answers 403 to `POST /containers/create` — `act` cannot execute via socket; mutating CI must run on host (compose comments `:815-825` admit this). Prompt's "allows creation/builds, runs ci.yml inside Docker" is inverted: actual `0.3.0` (not `0.1.1`) blocks creation. Piston tag `v2.0.0` never existed — actual digest-pinned (`:534`).
- **Fix:** correct Claims 8.1/8.2 to read-only-observer semantics; fix dispatch phase-5 text to host `act`.

### P1-9. Seeder live-idempotency unproven + prompt-stale (`seed-company.sh` absent, budget figure wrong)
- **File:** `scripts/seed-50-fleet.sh:599-686` (Pass 1 create + Pass 2 drift-only PATCH, `--fail-with-body` ✅); `ls scripts/seed*` → only `seed-50-fleet.sh` (no `seed-company.sh`).
- **Proof (Alpha):** dry-run verified 52 docs (1 company + 51 agents), `dangerouslySkipPermissions:false` ×51, XDG ×51, 49 disabled + exec-director 1800s + tpm 3600s, budget 1300000¢ (controller: cap `1300000`, `ROLE_LIST` = 51 agents per `:539` message — prior-report "50 wired + ai-red-teamer absent" appears resolved; re-verify `ROLE_LIST` count in current tree). Live two-pass rerun diff never executed (needs `make up`). Prompt budget "1,279,000¢/$12,790" matches neither code (1,300,000¢/$13,000) nor prior 1,270,000¢ — prompt stale.
- **Command:** `bash scripts/seed-50-fleet.sh --dry-run 2>&1 | head -30; ls scripts/seed*`
- **Fix:** rewrite prompt 5.1 (drop `seed-company.sh`), 5.3 (1,300,000¢); add live rerun-diff gate (needs stack).

### P1-10. Worktree archive litters on failed remove + same-second collision (Claim 6.2 "force-removing" false)
- **File:** `scripts/worktree-manager.sh:53` (branch `ticket-<id>` dash, not prompt's `ticket/<id>` slash), archive staging → `git worktree remove` (no `--force`, good) may fail 128 leaving partial `.worktrees/archive/<t>-<ts>/`; `mkdir -p` reuses same-second dirname (no `$RANDOM` guard unlike `backup-db.sh:106-116`).
- **Proof (Alpha, live):** dirty-worktree archive run left `audit-probe-…-20261017-130427/` after failed remove; retry reused identical dirname.
- **Fix:** stage to temp + rename on success (or remove archive dir when `remove` fails); add `$RANDOM` same-second guard; fix prompt branch name + drop "force-removing".

### P1-11. Claim 3.1 enforcement code not in repo — XDG/`OPENCODE_DISABLE_PROJECT_CONFIG` rest on unaudited upstream
- **Files:** `scripts/seed-50-fleet.sh:432-436` (emits `adapterConfig.env`); `docker-compose.yml:91` (`OPENCODE_DISABLE_PROJECT_CONFIG=true`); `docker/Dockerfile:21` (source commit placeholder).
- **Proof (Gamma):** `prepareOpenCodeRuntimeConfig` lives in `/tmp/paperclip` upstream, unpinned. `smoke §10` string-greps rendered config, never spawns an agent observing which config won.
- **Fix:** pin Paperclip source commit in `docker/Dockerfile` + `NOTES.md`; run canary live test (P0-3); label 3.1 "config-advice, live-unverified".

### P1-12. Dockerfile root-build + gosu-drop split-brain; base image mutable (Claim 1.3 live-unverified)
- **Files:** `docker/Dockerfile:77` (`USER root`, no later `USER`), `:113-115` (`chown node:node`), `:130-147` (drop via inherited entrypoint `gosu node`), `docker-compose.yml:153` (`./roles:/roles:ro`), `docker-compose.yml:90` (`heretek-crew/paperclip:wave1`, base `ghcr.io/paperclipai/paperclip:sha-73659c6` — 7-hex pseudo-tag, opaque).
- **Proof (Alpha/Beta/Gamma):** `imagetools inspect` resolves base (`sha256:b12822a3…`, amd64+arm64 ✅) but short-SHA tag ungreppable; production builds from `paperclip:official-local` whose source commit unrecorded. If base entrypoint changes or `PAPERCLIP_BASE_IMAGE` overridden, server + 51 children run as root; `/roles` `755 node:node` at build + `ro` at run is correct layering but root breaks it.
- **Fix:** record `PAPERCLIP_SOURCE_COMMIT` (`git -C /tmp/paperclip rev-parse HEAD`); constrain `PAPERCLIP_BASE_IMAGE` to digest pins; add `smoke §8` `id -u==1000` boot assertion in CI; consider `read_only:true` + tmpfs after live-boot verify.

### P1-13. Supply-chain concentrations: hound archived, piston tracks floating `latest`, minio 23-months-stale + auth-gated
- **Files:** `sidecars.yml:424` (`ghcr.io/hound-search/hound@sha256:5b7fd0…`, upstream `etsy/hound` archived — no future CVE fixes, digest freezes dead code; Wave C P1-14 comment exemplary but still dead code); `:534` (piston digest of upstream `latest`-only — `v2.0.0` never existed — self-vendoring to `ghcr.io/heretek-ai/piston` DECISION-NEEDED unlanded); `:685` (`quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z`, `imagetools inspect` → `401 Unauthorized`, ~23mo old, AGPLv3, Hub withdrawal).
- **Fix:** hound — vendor or migrate (livegrep/zoekt) per ranked options; piston — build from pinned source, push `ghcr.io/heretek-ai/piston:<semver>`; minio — evaluate 2026.x + localstack swap per in-file suggestion.

### P1-14. Six MCP declarations reference sidecars absent from every compose file (dead wiring)
- **Files:** `mlops-serving-eng` (`ollama-mcp@2.1.0`), `observability-eng`/`sre-incident-eng` (`prometheus-mcp-server==1.6.2`), `cache-streaming-eng` (`kafka-mcp-server==0.1.1`), `analytics-metrics-eng` (`mcp-clickhouse==0.7.0`), `load-stress-tester` (`k6-mcp-server==2.2.0`), `k8s-orchestrator`/`mlops-serving-eng` (`docker-mcp==0.2.0`) vs `grep -E "^  (kafka|clickhouse|prometheus|ollama|otel|k6)" docker-compose.sidecars.yml` → only `jaeger:`.
- **Proof (prior audit, still valid — controller did not find new services):** prompt Claims 11.5 (ollama 0.4.4)/11.7 (otel 0.113.0) describe absent services. Agents fail connection-refused.
- **Fix:** add missing services as pinned sidecars, or delete MCP declarations; minimum document "role-ready, infra-pending".

### P1-15. Unpinned MCP + obscure PyPI supply-chain drift (zero-`:latest` invariant violated in role configs)
- **Files:** `roles/binary-reverse-eng/opencode/opencode.json:253` (`@morluto/rea-mcp` bare — `npx -y` resolves `latest` each cold start); `uvx` pins `mcp-server-redis==0.1.1`, `mcp-server-kubernetes==0.1.6`, `mcp-server-qdrant==0.8.1`, `kafka-mcp-server==0.1.1`, `k6-mcp-server==2.2.0`, `mcp-clickhouse==0.7.0`, `docker-mcp==0.2.0`, `r2mcp==0.2.5`, `prometheus-mcp-server==1.6.2`; forks `@executeautomation/playwright-mcp-server@1.0.12`, `@upstash/context7-mcp@4.4.2`, `@cyanheads/git-mcp-server@2.15.3`.
- **Fix:** pin `@morluto/rea-mcp@<verified>` after `npm view` (confirm existence); `pip index versions` + provenance for each `uvx` pkg, prefer publisher-official, drop P1-14 dead entries; `npm view` each fork, migrate playwright/context7 to canonical if lagging.

---

## P2 / Medium (non-fatal lag, resourcing, doc mismatches)

- **P2-1. Shim `--variant` edge cases (Alpha, live-proven).** `scripts/opencode-shim.sh:201-203,258-267`: duplicate `--variant` last-wins (`--variant high --variant low` → `#low`) vs first-wins `--model` — inconsistent; trailing empty `--variant=` wipes prior value (`--variant high --variant=` → variant dropped silently); `--model=` empty + `--variant high` drops variant silently; dash-leading `--variant -high` (space form leaks stray positional, `=` form merges silently). Core 2.1–2.6 (strip `--dir` space/`=` forms, merge either order, `#`-guard, exactly-once `--auto` incl. `--auto=<bool>` + post-`--` exclusion, `--session` verbatim, `--` boundary byte-for-byte, exec streaming, exit-code propagation, GO-key no-clobber) VERIFIED. **Fix:** last empty `--variant=` must not clobber prior non-empty; normalize dash-leading handling; `[[ -f … ]]` in `resolve_real_bin` (`/tmp` dir passes `-x` → exit 126 `Is a directory` not clean 127); trim whitespace-only `OPENCODE_API_KEY` (`"   "` counts as set). Add `test-shim.sh` cases.
- **P2-2. Shim valueless-`--dir` swallows bare-word prompt.** `scripts/opencode-shim.sh:141-149`: `run --model m --dir prompt` → `run --model m --auto` (prompt consumed as path, exit 0 prompt-less). Prior P1-9 still open. **Fix:** fail closed — drop only `--dir`, preserve token (nonexistent-dir error louder than silent prompt loss); pin chosen behavior in `test-shim.sh`.
- **P2-3. Postgres floating minor, no digest.** `docker-compose.yml:28` `postgres:17-alpine` resolves live (`17.11-alpine3.24`, `sha256:b0f956…`, PG 19rc1 upstream) but every `pull` can move minor. File admits plan (Wave D P2-8). **Fix:** pin `17.<x>-alpine@sha256:…`, quarterly bump.
- **P2-4. Paperclip pseudo-tag provenance gap.** `sha-73659c6` 7-hex tag + unrecorded local source (see P1-12). **Fix:** record SHA, prefer semver/digest.
- **P2-5. Ghidra a full major behind + community trust + weak healthcheck.** `sidecars.yml:329` `blacktop/ghidra:11.2` vs Hub `12.1.4` current; in-file "one minor behind" comment now factually wrong; `pgrep -f ghidra` weak; community (`blacktop/`, not NSA upstream) single-maintainer trust. **Fix:** verify `:12.x`, digest-pin, probe `:1337` health.
- **P2-6. Mitmproxy a full major behind.** `:290` `11.0.2` vs Hub `12.2.3` current (prompt's 11.0.1→11.0.2 cosmetic). Test-profile gating limits blast radius. **Fix:** bump to 12.x quarterly.
- **P2-7. Mailpit ~10 minors behind; wiremock 3 behind.** `:649` `v1.21.8` vs Hub `v1.31.6`; `:710` `3.10.0-alpine` vs `3.13.x`. Test-mock severity only. **Fix:** quarterly bump.
- **P2-8. Firecrawl main mutable while 4 deps digest-pinned.** `:173` `:2.10.19` (only non-digest GHCR firecrawl pin; file admits pending plan) vs `:116,:139` + nuq/playwright digests (opaque, no human version comments). **Fix:** resolve main to digest with `#:2.10.19` comment; annotate opaque digests.
- **P2-9. `act-22.04` floating + 22.04 EOL ~6mo.** `:826` mutable tag, no digest; Ubuntu 22.04 EOL Apr 2027. Read-only-observer design sound — do not "fix" by widening proxy. **Fix:** digest-pin + plan 24.04 migration.
- **P2-10. Full-stack 32.6-CPU budget unasserted.** Every service carries `cpus`+`mem_limit` ✅ (rabbitmq 512m lean, ghidra MAXMEM-3G-vs-4g OOM edge — both admitted), but co-scheduling all profiles sums ~32.6 CPUs / ~50G+ (Beta computed) — physically impossible on one host; safety rests on profile gating + Makefile guard, no automated budget assertion. **Fix:** add full-stack budget assertion or documented co-scheduling matrix.
- **P2-11. `docker-android` resourcing + healthcheck.** `:760` `emulator_14.0_v3.8.0-p1` newest major ✅ but `cpus:2.0/mem:4g` wants 6–8g/4+ CPUs (OOM/boot-timeout risk); `:706` healthcheck assumes `adb` on PATH (unverified); `privileged+/dev/kvm` correctly isolated to `heretek-mobile` + profile-gated ✅. **Fix:** raise to 4 CPU/8g + host-requirement warning; verify healthcheck (`which adb`) else probe noVNC `:6080`.
- **P2-12. Backup/restore live-unexecuted; restore `.env` overrides CLI.** `scripts/backup-db.sh` (timestamped, `$RANDOM` collision, NUL-prune, opt-in `age` ✅, `bash -n`+`shellcheck` clean) + `scripts/restore-db.sh` (FILE required, extension allowlist, `--file=`/`--yes` parsing, no-TTY refusal, `ON_ERROR_STOP=1` ✅) — SQL path needs live postgres. `restore-db.sh:76-81` `source .env` with `set -a` overwrites explicit CLI `--file`; `:64` glob omits `*.age`; same-second `.age`→plaintext-extension collision (prior P1-10 — verify current `:95-105` still affected). **Fix:** snapshot CLI `FILE`/`RESTORE_YES` before sourcing; include `*.age` in listing; `OUTFILE=backup-${STAMP}-${RANDOM}.sql.gz${ENCRYPT:+.age}`; run backup→restore round-trip live gate.
- **P2-13. Prebuilt unpublished (safe-fail) + `latest` mint.** `docker-compose.prebuilt.yml:52` `ghcr.io/heretek-ai/heretek-crew:1.0.0` self-declares `manifest unknown`, no tags — `pull` fails closed as documented ✅; `docker-publish.yml:71` mints `:latest` (violates never-`:latest`), multi-arch `linux/arm64` backed by QEMU smoke in config only (not live-run here). **Fix:** `git tag v1.0.0`, verify manifest, digest-pin; remove `latest` tag or record exception; constrain `HERETEK_IMAGE` to digest pins.
- **P2-14. Publish gate never runs translation or plugin load (Claim 9.3 gap).** `.github/workflows/docker-publish.yml:83-106` asserts `--version` + `npm ls` — neither executes shim rewrite nor harness load (P0-1 passes gate by construction); arm64 unverified. **Fix:** gate step running fixture argv asserting `--model#variant`+`--auto` reach `opencode-bin` + plugin-load assertion (fail on `Die(`); add `linux/arm64` smoke before push.
- **P2-15. Redis 7.4 vs 8.x note; dual redis share one password; rabbitmq leanness; jaeger residue.** `redis:7.4.11` fixes CVE-2025-49844 ✅ — staying on 7.4 LTS vs 8.x current-major should be recorded decision; shared `REDIS_PASSWORD` consider per-service at rotation; rabbitmq 512m lean consider 1g; jaeger v2 migration correct, `COLLECTOR_OTLP_ENABLED` v1-era env boot-verify once. Neo4j `5.26.32-community-trixie` bullseye→trixie correct, heap 512m–1536m + pagecache 512m in 2.5g tight — monitor OOM. Hound `:6080` vs android `:6080` across exclusive profiles — remap hound `6081` (Makefile guard only protection). Gotenberg `--chromium-restart-after=30` bare number — confirm via logs.
- **P2-16. Seed O(n²) + `ROLE_DIR` hazard.** `seed-50-fleet.sh:561-563` re-GETs agent list per role (fine at n=51, fetch once); `ROLE_DIR` (`:435`) selects all config dirs — wrong value stamps all payloads with one role's config. **Fix:** assert `ROLE_DIR` matches iterated role in loop.

---

## P3 / Low / Cleanups

- **P3-1. Opaque digests without version comments** (nuq-postgres, playwright-service). Add `#: <tag>` readability comments.
- **P3-2. `local-ci-runner`/`semgrep` `sleep infinity` without healthchecks** — fine; optional no-op `true` healthcheck for `depends_on`.
- **P3-3. `firecrawl-rabbitmq` default guest creds** — `expose:`-only ✅; rotate to env-provided when convenient.
- **P3-4. Caddy one-liner `reverse-proxy`** (`docker-compose.yml:175`) vs Caddyfile — acceptable single-host; Caddyfile more auditable (headers/logging). Optional.
- **P3-5. `k8s-orchestrator` docker MCP without explicit `DOCKER_HOST`** — declare `tcp://docker-socket-proxy:2375` or remove (dead/future-activation hazard).
- **P3-6. `sabotage-qa-tester` piston curl advisory-only** — pin behind secret-bearing wrapper (see P0-4).
- **P3-7. Shim `resolve_real_bin` self-recursion** (`opencode-shim.sh:93-103`): string-compare misses symlink-aliased self → exec loop when `realpath` absent. Compare device+inode (`stat -c '%d:%i'`) as fallback. Non-issue on debian-slim.
- **P3-8. `workspaces/scratch/.gitkeep` missing** — first `up` with ci profile may create root-owned `/scratch`, breaking `node` runner. Add `.gitkeep`.
- **P3-9. `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET` empty default** (`${…:-}`) disables signature verification — fail closed or gate empty to private+localhost only.
- **P3-10. `npm install --force`** (`docker/Dockerfile:55`) may silently resolve peer conflicts — drop `--force`, pin explicitly.

---

## Investigated and CLEARED (no finding — do not re-file)

- **Shim core 2.1–2.6 premises:** `--dir` space/`=` stripping without swallowing trailing flags, variant merge either order, `#`-suffix guard, exactly-once `--auto` (incl. `--auto=<bool>`, post-`--` exclusion), `--session`/`-s` verbatim, `--` boundary byte-for-byte, exec streaming, exit propagation (mock exit 3 → 3), missing-binary 127, GO-key fallback no-clobber — Alpha live-probed ✅. `test-shim.sh` 46/46 accurate on these points; gaps are P2-1/P2-2 edges + P0-1/P2-14 live-integration.
- **Compose base validity:** postgres `expose:`-only internal (no `ports:`), healthcheck `pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}` byte-matches, paperclip loopback `127.0.0.1:3100`, caddy `${PROXY_DOMAIN:-localhost}` fallback, tailscale `v1.104.1` newest stable, `docker compose config` fail-closes without `.env` (8 interpolation errors demanding secrets).
- **Socket-proxy posture:** `POST/BUILD/EXEC/VOLUMES/NETWORKS=0`, `CONTAINERS/IMAGES/INFO/VERSION=1` — creation/exec blocked at proxy ✅; `local-ci-runner` no socket mount, GET-only `DOCKER_HOST`, ro checkouts + rw `/scratch` ✅.
- **Beta verified-modern (explicit non-findings):** `postgres:17-alpine` resolves, `caddy:2.11.7-alpine`, `tailscale:v1.104.1`, `redis:7.4.11` (CVE-2025-49844 fix), `rabbitmq:4.3.6`, `gotenberg:8.37.0`, `browserless:v2.24.2` (correct v2 org-path), `semgrep:1.181.0` (tip of 1.x), `socket-proxy:0.3.0`, `qdrant:v1.19.2`, `neo4j:5.26.32-community-trixie`, `node:24-trixie-slim`, per-service `cpus`+`mem_limit`, loopback ports, `heretek`/`heretek-devsec`/`heretek-mobile` segmentation; all 51 roles carry `timeout:5000`, `small_model=anthropic/claude-haiku-4-5`, `compaction{auto,prune,reserved:10000}`; zero `:latest` in code (all hits comments/policy/piston-upstream explanation); digest pins resolve (searxng, nuq-postgres, playwright, radare2, hound, piston, litellm); all 5 npm pins equal `dist-tags.latest` (`@opencode/cli@2.0.32`, `@opencode/client@2.0.32`, `harness@1.0.7`, `opencode-mem@2.31.3`, `@prevalentware/opencode-goal-plugin@0.1.64`).
- **Zero committed secrets:** `.env` uncommitted, `secrets/` only `.gitkeep`, no live `sk-/ghp_/AKIA` (only vendored fixtures/docs), seeder never echoes values, `postgres-init-readonly-role.sh` uses `psql -v` bind.
- **Prior-report items now resolved:** bare plugin names (scoped 51/51), 6 legacy roles (deleted), gotenberg/rabbitmq/redis/semgrep/qdrant/jaeger lags. Do not regress.

## Registry verification backlog (requires connected `docker manifest inspect` / `npm view` / `pip index`)

`ghcr.io/paperclipai/paperclip:sha-73659c6` age/successor; harness successor past 1.0.7; `@opencode/cli` past 2.0.32; `blacktop/ghidra` 12.x; PyPI `uvx` MCP packages provenance; `@morluto/rea-mcp` existence + pin; fork-vs-canonical playwright/context7/git MCP status; `opencode-rea` publication decision; minio 2026.x (Quay auth required — `401` observed).

---

## Remediation order

1. **P0-1** harness `rootDir` fix + live visibility gate → **P0-2** strip mutating harness tools from read-only roles → **P0-3** agent-env scrub + secret-mount scoping → **P0-4** piston segmentation + secret proxy.
2. **P1-1/P1-6** live enforcer probes + `fs:read` deny reordering → **P1-2** per-namespace MCP deny tails → **P1-3/P1-4** socket/proxy network hardening + firecrawl auth → **P1-5** password-file + GO-key scoping.
3. **P1-7/P1-8** claim-text corrections (dispatch, socket-proxy) → **P1-9** prompt budget/seed-script sync + live rerun gate → **P1-10** worktree temp-stage + `$RANDOM` guard → **P1-11/P1-12** Paperclip SHA pinning + UID boot assertion.
4. **P1-13** hound/piston/minio vendoring decisions → **P1-14/P1-15** dead/unpinned MCP cleanup.
5. **P2/P3** shim edges, postgres digest, ghidra/mitmproxy/mailpit/wiremock/firecrawl/act bumps, CPU budget assertion, backup/restore round-trip, prebuilt digest, publish-gate live tests.
