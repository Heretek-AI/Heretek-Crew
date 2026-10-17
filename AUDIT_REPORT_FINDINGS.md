# Adversarial Three-Subagent Fleet & Architecture Audit — Findings

**Target:** `/home/john/Projects/Heretek-Crew`
**Date:** 2026-10-17 | **Formation:** Alpha (Runtime), Beta (Version/Arch), Gamma (Security)
**Cardinal rule enforced:** Tests were re-run, not trusted. Every P0/P1 below cites `file:line` + proof command.
**Subagent sessions:** Alpha `ses_eb8d232b6ffe3Y277d9mkMw84w`, Beta `ses_eb8d232aeffepVroHNDsueH3k4`, Gamma `ses_eb8d232a6ffenCe95W7Q512FL4`

## Executive Summary

- **Shim core, seeds, backup/restore gates, Dockerfile user-drop are substantively real.** `test-shim.sh` 28/28 passes, `shellcheck` clean, live `opencode run --dir` correctly rejected by real binary v2.0.30.
- **6 sidecar pins fail pull today (P0).** `docker compose pull` under affected profiles is broken by construction.
- **`dispatch-pipeline.sh` is a log printer, not an orchestrator (P0).** No API calls, no polling, no merge — phase 6 deletes the branch unmerged.
- **`local-ci-runner` can never reach its socket proxy (P0).** Profile mismatch + no `depends_on`/command.
- **Permissions are advisory, not enforcing (P0).** `dangerouslySkipPermissions:true` on all agents + shim `--auto` + `roles/programmer` allow-all. Socket-proxy `POST:1` preserves a host-escape primitive. 7 working default secrets in `docker-compose.sidecars.yml`.
- **Budget cap ≠ sum, versions lag, hardening gaps** (P1/P2 below).

---

## P0 / Critical — Broken deploy, fatal vuln, defunct registry

### P0-1a. `searxng` tag pruned — pull 404
- **File:** `docker-compose.sidecars.yml:27` `image: searxng/searxng:2024.10.16-ac56c663b`
- **Proof:** `curl -s -o /dev/null -w '%{http_code}' https://hub.docker.com/v2/repositories/searxng/searxng/tags/2024.10.16-ac56c663b` → `404`; `?name=2024.10.16` count=0. Current tags are `2026.10.x-*`.
- **Fix (re-pin to live tag, verify before commit):**
```bash
TAG=$(curl -s 'https://hub.docker.com/v2/repositories/searxng/searxng/tags?page_size=5&ordering=-last_updated' | jq -r '.results[0].name')
echo "$TAG" # expect 2026.10.x-*
# then edit:
```
```diff
-    image: searxng/searxng:2024.10.16-ac56c663b
+    image: searxng/searxng:<LIVE-TAG-FROM-ABOVE> # e.g. 2026.10.11-9d5b5774f — re-verify with hub API
```

### P0-1b. `radare2:6.0.0` nonexistent — pull 404
- **File:** `docker-compose.sidecars.yml:295` `image: radare/radare2:6.0.0`
- **Proof:** hub tag `6.0.0` → `404`; neighbors `6.0.2` → `200`, `6.2.4` → `200`, `5.9.8` → `200`.
- **Fix:**
```diff
-    image: radare/radare2:6.0.0
+    image: radare/radare2:6.2.4
```

### P0-1c. `hound:v0.6.0` wrong prefix — pull 404
- **File:** `docker-compose.sidecars.yml:318` `image: ghcr.io/hound-search/hound:v0.6.0`
- **Proof:** GHCR manifest `v0.6.0` → `404`; `0.6.0` (no `v`) → `200`. Tag list: `['latest','0.5.0','0.5.1','0.6.0']`.
- **Fix:**
```diff
-    image: ghcr.io/hound-search/hound:v0.6.0
+    image: ghcr.io/hound-search/hound:0.6.0
```

### P0-1d. `litellm:v1.54.0` wrong prefix — pull 404
- **File:** `docker-compose.sidecars.yml:461` `image: ghcr.io/berriai/litellm:v1.54.0`
- **Proof:** `v1.54.0` → `404`; `main-v1.54.0` → `200`. Upstream publishes `main-vX.Y.Z`.
- **Fix (also ~10mo stale — prefer newer stable):**
```diff
-    image: ghcr.io/berriai/litellm:v1.54.0
+    image: ghcr.io/berriai/litellm:main-v1.54.0
 # better: audit then pin newest main-v1.65+ / v1.66-stable digest
```

### P0-1e. `piston:v2.0.0` has no such tag — only `latest` published
- **File:** `docker-compose.sidecars.yml:384` `image: ghcr.io/engineer-man/piston:v2.0.0`
- **Proof:** GHCR tag list = `['latest']` only; `v2.0.0` → `404`.
- **Fix (architectural decision required — zero-`latest` policy conflicts with upstream):**
```bash
# Option A (preferred): pin by digest on latest
docker buildx imagetools inspect ghcr.io/engineer-man/piston:latest --format '{{json .Manifest}}' | jq .
```
```diff
-    image: ghcr.io/engineer-man/piston:v2.0.0
+    image: ghcr.io/engineer-man/piston@sha256:<DIGEST-FROM-INSPECT>
 # Option B: vendor/self-build piston and push to ghcr.io/heretek-ai/piston:<semver>
```

### P0-1f. `minio/minio` repo withdrawn from Docker Hub — pull fails for any tag
- **File:** `docker-compose.sidecars.yml:508` `image: minio/minio:RELEASE.2024-11-07T00-52-20Z`
- **Proof:** Docker Hub `minio/minio` API returns `{"message":"object not found"}` — MinIO now ships via `quay.io/minio/minio`.
- **Fix:**
```diff
-    image: minio/minio:RELEASE.2024-11-07T00-52-20Z
+    image: quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z
 # then: docker buildx imagetools inspect <new> && convert to @sha256: digest pin
 # alt: replace with still-published S3 mock (e.g. adobe/s3mock or localstack) if MinIO licensing is a concern
```

### P0-2. `dispatch-pipeline.sh` hollow orchestrator + destructive “merge”
- **Files:** `scripts/dispatch-pipeline.sh:88-164`, `scripts/worktree-manager.sh:99,102`
- **Proof commands:**
```bash
grep -c 'curl\|api\|poll\|sleep\|PATCH\|POST\|GET' scripts/dispatch-pipeline.sh # → 1 (“status log” dry-run string, :161)
sed -n '88,164p' scripts/dispatch-pipeline.sh # phases 1,2,4,5 only log_step; phase 6 only archive, no git merge
grep -n 'merge\|fast-forward' scripts/dispatch-pipeline.sh # header :155 claims merge, body has none
```
Raw: phases 1/2/4/5 identical in dry-run vs execute (log-only); `COMPLETE ... finished successfully` at `:166` prints despite doing nothing; `archive` runs `git worktree remove --force` + `git branch -D` (unmerged branch destroyed, only `patch.diff` survives, nobody applies it).
- **Fix (fail-closed minimal — stop claiming merge; require explicit apply or real merge):**
```diff
-# Phase 6: Merge & Non-Destructive Archiving
+# Phase 6: Archive ONLY (no merge performed — see below)
 ...
-  bash scripts/worktree-manager.sh archive "${TICKET_ID}" "${BASE_BRANCH}"
+  echo "error: auto-merge disabled (fail-closed): review ${WORKTREE_DIR} then run git merge explicitly" >&2
+  echo "worktree retained at ${WORKTREE_DIR}; archive only after merge: bash scripts/worktree-manager.sh archive \"${TICKET_ID}\" \"${BASE_BRANCH}\"" >&2
+  exit 1
 # Full fix: implement Paperclip ticket PATCH (todo→in_progress→in_review→done),
 # agent task POSTs per phase, artifact existence asserts, and git merge --ff-only
 # before archive. Until then do not advertise a 6-phase relay.
```

### P0-3. `local-ci-runner` wiring broken — proxy unreachable, no runtime
- **File:** `docker-compose.sidecars.yml:608-620` vs `:354-381`
- **Proof (static, conclusive):**
```bash
sed -n '354,381p;608,620p' docker-compose.sidecars.yml
# runner profiles: ["ci","qa-testing"]; proxy profiles: ["core","devsec"] → --profile ci never schedules proxy
# runner has no depends_on/command/entrypoint; restart:"no"; DOCKER_HOST=tcp://docker-socket-proxy:2375 dangles
# volume ./workspaces:/workspaces vs paperclip ./workspaces:/paperclip/workspaces (:87) — path mismatch
```
- **Fix:**
```diff
   local-ci-runner:
     image: ghcr.io/catthehacker/ubuntu:act-22.04
-    profiles: ["ci", "qa-testing"]
+    profiles: ["ci", "qa-testing", "core"]
     restart: "no"
+    depends_on:
+      docker-socket-proxy:
+        condition: service_healthy
+    command: ["sleep", "infinity"]
     environment:
       DOCKER_HOST: "tcp://docker-socket-proxy:2375"
     volumes:
       - ./.github/workflows:/workflows:ro
-      - ./workspaces:/workspaces
+      - ./workspaces:/paperclip/workspaces
```
Plus either add `docker-socket-proxy` to `ci` profile or document required `--profile core,ci` invocation. See P0-5 for `POST:1` hardening.

### P0-4. Permissions advisory: `dangerouslySkipPermissions` + `--auto` + programmer allow-all
- **Files:** `scripts/seed-50-fleet.sh:367-368` (`"env" XDG..., "dangerouslySkipPermissions": True`), `scripts/seed-company.sh:200-201` (same), `scripts/opencode-shim.sh:214-221` (`--auto` injection), `roles/programmer/opencode/opencode.json:4-6` (`{"action":"*","resource":"*","effect":"allow"}`), `roles/programmer/AGENTS.md:1-8` (admits full access)
- **Proof:**
```bash
grep -rn dangerouslySkipPermissions scripts/ # both seed scripts, every agent
sed -n '214,221p' scripts/opencode-shim.sh
cat roles/programmer/opencode/opencode.json
grep -c '"action": "shell".*"effect": "allow"' roles/exec-director/opencode/opencode.json # prefix-glob allows present
```
Net: prompt-injection in a programmer ticket = arbitrary command as `node` with `./workspaces` write + all provider keys from `docker-compose.yml:70-80` in env. Fleet `shell git status* allow`-style prefix patterns (176 allows, e.g. `roles/exec-director/opencode/opencode.json:21-24`) are string-prefix fragile (`git status;…` continuations) if enforcer is prefix-match.
- **Fix (defense in depth; keep function):**
```diff
 # seed-50-fleet.sh build_agent_payload + seed-company.sh equivalent:
-        "dangerouslySkipPermissions": True,
+        "dangerouslySkipPermissions": False,
```
```diff
 # roles/programmer/opencode/opencode.json — replace allow-all with enumerated allows + deny tail:
-    { "action": "*", "resource": "*", "effect": "allow" }
+    { "action": "fs:read", "resource": "*", "effect": "allow" },
+    { "action": "fs:write", "resource": "/paperclip/workspaces/**", "effect": "allow" },
+    { "action": "shell", "resource": "git *", "effect": "allow" },
+    ... (enumerate pytest/npm/cargo/rg per stack, no bare prefix without argv-aware matcher) ...
+    { "action": "shell", "resource": "*", "effect": "deny" }
```
Plus: document that `--auto` + skip makes JSON permissions hints; add runtime smoke test attempting a denied tool and asserting refusal.

### P0-5. `docker-socket-proxy` `POST:1` = host-escape primitive via CI runner
- **File:** `docker-compose.sidecars.yml:354-381` (`CONTAINERS:1,IMAGES:1,POST:1,VOLUMES:0,NETWORKS:0`), `:608-620` runner (`DOCKER_HOST`, writable `./workspaces`)
- **Proof:** `VOLUMES=0/NETWORKS=0` blocks `/volumes/*` + `/networks/*` groups only. `POST /containers/create` body `Binds:["/:/host"]` or `--privileged` is part of create, not the blocked volume endpoint → pull → create → start → chroot. `BUILD`/`EXEC` unset (defaults allow). Any untrusted workflow/PR content executed in `act` = escape.
- **Fix:**
```diff
       CONTAINERS: "1"
       IMAGES: "1"
       INFO: "1"
       VERSION: "1"
-      POST: "1"
+      POST: "0"
+      BUILD: "0"
+      EXEC: "0"
       VOLUMES: "0"
       NETWORKS: "0"
       NODES: "0"
       SWARM: "0"
       SYSTEM: "0"
+      AUTH: "0"
```
Then verify CI still functions with GET-only proxy; if `act` needs image pull through proxy, run pulls on host Docker directly and keep proxy read-only, or isolate runner on a dedicated daemon.

### P0-6. Seven working default secrets in sidecars (public documented credentials)
- **Files:** `docker-compose.sidecars.yml:39,96,173,229,438,469,518-519`, `.env.example:82`
```bash
grep -n ':-' docker-compose.sidecars.yml
# :39 SEARXNG_SECRET:-dev_… :96/:173 FIRECRAWL_DB_PASSWORD:-firecrawl_secret_nuq_2026
# :229 BROWSERLESS_TOKEN:-heretek-stealth-token :438 NEO4J_PASSWORD:-heretek_knowledge_graph_secret_2026
# :469 LITELLM_MASTER_KEY:-sk-heretek-proxy-master-key :518-519 MINIO_ROOT_*:-heretekadmin/heretekminiopassword2026
# :470 DATABASE_URL ... POSTGRES_PASSWORD:-paperclip (fail-open fallback vs core :? fail-closed)
```
- **Fix (fail-closed like core `docker-compose.yml:26,58,64`):**
```diff
-      SEARXNG_SECRET: "${SEARXNG_SECRET:-dev_searxng_secret_key_heretek_crew_2026}"
+      SEARXNG_SECRET: "${SEARXNG_SECRET:?SEARXNG_SECRET must be set in .env}"
-      POSTGRES_PASSWORD: ${FIRECRAWL_DB_PASSWORD:-firecrawl_secret_nuq_2026}
+      POSTGRES_PASSWORD: ${FIRECRAWL_DB_PASSWORD:?FIRECRAWL_DB_PASSWORD must be set in .env}
-      TOKEN: "${BROWSERLESS_TOKEN:-heretek-stealth-token}"
+      TOKEN: "${BROWSERLESS_TOKEN:?BROWSERLESS_TOKEN must be set in .env}"
-      NEO4J_AUTH: "neo4j/${NEO4J_PASSWORD:-heretek_knowledge_graph_secret_2026}"
+      NEO4J_AUTH: "neo4j/${NEO4J_PASSWORD:?NEO4J_PASSWORD must be set in .env}"
-      LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY:-sk-heretek-proxy-master-key}"
+      LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY must be set in .env}"
-      MINIO_ROOT_USER: "${MINIO_ROOT_USER:-heretekadmin}"
-      MINIO_ROOT_PASSWORD: "${MINIO_ROOT_PASSWORD:-heretekminiopassword2026}"
+      MINIO_ROOT_USER: "${MINIO_ROOT_USER:?MINIO_ROOT_USER must be set in .env}"
+      MINIO_ROOT_PASSWORD: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD must be set in .env}"
-      DATABASE_URL: "postgres://${POSTGRES_USER:-paperclip}:${POSTGRES_PASSWORD:-paperclip}@postgres:5432/${POSTGRES_DB:-paperclip}"
+      DATABASE_URL: "postgres://${POSTGRES_USER:-paperclip}:${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set in .env}@postgres:5432/${POSTGRES_DB:-paperclip}"
```
Add matching `CHANGE_ME__` entries to `.env.example`; `make up` must fail without them.

---

## P1 / High — Deprecated, escape-adjacent, severe drift

### P1-1. Shim drops `--variant` with short `-m`
- **File:** `scripts/opencode-shim.sh:163-183` tracks only `--model`/`--model=`; `-m` falls to wildcard `:189-192` while `--variant` is consumed `:151-158`.
- **Proof (mock binary):** `OPENCODE_REAL_BIN=/tmp/mock run -m mymodel --variant high prompt` → `run --auto -m mymodel prompt` (variant lost, silent).
- **Fix:**
```diff
-        --model)
+        --model|-m)
 ...
-        --model=*)
+        --model=*|-m=*)
```
Add tests: `-m` + `--variant` (both orders), `-m=value` + `--variant=value`, existing-`#` preservation.

### P1-2. Worktree archive destructive + unsanitized IDs + masked failures
- **File:** `scripts/worktree-manager.sh:27-48,65-106`
- **Proof:**
```bash
grep -n 'command -v git' scripts/worktree-manager.sh # → 0 hits
# probe: create '../evil' saved only by git's ref check; create '/tmp/wt-abs' succeeds → workspaces/tickets/tmp/wt-abs + branch ticket-/tmp/wt-abs
sed -n '83-85,99,102p' scripts/worktree-manager.sh # || true on diff/status/log; remove --force; branch -D
```
- **Fix:**
```diff
+command -v git >/dev/null 2>&1 || { echo "error: git is required" >&2; exit 127; }
 cmd_create() {
   local ticket_id="$1"
+  [[ "${ticket_id}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$ ]] || { echo "error: invalid ticket-id '${ticket_id}' (allowlist [A-Za-z0-9._-])" >&2; exit 2; }
 ...
-  git -C "${target_dir}" diff "${base_branch}" > "${archive_dir}/patch.diff" || true
-  git -C "${target_dir}" status --short > "${archive_dir}/status.log" || true
-  git -C "${target_dir}" log -n 20 --oneline > "${archive_dir}/commits.log" || true
+  git -C "${target_dir}" diff "${base_branch}" > "${archive_dir}/patch.diff"
+  git -C "${target_dir}" status --short > "${archive_dir}/status.log"
+  git -C "${target_dir}" log -n 20 --oneline > "${archive_dir}/commits.log"
 ...
-  git worktree remove --force "${target_dir}"
+  git worktree remove "${target_dir}" # fail if dirty/locked — never --force in archive path
-    git branch -D "${branch_name}" || true
+    echo "note: retaining branch ${branch_name}; delete explicitly after merge (git branch -d)" >&2
```
Rename “Non-Destructive Archiving” until force paths are gone.

### P1-3. Restore has no connection termination; verification unasserted
- **File:** `scripts/restore-db.sh:94-117`
- **Proof:** `grep -n 'pg_terminate\|pg_cancel\|lock_timeout' scripts/*.sh` → 0; restore takes `AccessExclusiveLock` with only 120s startup wait; `TABLES` printed never asserted (`:116-117`); `read -r CONFIRM` on closed stdin aborts via `set -e` with poor signal.
- **Fix:**
```diff
 echo "[restore] restoring ${FILE} into ${POSTGRES_DB} (ON_ERROR_STOP=1)..."
+echo "[restore] terminating backend connections to ${POSTGRES_DB}..."
+docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d postgres -v ON_ERROR_STOP=1 -q \
+  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${POSTGRES_DB}' AND pid <> pg_backend_pid();"
 case "${FILE}" in
 ...
 echo "[restore] done: public schema holds ${TABLES} table(s)"
+if [[ ! "${TABLES}" =~ ^[0-9]+$ ]] || [[ "${TABLES}" -eq 0 ]]; then echo "error: restore verification failed (0 tables)" >&2; exit 1; fi
+if [[ ! -t 0 && "${ASSUME_YES}" != "1" ]]; then echo "error: no TTY for confirmation (use --yes/RESTORE_YES=1)" >&2; exit 1; fi
```

### P1-4. `OPENCODE_DISABLE_PROJECT_CONFIG` + runtime user delegated to unaudited upstream
- **Files:** `AGENTS.md:21`, `NOTES.md:63` claim it; `grep -rn OPENCODE_DISABLE_PROJECT_CONFIG --include='*.yml' --include='*.sh' --include='*.json' .` → prose only, zero enforcement; `docker/Dockerfile:37,80-87` relies on inherited `docker-entrypoint.sh` `exec gosu node`, not vendored.
- **Fix:** add defense-in-depth env in `docker-compose.yml` paperclip service + seed payloads and assert at boot:
```diff
     environment:
+      OPENCODE_DISABLE_PROJECT_CONFIG: "true"
       XDG_CONFIG_HOME: "/roles"
```
```bash
docker compose exec paperclip sh -c 'id; echo $OPENCODE_DISABLE_PROJECT_CONFIG' # expect uid=1000(node) + true
```

### P1-5. Permission schema fragmentation + MCP bypasses
- **Files:** 50 fleet roles `fs:*/shell/git_*/harness_*` (e.g. `roles/compliance-auditor/opencode/opencode.json:5-49`) vs 6 legacy `read/glob/grep/list/edit/write/bash/task` (`roles/director/opencode/opencode.json:4-16`); deny tails `shell * deny` vs `bash * deny` — `AGENTS.md:116` literal false for 6/56. `roles/dba-specialist/opencode/opencode.json:19-23` (`psql deny` vs `postgres_* allow` via `${POSTGRES_READONLY_URL}`), `roles/k8s-orchestrator/opencode/opencode.json:40-54` (`kubectl apply/delete deny` vs `kubernetes_*/docker_*/harness_* allow`), `roles/qa:10,13-14` (`bash * allow` + edit/write deny — exfil via curl/redirection), `roles/tester:5-12` (test-scoped writes + `bash * allow` = code exec via runner; `{test,spec}` glob overbroad).
- **Fix:** unify on one dialect; add explicit MCP deny tails (`{action:"*_ *",resource:"*",effect:"deny"}` per namespace or enumerate); set `POSTGRES_READONLY_URL` to a true read-only role at DB GRANT level (deny alone insufficient); narrow `qa/tester` bash to named test commands.

### P1-6. Network exposure exceptions + lateral movement
- **Files:** `docker-compose.yml:109-111` (caddy `80:80,443:443` all-interfaces under `--profile proxy`), `docker-compose.sidecars.yml:249` (`--web-host 0.0.0.0 --set block_global=false`), `:303` (`r2 -qc=H 0.0.0.0:9090`), `:580-582` (`privileged:true + /dev/kvm`), `docker-compose.yml:128-134` (`NET_ADMIN,SYS_MODULE + /dev/net/tun`).
- **Proof:** all `ports:` otherwise `127.0.0.1:`-bound (`:35,157,224,254,324,412,436,467,493,516,539,560,587-588`); intra-`heretek` `expose:` wide open (qdrant/neo4j-default-secret/minio-defaults/browserless-default-token/redis/rabbit/piston/gotenberg/mailpit/jaeger all reachable from compromised paperclip/CI container).
- **Fix:** document proxy-profile exposure + require `PAPERCLIP_DEPLOYMENT_EXPOSURE=private` + auth; scope mitmproxy to test-only profile with `block_global=true` default; add API keys/tokens to qdrant/redis/rabbit where supported or add network policies; gate `mobile`/`devsec` profiles separately.

### P1-7. Supply chain: unpinned MCP/npx/uvx + `opencode-mem` + weak smoke gate
- **Proof:** `grep -rhn 'npx -y\|uvx' roles/*/opencode/opencode.json` → ~50 unpinned (`server-github`, `git-mcp-server`, `aws-mcp`, `mcp-openapi-schema-explorer`, `k6-mcp`, `ollama-mcp`, `prometheus-mcp`, `mcp-server-qdrant`); only `@playwright/mcp@0.0.83`, `chrome-devtools-mcp@1.11.0`, `@mobile-next/mobile-mcp@0.1.2` pinned. Plugins `opencode-mem`, `opencode-harness`, `opencode-rea`, `@prevalentware/opencode-goal-plugin` unversioned. `smoke-test.sh:242-251` greps only `:latest`/`@latest` → floating-unpinned passes by design. `harness_*` glob semantics vs runtime tool names UNVERIFIABLE statically (tarball has `hashline-tools.js,ast-codemod.js,repomap.js,edit-transaction.js` but no `tool("…")` manifest).
- **Fix:** pin every `npx -y pkg@x.y.z` + `uvx pkg==x.y.z`, add `opencode-mem` install+`npm ls` assert in `docker/Dockerfile:51-55` and workflow `:99-100`, extend smoke-test to fail on any unpinned `npx/uvx`, runtime smoke: invoke a harness tool and assert registration.

### P1-8. Fleet budget cap mismatch + seed holes
- **Files:** `scripts/seed-50-fleet.sh:87` (`FLEET_BUDGET_CAP_CENTS:-1279000`), `:260-312` (sum `1270000`), `:263` comment admits gap, `:431-433` WARNING every run; `:539-544` PATCH omits `reportsTo` when `want=""` (stray director reportsTo never cleared); `seed-company.sh:159` `$((USD*100))` rejects decimals (`BUDGET_DIRECTOR_USD=99.99` → arithmetic syntax error).
- **Fix:**
```diff
-FLEET_BUDGET_CAP_CENTS="${FLEET_BUDGET_CAP_CENTS:-1279000}"
+FLEET_BUDGET_CAP_CENTS="${FLEET_BUDGET_CAP_CENTS:-1270000}"
 # or correct catalog + role_budget_cents if $12,790 is authoritative
-  if os.environ["PATCH_REPORTS_TO"]:
-      payload["reportsTo"] = os.environ["PATCH_REPORTS_TO"]
+  payload["reportsTo"] = os.environ["PATCH_REPORTS_TO"] or None  # explicit clear supported by API; else PATCH reportsTo:null
 # decimal budgets: use python cents conversion, not $((USD*100))
```

### P1-9. Stale/outdated versions + missing guards
- `@opencode/cli+client 2.0.31 → 2.0.32` (`docker/Dockerfile:31-33,51-54`; npm `versions` ends `…2.0.31,2.0.32`).
- `rabbitmq:3.13.7` (`sidecars.yml:70`) — 4.x current since 2024, 3.13 EOL-adjacent; plan 4.x migration.
- `semgrep:1.97.0` (`:339`) ~1yr behind; security-scanner drift matters.
- `jaeger:all-in-one:1.63.0` (`:552`) — v1 deprecated for v2 (`jaegertracing/jaeger:2.x`); short-term ok, migrate medium-term.
- `ghidra MAXMEM=4G` vs `mem_limit:4g` (`:277` vs `:292`) — JVM+overhead equals limit → OOM risk.
- No healthcheck on core `paperclip`/`caddy`/`tailscale` (`docker-compose.yml`); no `cpus/mem_limit` on `postgres`/`caddy`/`tailscale`.
- `docker-compose.prebuilt.yml:21-22` `ghcr.io/heretek-ai/heretek-crew:v1.0.0` → `401` anonymously (private-or-missing indistinguishable); no `v1.0.0` git tag; workflow `:95-96` `opencode --version || --help` fallback can mask broken shim.
- Brief Claims 11.x cite `otel-collector:0.113.0`, `ollama:0.4.4`, `browserless:v2.18.0`, `mitmproxy:11.0.1`, `socket-proxy:0.1.1` — file has `browserless:v2.24.2`, `mitmproxy:11.0.2`, `socket-proxy:0.3.0`, no otel/ollama strings at all (stale brief or wrong revision).
- **Fix:** bump cli/client to `2.0.32` (+ README table), schedule rabbitmq4/semgrep/jaeger-v2, set `MAXMEM 3G` or limit `5g`, add healthchecks+caps, publish+verify prebuilt tag publicly or document private-pull, tighten validation to require `--version`, reconcile brief or add otel/ollama services.

---

## P2 / Medium — Lag, allocation, doc mismatch

- **P2-1.** `redis:7.4.1-alpine` (×2, `:10,:51`), `qdrant:v1.12.5`, `wiremock:3.10.0-alpine`, `mailpit:v1.21.8`, `gotenberg:8.15.0`, `neo4j:5.26.0-community-bullseye` — all resolve (200) but 1–2 minors behind or oldstable base (`bullseye`). Functional; add Renovate/Dependabot cadence. Neo4j 5.26 LTS choice defensible.
- **P2-2.** Backup nits (`scripts/backup-db.sh:70-94`): same-second rerun overwrites; retention `ls -1t | tail` whitespace-fragile. Fix: `%Y%m%d-%H%M%S-$RANDOM` or fail if exists; `find -print0 | sort -z`.
- **P2-3.** Container hardening (`docker/Dockerfile:37,64-66`, `docker-compose.yml:82,87,93-94`): root build + entrypoint-chown + writable `./workspaces:/paperclip/workspaces` + writable `paperclip-data:/paperclip`, default caps, no `read_only/cap_drop/no-new-privileges` on paperclip (only `firecrawl-playwright:129-134` has it). `/roles:ro` (`:85`) confirmed good. Add `cap_drop: [ALL]` + minimal `cap_add`, `read_only:true` with tmpfs where feasible, or document why not.
- **P2-4.** Enabling all sidecar profiles reserves ~36 GB (`sum mem_limit` = 36,228 MB). Add guard note in `SUPPORTING_SERVICES.md`/`README.md`: select profiles, do not `up` everything on small hosts.
- **P2-5.** `tailscale` needs `NET_ADMIN/SYS_MODULE` (legitimate) — keep profile-gated + documented.

## P3 / Low / Cleanups

- **P3-1.** Shim suite gaps (`scripts/test-shim.sh`): zero coverage for `OPENCODE_GO_API_KEY` (`shim:56-58`), empty `--variant=`, duplicate `--model`, `--dir` mid-argv with missing value. Add cases; assert pre-existing `OPENCODE_API_KEY` not clobbered.
- **P3-2.** `seed-company.sh` decimal-budget error is loud (exit 1) — good fail-closed, poor message. Validate with regex + descriptive error.
- **P3-3.** `restore-db.sh:83-92` closed-stdin abort via `set -e` — add explicit TTY check (see P1-3 diff).
- **P3-4.** `roles/` count 56 dirs vs “50 roles” claim — 6 legacy (`director,pm,programmer,tester,qa,designer`) coexist with 50 fleet roles. Clarify which set each seed asserts; remove or namespace legacy set.
- **P3-5.** `paperclip` image `heretek-crew/paperclip:wave1` + `PAPERCLIP_BASE_IMAGE` default `paperclip:official-local` — document build order in `Makefile` target to avoid stale base.

---

## Verified Clean / Confirmed (do not regress)

- Shim `--dir` strip (space + `=`), bare-trailing `--dir`, `--auto` exactly-once incl. `--auto=false`, `--session`/`-s` preservation, `--` boundary, stdio streaming/`exec`, exit-code propagation, fail-closed 127 — `scripts/opencode-shim.sh:56-58,104-225` + 28/28 tests.
- `postgres:17-alpine` internal-only (`docker-compose.yml:22,28-36`), loopback `127.0.0.1:3100:3100` (`:55-56`), all sidecar `ports:` loopback-bound, `postgres` healthcheck `pg_isready`.
- `caddy:2.11.7-alpine`, `tailscale:v1.104.1`, `node:24-trixie-slim` (Node 24 LTS), `@heretek-ai/opencode-harness@1.0.7` = npm latest, digest-pinned `nuq-postgres` + `playwright-service`, `firecrawl:2.10.19`, `qdrant`, `neo4j`, `wiremock`, `mailpit`, `docker-android:emulator_14.0_v3.8.0-p1`, `act-22.04` all resolve.
- Seed two-pass idempotency + drift-only PATCH, heartbeat 48-off/2-on (1800/3600), 51 docs in dry-run, budget WARNING accurate.
- Backup timestamp/compression/empty-guard/health-gate, restore FILE/extension/typed-confirm/`ON_ERROR_STOP=1`/post-verify.
- `.gitignore:7-11` (`.env`, `backups/`), no secret echo in scripts, Dockerfile pinning + `tini` + binary asserts.

## Appendix — Proof commands run

```bash
# registry (Beta live 2026-10-17; re-run to confirm before fixing)
for t in 2024.10.16-ac56c663b; do curl -s -o /dev/null -w "%{http_code}\n" "https://hub.docker.com/v2/repositories/searxng/searxng/tags/$t"; done
for t in 6.0.0 6.0.2 6.2.4 5.9.8; do echo -n "radare2:$t "; curl -s -o /dev/null -w "%{http_code}\n" "https://hub.docker.com/v2/repositories/radare/radare2/tags/$t"; done
# GHCR (scoped token): manifest for hound v0.6.0→404 / 0.6.0→200; litellm v1.54.0→404 / main-v1.54.0→200; piston v2.0.0→404 / latest→200; firecrawl digests→200
npm view @opencode/cli version; npm view @opencode/client version # → 2.0.32
npm view @heretek-ai/opencode-harness version # → 1.0.7
bash scripts/test-shim.sh # 28 passed
opencode run --dir /tmp hi # ERROR Unrecognized flag: --dir, exit 1 (premise confirmed)
grep -rn dangerouslySkipPermissions scripts/; grep -n 'POST' docker-compose.sidecars.yml
grep -n ':-' docker-compose.sidecars.yml; grep -rn OPENCODE_DISABLE_PROJECT_CONFIG . --include='*.sh' --include='*.yml' --include='*.json'
bash scripts/seed-50-fleet.sh --dry-run 2>&1 | tail -5 # total 1270000 vs cap 1279000 WARNING
```
