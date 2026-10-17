# AUDIT_REPORT_FINDINGS.md — Adversarial Three-Subagent Fleet & Architecture Audit

**Target:** `/home/john/Projects/Heretek-Crew`
**Date (UTC):** 2026-10-17
**Prompt:** `PROMPT_ADVERSARIAL_FLEET_AUDIT.md` §§1–4 (11 domains, Claims 1.1–11.9)
**Formation:** Alpha (Runtime & Functionality) + Beta (Architecture & Version Modernity) + Gamma (Security, Sandboxing & Threat) — concurrent, independent, read-only
**Cardinal rule applied:** DO NOT BELIEVE TESTS. No conclusion drawn from `test-shim.sh` / `smoke-test.sh` exit 0 alone. Every FAIL below cites file:line + executed command + raw output/denial.
**Coordinator verification (2026-10-17):** `git status --short` clean; `grep -n docker-socket-proxy docker-compose.sidecars.yml` → `:531 image: tecnativa/docker-socket-proxy:0.5.0`; `grep -n heretek-crew docker-compose.prebuilt.yml` → `:52 image: ${HERETEK_IMAGE:-ghcr.io/heretek-ai/heretek-crew:1.0.0}`; `ls scripts/seed*` → only `seed-50-fleet.sh`; `grep -n "^  ollama:|^  otel"` → no matches.

---

## 0. Meta-finding: audit prompt §3 Domain 11 version table is STALE (applies to all triad members)

The prompt cites: searxng `2024.10.16-ac56c663b`, rabbitmq `3.13.7`, ghidra `11.2`, semgrep `1.96.0`, hound `v0.6.1`, piston `v2.0.0`, litellm `v1.52.16`, qdrant `v1.12.1`, neo4j `5.26.0`, jaeger `1.62.0`, mitmproxy `11.0.x`, socket-proxy `0.3.0`, gotenberg `8.15.0`, browserless `v2.18.0`, ollama `0.4.4`, otel-collector `0.113.0`.
The repo has been bumped past nearly all of these (Beta registry-confirmed: gotenberg `8.38.1`, browserless `v2.26.0`, ghidra `12.1.4`, semgrep `1.181.0`, hound `0.6.0`, neo4j `5.26.32`, litellm `main-v1.60.0`, qdrant `v1.19.2`, jaeger `2.22.0`, rabbitmq `4.3.6`, socket-proxy `0.5.0` [broken tag — see P0-1]).
**Action:** re-baseline `PROMPT_ADVERSARIAL_FLEET_AUDIT.md` §3 before the next audit or Alpha/Gamma will file false positives. Code wins over prompt where they diverge.

---

## 1. Prioritized Defect Matrix — P0 / Critical (broken deploy/exec, fatal sec, defunct registry)

### P0-1. Socket-proxy pin references NONEXISTENT tag — `core`/`devsec`/`ci` profiles cannot pull (Beta P0-1; corroborated by coordinator)
- **File:line:** `docker-compose.sidecars.yml:531` (`image: tecnativa/docker-socket-proxy:0.5.0`); stale comment at `:526` claims `0.3.0`.
- **Claim:** Domain 8 Claim 8.2 (daemon protection via `0.3.0` per prompt; file intends `0.5.0` GET-only).
- **Status:** FAIL.
- **Command:** `skopeo inspect docker://tecnativa/docker-socket-proxy:0.5.0` → `fatal ... reading manifest 0.5.0 in docker.io/tecnativa/docker-socket-proxy: manifest unknown`
- **Command:** `skopeo list-tags docker://tecnativa/docker-socket-proxy` → full set includes `v0.5.0` but NOT `0.5.0` — `0.5.0` series exists **only with `v` prefix**. In-file "Hub tag verified live 2026-10-17" false as written.
- **Remediation (fail-closed):**
```diff
-    image: tecnativa/docker-socket-proxy:0.5.0
+    image: tecnativa/docker-socket-proxy:v0.5.0
```
then `skopeo inspect docker://tecnativa/docker-socket-proxy:v0.5.0`, capture digest, re-pin `v0.5.0@sha256:<digest>` per file tag+digest convention. Never invent digest offline. Then `docker compose --profile core pull` must succeed.

### P0-2. Harness primitives 100% non-functional under pinned CLI — Domain 4 Claim 4.3 FAIL (Alpha P0-1 + Beta P1-4, same root cause)
- **Files:** `docker/Dockerfile:35-53` (self-admits), `harness/package/dist/index.js:601-605`, `.github/workflows/docker-publish.yml:162-184` (harness gate).
- **Claims:** 4.1/4.2 (install/plugin presence — PASS as pins) vs 4.3 (FNV-1a edits, AST transforms, blast-radius, doom-loop — FAIL live).
- **Status:** FAIL (fail-closed throw, no silent corruption — but flagship tooling claim false).
- **Commands:**
  - `npm pack @heretek-ai/opencode-harness@1.0.7` → `sed -n '596,605p'` shows `const inferredRoot = ctx?.directory ?? ctx?.worktree ?? … ?? process.cwd();` — `""` is not nullish so flows into `resolveHarnessOptions({rootDir:""})` which throws (`index.js:92-94`).
  - `node -e "setupOpenCodeV2Harness({directory:''})"` → `THREW AS DOCUMENTED: opencode-harness: rootDir must be a non-empty string (fail-closed)`.
  - `npm view @heretek-ai/opencode-harness versions` → tail `[..., "1.0.7"]` (latest == pinned, good) — `npm ls` presence ≠ loadable.
  - Publish gate `setup({directory:""})` must-not-throw → FAILs until upstream ships fix, so **no multi-arch image can ship** (reinforces P0-3).
- **Remediation (upstream, fail-closed):** apply `pick()` fix recorded in `docker/Dockerfile:42-45`, publish harness successor, bump `OPENCODE_HARNESS_VERSION`, re-run docker-publish harness gate (correctly FAILs today — blocking publish by design). Re-enumerate `EXTENDED_HARNESS_TOOL_NAMES` into `smoke-test.sh`; change gate fixture model `opencode/gemini-3.8-flash` to fake provider string so gate never depends on real model id.

### P0-3. Prebuilt image does not exist — Claim 9.2 unsatisfiable (Alpha P0-2 + Beta P1-1, same registry proof)
- **Files:** `docker-compose.prebuilt.yml:52` (`image: ${HERETEK_IMAGE:-ghcr.io/heretek-ai/heretek-crew:1.0.0}`), `.github/workflows/docker-publish.yml:73-75`.
- **Claim:** 9.2 zero-compilation prebuilt pull.
- **Status:** FAIL.
- **Commands:** `docker manifest inspect ghcr.io/heretek-ai/heretek-crew:1.0.0` / `skopeo inspect docker://ghcr.io/heretek-ai/heretek-crew:1.0.0` → `manifest unknown`; `skopeo list-tags` → 18 tags, **all `sha-*`, zero semver**. Honestly documented in-file (`prebuilt.yml:14-32`) but path unusable; Claim 9.1 multi-arch publish can never go green on current pins (gate FAIL per P0-2).
- **Remediation:** `git tag v1.0.0 && git push origin v1.0.0`, wait for workflow, then `docker manifest inspect ghcr.io/heretek-ai/heretek-crew:1.0.0` must resolve before operators use `-f docker-compose.prebuilt.yml`. Until then README "Option A (prebuilt)" dead; build locally. Once resolvable, replace tag pin with immutable `sha-<sha>` digest.

### P0-4. MCP wildcard allows with NO namespace deny tail bypass every shell deny (Gamma P0-G2)
- **Files:** `roles/*/opencode/opencode.json` (66 wildcard allows across ~40 roles with no matching deny); contrast correct template `roles/k8s-orchestrator/opencode/opencode.json:60-78` (`kubernetes_kubectl_exec* → deny` then `kubernetes_* → deny`; `docker_create*/docker_deploy* → deny` then `docker_* → deny`) and `threat-modeler` (`github_get/search/list allow + github_* deny` — correct GitHub template).
- **Claims:** 3.2/3.3 FAIL.
- **Command:** enumerate every `allow` ending `_*`, check for matching namespace `deny` → 66 gaps, e.g. `a11y-specialist playwright_* (no deny)`, `chrome-devtools_* (no deny)`, `exec-director github_*, memory_* (no deny)`, `product-director github_*, memory_* (no deny)`, `vector-rag-spec qdrant_* (no deny)`, `binary-reverse-eng rea_*, r2_* (no deny)`, `appsec-engineer semgrep_* (no deny)`, `data-pipeline-eng duckdb_* (no deny)`.
- **Attack:** compromised agent gets full tool surface despite shell deny tail. `AGENTS.md:149-157` admits "MCP namespaces bypass shell denies" but fleet not yet fixed.
- **Remediation (fail-closed, per role, e.g. exec-director):**
```json
{"action": "github_get_*", "resource": "*", "effect": "allow"},
{"action": "github_search_*", "resource": "*", "effect": "allow"},
{"action": "github_list_*", "resource": "*", "effect": "allow"},
{"action": "github_*", "resource": "*", "effect": "deny"},
```
Apply fleet-wide: enumerate exact read-only MCP verbs needed, allow those, then `<namespace>_* → deny`. Copy k8s-orchestrator / dba-specialist (`postgres_query* allow + postgres_* deny`) / threat-modeler pattern.

### P0-5. Unauthenticated RCE-as-a-service reachable from shared net: piston :2000, ghidra :1337, radare2 :9090 /cmd/ (Gamma P0-G3)
- **Files:** `docker-compose.sidecars.yml:583-632` (piston `expose: 2000`, heretek net), `:367-456` (ghidra :1337 + radare2 :9090 `r2 -qc=H 0.0.0.0:9090`, heretek-devsec net), `roles/sabotage-qa-tester/opencode/opencode.json` (exact-host curl pins), bridge `docker-compose.sidecars.yml:970-974` (paperclip joins heretek-devsec).
- **Claims:** Domain 8 / 11.3 / 11.4 FAIL-OPEN by design; in-file mitigations advisory only.
- **Attack paths:** (1) any `heretek` container `POST http://piston:2000/api/v2/execute` zero creds; (2) paperclip bridges into heretek-devsec so any agent-code-exec reaches ghidra :1337 / r2 `:9090/cmd/`; (3) sabotage-qa-tester curl pins are prefix-matched (see P0-6) compounding SSRF reach.
- **Remediation:** front :2000/:1337/:9090 with shared-secret sidecar proxy (or per-request tokens mounted only into RE-needing roles) before untrusted-sample/multi-tenant use; until then keep devsec+qa-testing profiles OFF by default, add compose-level guard refusing `--profile devsec` + `--profile web-research` in one invocation, move piston onto isolated net (tracked Wave E P0-4 residual).

### P0-6. Prefix-match shell bypass structurally unmitigated (Gamma P0-G1; Alpha P2-3 corroborates)
- **Files:** all 51 `roles/*/opencode/opencode.json`; `AGENTS.md:130-143`; `scripts/seed-50-fleet.sh:437-440` ("even per-role opencode.json allow-lists are only hints once CLI runs with --auto"); shim `scripts/opencode-shim.sh:24-36`.
- **Claim:** 3.2 PARTIAL (shape PASS 51/51 `permissions[-1] == {shell,*,deny}`; enforcement FAIL-OPEN by admission).
- **Commands:** allow-frequency scan → top allow `git status*` in **47/51** roles (+ `npm test*`, `pytest*`, `go test*`, `cargo test*`, `curl -s http://piston:2000/...*`, `python3 pipelines/*`); `AGENTS.md:130-131` admits continuations `git status; <payload>` match prefix when enforcer prefix-based; `:134-136` admits semantics unpinned/live-untested.
- **Attack:** `git status; id`, `git status||id`, `git status$(id)` — deny tail never fires if enforcer prefix-based (assumed until live probes `AGENTS.md:138-139` run).
- **Remediation:** (1) run 4 live probes through seeded fleet agent turn, record allow/deny; claim no sandboxing until all 4 deny; (2) if any allows, replace prefix allows with argv-aware wrapper validating `argv[0..n]` exactly, rejecting `;||&&$()`; pin enforcer version+semantics in `NOTES.md`; (3) reduce blast radius now: drop `git status*` where unneeded; scope remainder to `git status --porcelain -- <path>` wrapper. Plus live-canary asserting Paperclip exact argv order in `NOTES.md`.

---

## 2. P1 / High

### P1-1. Paperclip source-commit pin provenance conflict — UNRESOLVED, needs re-verification (Alpha P1-1 vs Beta P2-7 disagree)
- **Files:** `docker/Dockerfile:20-21`, `NOTES.md:366`, `.github/workflows/docker-publish.yml:20`, `docker-compose.yml:94-95`, `docker/Dockerfile:63-64` (`FROM ${PAPERCLIP_BASE_IMAGE}` default `paperclip:official-local`).
- **Claim:** 1.1.
- **Alpha evidence (FAIL):** `GET /repos/paperclipai/paperclip/git/commits/73659c6b27c1d9726f2da9ca39f256eefddac66` → 404; `/commits/<sha>` → 422; raw Dockerfile → 404; full SHA nowhere in `paperclipai/paperclip` (default branch `master` not `main`). GHCR tag `sha-73659c6` IS real multi-arch — image genuine but source unverifiable.
- **Beta evidence (PASS):** `GitHub API /commits/73659c6` → sha match, author Devin Foley, 2026-10-16; prebuilt base `ghcr.io/paperclipai/paperclip:sha-73659c6` exists (digest `sha256:b12822a3…`).
- **Status:** CONFLICT — treat as P1 until single live re-check closes it.
- **Remediation:** re-clone upstream at tag build commit, record `git rev-parse HEAD` + `git log -1` + registry digest in `docker/Dockerfile` + `NOTES.md`; if commit gone, rebuild base from resolvable commit, rotate tag. Add CI assertion `git -C /tmp/paperclip rev-parse HEAD == recorded commit` before build, or move base to GHCR digest pin.

### P1-2. Claimed sidecars absent from compose: `ollama`, `otel-collector` (Alpha P1-2 + Beta P2-6)
- **File:** `docker-compose.sidecars.yml` (38 services); `grep -n "^  ollama:|^  otel"` → no matches; anchored grep finds all other claimed services (hound:460 … jaeger:821).
- **Claims:** 11.5 (`ollama/ollama:0.4.4`), 11.7 (`otel/opentelemetry-collector-contrib:0.113.0`) FAIL as stated. `SUPPORTING_SERVICES.md:1169` confesses "specified but NOT composed" (cites `0.5.4`, contradicting prompt `0.4.4`).
- **Remediation:** either add services (pinned + profiled + healthchecked) or strike claims + role docs referencing endpoints.

### P1-3. Non-root runtime depends on unverified upstream entrypoint internals (Alpha P1-3 + Gamma P2-G4: PARTIAL → PASS-pending-live)
- **Files:** `docker/Dockerfile:129-146`, `docker-compose.yml:193-197`; upstream `master` (`apt-get install … gosu`, `ENTRYPOINT ["tini","--","docker-entrypoint.sh"]`, ends `exec gosu node "$@"`).
- **Claim:** 1.3.
- **Gap:** pin doesn't resolve (see P1-1); repo asserts nothing mechanically about base; only live `id -u` gate catches post-boot. `smoke §8` (`docker compose exec paperclip id -u == 1000`) is live gate, ungated here.
- **Remediation:** build-time assertion `docker pull $PAPERCLIP_BASE_IMAGE && docker run --rm --entrypoint sh $BASE -c 'command -v gosu && grep -q "exec gosu node" /usr/local/bin/docker-entrypoint.sh'`; do not assert non-root without live gate.

### P1-4. MinIO pin unpullable anonymously (Beta P1-2)
- **File:** `docker-compose.sidecars.yml:774` (`quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z`); honest note `:760-773` incl. AGPLv3.
- **Claim:** 11.6.
- **Command:** `skopeo inspect docker://quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z` → `unauthorized: access to the requested resource is not authorized`.
- **Remediation:** provision quay robot account into CI/host docker config + record digest, or mirror to `ghcr.io/heretek-ai/minio:<RELEASE>` + pin digest; evaluate localstack alternative next bump. No digest invented offline.

### P1-5. Mitmproxy full major behind (Beta P1-3)
- **File:** `docker-compose.sidecars.yml:331` (`mitmproxy/mitmproxy:11.0.2` + digest `sha256:92ab9e…` resolves).
- **Claim:** 11.8.
- **Command:** `skopeo list-tags docker://mitmproxy/mitmproxy` tail → `['12.2.0','12.2.1','12.2.2','12.2.3']`. Full-major lag on intercept proxy, security-relevant. File admits quarterly plan — keep severity.
- **Remediation (quarterly, live-verified):** re-resolve newest `12.x`, bump tag+digest together, re-verify `:8081` healthcheck on first qa-testing boot (v12 behavior NOT verified from here).

### P1-6. Caddy proxy binds 0.0.0.0:80/443; Makefile-only guard (Alpha P2-1 + Gamma P1-G1: PASS with weak enforcement)
- **Files:** `docker-compose.yml:239-241` (`80:80,443:443`; rendered `config --format json`: caddy `host_ip=None`, every other service `host_ip='127.0.0.1'`); `Makefile:57-64` guard-proxy; note `:230-238` honest.
- **Claim:** 1.4 (Caddy `2.11.7-alpine` multi-arch w/ `localhost` default — PASS; tailscale `v1.104.1` w/ `--advertise-tags=tag:heretek` — PASS).
- **Gap:** raw `docker compose --profile proxy up` bypasses guard (admitted "deferred"). Single typo publishes stack to LAN/Internet.
- **Remediation:** keep guard; document `make proxy-up` only path; long-term compose gate (override entrypoint `sh -c 'test … && exec caddy …'`) or `pre-up` hook; verify `ss -tlnp | grep -E ':80|:443'` in `make proxy-up`.

### P1-7. Socket-proxy GET-recon open to every `heretek`-net container (Alpha P2-2 + Gamma P1-G2: proxy config PASS, placement residual)
- **File:** `docker-compose.sidecars.yml:525-581` (after P0-1 tag fix; `CONTAINERS/IMAGES/INFO/VERSION=1`, `POST/BUILD/EXEC/VOLUMES/NETWORKS/NODES/SWARM/SYSTEM/AUTH=0`, socket `:ro`, `expose: 2375` no host ports — correct).
- **Claim:** 8.2 (GET-only BY DESIGN — PASS; prompt stale `0.1.1`/`0.3.0` and inverted wording — prompt wrong, file correct).
- **Gap (admitted `:548-553`):** any heretek-networked container gets unauthenticated GET-recon. No source-IP allowlist; `heretek-ci` dedicated-net move deferred.
- **Remediation:** relocate proxy + `local-ci-runner` to dedicated `heretek-ci` net or iptables/source-IP allowlist; verify `docker compose run --rm <untrusted> wget -qO- http://docker-socket-proxy:2375/version` denies. Never weaken POST/BUILD/EXEC to "fix" CI (Domain 8 Claims 8.1/8.2 corrected: `local-ci-runner` `ghcr.io/catthehacker/ubuntu:act-22.04` `sleep infinity` `:ro` + `/scratch` is quarantined read-only observer; mutating `act` runs on HOST only).

### P1-8. `DATABASE_URL` superuser password in paperclip env (Gamma P1-G3)
- **File:** `docker-compose.yml:116` (`DATABASE_URL: postgres://${POSTGRES_USER}:…${POSTGRES_PASSWORD:?…}@postgres:5432/…`); self-flags `:105-115`.
- **Claims:** 1.1/3.1 PASS-functionally, P1 hygiene.
- **Verification:** `scripts/seed-50-fleet.sh:465-471` adapterConfig.env only `XDG_CONFIG_HOME` + `OPENCODE_DISABLE_PROJECT_CONFIG`; `smoke-test.sh:1519-1530` greps dry-run payloads. Shape-level only — upstream inheritance (`/tmp/paperclip`) needs live canary.
- **Remediation:** implement in-file plan (Docker secret + entrypoint-assembled URL); until then keep `smoke §4` green + live `printenv | grep -c DATABASE_URL == 0` agent-turn gate.

### P1-9. Backup/restore `source .env` executes file as shell + retention fail-open (Gamma P1-G4 + Alpha P2-4)
- **Files:** `scripts/backup-db.sh` (~`:70` `set -a; source ./.env; set +a`; `:166-182` non-numeric `BACKUP_RETENTION_COUNT` → `keeping all dumps` disk-fill; admitted `:74-82`), `scripts/restore-db.sh` (same pattern).
- **Claims:** 10.1/10.2 PASS-functionally, P1 hardening.
- **Attack:** malicious `.env` command substitution executes with operator privs.
- **Remediation:**
```bash
[[ "${BACKUP_RETENTION_COUNT:-5}" =~ ^[0-9]+$ ]] || { echo "error: BACKUP_RETENTION_COUNT must be a non-negative integer" >&2; exit 1; }
```
Replace `source` with restricted parser (`grep -E '^(POSTGRES_USER|POSTGRES_DB|BACKUP_DIR|BACKUP_RETENTION_COUNT|BACKUP_AGE_RECIPIENT|BACKUP_PLAINTEXT_OK)=' .env` + safe assignment).

### P1-10. XDG isolation config-advice, not proven isolation (Gamma P1-G5)
- **Files:** `scripts/seed-50-fleet.sh:75-79,422-471`; `docker-compose.yml:117-120`; `AGENTS.md:20-24`.
- **Claim:** 3.1 PARTIAL (honestly labeled live-unverified).
- **Evidence:** seed payload correct; `ROLE_DIR` hazard guard (`:427-430` + python assert) fail-closed. Copying/merging in upstream Paperclip (`/tmp/paperclip`, base locally-tagged `paperclip:official-local`); canary + child-scrub ungated statically.
- **Remediation:** record Paperclip source commit, run canary (plant canary `opencode.json` + `.opencode/` in scratch workspace, one agent turn, assert ignored) + `printenv` child-scrub probe before claiming isolation.

### P1-11. Claim 3.3 "read-only separation" false as worded (Gamma P1-G6)
- **Evidence:** scan all 51 `opencode.json` → EVERY role has scoped `fs:write` allows. Zero `fs:write * allow` (good); every `fs:write * → deny` tail exists. Implementation is reasonable scoped-write, narrative overclaims.
- **Remediation:** correct Claim 3.3 to "scoped-write separation"; list truly edit-denied roles if any.

---

## 3. P2 / Medium

### P2-1. Browserless ~31 releases behind (Beta P2-1)
- **File:** `docker-compose.sidecars.yml:294` (`ghcr.io/browserless/chromium:v2.26.0` + digest `sha256:899026f6…` resolves). GHCR tail → `['v2.56.6','v2.56.7','v2.57.0','v2.57.1']`. CDP/stealth surface moves fast.
- **Fix:** quarterly bump tag+digest together after verifying `/pressure` healthcheck. Claim 11.2 CDP `ws://browserless:3000` otherwise sound.

### P2-2. Firecrawl `2.10.19` vs live `2.11.532` (Beta P2-2)
- **File:** `docker-compose.sidecars.yml:195`. GHCR `2.x` tail → `['2.11.528',...,'2.11.532']`. No drift: tag digest == pinned `sha256:50446cbc…`. Quarterly bump tag+digest together.

### P2-3. LiteLLM `main-v1.60.0` vs live `main-v1.82.3` (Beta P2-3)
- **File:** `docker-compose.sidecars.yml:709`. GHCR tail → `['main-v1.61.1','main-v1.61.3','main-v1.61.7','main-v1.82.3']`. Tag↔digest binding exact. Quarterly bump; re-verify `/health/readiness`.

### P2-4. Mailpit `v1.21.8` vs `v1.31.6` — admitted, keep quarterly plan (Beta P2-4) — `docker-compose.sidecars.yml:738`
### P2-5. Wiremock `3.10.0-alpine` vs `3.13.2-alpine` — admitted, keep plan; do NOT jump to `4.0.0-beta` (Beta P2-5) — `docker-compose.sidecars.yml:803`
### P2-6. Base-image supply chain checkout-dependent (Beta P2-7) — `docker/Dockerfile:63-64`, `docker-compose.yml:94-95`. Fix: CI assertion `git -C /tmp/paperclip rev-parse HEAD == recorded commit` before build, or GHCR digest pin.
### P2-7. Tight memory fits — self-flagged, monitor live (Beta P3-1) — ghidra `MAXMEM=3G` vs `4g` (`:399-402`); neo4j heap `1536m`+pagecache `512m` inside `2.5g` (`:670-672` TIGHT); rabbitmq `512m` lean (`:90-91`). Confirm via `docker stats` on first profile up.
### P2-8. Sensitive volumes without rotation note (Gamma P2-G2) — `docker-compose.sidecars.yml:344-345,983-992`. Mitmproxy CA in named volume, no rotation/expiry. Fix: document CA rotation + purge; confirm `mitmproxy-certs` never mounts into agent-reachable roles.

---

## 4. P3 / Low / Cleanups + Verified PASS ledger

### P3-1. Semgrep `healthcheck: ["CMD-SHELL","true"]` meaningless but harmless (admitted in-file)
### P3-2. Restore `ls -1t` breaks on exotic filenames (SC2012 noted in-file)
### P3-3. Tailscale healthcheck can't distinguish "socket up" from "mesh joined" (empty `TS_AUTHKEY` default) — cosmetic
### P3-4. Shim intentional-loud behaviors (PASS, documented): (a) `--dir <existing-file>` non-dir path preserved as prompt text, exit 0 — hand-typed only; (b) whitespace-only `OPENCODE_API_KEY` left in env — binary fails loudly on auth
### P3-5. `..`-containing worktree IDs pass allowlist but git rejects refname loudly — fail-closed
### P3-6. Docker-android `emulator_14.0_v3.8.0-p1` (`:853`) resolves; `privileged`+/dev/kvm/4.0/8g + co-scheduling guard sane. Recency vs Android 15/16 on mobile-profile cycle.
### P3-7. Firecrawl digest-only pins (nuq-postgres, playwright-service `:127`/`:154`) both resolve; acceptable per zero-`:latest`; record originating tags if documented. Piston upstream-`latest`-only handled correctly (digest pin, no `:latest`, vendoring plan `:584-596`).

### Verified PASS (registry/file/live-probe confirmed 2026-10-17)
- **Domain 2 all six claims PASS vs real `2.0.32` binary:** `run --help` shows no `--dir`/`--variant`, `--model provider/model#variant`, `--auto`, `--session,-s`. Shim live-probes: order-independent merge, first-wins duplicate `--model`, `-m=` merge, single `--auto` both slots, `--` terminator, `--session` verbatim, GO-key fallback incl. trims, dangling/dir `OPENCODE_REAL_BIN` → 127, self-ref → 127, `auth` passthrough. Best-engineered artifact in scope.
- **Domain 1:** `127.0.0.1:3100`, postgres expose-only + `pg_isready` healthcheck, caddy `2.11.7-alpine` newest `-alpine`, tailscale `v1.104.1` newest `v1.x`.
- **Domain 5 PASS:** sole seeder, 51 roles, `total fleet budget: 1300000 cents ($13000.00 USD)` via live `--dry-run`, timers 1800/3600.
- **Domain 6 PASS (live scratch-repo):** `create` → branch `ticket-TKT-001` (dash); `archive` dirty → exit 1, no `--force` anywhere.
- **Domain 7 PASS:** zero runtime `curl|PAPERCLIP_URL|/api/|poll|wget` outside comments; execute provisions worktree + `task_plan.md` only.
- **Domain 8 `local-ci-runner` PASS as corrected** (`sleep infinity`, `:ro`, `DOCKER_HOST=tcp://…:2375`, `restart:"no"`); unverified whether `docker`/`act` CLIs inside image (no pull).
- **Domain 10 PASS:** timestamped+gzip+no-overwrite+non-empty+retention; FILE/extension/TTY-confirm/backend-terminate/`ON_ERROR_STOP=1`/table-count; `postgres-init-readonly-role.sh` `psql -v` binding, placeholder rejection, SELECT-only grants; age-encryption genuinely fail-closed.
- **Domain 11 bindings:** all host binds loopback except caddy; zero `:latest` in any `image:`; every sidecar carries `cpus`+`mem_limit` 26/26.
- **Registry-current pins:** postgres `17.11-alpine@sha256:b0f956…` newest 17.x intact; caddy newest; tailscale newest v1.x; redis `7.4.11-alpine` ×2 (CVE-2025-49844 fixed LTS); rabbitmq `4.3.6` newest 4.3.x; gotenberg `8.38.1` newest; semgrep `1.181.0` newest; qdrant `v1.19.2` + `mcp-server-qdrant==0.8.1` (PyPI latest) coherent; neo4j `5.26.32-community-trixie` exact LTS; jaeger `2.22.0` v1→v2 done; searxng/radare2/hound/nuq/playwright/act-22.04/ghidra digests resolve; `@opencode/cli@2.0.32`+`@opencode/client@2.0.32` == npm latest; `opencode-mem@2.31.3`, `@prevalentware/opencode-goal-plugin@0.1.64` == latest; all role MCP servers == latest; no floats.
- **Fleet hardening 51/51 PASS:** `small_model=anthropic/claude-haiku-4-5`, `compaction={auto,prune,reserved:10000}`, local MCP `timeout=5000`, `DOCKER_HOST=tcp://docker-socket-proxy:2375` (k8s-orchestrator+mlops), `KUBECONFIG=/paperclip/secrets/kubeconfig-readonly`, `fs:read` denies cover 8 secret patterns sorted before allows, skills symlinks 51/51 + both paths declared, zero `fs:write * allow`, every `fs:write * → deny` tail exists, secret grep only `:?`/`${VAR}`/`--help`/dummies — no hardcoded creds, no `set -x` leaks, qdrant `${QDRANT_API_KEY}` by reference correct.
- **Inside-container `0.0.0.0` correctly contained** (firecrawl `HOST: 0.0.0.0` `:213`, mitmweb `:338`, r2 `:446` — publish only via `127.0.0.1:` or `expose:`-only).

---

## 5. Top remediation order

1. **P0-1** socket-proxy `v0.5.0` tag fix + digest re-pin (unblocks 3 profiles).
2. **P0-4** MCP namespace deny tails fleet-wide (copy k8s-orchestrator/threat-modeler).
3. **P0-5** proxy-front piston/ghidra/r2; refuse combined devsec+untrusted profiles; isolate piston net.
4. **P0-6** live prefix-bypass 4-probe suite; argv-aware wrappers if any allows.
5. **P0-2/P0-3** harness successor + `v1.0.0` tag publish (unblocks prebuilt + CI green).
6. **P1-1** close Paperclip commit conflict with single live re-check + CI assertion.
7. **P1-2** compose or delete ollama/otel claims.
8. **P1-6/P1-7/P1-8/P1-9/P1-10/P1-11** caddy gate, heretek-ci net, password-file, dotenv parser, canary isolation test, Claim 3.3 reword.
9. **P2** quarterly bump cycle + `docker stats` watch + CA rotation doc.
10. **Prompt** re-baseline Domain 11 table to repo reality.

---

## 6. Auditor provenance

- Alpha `ses_eb4c0cd75ffeBfRtbaxP0XtgiS`: real `@opencode/cli-linux-x64@2.0.32` binary `run --help`+`strings`, recorder-binary shim probes, `docker compose config --format json` w/ dummy secrets, scratch-repo worktree create/archive, `npm pack` harness + `node -e` throw repro, `docker manifest inspect` + `npm view`, upstream Paperclip Dockerfile/entrypoint via GitHub raw.
- Beta `ses_eb4c0cd5cffeiAV4nGgfwFYW9p`: `skopeo inspect/list-tags`, `npm view`, `git ls-remote`, GitHub API, PyPI JSON live 2026-10-17 on compose/Dockerfile/workflow/51 role JSONs.
- Gamma `ses_eb4c0cd4fffeUczlHIvDNMYssS`: 51-file `opencode.json` permission/MCP/`fs:read`/`fs:write`/hardening scan, full `ports:` sweep, `grep -rn PASSWORD|SECRET|API_KEY|TOKEN`, seed/smoke shape-vs-enforcement analysis. Read-only, no modifications.
- Coordinator ground-truth re-checks: git clean, socket-proxy `:531`, prebuilt `:52`, single seeder, no ollama/otel service.
