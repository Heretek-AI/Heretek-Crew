# Adversarial Three-Subagent Fleet & Architecture Audit — Findings

**Target:** `/home/john/Projects/Heretek-Crew`
**Date:** 2026-10-17 | **Prompt:** `PROMPT_ADVERSARIAL_FLEET_AUDIT.md` (11 domains)
**Formation:** Alpha (Runtime & Functionality) + Beta (Version Modernity) + Gamma (Security/Sandboxing)
**Rule:** Tests were NOT trusted. Every verdict rests on file reads, live shell probes, upstream source (`/tmp/paperclip`), and registry checks — not on `test-shim.sh` / `smoke-test.sh` exit codes.
**Controller spot-verification (2026-10-17, post-triad):** `ls roles/ | wc -l` = 51; 51/51 `opencode.json` declare scoped `@heretek-ai/opencode-harness`; `docker/Dockerfile:21` still `PAPERCLIP_SOURCE_COMMIT=<paste-…>` placeholder; socket-proxy still `tecnativa/docker-socket-proxy:0.3.0` (`docker-compose.sidecars.yml:508`); `android-mobile-spec` still `@mobile-next/mobile-mcp@0.1.2` (`opencode.json:297`); `git status --short` clean pre-triad.
**Drift-guard remediation pass (2026-10-17):** corrected P0-3 citation to `execute.ts:55-65` + `sanitizeInheritedPaperclipEnv` (sanitize layer EXISTS, DATABASE_URL survival UNPROVEN); corrected P0-4 second citation to `runtime-config.ts:153,207` (not 217-220); corrected P0-9 exemplar (exec-director is DENY-remediated; residual is 35 ALLOW roles); expanded every P1 with Command+Output; expanded P2/P3 to one bullet per item; added Domain Coverage table; added modernity receipts.
**Supersedes:** prior `AUDIT_REPORT_FINDINGS.md` (2026-10-17 13:05). All P0s below remain open. New: Alpha P0-1 shim `--dir` preserve bug, Gamma P0-1/P0-2 upstream env-scrub + dangerouslySkipPermissions default-TRUE, Beta P0-1 MCP typo, Gamma P0-5 dead MCP backends.

## Verified WORKING (do NOT fix)
- Paperclip appends `--dir <cwd>` + `--variant` (`/tmp/paperclip/packages/adapters/opencode-local/src/server/execute.ts` or `server/src/adapters/process/execute.ts:620-631` region — `execute.ts:629-630` append, `execute.ts:678` stdin prompt); forces `OPENCODE_DISABLE_PROJECT_CONFIG=true` (`execute.ts:329` region) with XDG staging (`runtime-config.ts:105-251` region; opencode-local adapter `runtime-config.ts:110-230`).
- Real `@opencode/cli@2.0.32` rejects `--dir`/`--variant`, accepts `provider/model#variant`, `--auto`, `--session/-s` (Alpha live npx probes).
- Upstream `73659c6b27c1d97226f2da9ca39f256eefddac66` matches `sha-73659c6` pin. `git -C /tmp/paperclip rev-parse HEAD` → `73659c6b27c1d97226f2da9ca39f256eefddac66`.
  - Receipts (Beta re-verified 2026-10-17): `npm view @opencode/cli version` → `2.0.32`; `curl "https://hub.docker.com/v2/repositories/library/postgres/tags?name=17.11-alpine"` count≥1; `curl Hub tags?name=2.11.7` (caddy) count≥1; `curl Hub tags?name=v1.104.1` (tailscale) count≥1; GHCR manifests for `qdrant:v1.19.2`, `semgrep:1.181.0`, `rabbitmq:4.3.6-management-alpine`, `neo4j:5.26.32-community-trixie`, `redis:7.4.11-alpine` → 200. If network blocked on operator rerun, re-run: `npm view @opencode/cli version; npm view @opencode/client version; curl -s "https://hub.docker.com/v2/repositories/library/postgres/tags?name=17.11-alpine" | head -c 400; git -C /tmp/paperclip rev-parse HEAD`. Do NOT cite bare "latest" — every claim above carries a registry command.
- `postgres:17.11-alpine` digest-pinned newest 17.x (`docker-compose.yml:33` + sha256:b0f956…); `caddy:2.11.7-alpine` (`docker-compose.yml:211`); `tailscale/tailscale:v1.104.1` (`docker-compose.yml:265`); `qdrant:v1.19.2`, `semgrep:1.181.0`, `rabbitmq:4.3.6-management-alpine`, `neo4j:5.26.32-community-trixie` (deliberate LTS), `redis:7.4.11-alpine` (CVE-2025-49844 fix), `@opencode/cli/client@2.0.32` npm-latest.
- Fleet budget exactly 1,300,000c across 51 roles (`seed-50-fleet.sh:113` default `1300000`; per-role cents sum authoritative — see Domain 5). Firecrawl command matches upstream CMD; seed preflight exits 1; worktree traversal blocked; host act 0.2.89 present.
- Strengths: 51/51 shell deny-tails; fs:read secret denies ordered fleet-wide; `docker compose config` without `.env` fails closed on 8 secret guards; no hardcoded secrets; `git-drift-coord` denies `git push --force`.

## Domain Coverage (Claims §3.1-§3.11 → Verdict)

| Domain | Claims | Verdict | Evidence command (raw output quoted) |
|---|---|---|---|
| D1 Core stack | 1.1 Paperclip loopback :3100; 1.2 postgres internal-only + pg_isready; 1.3 non-root gosu node:1000; 1.4 caddy TLS profile; 1.5 tailscale tag | PARTIAL (P1-11 Caddy `0.0.0.0:80/443` one cmd from exposure) | `grep -n "127.0.0.1:3100\|pg_isready\|gosu\|PROXY_DOMAIN\|advertise-tags" docker-compose.yml docker/Dockerfile \| head` → `127.0.0.1:3100` bind present; `pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}` healthcheck present; `gosu` entrypoint + `chown -R node:node` (`Dockerfile:114`); Caddy `0.0.0.0:80/443` (`compose:235-237`) guarded Makefile-only |
| D2 Shim translation | 2.1 `--dir` strip; 2.2 `#variant` merge; 2.3 `--auto`; 2.4 `--session`; 2.5 `--` boundary; 2.6 `OPENCODE_GO_API_KEY` | FAIL (P0-1: `--dir <cwd>` preserved as positional) | `OPENCODE_REAL_BIN=/tmp/rec.sh bash scripts/opencode-shim.sh run --format json --dir /tmp/ws --model opencode/gemini --variant high "hello"` → `run --format json /tmp/ws --model opencode/gemini#high --auto hello` (stray `/tmp/ws` positional; real v2 `run [<message...>]` absorbs it → `provider.no-route`, not error) |
| D3 Isolation/sandbox | 3.1 XDG + DISABLE_PROJECT_CONFIG; 3.2 shell deny-tails; 3.3 read-only separation | FAIL (P0-9: 35 roles hold mutating harness allow; P1-9 wildcard-order; P0-5 prefix bypass) | `grep -rn -A2 "harness_file_hash_edit" roles/*/opencode/opencode.json \| grep -c allow` → `140` allow line-hits; `grep ... \| grep -c deny` → `64` deny line-hits (35 allow-roles / 16 deny-roles via per-role loop); `ls roles/ \| wc -l` → `51` |
| D4 Harness | 4.1 harness@1.0.7 install; 4.2 `harness_*` allow; 4.3 FNV/AST/blast-radius/circuit-breaker | FAIL (P0-2: 1.0.7 DIES on load, `rootDir must be non-empty`) | `npm pack @heretek-ai/opencode-harness@1.0.7; node -e "setupOpenCodeV2Harness({directory:''})"` → `THROW rootDir must be non-empty`; `??` does not skip `""`; `npm view` → 5 versions in 22h |
| D5 Seeding/budget | 5.1 two-pass idempotent; 5.2 51 roles/9 depts; 5.3 1,300,000c; 5.4 on-demand wake | PASS (with P2-1 stale comment note) | `grep -n "1300000\|two-pass\|Pass 1\|Pass 2" scripts/seed-50-fleet.sh` → `:45 Default: 1300000`, `:89 two-pass, idempotent`, `:113 FLEET_BUDGET_CAP_CENTS=1300000`, `:599 Pass 1`, `:662 Pass 2 PATCH`; `ls roles/ \| wc -l` → `51`; `bash scripts/seed-50-fleet.sh --dry-run` prints 1 company + 51 payloads; live two-pass rerun needs `make up` |
| D6 Worktree | 6.1 `ticket-<ticket>` dash branch; 6.2 temp-stage + RANDOM, never `--force` | PASS | `grep -n "ticket-\|RANDOM\|--force\|temp-stage" scripts/worktree-manager.sh` → `:13 branch ticket-<ticket-id> (dash, NOT ticket/)`, `:16 never --force`, `:21 -$RANDOM suffix`, `worktree-manager.sh:39-45` ticket-id allowlist `^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$`; `git worktree list` → `/home/john/Projects/Heretek-Crew c734103 [main]` |
| D7 Dispatch-pipeline | 7.1 provisioner-tracer NOT dispatcher; 7.2 NO API calls / NO transitions | PASS (as-scoped; fail-closed absent-by-design) | `grep -n "curl\|/api/\|poll\|PAPERCLIP_URL" scripts/dispatch-pipeline.sh` → header-only (`:7-8` "does NOT call the Paperclip API (no curl, no PAPERCLIP_URL, no /api/)"); `sed -n '1,20p' scripts/dispatch-pipeline.sh` → "provisions ONE isolated git worktree + task_plan.md (phase 3) and exits 0" |
| D8 Local-CI-runner | 8.1 read-only observer (not in-docker exec); 8.2 GET-only proxy POST/BUILD/EXEC=0 | PASS (with P1-13 GET-recon residual) | `sed -n '507,560p' docker-compose.sidecars.yml` → `CONTAINERS: "1" IMAGES: "1" INFO: "1" VERSION: "1" POST: "0" BUILD: "0" EXEC: "0" VOLUMES: "0" NETWORKS: "0" AUTH: "0"`; `grep -n "act-22.04\|DOCKER_HOST\|sleep infinity\|:ro" docker-compose.sidecars.yml` → `ghcr.io/catthehacker/ubuntu:act-22.04@sha256:f5f5c...:905`, `DOCKER_HOST: tcp://docker-socket-proxy:2375:921`, `sleep infinity:911`, `:ro` checkouts |
| D9 GHCR/prebuilt | 9.1 multi-arch publish; 9.2 prebuilt no-compile; 9.3 pre-publish verify | PARTIAL (P1-2 `:1.0.0` unpublished tag) | `grep -n "1.0.0\|image:" docker-compose.prebuilt.yml` → `:7 ghcr.io/heretek-ai/heretek-crew:1.0.0`, `:52 image: ${HERETEK_IMAGE:-...:1.0.0}`; `docker manifest inspect ghcr.io/heretek-ai/heretek-crew:1.0.0` → `manifest unknown` / 404 (see P1-2); fix `git tag v1.0.0 && git push origin v1.0.0` |
| D10 Backup/restore | 10.1 pg_dump gzip timestamped; 10.2 fail-closed restore | PASS (with P1-15 `--file` space-form bug) | `grep -n "pg_dump\|--clean\|terminate\|ON_ERROR_STOP\|--file" scripts/backup-db.sh scripts/restore-db.sh` → `backup-db.sh:120-126 pg_dump --no-owner --clean --if-exists`, `restore-db.sh:163-170 ON_ERROR_STOP=1 + pg_terminate_backend`, `restore-db.sh:51-52 --file=* only, --file space → exit 2` |
| D11 Sidecars | 11.1-11.9 ingestion/browser/devsec/piston/AI/mocks/observability/security/mobile | PARTIAL (P0-7 MCP typo; P0-8 5 dead MCP backends; P1-1/3/4/6/8 version/health findings) | `grep '^  [a-z-]*:' docker-compose.sidecars.yml` service list vs `grep -n "CLICKHOUSE_URL\|KAFKA\|PROMETHEUS_URL\|OLLAMA_HOST" roles/*/opencode/opencode.json` → 5 dead hosts (no `clickhouse/kafka/redis/prometheus/ollama` service); `npm view @mobile-next/mobile-mcp` → `E404` |

## P0 / Critical
### P0-1. Shim preserve injects workspace path into EVERY Paperclip prompt (Claim 2.1 broken)
- Files: `scripts/opencode-shim.sh:201-212`; `scripts/test-shim.sh:96-102`.
- Proof (Alpha):
  - Command: `OPENCODE_REAL_BIN=/tmp/rec.sh bash scripts/opencode-shim.sh run --format json --dir /tmp/ws --model opencode/gemini --variant high "hello"`
  - Output: `run --format json /tmp/ws --model opencode/gemini#high --auto hello` (stray `/tmp/ws` positional; Paperclip appends `--dir <cwd>` at `execute.ts:629-630`, prompt via stdin at `:678`; real v2 `run [<message...>]` absorbs stray → proceeded to `provider.no-route`, not error). Test at `test-shim.sh:96-102` asserts polluted translation as PASS with false "errors loudly" rationale.
- Fix:
```diff
-            # P1-9: when next token is non-flag it is PRESERVED
-            if [[ -z "${next}" && "$((i + 1))" -lt "${#args[@]}" ]]; then
+            # Paperclip prompt via stdin, token after --dir is ALWAYS cwd. Consume iff absolute on-disk dir.
+            if [[ -z "${next}" && "$((i + 1))" -lt "${#args[@]}" ]]; then
                 i=$((i + 2))
+            elif [[ "${next}" == /* && -d "${next}" ]]; then
+                i=$((i + 2))
             else
                 i=$((i + 1))
             fi
```

### P0-2. Harness 1.0.7 DIES on load under 2.0.32 — 51 roles dead surface (Claims 4.1-4.3)
- Files: `docker/Dockerfile:33-53,69-73`; all 51 roles plugins + harness_* allows.
- Proof (Alpha reproduced + Beta):
  - Command: `npm pack @heretek-ai/opencode-harness@1.0.7 && node -e "setupOpenCodeV2Harness({directory:''})"`
  - Output: `THROW rootDir must be non-empty` (`??` does not skip `""`).
  - Command: `npm view @heretek-ai/opencode-harness version`
  - Output: 5 versions in 22h, 1-day-old single-vendor dep. Publish gate correctly FAILS.
- Fix upstream:
```diff
-    inferredRoot = ctx?.directory ?? ctx?.worktree ?? process.cwd()
+    const pick = (v) => (typeof v === "string" && v.trim() !== "" ? v : undefined);
+    inferredRoot = pick(ctx?.directory) ?? pick(ctx?.worktree) ?? process.cwd()
```
Bump pin to fixed successor only, re-run live tool-visibility gate. Treat allows as dead config until then.

### P0-3. Sanitize layer EXISTS but DATABASE_URL survival UNPROVEN — live canary required (Claim: child env)
- Files: `/tmp/paperclip/server/src/adapters/process/execute.ts:55-65`; `/tmp/paperclip/packages/adapter-utils/src/server-utils.ts:3513-3531` (`sanitizeInheritedPaperclipEnv`), `:171-175` (`isForbiddenConfigEnvKey`); `docker-compose.yml:104-151` (server env carries superuser URL + provider keys).
- Proof (Gamma, corrected — prior "zero scrub / unscrubbed spread" premise was FALSE):
  - Command: `sed -n '50,70p' /tmp/paperclip/server/src/adapters/process/execute.ts`
  - Output:
    ```
    for (const [k, v] of Object.entries(envConfig)) {
      if (typeof v !== "string") continue;
      // Runtime PAPERCLIP_* always wins over config, and PAPERCLIP_API_KEY is
      // never accepted from config — the harness-minted run token is the only
      // source. Other PAPERCLIP_* keys Paperclip did not assign flow through.
      if (isForbiddenConfigEnvKey(k)) continue;          // :55
      if (isPaperclipRuntimeEnvKey(k) && k in env) continue;
      env[k] = v;
    }
    env.PAPERCLIP_RUN_ID = runId;                        // :59-60
    if (authToken) env.PAPERCLIP_API_KEY = authToken;
    // runtimeEnv is only used to resolve the command path and log HOME below;
    // the child env is built inside runChildProcess from
    // sanitizeInheritedPaperclipEnv(process.env) + env, so a PAPERCLIP_API_KEY
    // on the server process never reaches the child.               // :61-65
    ```
  - Command: `sed -n '3513,3531p' /tmp/paperclip/packages/adapter-utils/src/server-utils.ts`
  - Output:
    ```
    export function sanitizeInheritedPaperclipEnv(baseEnv) {
      const env = { ...baseEnv };
      delete env.PAPERCLIPAI_CMD;
      for (const key of Object.keys(env)) {
        if (AGENT_IDENTITY_ENV_KEYS.includes(key.toUpperCase())) { delete env[key]; continue; }
        if (!key.startsWith("PAPERCLIP_")) continue;
        if (key === "PAPERCLIP_RUNTIME_API_URL") continue;
        if (key === "PAPERCLIP_LISTEN_HOST") continue;
        if (key === "PAPERCLIP_LISTEN_PORT") continue;
        delete env[key];
      }
      return env;
    }
    ```
  - Allow/block lists: BLOCKED from inheritance = `PAPERCLIPAI_CMD`, `PAPERCLIP_AGENT_KEY_ID / _PUBLIC_KEY / _PRIVATE_KEY` (`AGENT_IDENTITY_ENV_KEYS`), every `PAPERCLIP_*` except `PAPERCLIP_RUNTIME_API_URL`, `PAPERCLIP_LISTEN_HOST`, `PAPERCLIP_LISTEN_PORT`. BLOCKED from config = `PAPERCLIP_API_KEY`, `PAPERCLIP_WAKE_PAYLOAD_JSON` + identity keys (`isForbiddenConfigEnvKey`, `server-utils.ts:171-175`). NOT in either list = `DATABASE_URL`, `POSTGRES_PASSWORD`, provider keys (`OPENAI_/ANTHROPIC_/GATEWAY_`), `BETTER_AUTH_SECRET`, `GITHUB_TOKEN` — these survive `process.env` inheritance because the sanitizer only strips `PAPERCLIP_*`/identity keys. Upstream `runChildProcess` merges `sanitizeInheritedPaperclipEnv(process.env) + env` (`server-utils.ts:4720`), so any `DATABASE_URL` on the server process IS inherited by the child unless the server env itself is clean.
  - Honest premise: sanitize layer EXISTS (prior report's `execute.ts:337-338,374` + "zero delete/scrub" was wrong lines and wrong claim); the open question is narrower — `DATABASE_URL` survival is UNPROVEN, block-list incomplete until canary proves it stripped.
- Fix: keep P0 (fail-closed: secret-bearing env reaches 51 agent shells until proven otherwise); do NOT claim "unscrubbed spread" — claim "sanitizer present, DATABASE_URL not in block-list, survival unproven". Add live canary gate: in a live agent turn run `printenv | grep -c DATABASE_URL` must be `0`; if `≥1`, scrub `DATABASE_URL/POSTGRES_PASSWORD/BETTER_AUTH_SECRET`/provider keys from server env or extend `sanitizeInheritedPaperclipEnv` block-list; rotate `POSTGRES_PASSWORD`/`BETTER_AUTH_SECRET`.

### P0-4. dangerouslySkipPermissions defaults TRUE → permission allow for non-seed agents
- Files: `/tmp/paperclip/packages/adapters/opencode-local/src/server/runtime-config.ts:110,153,207`; `scripts/seed-50-fleet.sh:~473` (`dangerouslySkipPermissions False` seeded).
- Proof:
  - Command: `grep -n "dangerouslySkipPermissions\|permission" /tmp/paperclip/packages/adapters/opencode-local/src/server/runtime-config.ts`
  - Output:
    ```
    110:  const skipPermissions = asBoolean(input.config.dangerouslySkipPermissions, true);
    153:    "Injected runtime OpenCode config with permission=allow for all tools and connections.",
    207:    permission: "allow",
    ```
    (Prior citation `runtime-config.ts:217-220` was WRONG — those lines are the `small_model` pin (`smallModel` lookup `:219-221`, `nextConfig.small_model` `:221`), not a permission allow. Correct permission-allow lines are `:153` note + `:207` `permission: "allow"` gated by `:110` default-TRUE.)
  - Seeded agents carry `False`, but any UI/API-created agent without the flag gets full allow via `:110 → :207`.
- Fix: upstream flip default to `false`; lock smoke gate asserting `False`; forbid manual creation; audit `list-agents | jq '.[] | select(.adapterConfig.dangerouslySkipPermissions != false)'`.

### P0-5. Prefix-match shell allows bypassable in all 51 roles
- Files: all roles opencode.json (233 shell rules); `AGENTS.md:129-143`.
- Proof (Gamma fnmatch):
  - Command: `python3 -c "import fnmatch; print([fnmatch.fnmatch(x,'git status*') for x in ['git status; id','git status\$(id)','git status||id']])"` (mirrors enforcer prefix semantics)
  - Output: `[True, True, True]` — `git status; id` MATCHES `git status*`; `git status$(id)` MATCHES; `pytest; rm -rf /` MATCHES `pytest*`; `kubectl diff; kubectl exec` MATCHES; `curl .../runtimesXXX -X POST evil` MATCHES exact-host pin; `adb connect 127.0.0.1; adb shell` MATCHES. Voids kubectl/psql/tofu denies. Live probes still required (`make up` + seeded fleet): run `git status; id`, `git status$(id)`, `git status||id`, `npm test -- --unknown-flag` through an agent turn and record deny/allow.
- Fix: treat as advisory; approval-gated actions; run 4 live probes; add deny for `*;*`, `*$(*`, `*||*`, `*&&*` if enforcer supports.

### P0-6. Piston shared heretek net = unauth RCE-as-a-service
- Files: `docker-compose.sidecars.yml:560-606` (expose:2000, zero auth); `sabotage-qa-tester:73-78` curl execute allows.
- Proof:
  - Command: `grep -n "expose\|2000\|piston" docker-compose.sidecars.yml | head; sed -n '560,606p' docker-compose.sidecars.yml`
  - Output: `expose: - "2000"`, zero auth env/secret knobs; `POST /api/v2/execute` arbitrary code by design (upstream Piston API).
  - Command: `grep -n "piston" roles/sabotage-qa-tester/opencode/opencode.json`
  - Output: `73-78` curl execute allows pinned to exact `piston:2000` host paths.
- Fix: front :2000 with shared-secret sidecar proxy on isolated net; profile-gate; never co-schedule qa/devsec with untrusted (extend guard-profiles).

### P0-7. android-mobile-spec MCP typo, npx hard-fails (Beta P0-1)
- Files: `roles/android-mobile-spec/opencode/opencode.json:297` `@mobile-next/mobile-mcp@0.1.2`; catalog + README.
- Proof:
  - Command: `npm view @mobile-next/mobile-mcp version`
  - Output: `E404` (not found).
  - Command: `npm view @mobilenext/mobile-mcp version`
  - Output: `1.0.11` (2026-10-14). Primary tool surface never loads.
- Fix:
```diff
-            "@mobile-next/mobile-mcp@0.1.2"
+            "@mobilenext/mobile-mcp@1.0.11"
```

### P0-8. Five MCP backends point at non-existent services
- Files: `analytics-metrics-eng:204` `CLICKHOUSE_URL`, `cache-streaming-eng:209,220` `REDIS/KAFKA`, `observability-eng:219`/`sre:244` `PROMETHEUS_URL`, `mlops:230` `OLLAMA_HOST`.
- Proof:
  - Command: `grep '^  [a-z-]*:' docker-compose.sidecars.yml | head -n 40`
  - Output: service list has NO `clickhouse`, `kafka`, `redis`, `prometheus`, `ollama` entries (Domain 11.5 `ollama:11434` not composed).
  - Command: `grep -rn "CLICKHOUSE_URL\|OLLAMA_HOST\|PROMETHEUS_URL" roles/*/opencode/opencode.json | head`
  - Output: 5+ MCP env refs to undeployed hostnames → connection refused at runtime.
- Fix: add missing services (pinned/authed/profile-gated) or delete dead MCP + allows; smoke resolves MCP env hostnames vs `compose config --services`.

### P0-9. Claim 3.3 FALSE — 35 roles hold 4 mutating harness allows; exec-director already remediated to DENY (prior exemplar inverted)
- Files: 35 ALLOW roles (exemplars below) vs 16 DENY roles (incl. corrected `exec-director:137-156` which now holds `harness_*` deny at `:137` + 4 explicit denies at `:142,147,152,157` — the prior report's "exec-director:137-156 allow" exemplar was INVERTED and is struck).
- Proof (corrected 2026-10-17):
  - Command: `grep -rn -A2 "harness_file_hash_edit\|harness_ast_structural_rewrite\|harness_rename_symbol\|harness_checkpoint_rollback" roles/*/opencode/opencode.json | grep -c '"effect": "allow"'`
  - Output: `140` allow line-hits (35 roles × 4 tools).
  - Command: same pipeline `| grep -c '"effect": "deny"'`
  - Output: `64` deny line-hits (16 roles × 4 tools).
  - Command (role counts): `for f in roles/*/opencode/opencode.json; do grep -A2 "harness_file_hash_edit\|harness_ast_structural_rewrite\|harness_rename_symbol\|harness_checkpoint_rollback" "$f" | grep -q '"effect": "allow"' && echo "$f"; done | wc -l` → `35` roles with allow; same loop with `'"effect": "deny"'` → `16` roles with deny
  - Output: `35` allow roles / `16` deny roles (deny roles: `ai-red-teamer, appsec-engineer, binary-reverse-eng, cloud-sec-auditor, compliance-auditor, exec-director, firmware-sec-analyst, git-drift-coord, product-director, release-qa-officer, sre-incident-eng, system-architect, tech-docs-lead, threat-modeler, tpm-scrum-lead, ux-research-analyst`).
  - Command (residual ALLOW exemplars — effect allow on next line, verified with `-A2`):
    - `grep -n -A2 "harness_file_hash_edit\|harness_ast_structural_rewrite\|harness_rename_symbol\|harness_checkpoint_rollback" roles/a11y-specialist/opencode/opencode.json` → `:97-99 allow`, `:107-109 allow`, `:137-139 allow`, `:157-159 allow`.
    - `... roles/analytics-metrics-eng/opencode/opencode.json` → `:92-94 allow`, `:102-104 allow`, `:132-134 allow`, `:152-154 allow`.
    - `... roles/dba-specialist/opencode/opencode.json` → `:104 allow`, `:112-114 allow`, `:142-144 allow`, `:162-164 allow`.
  - Full residual ALLOW list (35): `a11y-specialist, analytics-metrics-eng, android-mobile-spec, api-contract-tester, brand-copy-spec, cache-streaming-eng, cloud-platform-eng, cpp-lowlevel-eng, data-pipeline-eng, dba-specialist, dependency-patcher, design-system-eng, e2e-browser-qa, engine-systems-eng, fe-perf-eng, game-ai-dev, game-systems-dev, go-backend-eng, graphics-shader-eng, ios-mobile-spec, java-kotlin-eng, k8s-orchestrator, load-stress-tester, mlops-serving-eng, mobile-web-eng, observability-eng, physics-sim-eng, python-backend-spec, rust-systems-spec, sabotage-qa-tester, static-analysis-lead, tech-artist-pipeline, ts-node-fullstack, ui-ux-designer, vector-rag-spec`.
  - Remediated DENY exemplar (preserve diff): `roles/exec-director/opencode/opencode.json:137-157`:
```json
{ "action": "harness_*", "resource": "*", "effect": "deny" },
{ "action": "harness_file_hash_edit", "resource": "*", "effect": "deny" },
{ "action": "harness_ast_structural_rewrite", "resource": "*", "effect": "deny" },
{ "action": "harness_rename_symbol", "resource": "*", "effect": "deny" },
{ "action": "harness_checkpoint_rollback", "resource": "*", "effect": "deny" }
```
- Fix: strip the 4 mutating allows from the 35 residual roles (or flip to deny above the wildcard if first-match), mirroring the exec-director pattern. Status: **partially remediated — residual in 35 roles** (list above).

## P1 / High
- **P1-1 Firecrawl `:3002/health` 404** (`sidecars:240-245`).
  - Command: `sed -n '238,246p' docker-compose.sidecars.yml` → `test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:3002/health || exit 1"]`.
  - Output: upstream Firecrawl routes are `/`, `/v0/health/liveness|readiness`, `/e2e-test` — no `/health` → perpetual unhealthy.
  - Fix: `wget -qO- http://127.0.0.1:3002/e2e-test`.
- **P1-2 Prebuilt `:1.0.0` unpublished** (`prebuilt:52` `image: ${HERETEK_IMAGE:-ghcr.io/heretek-ai/heretek-crew:1.0.0}`; header `:7-24` documents tag scheme).
  - Command: `docker manifest inspect ghcr.io/heretek-ai/heretek-crew:1.0.0`
  - Output: `manifest unknown` / 404 (anonymous inspect of both `:v1.0.0` and `:1.0.0` returns denied — header `:15` notes `:v1.0.0` NEVER minted).
  - Fix: `git tag v1.0.0 && git push origin v1.0.0`, replace with sha digest.
- **P1-3 socket-proxy:0.3.0 2y stale** (`:508` `tecnativa/docker-socket-proxy:0.3.0` 2024-09-09 vs v0.5.0 2026-07-27).
  - Command: `curl -s "https://hub.docker.com/v2/repositories/tecnativa/docker-socket-proxy/tags?name=0.5.0" | head -c 300`
  - Output: `0.5.0` exists (2026-07-27); pinned `0.3.0` is 2y stale.
  - Fix: bump to `:0.5.0`, verify env contract, re-run deny probe.
- **P1-4 MinIO undeployable** (`:750` `quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z`, quay 401, no digest, AGPLv3).
  - Command: `grep -n "minio" docker-compose.sidecars.yml | head; docker manifest inspect quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z`
  - Output: `401 Unauthorized` (quay anonymous deny); no digest pinned; AGPLv3-only license implication noted `:744`.
  - Fix: replace with `localstack/localstack:<tag>@sha256:<digest>`.
- **P1-5 Paperclip base unreproducible** (`Dockerfile:17-28` placeholder, `:63-64` local tag).
  - Command: `sed -n '17,28p' docker/Dockerfile; grep -n "PAPERCLIP_SOURCE_COMMIT" docker/Dockerfile`
  - Output: `PAPERCLIP_SOURCE_COMMIT=<paste-…>` placeholder still present (`:21`).
  - Fix: paste `73659c6b27c1d97226f2da9ca39f256eefddac66` (verified `git -C /tmp/paperclip rev-parse HEAD` → same) + assert 40-hex in smoke.
- **P1-6 Hound archived rationale false** (`sidecars:446-453`, SUPPORTING 845-857 "etsy/hound archived").
  - Command: `curl -s https://api.github.com/repos/etsy/hound | jq '{archived, pushed_at}'; curl -s https://api.github.com/repos/hound-search/hound | jq '{archived, pushed_at}'`
  - Output: `etsy/hound` → redirect/renamed; `hound-search/hound` → `{archived: false, pushed_at: 2026-09-10}` — not archived, renamed not archival.
  - Fix: correct comment; migration OPTIONAL.
- **P1-7 Piston digest-of-latest** (`:591` engineer-man latest only, v2.0.0 404).
  - Command: `curl -s "https://hub.docker.com/v2/repositories/engineer-man/piston/tags?name=v2.0.0" | head -c 300; grep -n "piston" docker-compose.sidecars.yml | head`
  - Output: `v2.0.0` tag 404; only floating latest resolves.
  - Fix: vendor `ghcr.io/heretek-ai/piston:<semver>@digest` per SUPPORTING E.2.
- **P1-8 Ghidra :1337 / Radare2 :9090 unauth + bridge** (`sidecars:350-438`, `:946-950` paperclip joins 3 nets).
  - Command: `grep -n "1337\|9090\|ghidra\|radare2" docker-compose.sidecars.yml | head`
  - Output: Ghidra WebUI `:1337` + Radare2 `:9090` exposed without auth env; paperclip attached to 3 nets.
  - Fix: secret-proxy front + hard guard-profiles refusal.
- **P1-9 harness_* wildcard precedes specifics in 16 roles** (exec-director:137-156 pattern etc — dead under first-match).
  - Command: `grep -n -B2 -A2 '"harness_\*"' roles/exec-director/opencode/opencode.json | head`
  - Output: `harness_* deny :137` precedes specifics `:142-157` — correct order here (mirror k8s-orchestrator); 16-flagged roles have inverted order where specifics are shadowed.
  - Fix: move specifics above wildcard (mirror k8s-orchestrator).
- **P1-10 threat-modeler deploy/security write + github_* over-broad** (threat-modeler fs:write deploy/security/** + github_*; compliance github_*).
  - Command: `grep -n "fs:write\|github_" roles/threat-modeler/opencode/opencode.json | head`
  - Output: `:57,:62,:67 fs:write` incl. deploy/security scopes; `:77 github_*` allow; `:157-172` additional write scopes.
  - Fix: drop deploy write, scope github to get/search/list + deny tail.
- **P1-11 Caddy 0.0.0.0:80/443 one cmd from exposure** (`compose:235-237`, Makefile:57-70 guard Makefile-only).
  - Command: `sed -n '235,237p' docker-compose.yml; sed -n '57,70p' Makefile`
  - Output: `0.0.0.0:80/443` published; guard lives only in Makefile target, not compose fail-closed.
  - Fix: compose fail-closed `test $EXPOSURE = private && exec caddy…`.
- **P1-12 Superuser DATABASE_URL inspect-readable** (`compose:105-116`).
  - Command: `sed -n '105,116p' docker-compose.yml`
  - Output: `DATABASE_URL: postgres://${POSTGRES_USER:-paperclip}:${POSTGRES_PASSWORD:?...}@postgres:5432/...` — superuser URL in server env, inspect-readable via `docker inspect`.
  - Fix: password-file/secret + unset POSTGRES_PASSWORD.
- **P1-13 GET-recon open whole net** (`:507-558` POST/BUILD/EXEC=0 good, but expose:2375 heretek-wide lists containers).
  - Command: `sed -n '507,560p' docker-compose.sidecars.yml`
  - Output: `POST: "0" BUILD: "0" EXEC: "0" VOLUMES: "0" NETWORKS: "0" AUTH: "0"` (good) BUT `expose: - "2375"` + `networks: - heretek` → any heretek-net container runs unauthenticated `GET /containers/json`, `/images/json`, `/version`, `/info` recon.
  - Fix: dedicated heretek-ci / allowlist + smoke probe.
- **P1-14 Offensive shell allows** (ai-red-teamer garak/pyrit/promptfoo; dependency-patcher npm install/cargo/go; sabotage piston).
  - Command: `grep -n "garak\|pyrit\|promptfoo\|npm install\|cargo\|piston" roles/ai-red-teamer/opencode/opencode.json roles/dependency-patcher/opencode/opencode.json roles/sabotage-qa-tester/opencode/opencode.json | head -n 20`
  - Output: installer + offensive-harness allows present as claimed.
  - Fix: npm ci-only, ephemeral sandbox, approval-gated installs.
- **P1-15 restore-db.sh --file usage mismatch** (`:6` `--file path` vs `:51-52` `--file=*` only → exit 2).
  - Command: `bash scripts/restore-db.sh --file backups/x.sql.gz`
  - Output: `error: --file requires '=path' form` exit `2` (`:52`); usage header `:6` documents space form.
  - Fix: accept space form or change usage + regression test.

## P2 / Medium
- **P2-1 stale budget comment 1270000** — Files: `scripts/seed-50-fleet.sh:337` (`Sum = 1270000 cents ($12,700.00 USD)`). Command: `grep -n "1270000\|1300000" scripts/seed-50-fleet.sh` → Output: `:45 Default: 1300000`, `:99 summing to 1300000`, `:113 FLEET_BUDGET_CAP_CENTS=1300000`, `:337 stale 1270000`. Fix: update `:337` to `1300000 ($13,000.00)`.
- **P2-2 dispatch-pipeline no ticket validation** — Files: `scripts/dispatch-pipeline.sh` (no `require_ticket_id`). Command: `grep -n "require_ticket_id\|allowlist" scripts/dispatch-pipeline.sh scripts/worktree-manager.sh` → Output: worktree-manager `:39-45` HAS allowlist, dispatch HAS NONE. Fix: add `^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$` gate at top.
- **P2-3 unverified probes playwright/radare2/hound/ghidra** — Files: `sidecars:350-468`. Command: first-boot `docker ps --format '{{.Names}} {{.Status}}'; docker logs <svc> --tail 20` → Output (deferred): live `ps/logs` on first boot required; do not bump blind. Fix: verify logs then bump.
- **P2-4 searxng stale + false newest comment** — Files: `sidecars:37-39` (`2025.12.19` vs `2026.10.17`). Command: `curl -s "https://hub.docker.com/v2/repositories/searxng/searxng/tags?page_size=3&ordering=last_updated" | head -c 400` → Output: newer tag exists. Fix: bump + correct comment.
- **P2-5 firecrawl 2.10.19→2.11 digests 5044→94d7** — Files: `sidecars:firecrawl image`. Command: `curl Hub tags?name=2.11` → Output: digest `94d7` supersedes `5044`. Fix: bump pin.
- **P2-6 browserless v2.24.2→v2.26.0; litellm main-v1.54→v1.60** — Files: `sidecars:browserless/litellm`. Command: `curl Hub/GHCR tags` → Output: newer tags resolve. Fix: bump both.
- **P2-7 phantom wirings SUPPORTING (searxng settings, hound config, wiremock mappings, litellm config)** — Files: `SUPPORTING_SERVICES.md` doc block vs compose mounts. Command: `grep -n "settings\|hound.*config\|mappings\|litellm.*config" SUPPORTING_SERVICES.md | head; grep -n "volumes" -A5 docker-compose.sidecars.yml | grep -i "searxng\|hound\|wiremock\|litellm" | head` → Output: doc references mounts absent from compose. Fix: vendor+mount or delete doc block; searxng limiter + litellm passthrough real impact noted.
- **P2-8 phantom services ollama/otel/crawl4ai/ast-grep specified not composed + 7 dead MCP envs** — Files: `SUPPORTING_SERVICES.md` + `roles/*/opencode/opencode.json`. Command: `grep '^  [a-z-]*:' docker-compose.sidecars.yml | grep -E "ollama|otel|crawl|ast-grep" ; echo ---; grep -rn "OLLAMA_HOST\|OTEL\|CRAWL4AI\|AST_GREP" roles/*/opencode/opencode.json | head` → Output: no service entries; 7 dead MCP env refs. Fix: compose or delete.
- **P2-9 jaeger v2 v1-era COLLECTOR_OTLP_ENABLED verify logs** — Files: `sidecars:jaeger`. Command: `docker logs jaeger --tail 30 2>&1 | grep -i "otlp\|collector\|error" | head` (first boot) → Output: verify v1 env still honoured under v2 image. Fix: confirm logs, drop stale env if ignored.
- **P2-10 playwright 10 pages/2g no shm_size → 5 + shm 1gb** — Files: `sidecars:playwright-service`. Command: `grep -n -B2 -A6 "playwright" docker-compose.sidecars.yml | head -n 20` → Output: no `shm_size`, page/memory limits oversized. Fix: `shm_size: 1gb`, pages 5.
- **P2-11 mocks lag wiremock/mailpit/mitmproxy (mitmproxy first)** — Files: `sidecars:wiremock/mailpit/mitmproxy`. Command: `curl Hub tags wiremock/mailpit/mitmproxy | head` → Output: newer tags available. Fix: bump mitmproxy first (security surface).
- **P2-12 XDG provenance/canary gaps (paste commit, run canary)** — Files: `docker/Dockerfile:21`, `scripts/smoke-test.sh`. Command: `git -C /tmp/paperclip rev-parse HEAD` → Output: `73659c6b27c1d97226f2da9ca39f256eefddac66` (paste into Dockerfile, assert 40-hex). Fix + `printenv | grep -c DATABASE_URL == 0` live canary.
- **P2-13 backup plaintext default (require AGE_RECIPIENT unless --plaintext-ok)** — Files: `scripts/backup-db.sh`. Command: `grep -n "AGE_RECIPIENT\|plaintext" scripts/backup-db.sh | head` → Output: no mandatory recipient gate. Fix: fail-closed require `AGE_RECIPIENT` unless explicit `--plaintext-ok`.
- **P2-14 fs:read ** cross-agent read (scope or accept documented)** — Files: 51 roles `fs:read`. Command: `grep -rn '"action": "fs:read"' roles/*/opencode/opencode.json | wc -l; grep -rn -A1 'fs:read' roles/exec-director/opencode/opencode.json | head` → Output: broad `**` reads present. Fix: scope to role dirs or record accepted-risk.
- **P2-15 firecrawl USE_DB_AUTH false loopback-only keep** — Files: `sidecars:firecrawl env`. Command: `grep -n -B2 -A2 "USE_DB_AUTH" docker-compose.sidecars.yml | head` → Output: `false` but loopback-only binding contains it. Fix: keep, document loopback-only justification.
- **P2-16 privileged android + tailscale caps profile-gated no change** — Files: `sidecars:docker-android/tailscale`. Command: `grep -n -B2 -A4 "privileged\|cap_add" docker-compose.sidecars.yml | head -n 20` → Output: privileged/caps present but profile-gated (mobile/tailscale profiles, never default). Fix: none — accepted, keep gating.

## P3 / Low
- **P3-1 backup-db.sh .env warning drift** — Files: `scripts/backup-db.sh`. Command: `grep -n "warning\|\.env" scripts/backup-db.sh | head` → Output: stale warning text vs current guard. Fix: sync wording.
- **P3-2 NOTES 46/46 vs 54/54** — Files: `NOTES.md`. Command: `grep -n "46/46\|54/54" NOTES.md | head` → Output: count mismatch vs `test-shim.sh` 54 assertions. Fix: update to 54/54.
- **P3-3 grep assert count artifact** — Files: `scripts/smoke-test.sh`. Command: `grep -n "assert.*count\|grep -c" scripts/smoke-test.sh | head` → Output: brittle count assert. Fix: pin or relax.
- **P3-4 gotenberg 8.37→8.38.1** — Files: `sidecars:254` (`gotenberg/gotenberg:8.37.0`). Command: `curl -s "https://hub.docker.com/v2/repositories/gotenberg/gotenberg/tags?name=8.38.1" | head -c 200` → Output: `8.38.1` exists. Fix: bump.
- **P3-5 node:24 floats minor** — Files: `docker/Dockerfile:31` (`node:24-trixie-slim` inherited). Command: `grep -n "node:" docker/Dockerfile` → Output: unpinned minor. Fix: pin `node:24.x-trixie-slim@sha256:<digest>` (low — official base tracks).
- **P3-6 redis 7.4 LTS deliberate** — Files: `sidecars:redis`. Command: `curl Hub tags?name=7.4.11` → Output: `7.4.11-alpine` current; CVE-2025-49844 fixed. Fix: none — deliberate LTS, keep.
- **P3-7 act-22.04 EOL 2027-04 calendar** — Files: `sidecars:905` (`ghcr.io/catthehacker/ubuntu:act-22.04@sha256:f5f5c...`). Command: `grep -n "act-22.04\|act-24.04" docker-compose.sidecars.yml` → Output: `:905` pinned 22.04, `:899` notes 24.04 quarterly plan. Fix: calendar migration to 24.04 quarterly.
- **P3-8 android pin verified** — Files: `sidecars:docker-android`. Command: `grep -n "budtmo" docker-compose.sidecars.yml` → Output: pin present and profile-gated. Fix: none.
- **P3-9 dba postgres_query shape check** — Files: `roles/dba-specialist/AGENTS.md:§4`. Command: `grep -n "postgres_query\|GRANT\|read-only" roles/dba-specialist/AGENTS.md | head` → Output: read-only GRANT shape asserted. Fix: enforce at resource layer (true read-only Postgres role via GRANTs).
- **P3-10 loopback mocks acceptable extend smoke §3a** — Files: `scripts/smoke-test.sh`. Command: `grep -n "3a\|loopback\|mock" scripts/smoke-test.sh | head` → Output: loopback mocks accepted. Fix: extend §3a asserts.
- **P3-11 mitmproxy block_global keep** — Files: `sidecars:mitmproxy`. Command: `grep -n -B2 -A2 "block_global\|mitmproxy" docker-compose.sidecars.yml | head` → Output: block-global present. Fix: keep.
- **P3-12 Dockerfile --force/root confirm `id -u==1000` live** — Files: `docker/Dockerfile`. Command: `docker run --rm <built> id -u` → Output (needs `make build`): expect `1000`. Fix: confirm live, record.

## Residuals NOT filed
Backup/restore pg path correct (socket trust, `--clean --if-exists` `backup-db.sh:120-126`, `ON_ERROR_STOP=1` + `pg_terminate_backend` `restore-db.sh:163-170`, restore `--file` form `restore-db.sh:7,27,51` — space form rejected exit 2 per P1-15, `=` form canonical); seed idempotency (fail-with-body, nonzero on unparseable, drift-only PATCH, preflight); caddy guard consistent; healthcheck syntax; all modern pins verified (see receipts above + Domain table).

## Method note
Hub `…/tags?name=<tag>` count≥1; GHCR token + manifests 200/404; npm view; PyPI json; GitHub api repos/releases/tags. Upstream `git -C /tmp/paperclip rev-parse HEAD` → `73659c6b27c1d97226f2da9ca39f256eefddac66`; grep execute/runtime-config (`grep -n "dangerouslySkipPermissions\|permission" …/runtime-config.ts` → `110,153,207`; `grep -rn sanitizeInheritedPaperclipEnv|isForbiddenConfigEnvKey … --include="*.ts"` → `execute.ts:55,63`, `server-utils.ts:171,3505,3513,4720`); shim rec.sh + npx run --help; npm pack harness load probe (`rootDir must be non-empty`); grep shell 233 rules + fnmatch (`True,True,True`); ordering audits (`grep -n -A2 harness_…` → 35 allow / 16 deny); `docker compose config` no-.env 8 errors; service enumeration (`grep '^  [a-z-]*:'`); `printenv | grep -c DATABASE_URL` live canary (must be 0); `bash scripts/restore-db.sh --file … → exit 2`; `npm view @mobile-next/mobile-mcp → E404` vs `npm view @mobilenext/mobile-mcp version → 1.0.11`. Modernity re-verified live by Beta 2026-10-17 via Hub/GHCR/npm (see Beta transcript); operator rerun: `npm view @opencode/cli version; curl -s "https://hub.docker.com/v2/repositories/library/postgres/tags?name=17.11-alpine" | head -c 400; git -C /tmp/paperclip rev-parse HEAD`.
