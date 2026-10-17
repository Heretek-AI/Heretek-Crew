# ADVERSARIAL FLEET AUDIT — CONSOLIDATED FINDINGS (2026-10-17 re-audit)

**Target:** `/home/john/Projects/Heretek-Crew`
**Date:** 2026-10-17 | **Formation:** Alpha (Runtime & Functionality) + Beta (Version/Arch) + Gamma (Security)
**Prompt:** `PROMPT_ADVERSARIAL_FLEET_AUDIT.md` (11 domains, claims 1.1–11.9)
**Rule:** Tests were NOT trusted. Findings below rest on file reads, live-binary/registry evidence from subagents, and controller spot re-verification.
**Controller spot-verified 2026-10-17:** `ls roles/ | wc -l` = **51** (6 legacy roles deleted since 2026-10-16 report); `plugins` now scoped in 49/51 roles; `FLEET_BUDGET_CAP_CENTS=1270000`; socket-proxy `POST/BUILD/EXEC=0`; `dispatch-pipeline.sh` exits 1 with zero Paperclip calls; `backup-db.sh` collision branch drops `.age`; `docker-compose.prebuilt.yml:40` pin still unpublished by its own header admission.
**Supersedes:** prior `AUDIT_REPORT_FINDINGS.md` (2026-10-16). Resolved since then: bare `plugins: ["opencode-harness"]` (now scoped), 6 legacy `bash`-dialect roles (deleted), gotenberg 8.15.0 CVEs (now 8.37.0), rabbitmq 3.13.7 EOL (now 4.3.6), redis 7.4.1 CVE (now 7.4.11), semgrep/qdrant/jaeger lags (now current). New P0s below replace them.
**Prompt-staleness warning:** the audit prompt's Domain 11 version table is itself outdated (lists searxng 2024.10.16, firecrawl 2.10.19 mutable, gotenberg 8.15.0, browserless v2.18.0, radare2 5.9.8, semgrep 1.96.0, piston v2.0.0, litellm v1.52.16, qdrant v1.12.1, neo4j 5.26.0, ollama 0.4.4, mailpit v1.21.4, wiremock 3.10.0, minio 2024-11-07, jaeger 1.62.0, otel 0.113.0, mitmproxy 11.0.1, socket-proxy 0.1.1, android emulator_14.0_v3.8.0-p1). The repo has moved on (see Beta verified-sound list); claims citing those old pins should be refreshed, not treated as current defects where the repo already bumped.

---

## P0 / Critical (broken deployment/execution, fatal security, defunct registry)

### P0-1. Harness plugin DIES on load with role-identical config — all Domain 4 primitives unreachable (Claims 4.1–4.3 broken)
- **Files:** `roles/*/opencode/opencode.json` (`plugins` arrays) × `@heretek-ai/opencode-harness@1.0.7` `dist/index.js:605-624` (root-cause `dist/index.js:92-94,605-611`).
- **Claim:** 4.3 provides FNV-1a `file_hash_edit`, AST transforms, blast-radius, doom-loop breakers.
- **Proof (Alpha, live binary `opencode@2.0.32` + unpacked harness 1.0.7 tarball):**
  1. Built fixture `opencode.json` with role-identical declarations, ran real `opencode run --format json` → model replied verbatim **"The tool `file_hash_read` is not available in my toolset."**, fell back to built-in `read`.
  2. `--standalone --print-logs --log-level debug` log: `plugin" plugin.id=@heretek-ai/opencode-harness cause="Cause([Die(Error: opencode-harness: rootDir must be a non-empty string (fail-closed))])"`.
  3. Root cause: `inferredRoot = ctx?.directory ?? ctx?.worktree ?? ... ?? process.cwd()` — `??` does not skip `""`; host 2.0.32 supplies empty-string directory → `resolveHarnessOptions({rootDir: ""})` throws. Unit proof: `setupOpenCodeV2Harness({directory:""})` → DIED; `setupOpenCodeV2Harness({})` → LOADED. Chain must be falsy-tolerant (`||` / empty-filter).
  4. Repo's own `scripts/smoke-test.sh:81-82` concedes harness effectiveness "is still asserted only by a live agent run" — Alpha ran it, and it fails.
- **Fix (fail-closed, upstream + repo gate):**
```diff
- inferredRoot = ctx?.directory ?? ctx?.worktree ?? ctx?.location?.directory ?? ctx?.location?.worktree ?? process.cwd()
+ const pick = (v) => (typeof v === "string" && v.trim() !== "" ? v : undefined);
+ inferredRoot = pick(ctx?.directory) ?? pick(ctx?.worktree) ?? pick(ctx?.location?.directory) ?? pick(ctx?.location?.worktree) ?? process.cwd()
```
Then pin + re-verify with a live `run` asserting a harness tool call succeeds; add a publish-gate live test asserting tool visibility (see P1-8), not just `npm ls`.

### P0-2. Claim 3.3 FALSE — "read-only" roles hold 4 file-mutating harness tools (universal read-only bypass)
- **Files:** all 51 `roles/*/opencode/opencode.json` (e.g. `roles/exec-director/opencode/opencode.json:47-92`); controller confirms identical 14-tool harness allow set fleet-wide.
- **Claim:** Domain 3 Claim 3.3 — executive/PM/auditing roles "cannot execute code modification tools."
- **Proof (Gamma, JSON sweep 51/51):** `exec-director` scopes `fs:write` to `docs/executive/**` + `fs:write * deny`, but allows with `resource: "*"`:
  - `harness_file_hash_edit`, `harness_ast_structural_rewrite`, `harness_rename_symbol`, `harness_checkpoint_rollback` (all write primitives).
  Affected "read-only" roles include `exec-director`, `product-director`, `threat-modeler`, `compliance-auditor`, `tech-docs-lead`, `ux-research-analyst`. `smoke-test.sh:630-658` asserts only that harness allows == manifest + `harness_*` deny tail — it enforces uniformity, not least privilege. Nothing in-repo proves the harness consults `fs:write` scoping; the two namespaces are independent literals, enforcer lives in external npm + `/tmp/paperclip` (unverifiable here).
- **Bypass (no shell needed):** as `exec-director`, invoke `harness_file_hash_edit` on `src/auth.ts` (`resource: "*"`). `fs:write * deny` does not cover `harness_*`.
- **Fix:** strip the 4 mutating tools from every read-only-charter role; replace with denies:
```json
{ "action": "harness_file_hash_edit", "resource": "*", "effect": "deny" },
{ "action": "harness_ast_structural_rewrite", "resource": "*", "effect": "deny" },
{ "action": "harness_rename_symbol", "resource": "*", "effect": "deny" },
{ "action": "harness_checkpoint_rollback", "resource": "*", "effect": "deny" }
```
Plus smoke assertion: any role without non-docs `fs:write` allow MUST NOT allow those 4. Until then retract Claim 3.3 — the fleet has zero read-only roles. (Blocked on P0-1 fix for live verification of enforcement.)

### P0-3. All agents share one OS user + one filesystem — XDG isolates config only, not secrets or data (Claim 3.1 overstated)
- **Files:** `docker-compose.yml:100-130` (single `paperclip` container), `docker/Dockerfile:90-95` (all children `node` UID 1000), `scripts/seed-50-fleet.sh:435` (`XDG_CONFIG_HOME=/roles/<id>`).
- **Claim:** Domain 3 Claim 3.1 "per-role isolation."
- **Proof (Gamma, verified in-repo):** one UID, one mount namespace, one RW `/paperclip/workspaces`, one RO `/paperclip/secrets/kubeconfig-readonly`. XDG only selects which `opencode.json` loads. 48/51 roles hold `fs:read ** allow` (only `exec-director`, `product-director`, `ux-research-analyst` scoped); no `fs:read` deny covers `secrets/`, `*.kubeconfig`, `*token*`, `*key*.json` (denies cover only `.env` patterns). Child env inherits paperclip server env unless upstream scrubs it (code in `/tmp/paperclip`, not in repo): `docker-compose.yml:86-117` puts superuser `DATABASE_URL` (full `POSTGRES_PASSWORD`), `GITHUB_TOKEN`, 11 provider keys into that env. Dba `shell psql* deny` + read-only MCP URL are moot if agent inherits superuser `DATABASE_URL` — any shell-bypass (P1-1) or env-echo yields full write DB access.
- **Fix:** (a) mount kubeconfig only into k8s-orchestrator runtime (or move into MCP env via fd the fs tools can't address); (b) live-test that agent child env lacks `DATABASE_URL`/`POSTGRES_PASSWORD`/`BETTER_AUTH_SECRET`/provider keys (allowlist `adapterConfig.env`, scrub inheritance in `prepareOpenCodeRuntimeConfig`); (c) add `fs:read` denies for `**/secrets/**`, `**/kubeconfig*`, `**/*.pem`, `**/id_rsa*`, or scope `fs:read **` per role.

### P0-4. Dispatch pipeline executes nothing but worktree creation, never exits 0, never touches Paperclip (Claims 7.1, 7.2 false)
- **File:** `scripts/dispatch-pipeline.sh` (`:132`, `:182-184`).
- **Proof (Alpha):** `grep -c "curl\|PAPERCLIP_URL\|/api/" scripts/dispatch-pipeline.sh` → **0**. Phases 1/2/4/5 are `log_step` prints (execute-mode bodies exist only under `--dry-run`); only executing statement is phase 3 `worktree-manager create`. Execute mode unconditionally `exit 1`, so happy path reports failure to any CI gate; Claim 7.2 ticket transitions (`todo→in_progress→in_review→done`) have zero implementing code. Controller confirms `exit 1` at `:90,184`.
- **Fix:** rename/re-scope as provisioner-tracer (header `:5-12` already admits this — promote into claim docs), or implement real Paperclip ticket API calls with `--fail`-checked curl; make execute mode exit 0 after phase-3 provisioning.

### P0-5. `binary-reverse-eng` references a plugin that does not exist on npm (`opencode-rea`)
- **Files:** `roles/binary-reverse-eng/opencode/opencode.json` (`plugins: ["opencode-rea", ...]`, controller re-verified) × registry; `docker/Dockerfile:55-59` installs only cli/client/harness/opencode-mem.
- **Proof (Alpha):** `npm view opencode-rea version` → `E404 Not Found`. Role's designed tool surface can never materialize. Related: `exec-director` references `@prevalentware/opencode-goal-plugin` (exists at 0.1.64) but Dockerfile does not install it — resolves only by ambient cache luck.
- **Fix:** publish/vendor `opencode-rea` and add to Dockerfile install + publish verification, or remove from role; add `@prevalentware/opencode-goal-plugin@<pin>` to Dockerfile; extend `docker-publish.yml` verification to assert every plugin string in any `roles/*/opencode/opencode.json` resolves (`opencode plugin list` / `npm ls -g`).

### P0-6. Prebuilt path unpublishable — pinned image does not exist (Claim 9.2 broken)
- **Files:** `docker-compose.prebuilt.yml:7,40` pins `ghcr.io/heretek-ai/heretek-crew:1.0.0`; header `:14-16` admits anonymous `manifest inspect` returns `manifest unknown`, no git tags exist. Controller re-verified.
- **Proof (Alpha+Beta):** zero-compilation path is a guaranteed pull failure. Also `docker-publish.yml:71` mints a `:latest` tag on semver releases, violating the repo's own never-`:latest` invariant (Alpha P1-5).
- **Fix:** `git tag v1.0.0 && git push origin v1.0.0`, wait for publish workflow, `docker manifest inspect ...:1.0.0`, replace tag pin with immutable digest; remove `latest` raw tag from `docker-publish.yml:71` or record scoped exception; until then README must route operators to local build only. Constrain `HERETEK_IMAGE` override (Beta P2-13) to digest-pinned values only.

---

## P1 / High (deprecated, missing error handling, escape vectors, architectural drift)

### P1-1. Shell allows are unenforced-as-sandbox; every `git status*` allow is one `;` away from escape (Claim 3.2 overstated)
- **Files:** all 51 roles (each holds at least `git status*`; controller: `exec-director` has `git status*`/`git log*`; `product-director`/`threat-modeler` have zero shell allows — verify per role).
- **Proof (Gamma):** `AGENTS.md:128-132` concedes prefix-pattern semantics (`git status; <payload>` matches when enforcer is prefix-based). Enforcer is upstream OpenCode v2 / Paperclip (`/tmp/paperclip`, not in repo); no in-repo test executes a real denial — `smoke-test.sh §3` checks JSON shapes only. If prefix-based, `exec-director` payload `git status; cat /paperclip/secrets/kubeconfig-readonly; env | grep -i key` exfiltrates creds + keys. Higher-value allows widen it inherently: `dependency-patcher` `npm install*`/`go test*`/`pytest*` (arbitrary code via package scripts), `android-mobile-spec` `adb connect*` (arbitrary host:port probe), `sabotage-qa-tester` `curl … piston:2000/api/v2/execute*` (RCE by design on shared net with no piston auth — see P1-5).
- **Fix:** (a) live-test pinned enforcer with `git status; id`, `git status$(id)`, `git status||id`, `npm test -- --unknown-flag`, record denials; (b) treat shell allows as advisory until argv-aware enforcement proven, enforce at resource layer (read-only DB, read-only kubeconfig, remove superuser `DATABASE_URL` from agent env — P0-3); (c) narrow `adb connect*` to host allowlist or drop; (d) document actual enforcer semantics + version in `AGENTS.md`.

### P1-2. Six MCP declarations reference sidecars absent from every compose file (dead wiring)
- **Files:** role MCP blocks vs `docker-compose.sidecars.yml` service list.
- **Proof (Beta, local grep):** `ollama-mcp@2.1.0` (`mlops-serving-eng`), `prometheus-mcp-server==1.6.2` (`observability-eng`, `sre-incident-eng`), `kafka-mcp-server==0.1.1` (`cache-streaming-eng`), `mcp-clickhouse==0.7.0` (`analytics-metrics-eng`), `k6-mcp-server==2.2.0` (`load-stress-tester`), `docker-mcp==0.2.0` (`k8s-orchestrator`, `mlops-serving-eng`) — `grep -E "^  (kafka|clickhouse|prometheus|ollama|otel|k6)" docker-compose.sidecars.yml` returns only `jaeger:` (`:648`). Prompt Claims 11.5 (ollama 0.4.4) and 11.7 (otel-collector 0.113.0) describe services absent from the file. Agents holding these configs fail with connection-refused.
- **Fix:** add missing services as pinned sidecars, or delete corresponding MCP declarations. Minimum: document as "role-ready, infra-pending."

### P1-3. Seeder never checks write-path results — idempotency unproven (Claim 5.1)
- **File:** `scripts/seed-50-fleet.sh:182-189` (`curl -sS -m 30`, no `-f`), `:530` health check (any HTTP incl. 500 = "healthy"), `:619` (`api PATCH … > /dev/null`, status ignored), `:457-493` JSON-parse exceptions → `sys.exit(0)` → `""` = "not found".
- **Proof (Alpha, logic):** 500 page on GET → parsed as "missing" → duplicate-create POST → confusing failure; failed Pass-2 PATCH (rejected `reportsTo`/`budgetMonthlyCents`) exits 0 silently, so "PATCH only upon drift" can silently not-happen while reporting success.
- **Fix:** add `--fail-with-body` (or `-f` + error capture) to `api()` and health check; `PATCH … || exit 1` with body-on-error; JSON-parse failure must exit nonzero, not masquerade as empty.

### P1-4. Fleet-count + budget drift: 51 dirs on disk, seeder wires 50; prompt budget figure matches neither (Claims 5.2, 5.3)
- **Files:** `ls roles/` = 51 (controller verified); `scripts/seed-50-fleet.sh:192-205` `ROLE_LIST` = 50 entries, `ai-red-teamer` absent (`grep -c` → 0); `FLEET_BUDGET_CAP_CENTS=1270000` (`:111`).
- **Proof (Alpha+Beta):** computed sum of `role_budget_cents` = **1,270,000¢ ($12,700.00)**. Prompt Claim 5.3 ($12,790 / 1,279,000¢) matches neither code nor `ROLE_CATALOG_50.md:120` ($12,700). Role 51 budgeted $300 pending promotion → would total 1,300,000, not 1,279,000 — prompt figure is stale/wrong. Prior report's "56 roles" (50+6 legacy) is now obsolete: legacy 6 deleted, `ai-red-teamer` added unseeded.
- **Fix:** promote `ai-red-teamer` into `ROLE_LIST`/hierarchy/budgets (52 payloads incl. company) or delete/quarantine the dir; correct Claim 5.3 to 1,270,000¢ ($12,700.00); gate with role-dir-count assertion. Also fix `seed-50-fleet.sh:501-502` warning path (fires every run until reconciled).

### P1-5. Unauthenticated RCE-capable services on shared nets
- **Files:** `docker-compose.sidecars.yml:343` (`r2 -qc=H 0.0.0.0:9090`), `:439+` piston (no auth env — upstream OSS has none), `:182` firecrawl `USE_DB_AUTHENTICATION: "false"`, ghidra `:1337` (no auth env).
- **Proof (Gamma):** radare2 HTTP exposes `/cmd/` command execution, `expose:`-only on `heretek-devsec` — but `paperclip` joins all three nets, so any agent-code-exec bridges segments by design. Piston intended consumer `sabotage-qa-tester` (`curl …/api/v2/execute*`) proves arbitrary code via HTTP; any SSRF/prefix-bypass anywhere reaches it (no auth — piston sandbox is the only layer). Firecrawl crawl API on `127.0.0.1:3002` needs no credential + fetches arbitrary URLs by design = SSRF-to-internal primitive for anyone reaching `:3002`.
- **Fix:** front r2/ghidra/piston with shared-secret proxy or per-request tokens mounted only into needing roles; set firecrawl auth (`USE_DB_AUTHENTICATION=true` + secret) or restrict `:3002`; record residual risk in `SUPPORTING_SERVICES.md`: segmentation contains sidecar-initiated movement, not agent-initiated (paperclip-as-bridge).

### P1-6. Domain 8 claims contradict remediated implementation (Claims 8.1, 8.2 false as stated)
- **Files:** `docker-compose.sidecars.yml:398-437` (`POST/BUILD/EXEC/VOLUMES/NETWORKS: "0"`) vs prompt claims ("allows container creation and builds", "run ci.yml inside Docker").
- **Proof (Alpha; Gamma confirms code is GOOD, claims stale):** with `POST=0/BUILD=0` proxy answers 403 to `POST /containers/create` — `act` steps cannot execute via `DOCKER_HOST=tcp://docker-socket-proxy:2375` (`local-ci-runner:719-757`). File comments (`:410-415,:724-734`) admit runner is read-only observer, mutating CI must run via host `act`. `dispatch-pipeline.sh:167` dry-run text still says "Triggered local-ci-runner container."
- **Fix:** correct claims 8.1/8.2 to read-only-observer semantics; fix dispatch phase-5 text to direct operators to host `act`. Residual: `expose: 2375` on shared `heretek` net lets any container list images/containers + `info/version` unauthenticated (GET-recon) — record as accepted risk. Also: k8s-orchestrator `docker-mcp` block declares no `DOCKER_HOST` and paperclip mounts no socket — dead or future-activation hazard; declare `DOCKER_HOST=tcp://docker-socket-proxy:2375` explicitly or remove.

### P1-7. `fs:read` `.env` denies ordered AFTER `fs:read ** allow` — dead rules under first-match semantics
- **Files:** every role file (e.g. `roles/exec-director`, `roles/dba-specialist`): `fs:read ** allow` first, four `.env` read-denies ~10 entries later. Contrast `fs:write` where `*` deny correctly follows scoped allows.
- **Proof (Gamma):** if enforcer is first-match-wins, `**` matches `.env` before deny consulted → 48 `**`-reader roles read any workspace `.env`. If deny-override/most-specific-wins, denies hold. Neither semantics pinned, documented, or live-tested (grep precedence docs: zero hits). Asymmetry evidences unreviewed ordering.
- **Fix:** move all `fs:read … deny` ABOVE any `fs:read … allow` in every role file (fail-closed under both semantics); fix generator `scripts/generate-50-roles.py`; add live negative test (`read .env` must be denied).

### P1-8. Claim 3.1 enforcement code not in repo — XDG/`OPENCODE_DISABLE_PROJECT_CONFIG` rest on unaudited upstream
- **Files:** `scripts/seed-50-fleet.sh:76` (comment only), `:432-436` (emits `adapterConfig.env`); `docker-compose.yml:91` (`OPENCODE_DISABLE_PROJECT_CONFIG=true`), `:124` (`./roles:/roles:ro`).
- **Proof (Gamma):** `prepareOpenCodeRuntimeConfig` implementation (`execute.ts:329` per `NOTES.md:63`) lives in `/tmp/paperclip` upstream — outside repo, unpinned to any Paperclip commit (`PAPERCLIP_BASE_IMAGE=paperclip:official-local`, unversioned local checkout). `smoke-test.sh:194-200,948-954` asserts via string greps of rendered config, never by spawning an agent and observing which config won. Whether workspace `.opencode/` can override staged config and whether XDG is honored per-agent are live-unverified.
- **Fix:** pin Paperclip source commit in `docker/Dockerfile` + `NOTES.md`; live test: plant canary `opencode.json` + `.opencode/` in scratch workspace, run one agent turn, assert canary ignored. Until then label 3.1 "config-advice, live-unverified."

### P1-9. Shim silently swallows valueless `--dir`'s following bare-word prompt (Claim 2.1 violated)
- **File:** `scripts/opencode-shim.sh:141-149` (controller verified: drops flag + next non-flag token as path).
- **Proof (Alpha, live mock binary):** `shim run --model m --dir prompt` → forwards `run --model m --auto` — user prompt consumed as dir path, run proceeds prompt-less, exit 0, no error.
- **Fix:** fail closed — when `--dir` followed by non-flag token, ambiguity between path and prompt cannot be resolved; prefer dropping only `--dir` and preserving the token (nonexistent-dir error from real binary is louder than silent prompt loss); document ambiguity; add `test-shim.sh` case pinning chosen behavior.

### P1-10. `backup-db.sh:103-105` drops `.age` suffix on same-second collision — encrypted backup unrestorable by documented command
- **File:** `scripts/backup-db.sh:95-105` (controller verified: `OUTFILE=backup-STAMP.sql.gz.age`; collision branch reassigns to `backup-STAMP-RANDOM.sql.gz` with plaintext extension but age-encrypted bytes).
- **Proof (Alpha, logic):** `restore-db.sh:142-148` routes by extension → `gunzip -c` on age bytes → `not in gzip format`, abort. Same-second rerun under `BACKUP_AGE_RECIPIENT` yields a dump the documented restore path cannot read.
- **Fix:** `OUTFILE="${BACKUP_DIR}/backup-${STAMP}-${RANDOM}.sql.gz${ENCRYPT:+.age}"` — derive collision name from already-suffixed name.

### P1-11. Publish gate cannot catch P0-1 — pre-publish verification never runs translation or plugin load (Claim 9.3 gap)
- **File:** `.github/workflows/docker-publish.yml:83-106`.
- **Proof (Alpha):** asserts `opencode --version`, `opencode-bin --version`, `npm ls` — none executes shim rewrite path or loads harness plugin (which dies per P0-1). Shim regression or plugin-load failure passes gate by construction. Multi-arch arm64 likewise unverified (Beta P2-12: builds/verifies amd64 only, pushes `linux/arm64` claim at `:113` untested).
- **Fix:** gate step running built image with fixture argv through `opencode` asserting merged `--model#variant` + `--auto` reaches `opencode-bin`, plus plugin-load assertion (fail build if `Die(` for pinned harness); add `docker run --platform linux/arm64` smoke before push.

### P1-12. Unpinned MCP + obscure PyPI supply-chain drift
- **Files:** `roles/binary-reverse-eng/opencode/opencode.json:253` (`"@morluto/rea-mcp"` bare — `npx -y` resolves `latest` each cold start); `uvx` pins `mcp-server-redis==0.1.1`, `mcp-server-kubernetes==0.1.6`, `mcp-server-qdrant==0.8.1`, `kafka-mcp-server==0.1.1`, `k6-mcp-server==2.2.0`, `mcp-clickhouse==0.7.0`, `docker-mcp==0.2.0`, `r2mcp==0.2.5`, `prometheus-mcp-server==1.6.2` (single-digit minors, small publishers); forked npm MCPs `@executeautomation/playwright-mcp-server@1.0.12` (5 roles) vs canonical `@playwright/mcp`, `@upstash/context7-mcp@4.4.2` vs official, `@cyanheads/git-mcp-server@2.15.3`, `@modelcontextprotocol/server-postgres@0.6.2` (possibly superseded).
- **Fix:** pin `@morluto/rea-mcp@<verified>` after `npm view` (also confirm existence — obscure scope); `pip index versions` / PyPI provenance for each `uvx` package, prefer publisher-official servers, drop entries whose infra doesn't exist (P1-2); `npm view` each fork, migrate playwright/context7 to canonical if forks lag. Violates zero-floating-tags invariant.

### P1-13. Piston pinned to digest of upstream floating `latest` (sustainability hole, self-acknowledged)
- **File:** `docker-compose.sidecars.yml:440-454` (`ghcr.io/engineer-man/piston@sha256:2f66b7…`); comments admit upstream publishes ONLY `latest`, vendoring to `ghcr.io/heretek-ai/piston:<semver>` blocked (GHCR 401 without auth). Prompt Claim 11.4 `v2.0.0` tag does not exist upstream.
- **Fix (per file's own plan):** maintainer builds piston from pinned source tag, pushes `ghcr.io/heretek-ai/piston:<semver>`, replaces with that digest.

### P1-14. `docker-android` under-resourced + suspect healthcheck; Hound on archived upstream
- **Files:** `docker-compose.sidecars.yml:680,713-714` (emulator `cpus: 2.0 / mem_limit: 4g` — full AOSP + noVNC realistically wants 6–8g / 4+ CPUs; expect OOM/boot-timeout); `:706` healthcheck `adb devices | grep -q device` assumes `adb` on PATH (unverified); `Android 14` image while 15/16 exist. `:360` hound `ghcr.io/hound-search/hound@sha256:5b7fd0…` — org migration good, but upstream `etsy/hound` archived/inactive (no future CVE fixes; digest freezes dead code).
- **Fix:** raise android to `cpus: 4.0 / mem_limit: 8g` + host-requirement warning; verify healthcheck (`docker run --rm <img> which adb`) else probe noVNC `:6080`; record tracked decision for hound: vendor or migrate (livegrep/zoekt).

---

## P2 / Medium (non-fatal lag, suboptimal allocation, doc mismatches)

- **P2-1. Claim 4.2 text factually inverted vs repo.** Prompt says all 50 roles permit via `{harness_*, allow}`; repo holds 14 per-tool `harness_<tool>` allows + `{harness_*, deny}` tail (controller: `exec-director` shows 14 allows + deny). Tarball registers bare names (`file_hash_read`, …), no literal `harness_`-prefixed tool name in package — whether `harness_file_hash_read` authorizes anything depends on undocumented enforcer namespacing no test exercises (moot until P0-1 fixed). Fix: after P0-1, run live allow/deny matrix, pin semantics in `smoke-test.sh`, correct claim text.
- **P2-2. Shim edge cases (Alpha P2-1–P2-3, live-proven).** (a) Drops `--variant` for attached short `-mmodel` (`run -mmodel --variant high prompt` → `run --auto -mmodel prompt`) — downgraded: real binary rejects `-mmodel` anyway (exit 1), so misleading error only. (b) Leaks empty-string positionals (`--variant ''` / `--dir ""` forward stray `""`). Fix: skip empty-string consumed values, let real binary error cleanly. (c) Duplicate `--model` merges into LAST occurrence (test-shim pins last-wins); real-binary duplicate behavior unverified (first-wins or error plausible). Fix: live-probe duplicates against 2.0.32 once, pin true semantics.
- **P2-3. `restore-db.sh` lets `.env` override explicit CLI `--file`.** `FILE` parsed `:43-57`, then `:76-81` `source .env` with `set -a` overwrites it. Fix: snapshot CLI `FILE`/`RESTORE_YES` before sourcing, restore after (or source `.env` first). Also `:64` "available dumps" glob omits `*.age` (encrypted operators see "(none)"); `:141` interpolates `${POSTGRES_DB}` into SQL single quotes (breaks on quote-containing names) — use `psql -v` bind; `source .env` executes arbitrary shell — consider restricted dotenv parser for the 4 consumed keys (Alpha P3-2).
- **P2-4. `worktree-manager.sh:55-58` adopts any pre-existing directory.** `create` returns 0 if `target_dir` exists without verifying worktree registration/branch (`git worktree list --porcelain` missing) — stale/foreign dir silently adopted, `dispatch-pipeline` writes `task_plan.md` into it. Fix: verify `git worktree list` contains dir AND branch `ticket-<id>`, else fail closed. Archive litters partial dirs on `manifest.json rev-parse` failure (`:120`) — trap-cleanup just-created dir (Alpha P3-5).
- **P2-5. Claim 1.3 (non-root via `gosu`) unverifiable from repo; Dockerfile split-brain.** `docker/Dockerfile:41` `USER root`, no later `USER`; drop to `node` happens in base-image `docker-entrypoint.sh` (`/tmp/paperclip`, not in repo) via `gosu node` per `:84-95` comment. `USER_UID/USER_GID` (`docker-compose.yml:106-107`) consumed nowhere in-repo. If base entrypoint changes or `PAPERCLIP_BASE_IMAGE` overridden, server runs as root with zero in-repo signal; RW `/paperclip/workspaces` bind then writes host files as root. Positive: `no-new-privileges:true` (paperclip/postgres/caddy/tailscale/firecrawl-playwright), postgres `cap_drop: ALL` — good. Fix: pin `PAPERCLIP_BASE_IMAGE` digest; build+boot assertion effective UID==1000 (`docker compose exec paperclip id`) in `smoke-test.sh`; `USER node` defense-in-depth default or `gosu` existence check at build. `npm install --force` (`:55`) can silently resolve peer conflicts — drop `--force`, pin explicitly.
- **P2-6. Network posture: one all-interfaces binding (caddy 80/443) — intentional but honor-system.** Full `ports:` sweep: every published port `127.0.0.1:<host>:<ctr>` except `docker-compose.yml:181-183` caddy `"80:80"`, `"443:443"`. All DBs/queues (`:5432`, rabbitmq mgmt, redis×2, qdrant `:6333`, neo4j `:7687`, litellm `:4000`, piston `:2000`, r2 `:9090`, ghidra `:1337`) `expose:`-only or loopback-published. `0.0.0.0` strings in sidecars are container-internal listens — correct. Caddy exposure flagged in-file with correct conditions, but nothing enforces: `--profile proxy` + `public` exposure value is a one-word change to internet-facing auth surface. Fix: preflight refusing `--profile proxy` unless `PAPERCLIP_DEPLOYMENT_EXPOSURE=private` and `BETTER_AUTH_SECRET` non-placeholder (compose already fail-closes latter via `:?`).
- **P2-7. Secret hygiene residuals (strong defaults, 3 gaps).** Good: no `.env` in repo, `.gitignore` covers `.env`/`backups/`/`secrets/*`, `${VAR:?}` guards, `CHANGE_ME__` placeholders, seeder never echoes values, `postgres-init-readonly-role.sh` uses `psql -v` bind. Gaps: (1) superuser `DATABASE_URL` with embedded password in process env (`docker-compose.yml:86`) — visible to `docker inspect`, `/proc/<pid>/environ`, transcript dumps; prefer password-file/Docker secret, keep only `POSTGRES_READONLY_URL` in agent-reachable env. (2) `./workspaces/scratch` (runner `/scratch:rw`) absent in-repo (only `.gitkeep`, `tickets/`) — first `up` with ci profile may create root-owned, breaking `node` runner; add `workspaces/scratch/.gitkeep`. (3) `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET` defaults empty (`${…:-}`) = disables signature verification; fail closed or gate empty default to private+localhost only.
- **P2-8. Version/architecture notes (Beta P2-1–P2-14, local evidence).** `postgres:17-alpine` floating minor — pin `17.<x>-alpine` + digest, quarterly bump. `node:24-trixie-slim` inherited via `PAPERCLIP_BASE_IMAGE=paperclip:official-local` requiring manual `/tmp/paperclip` prep (`Makefile:60`) — automate/document. Firecrawl main `:2.10.19` mutable while 4 deps digest-pinned — resolve to digest with `#:2.10.19` comment; `nuq-postgres`/`playwright-service` digests lack human-readable tag comments. `blacktop/ghidra:11.2` community image, likely one minor behind, weak `pgrep -f ghidra` healthcheck — verify `:11.3+`, digest-pin, probe `:1337`. Jaeger v2 migration correct but `COLLECTOR_OTLP_ENABLED=true` kept on "harmless if ignored" assumption — boot-verify once. Neo4j `5.26.32-community-trixie` defensible LTS but heap 512m–1536m + pagecache 512m inside 2.5g limit is tight — monitor OOM. Host port 6080 claimed by hound (`:366`) and android (`:699`) across mutually-exclusive profiles — only Makefile guard prevents collision; remap hound to `6081`. MinIO `RELEASE.2024-11-07` ~2yr stale, digest pending (Quay auth-gated), only `:9001` host-published (confirm S3 `:9000` expose-only intentional); evaluate 2026.x + localstack suggestion (AGPLv3). Gotenberg `--chromium-restart-after=30` bare number — confirm via `docker logs gotenberg | grep -i chromium`. Dual redis share one `REDIS_PASSWORD` — consider per-service at next rotation. RabbitMQ `512m` lean — consider 1g. Minor lags (wiremock 3.10.0→3.13+, mailpit v1.21.8, act-22.04→24.04) — quarterly bump. `local-ci-runner`/`semgrep` `sleep infinity` without healthchecks — fine, or no-op `true` healthcheck for `depends_on`.
- **P2-9. Seed performance + `ROLE_DIR` hazard.** Pass-1 re-GETs agent list per role (`seed-50-fleet.sh:561-563`, 50 LIST calls O(n²)) — fine at n=50, fetch once. `ROLE_DIR` env (`:435`) selects all 51 config dirs at generation; wrong value silently stamps all payloads with one role's config — assert `ROLE_DIR` matches iterated role in loop (Gamma P3-4).

---

## P3 / Low / Cleanups

- **P3-1. Shim `resolve_real_bin` self-recursion guard degrades without `realpath`** (`opencode-shim.sh:93-103`): string-compare fallback misses symlink-aliased self-reference → exec loop. Non-issue on debian-slim (coreutils present); compare device+inode (`stat -c '%d:%i'`) when `realpath` absent.
- **P3-2. `sabotage-qa-tester` piston curl + `adb connect*` scoping.** Pin piston curl to secret-bearing wrapper so arbitrary-URL POSTs aren't one prefix-match from unauthenticated RCE-as-a-service; narrow `adb connect*` to allowlist (see P1-1).
- **P3-3. `firecrawl-rabbitmq` default guest creds** — disclosed in-file, `expose:`-only. Rotate to env-provided cookie/user when convenient.
- **P3-4. Caddy one-liner `reverse-proxy`** (`docker-compose.yml:175`) vs Caddyfile — acceptable single-host; Caddyfile more auditable (headers, logging). Optional.
- **P3-5. `k8s-orchestrator` docker MCP without `DOCKER_HOST`** — declare explicitly or remove (see P1-6).

---

## Investigated and CLEARED (no finding — do not re-file)

- **Dispatch heredoc injection:** suspected `cat <<EOF` with `${FEATURE_PROMPT}` executing `$(…)` — disproven by replica test (expansions not re-scanned; payload literal). Safe.
- **Shim core translations (2.1–2.6 premises):** `--dir`/`--variant` rejection (exit 1, exact "Unrecognized flag"), `--model provider/model#variant`, `--auto` semantics, `--session`/`-s`, `--` terminator, exec streaming, exit propagation, missing-binary 127, `OPENCODE_GO_API_KEY` fallback + no-clobber — verified live against real 2.0.32 or faithful mock. `test-shim.sh` accurate on these points; gaps are untested live-integration (P0-1, P1-11).
- **Compose base validity:** `docker compose config` exits 0 (vars supplied); postgres internal-only (`expose` only), paperclip loopback `127.0.0.1:3100`, healthcheck `$$` escaping, caddy `localhost` fallback, tailscale tag default — as claimed statically.
- **Backup retention/pruning:** NUL-delimited mtime sort, double-collision abort, empty-dump removal, `pipefail` streaming — correct; only P1-10 suffix bug breaks it.
- **Beta verified-sound (explicit non-findings):** `redis:7.4.11` (CVE-2025-49844 fix), `rabbitmq:4.3.6`, `gotenberg:8.37.0`, `qdrant:v1.19.2` + API-key auth, `neo4j …-trixie`, `semgrep:1.181.0`, `tecnativa/docker-socket-proxy:0.3.0` (GET-only env), `browserless:v2.24.2`, `mitmproxy:11.0.2`, searxng/radare2/hound/litellm digest pins, per-service `cpus`/`mem_limit`, loopback ports, `heretek`/`heretek-devsec`/`heretek-mobile` segmentation; all 51 roles carry `"timeout": 5000`, `small_model`, `compaction`; publish workflow action pins modern (`checkout@v4`, `buildx@v3`, `ubuntu-22.04`).
- **Prior-report P0-6/P0-7, P1-4, P1-10 (partial), P1-11, P2-1 now resolved** by version bumps (gotenberg/rabbitmq/redis/semgrep/qdrant/jaeger), legacy-role deletion, scoped plugin names. Do not regress.

## Registry verification backlog (offline — requires `docker manifest inspect` / `npm view` / `pip index` on connected host)

`ghcr.io/paperclipai/paperclip:sha-73659c6`; `@heretek-ai/opencode-harness@1.0.7` successor; `@opencode/cli@2.0.32` successor; `opencode-mem@2.31.3`; `caddy:2.11.7-alpine`; `tailscale/tailscale:v1.104.1`; `blacktop/ghidra:11.2` successors; all PyPI `uvx` MCP packages; `@morluto/rea-mcp` existence; fork-vs-canonical playwright/context7/git MCP status; `opencode-rea` publication decision.

---

## Remediation order

1. **P0-1** harness `rootDir` empty-string fix + live tool-visibility gate → **P0-2** strip mutating harness tools from read-only roles (then live-verify) → **P0-3** agent-env scrub + secret-mount scoping.
2. **P0-4** dispatch rename-or-implement + exit-0 → **P0-5** `opencode-rea`/goal-plugin install-or-remove → **P0-6** publish `v1.0.0`, digest-pin prebuilt, drop `latest`.
3. **P1-1/P1-7** live enforcer probes + `fs:read` deny reordering → **P1-5** front unauth RCE services → **P1-3/P1-4** seeder `--fail` + `ai-red-teamer` decision + budget correction → **P1-6/P1-8** claim-text corrections (socket-proxy, XDG).
4. **P1-2/P1-12** dead/unpinned MCP cleanup → **P1-13/P1-14** piston vendoring + android resourcing → **P1-9/P1-10/P1-11** shim prompt-loss, backup suffix, publish-gate live tests.
5. **P2/P3** table + cwd + restore + worktree + UID + network-preflight + secret-file fixes.
