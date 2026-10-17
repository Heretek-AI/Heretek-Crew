# Stage 1 Remediation Log — Phase 0 Re-verify + Phase 1 P0 (blocking)

**Worktree:** `/tmp/opencode/heretek-remediate` (branch `remediate/audit-findings`)
**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md`
**Status:** all P0 fixed, verified empirically. Changes left UNCOMMITTED for QA/Drift-Guard.

## Phase 0 — Re-verification results (all P0 reproduced)

| Finding | Proof command re-run | Result |
|---|---|---|
| P0-1a searxng | `curl .../searxng/searxng/tags/2024.10.16-ac56c663b` → `404` | REPRODUCED |
| P0-1b radare2 | tags `6.0.0`→`404`, `6.0.2`→`200`, `6.2.4`→`200`, `5.9.8`→`200` | REPRODUCED |
| P0-1c hound | GHCR manifest `v0.6.0`→`404`, `0.6.0`→`200` (bearer-token flow) | REPRODUCED |
| P0-1d litellm | GHCR manifest `v1.54.0`→`404`, `main-v1.54.0`→`200` | REPRODUCED |
| P0-1e piston | GHCR manifest `v2.0.0`→`404`, `latest`→`200` | REPRODUCED |
| P0-1f minio | Hub `minio/minio` repo + tag → `{"message":"object not found"}` / `404` | REPRODUCED |
| P0-2 dispatch | `grep -c 'curl\|api\|poll\|sleep\|PATCH\|POST\|GET'` → **`0`** (audit said 1; hollow either way — even less function than reported). Header `:11` claims merge, body has none; execute path called `worktree-manager.sh archive` (`remove --force` + `branch -D`) | REPRODUCED (stronger) |
| P0-3 ci-runner | runner `profiles: ["ci","qa-testing"]` vs proxy `["core","devsec"]`; no `depends_on`/`command`; volume `./workspaces:/workspaces` vs paperclip `/paperclip/workspaces` | REPRODUCED |
| P0-4 perms | `dangerouslySkipPermissions: True` in both seed scripts; `roles/programmer` bare allow-all; shim `--auto` injection confirmed | REPRODUCED |
| P0-5 proxy | `POST: "1"`, no BUILD/EXEC/AUTH keys (defaults allow) | REPRODUCED |
| P0-6 secrets | 7 working `:-default` credentials at `:39,:96,:173,:229,:438,:469,:518-519` (+`:470` DATABASE_URL fallback) | REPRODUCED |

Audit variance note: searxng newest live tag is `2025.12.19-8bf600cc6` (audit cited `2026.10.x-*`;
registry moved on — re-resolved live, see P0-1a). No proof contradicted the audit.

## P0-1 image pins → `docker-compose.sidecars.yml`

Digests resolved live via `skopeo inspect` (multi-arch index digests):

| Svc | Old (404) | New pin | Digest |
|---|---|---|---|
| searxng `:27` | `searxng/searxng:2024.10.16-ac56c663b` | `searxng/searxng@sha256:13de…e24e9` | tag `2025.12.19-8bf600cc6`, Hub `200` |
| radare2 `:295` | `radare/radare2:6.0.0` | `radare/radare2@sha256:88b7…d2ae37` | tag `6.2.4` per audit |
| hound `:318` | `ghcr.io/hound-search/hound:v0.6.0` | `.../hound@sha256:5b7f…c470e` | tag `0.6.0` (no `v`), GHCR `200` |
| litellm `:461` | `ghcr.io/berriai/litellm:v1.54.0` | `.../litellm@sha256:eb14…d3f6d5` | tag `main-v1.54.0`, GHCR `200` |
| piston `:384` | `ghcr.io/engineer-man/piston:v2.0.0` | `.../piston@sha256:2f66…127a` | digest of upstream `latest` (only tag published) — **no `:latest` tag used** |
| minio `:508` | `minio/minio:RELEASE...` | `quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z` (tag pin, exact) | digest NOT resolvable: quay.io auth-gates anonymous manifest inspection (`401` on registry token flow, `skopeo`, and `docker manifest inspect` for minio only — control probes `quay.io/prometheus/prometheus:latest` succeed, so this is per-org gating, not a client fault). Digest pin deferred until authed pulls exist. |

**Product decision flagged (not blocking Stage 1):** piston vendor/self-build to
`ghcr.io/heretek-ai/piston:<semver>` to drop dependence on a floating upstream tag
(comment left at the pin site; see audit P0-1e option B). MinIO alternative
(S3 mock/localstack) is a product call for a later stage.

## P0-2 dispatch-pipeline → `scripts/dispatch-pipeline.sh`

- Phase 6 header renamed to `Archive ONLY (no merge performed)`; execute path now prints
  `error: auto-merge disabled (fail-closed)` + retain instructions and `exit 1`
  **before** any archive call (destructive `worktree-manager.sh archive` no longer invoked).
- Dry-run Phase 6 advertises the manual-merge requirement instead of fake rebase/archive.
- File header + final `COMPLETE` line de-claimed (no more "finished successfully" / "6-phase relay").
- `scripts/worktree-manager.sh` untouched in Stage 1 (its `:99,102` force-paths are cited as
  proof only; full hardening is P1-2, separate stage).
- Empirical proof (execute mode, scratch ticket `tkt-p0probe`, base `remediate/audit-findings`):
  `exit=1`, `WORKTREE-RETAINED`, `BRANCH-RETAINED`; probe artifacts fully cleaned up
  (`worktree remove`, `branch -D`, `worktree prune` — `git status` shows only intended edits).

## P0-3 local-ci-runner → `docker-compose.sidecars.yml:608-620`

Applied audit diff + documented invocation (`--profile core,ci` note on the service):
`profiles + ["core"]`, `depends_on docker-socket-proxy (service_healthy)`,
`command: ["sleep", "infinity"]`, volume fixed to `./workspaces:/paperclip/workspaces`.
Rendered config confirms all four.

## P0-4 permissions

- `roles/programmer/opencode/opencode.json`: bare allow-all replaced with enumerated
  allows (read-all; writes scoped to `workspaces/**` + `/paperclip/workspaces/**`;
  named `git`/`npm`/`npx`/`pytest`/`cargo`/`go` test+build commands; `codebase-memory_*`,
  `context7_*`, `harness_*` namespaces) closed by `fs:write * deny` + terminal
  `shell * deny` tail — fleet dialect, consistent with `ts-node-fullstack`.
- `roles/programmer/AGENTS.md`: "full tool access" paragraph rewritten to describe the
  enumerated policy (doc/code drift closed).
- `scripts/seed-50-fleet.sh:≈357`, `scripts/seed-company.sh:≈190`:
  `"dangerouslySkipPermissions": True` → `False` + hints-only comment (skip+`--auto`
  documented as defense-in-depth, not a sandbox boundary).
  - Process note: first attempt placed the comment *inside* the backslash-continued
    `VAR=… \` env chain, which silently broke env delivery to `python3` — `shellcheck`
    SC2034 flagged it, comments moved above the chain, re-verified clean + dry-runs green.
- `scripts/smoke-test.sh`: new section `3b` static denied-tool probe (programmer has no
  allow-all + terminal shell deny; both seed scripts set skip `False` with no `True`
  remaining; proxy denies POST/BUILD/EXEC). Feasible static form; runtime tool-refusal
  probe needs a live Paperclip+OpenCode run (live gate, out of scope Stage 1).

## P0-5 socket-proxy → `docker-compose.sidecars.yml:354-381`

`POST: "1"` → `"0"`; added `BUILD: "0"`, `EXEC: "0"`, `AUTH: "0"` (+ explanatory comment).
GET-only (`CONTAINERS/IMAGES/INFO/VERSION: "1"`, `VOLUMES/NETWORKS/NODES/SWARM/SYSTEM: "0"` kept).
CI functionality on a GET-only proxy is **not yet runtime-verified** (needs `make up` + act
run) — flagged for the live stage; comment records the fallback (host-direct pulls /
dedicated daemon).

## P0-6 secrets → `docker-compose.sidecars.yml` + `.env.example`

All 7 fail-open defaults converted to `:?` fail-closed
(`SEARXNG_SECRET`, 2× `FIRECRAWL_DB_PASSWORD`, `BROWSERLESS_TOKEN`, `NEO4J_PASSWORD`,
`LITELLM_MASTER_KEY`, `MINIO_ROOT_USER/PASSWORD`, `DATABASE_URL`'s `POSTGRES_PASSWORD`
leg). Remaining `:-` occurrences are non-secret identifiers only
(`FIRECRAWL_DB_USER`, `POSTGRES_USER/DB`, empty `OPENAI_*` optionals).
`.env.example`: replaced the stale commented-out real defaults with `CHANGE_ME__`
entries for all 7 vars (+ generation commands). No secrets committed (placeholders only).
(Edit tool refused the `.env*` path per secret-hygiene guard — applied via exact-match
scripted replacement instead; content identical in effect.)

## Test results (must-keep-green set)

- `bash scripts/test-shim.sh` → **28 passed, 0 failed**.
- `bash scripts/smoke-test.sh --check-only` → **228 passed, 0 failed, 3 skipped**
  (baseline before changes: 225 passed — +3 new 3b checks, zero regressions).
- `shellcheck` on all 8 scripts → **zero warnings** (caught + fixed one real breakage, §P0-4).
- `bash scripts/seed-company.sh --dry-run` → 6 payloads, all `skip false`, no `True`.
- `bash scripts/seed-50-fleet.sh --dry-run` → **51 docs**, all `skip false`, exit 0;
  budget `WARNING` (1270000 vs cap 1279000) **remains — expected, P1-8 is Stage 2 scope**.
- `docker compose -f docker-compose.yml -f docker-compose.sidecars.yml --profile … config` →
  **exit 0** with all profiles; all 6 new pins render; negative probe (secrets unset) fails
  naming the exact missing var (fail-closed proven both directions).
- `make test` (= smoke live mode, no `--check-only`) → 228 passed / **2 failed, both
  environmental** (`postgres not healthy`, `paperclip not responding` — stack not running;
  identical failures on unmodified baseline). Full green requires `make up` (live stage).

## Files changed (uncommitted)

- `docker-compose.sidecars.yml` (P0-1 ×6, P0-3, P0-5, P0-6 ×7)
- `scripts/dispatch-pipeline.sh` (P0-2)
- `scripts/smoke-test.sh` (P0-4 denied-tool probe §3b)
- `scripts/seed-50-fleet.sh`, `scripts/seed-company.sh` (P0-4 skip=False)
- `roles/programmer/opencode/opencode.json`, `roles/programmer/AGENTS.md` (P0-4 PoLP)
- `.env.example` (P0-6 CHANGE_ME entries)

## Self-audit notes

- Fail-closed everywhere: pipeline exits 1 retaining work; compose refuses without secrets;
  seeds request enforcement; proxy denies writes; no `|| true`/`TODO`/dummy returns added.
- Minimal diffs; deny tails preserved; no floating tags (5 digests + 1 exact RELEASE tag);
  scripts keep `--dry-run`/`--help` + `set -euo pipefail`; no secrets in repo.
- Not done in Stage 1 (explicitly out of scope): P1-2 worktree hardening, P1-8 budget cap,
  runtime act-against-read-only-proxy verification, live `make up` green.
- No commits, no merges, no subagents used.

---

# Stage 2 Remediation Log — Phase 2 P1 (High) + Stage-1 nits

**Worktree:** `/tmp/opencode/heretek-remediate` (branch `remediate/audit-findings`)
**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md` P1-1…P1-9
**Status:** all P1 fixed, verified empirically (green tests re-proven, not trusted).
Changes left UNCOMMITTED for QA/Drift-Guard. No proof contradicted the audit;
two probes refined the prescribed fix (caddy admin endpoint, rea-mcp),
both recorded below — no stoppage was needed (no product decision blocked progress).

## P1-1 Shim drops `--variant` with short `-m` → `scripts/opencode-shim.sh`, `scripts/test-shim.sh`

- `scripts/opencode-shim.sh`: `--model)` → `--model|-m)`, `--model=*)` → `--model=*|-m=*)`
  (+ header rule-2 doc). New `model_eq_prefix` preserves the exact `=` flag form,
  so `-m=m#v` no longer rewrites to `--model=m#v`.
- `scripts/test-shim.sh`: +4 cases (8a–8d): `-m`+`--variant` both orders,
  `-m=`+`--variant=` prefix preservation, existing-`#` non-doubling via `-m`.
- Proof (audit's mock-binary probe verbatim):
  `OPENCODE_REAL_BIN=/tmp/opencode/p1proof/mock bash scripts/opencode-shim.sh run -m mymodel --variant high prompt`
  → `run / -m / mymodel#high / --auto / prompt` (variant kept, both orders; `-m=` form keeps `-m=`).
- Tests: `bash scripts/test-shim.sh` → **32 passed, 0 failed** (was 28).

## P1-2 Worktree archive hardening → `scripts/worktree-manager.sh`

- Added `command -v git` gate (exit 127), `require_ticket_id` allowlist
  `^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$` enforced in create/rebase/archive,
  removed all three `|| true` masks, `remove --force` → plain `remove`,
  `branch -D` → retain-note; header rewritten (no more "delete branch").
- Proof: `create '../evil'` / `create '/tmp/wt-abs'` → exit 2, nothing created;
  dirty-worktree `archive` → git refuses (exit 128), worktree+branch+uncommitted
  file intact; clean `archive` → worktree removed, branch retained, evidence dir
  written. Probe artifacts fully cleaned (`branch -d`, archive removed, prune).
- Tests: `shellcheck` clean.

## P1-3 Restore termination + asserted verification → `scripts/restore-db.sh`

- Added `pg_terminate_backend` (via `postgres` db, before the pipe into target),
  TABLES trimmed + asserted numeric non-zero (fail-closed exit 1), TTY gate
  before the typed prompt (closed stdin → immediate error, no `set -e` abort);
  header steps rewritten (7 steps).
- Proof: `--file=x.sql < /dev/null` (no `--yes`) → `error: no TTY for
  confirmation` exit 1; assert matrix: `0`/empty/`abc` REJECT, `12`/` 7 ` ACCEPT.
- Tests: `shellcheck` clean. Full restore still needs a live stack (tracked).

## P1-4 `OPENCODE_DISABLE_PROJECT_CONFIG` defense-in-depth → `docker-compose.yml`, both seed scripts, `scripts/smoke-test.sh`

- `docker-compose.yml` paperclip env: `OPENCODE_DISABLE_PROJECT_CONFIG: "true"` (+ comment);
  both seeds' `adapterConfig.env` carry the same key (header comments updated).
- Smoke §2 asserts the rendered config contains it; §4 asserts it in both dry-runs.
- Proof: `docker compose config | grep` → `OPENCODE_DISABLE_PROJECT_CONFIG: "true"`;
  seed-50 dry-run 50 hits, seed-company 6 hits.
- Scope note: in-container boot assertion lives in upstream's entrypoint (not
  vendored here); rendered-config + payload assertions are the in-repo gates.

## P1-5 Permission tightening → 2 role configs, 3 charters, `AGENTS.md`, `scripts/smoke-test.sh`

- `roles/qa`, `roles/tester`: `bash * allow` → named test commands only
  (qa: `npm test*`, `npm run test*`, `npx playwright*`; tester adds `npx vitest*`,
  `pytest*`, `cargo test*`, `go test*`) + terminal `bash * deny`. Charters updated.
- `roles/dba-specialist/AGENTS.md` §4: `POSTGRES_READONLY_URL` must be a true
  read-only role + GRANT SQL (DB change out of scope; deny alone insufficient).
- `AGENTS.md` §4: two-dialect note (fleet `shell` vs legacy `bash` tails),
  argv prefix-matcher limitation, MCP-bypass limitation with resource-layer rule.
- Smoke: §3 allow-all exception REMOVED (no bare allow-all remains anywhere —
  scanned all 56); §3b adds qa/tester narrowing guards + dba/k8s
  MCP-boundary-deny regression guards; header comments updated.
- Proof: all 56 role files end in their dialect's `*` deny tail (scripted sweep:
  56 checked, 0 without); smoke §3b prints each narrowed set.
- Floor note (tracked product decision): full single-dialect unification + generic
  per-namespace MCP deny tails need the runtime enforcer's tool-name contract
  (unverifiable statically — inventing deny action names would be theater).

## P1-6 Network exposure → `docker-compose.yml`, `docker-compose.sidecars.yml`

- Caddy all-interfaces exposure note + `PAPERCLIP_DEPLOYMENT_EXPOSURE=private` rule.
- mitmproxy: profiles → `["qa-testing"]` only, `block_global=false` → `true` (+ comment).
- Auth/lateral-movement notes on qdrant (no key), both redises (no requirepass),
  rabbitmq (guest creds, expose-only; 4.x tracked), radare2 bind note, devsec
  category gating note, docker-android privileged gating note.
- Proof: rendered `block_global=true` under qa-testing; mitmproxy absent under
  devsec; all profiles render (`core`, `web-research`, `devsec`, `ai-gateway`,
  `observability`, `mobile`, documented `qa-testing+core` / `ci+core` pairs).
- Pre-existing (Stage 1, untouched): single `--profile qa-testing`/`ci` without
  `core` fails on runner→proxy `depends_on` — verified identical on HEAD baseline
  reconstruction modulo Stage-1's own `depends_on`; documented pairing stands.

## P1-7 Supply chain pins → 50 role configs, generator, Dockerfile, workflow, smoke gate

- Pinned 20/21 unpinned MCP commands to live-resolved exact versions
  (npm `@x.y.z`, uvx `==x.y.z` — `uvx 'cowsay==6.1'` probe proved the `==`
  positional form installs): git-mcp 2.15.3, server-github 2025.4.8,
  server-postgres 0.6.2, server-filesystem 1.0.0, server-memory 1.0.0,
  context7-mcp 4.4.2, playwright-mcp-server 1.0.12, openapi-explorer 1.3.5,
  aws-mcp 1.0.2, ollama-mcp 2.1.0, codebase-memory-mcp 0.12.1 (bare binary →
  pinned npx; npm bin verified), clickhouse 0.7.0, r2mcp 0.2.5, redis 0.1.1,
  kafka 0.1.1, duckdb 1.1.0, k8s 0.1.6, docker-mcp 0.2.0, k6 2.2.0,
  prometheus 1.6.2, qdrant 0.8.1. All agree with the catalog's "verified v"
  annotations except codebase-memory-mcp (catalog PyPI v0.12.0, live 0.12.1 both
  indexes — pinned live).
- Sole exception: `@morluto/rea-mcp` is NOT on npm (registry 404) — **product
  decision:** publish it or migrate the role to `rea-agents@6.5.0` (morluto's
  published package). Left unpinned + tracked; gate fails on anything else.
- `scripts/generate-50-roles.py`: `MCP_NPX_PINS`/`MCP_UVX_PINS` maps +
  `pin_mcp_command()` enforced in `normalize_config` (dies on unpinned; the new
  gate caught the catalog's unscoped `mobile-mcp` on first run — reordered so the
  android special-case normalizes first). Regeneration probe: 202 files, and all
  50 generated `mcp` blocks equal the hand-pinned on-disk files (0 mismatches).
- `docker/Dockerfile`: `opencode-mem@2.31.3` (real plugin pkg, dist-tag latest)
  added to install + `npm ls` assert + `OPENCODE_MEM_VERSION` ENV + pin comment.
  `opencode-rea` (npm 404) and `@prevalentware/opencode-goal-plugin` (0.1.64 live,
  install not added — minimal diff) tracked as decisions. Workflow step 3 asserts
  harness+mem. Image build itself needs `paperclip:official-local` (live stage).
- Smoke: new pin gate (npx `pkg@ver` / uvx `pkg==ver`, exception-set drift
  detection) + header docs + harness-registration live-only note.
- Proof: gate green on tree; mutation probe (`uvx evil-unpinned-pkg` in qa)
  → `FAIL: qa: unpinned uvx package`, SMOKE FAIL — restored after.

## P1-8 Budget cap + seed holes → both seed scripts, generator, smoke §4

- Cap `1279000` → `1270000` in `seed-50-fleet.sh:87` (+ header comments rewritten —
  discrepancy closed, WARNING retained for env-override drift) and generator
  `DOCUMENTED_FLEET_CAP_CENTS` (also fixed — audit cited only the seed script).
- PATCH always carries explicit `reportsTo` (`null` clears strays) in BOTH seeds
  (seed-company had the identical hole for Director).
- `seed-company.sh` decimal budgets: `$((USD*100))` → `Decimal`-based
  `budget_usd_to_cents` with shape validation + descriptive error (also closes P3-2).
- Smoke §4: seed-50 now asserts total==cap with NO warning (numeric compare).
- Proof: dry-run → 51 docs, `total ... 1270000 cents ... (cap 1270000 cents)`,
  0 WARNINGs; `BUDGET_DIRECTOR_USD=99.99` → 9999, `49.95` → 4995; `abc` → exit 1
  with descriptive error; PATCH null form `{"reportsTo": null}` shown;
  generator re-run → 0 WARNINGs.

## P1-9 Versions + guards → Dockerfile, README, AGENTS.md, NOTES.md, both composes, prebuilt, workflow, SUPPORTING_SERVICES.md

- `@opencode/cli`+`client` 2.0.31 → **2.0.32** (npm: series ends …2.0.31,2.0.32)
  in Dockerfile (comment/ENV/labels), README table + diagram + upgrade row,
  AGENTS.md ×2, NOTES.md pinned-stack/verified-facts/links (historical
  inspection notes left intact), compose comment, workflow labels, smoke pin
  row, shim header. Zero `2.0.31` stragglers outside dated prose.
- rabbitmq 4.x / semgrep / jaeger-v2 scheduled via comments (no blind bumps).
- ghidra `MAXMEM 4G` → `3G` (headroom inside the 4g limit).
- postgres +`cpus/mem`; paperclip +healthcheck (curl `/`, unhealthy-flag only —
  no health-gated dependents) with caps-left-alone rationale (entrypoint chown);
  caddy +healthcheck +`cap_drop ALL`/`NET_BIND_SERVICE` +`cpus/mem`;
  tailscale +healthcheck (socket liveness, not login) +`cap_drop ALL` (keeps
  NET_ADMIN/SYS_MODULE) +`cpus/mem`.
- **Probe refinement (audit-proof-adjacent):** `caddy reverse-proxy` prints
  `admin endpoint disabled` — the naive `:2019` healthcheck would have failed
  forever. Replaced with a listener-response probe (`wget -S … | grep HTTP/`),
  proven exit 0 against a live `caddy:2` container under the exact dropped-caps
  profile; `:2019` probe proven exit 1. Caps bind pattern proven (listeners up,
  no permission-denied). Exact-image + stack-liveness checks are live-stage.
- Prebuilt: private-pull auth doc (`401` = private-or-missing; login steps; no
  v1.0.0 tag yet tracked). Workflow: `--version` REQUIRED (fallback removed,
  steps renumbered).
- SUPPORTING_SERVICES.md: ollama + otel-collector marked "specified but NOT
  composed" (the cited brief lives outside the repo; compose is authoritative).
- Proof: `docker compose config` renders all new fields under `proxy`+`tailscale`
  profiles; every sidecar profile renders with documented pairings.

## Stage-1 nits (fixed now)

- P0-3 NOTE: `--profile core,ci` → `--profile core --profile ci` (sidecars
  runner comment + dispatch Phase 5, which also gained its `[DRY-RUN]` prefix —
  the shared context line moved into the dry-run branch with the fixed profile).
- Minio `digest TODO` → `digest PENDING` + non-stub clarification.
- `.env.example`: `CHANGE_ME__` replace-before-`make up` stress comment
  (applied via scripted replacement — `.env*` edit guard, same as Stage 1).

## Test results (must-keep-green set + P1 proofs)

- `bash scripts/test-shim.sh` → **32 passed, 0 failed** (28 baseline + 4 P1-1).
- `bash scripts/smoke-test.sh --check-only` → **233 passed, 0 failed, 3 skipped**
  (225 pre-Stage-1 baseline → 228 Stage 1 → 233: +P1-4/+P1-5/+P1-7 gates).
- Mutation probes: pin gate FAILs on injected unpinned pkg (then restored);
  worktree invalid-ID/dirty-archive refusals; restore TTY gate; budget WARNING=0.
- `shellcheck` on all `scripts/*.sh` → zero warnings (`.py` N/A — shell-only tool).
- `bash scripts/seed-company.sh --dry-run` → 6 payloads, skip false.
- `bash scripts/seed-50-fleet.sh --dry-run` → **51 docs, no WARNING** (cap == sum).
- `docker compose config` (default, prebuilt, all sidecar profiles/pairs) → exit 0.
- `make test` (live mode, stack down) → 233 passed / same 2 environmental fails as
  Stage-1 baseline (`postgres not healthy`, `paperclip not responding`) — no new
  failures; full green needs `make up` (live stage).
- Registry proofs: npm/PyPI live versions recorded in P1-7/P1-9 above;
  `@morluto/rea-mcp` + `opencode-rea` npm 404s recorded as product decisions.

## Files changed (uncommitted, Stage 2 only)

- `scripts/opencode-shim.sh`, `scripts/test-shim.sh` (P1-1)
- `scripts/worktree-manager.sh` (P1-2)
- `scripts/restore-db.sh` (P1-3)
- `docker-compose.yml` (P1-4 env, P1-6 caddy note, P1-9 healthchecks/caps)
- `scripts/seed-50-fleet.sh`, `scripts/seed-company.sh` (P1-4 env, P1-8)
- `scripts/generate-50-roles.py` (P1-7 pins, P1-8 cap)
- `scripts/smoke-test.sh` (§2/§3/§3b/§4/§5 gates + pin gate)
- `scripts/dispatch-pipeline.sh` (nits: DRY-RUN prefix + profile fix)
- `roles/*/opencode/opencode.json` (50 fleet pins; qa/tester narrowing)
- `roles/qa|tester|dba-specialist/AGENTS.md`, `roles/dba-specialist` MCP pin note (P1-5)
- `AGENTS.md` (PoLP dialect/limitation docs, 2.0.32)
- `docker/Dockerfile`, `.github/workflows/docker-publish.yml` (P1-7 mem, P1-9 ver)
- `docker-compose.sidecars.yml` (P1-6 notes, P1-9 plans, P1-2 n/a, nits)
- `docker-compose.prebuilt.yml` (P1-9 private-pull doc)
- `README.md`, `NOTES.md`, `SUPPORTING_SERVICES.md` (P1-9 versions/status)
- `.env.example` (replace-before-up stress comment)

## Self-audit notes (Stage 2)

- Fail-closed kept: allowlist exits 2, archive refuses dirty, restore asserts +
  TTY-gates, gates fail on unpinned/drift, no `|| true` added (3 removed),
  no TODO/dummy/empty catches, no floating tags (21 exact pins), deny tails on
  all 56, no secrets touched.
- Two audit refinements from live probes (caddy admin-disabled; rea-mcp 404) —
  neither contradicts the audit; both handled fail-closed + tracked.
- Product decisions flagged (not blocking): REA MCP distribution
  (`@morluto/rea-mcp` unpublished vs `rea-agents@6.5.0`), `opencode-rea` plugin
  unpublished, piston vendor build (Stage 1 carryover), MinIO alternative
  (carryover), prebuilt tag publication, single-dialect + MCP-deny unification
  (needs enforcer contract), live verifications (image build, proxy health,
  tailscale socket, act-on-read-only-proxy, harness registration).
- No commits, no merges, no subagents used.

---

# Stage 3 Remediation Log — Phase 3 P2/P3 + Stage-2 nit

**Worktree:** `/tmp/opencode/heretek-remediate` (branch `remediate/audit-findings`)
**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md` P2-1…P2-5, P3-1…P3-5
**Status:** all P2/P3 closed or verified-present, tests re-proven empirically.
Changes left UNCOMMITTED for QA/Drift-Guard. No proof contradicted the audit;
one probe exposed a real wart beyond the audit text (P3-2 traceback noise),
fixed fail-closed on the spot. No stoppage needed (no product decision blocked
progress).

## P2-1 Version-lag cadence → `SUPPORTING_SERVICES.md` §10 ¶1b (doc, no bumps)

- New `### 1b. Profile Selection Guard & Version Maintenance Cadence`: names
  the lagging pins (`redis:7.4.1-alpine` ×2, `qdrant:v1.12.5`,
  `wiremock:3.10.0-alpine`, `mailpit:v1.21.8`, `gotenberg:8.15.0`,
  `neo4j:5.26.0-community-bullseye`), declares neo4j 5.26 LTS deliberate,
  sets the Renovate/Dependabot-style review cadence (owned by
  `dependency-patcher`), and mandates live-registry verification before any
  re-pin (Stage-1 P0-1 lesson). Zero tags changed — document-the-plan only,
  per the task.

## P2-2 Backup nits → `scripts/backup-db.sh` (code, proven)

- Same-second overwrite: timestamp collision now diverts to a `-$RANDOM`
  suffix; a second collision aborts fail-closed (`exit 1`) instead of
  clobbering. Header steps rewritten to describe the guarantee.
- Retention: `ls -1t | tail` replaced with `find -printf '%T@ %p\0' |
  sort -z -n` (oldest-first, NUL-delimited) + indexed prune loop.
- Proof: scratch-dir probe with 4 dumps incl. a space-name and a newline-name
  at retention=2 → pruned exactly the 2 oldest, kept the 2 newest; empty-dir
  probe → `mapfile` exit 0, count 0 (set -e safe). `shellcheck` clean.

## P2-3 Container hardening → `docker-compose.yml` (code + documented why-not)

- `postgres`: `cap_drop: [ALL]` + minimal `cap_add`
  (CHOWN, DAC_OVERRIDE, SETGID, SETUID — exactly what the official gosu
  entrypoint needs) + `no-new-privileges:true`.
- `paperclip`: `no-new-privileges:true` ADDED; `cap_drop`/`read_only`
  explicitly NOT set with rationale (entrypoint repairs volume ownership as
  root before `exec gosu node`; server writes workspaces + data volume +
  /tmp by design; read-only root needs live-boot verification — tracked).
- `caddy`: `no-new-privileges:true` added alongside existing
  `cap_drop ALL`/`NET_BIND_SERVICE`.
- `tailscale`: `no-new-privileges:true` added alongside existing
  `cap_drop ALL` + NET_ADMIN/SYS_MODULE (tun setup uses capabilities, not
  new privileges — unaffected).
- Proof: `docker compose config` renders exit 0 on default AND
  proxy/tailscale profiles; all 4 services carry `no-new-privileges:true`
  (2 under default profile, 4 with proxy+tailscale).

## P2-4 All-profiles guard → `SUPPORTING_SERVICES.md` §10 ¶1b (doc)

- Guard note with the live-computed figure: summed `mem_limit` ≈ **42 GB**
  across sidecars (audit cited ~36 GB; recomputed from the file — higher,
  so the warning is stronger). Directs operators to select profiles per
  task with an example invocation.

## P2-5 Tailscale caps → verified present, comment strengthened

- `cap_add NET_ADMIN/SYS_MODULE` + `cap_drop ALL` + `profiles: ["tailscale"]`
  all confirmed in `docker-compose.yml:177-183`; hardening comment extended
  to state profile-gating explicitly. No behavioral change (already correct).

## P3-1 Shim suite gaps → `scripts/test-shim.sh` 32 → 39 (all green)

- 8e: empty `--variant=` dropped, model untouched. 8f: duplicate `--model`
  merges into the LAST occurrence (earlier passes through for the real
  binary to judge — behavior locked, not changed). 8g: mid-argv valueless
  `--dir` drops alone, following flag survives.
- 4 env-mock cases via a second mock recording `OPENCODE_API_KEY`:
  GO-key fallback exports; pre-existing key NOT clobbered; neither set →
  UNSET; empty GO key does not clobber to empty.
- Proof: `bash scripts/test-shim.sh` → **39 passed, 0 failed**; `shellcheck`
  clean.

## P3-2 Decimal-budget message → hardened beyond Stage 2 (code)

- Stage 2's regex + descriptive error verified (`abc` → exit 1 with the
  clear message; `99.99` → 9999), BUT the probe exposed trailing noise: the
  empty substitution fell through into a Python `ValueError` traceback.
- Fix: `build_agent_payload` resolves `budget_cents` up front with
  `|| return 1`, so malformed input aborts on the descriptive error alone.
- Proof: `BUDGET_DIRECTOR_USD=abc --dry-run` → exit 1, stdout stops after
  the company line, stderr is exactly the one descriptive line, zero
  traceback.

## P3-3 Restore TTY check → verified explicit (no change)

- `scripts/restore-db.sh:87-91` already gates `[[ ! -t 0 ]]` before the
  typed prompt. Proof: `FILE=<real .sql path> ... < /dev/null` (no `--yes`)
  → `error: no TTY for confirmation …` exit 1. Closed stdin can no longer
  reach the `set -e` abort.

## P3-4 Roles 56-vs-50 → doc clarification (minimal, no moves)

- Audit's "remove or namespace legacy set" rejected in favor of the
  doc-clarification option: one `Scope note (P3-4)` header comment in EACH
  seed script stating which set it seeds (6 legacy prototype vs 50 fleet),
  that both coexist (56 dirs), and that smoke asserts each seed's own count
  (7 vs 51 documents). `README.md`'s fleet section already documents the
  coexistence (left untouched). No role dirs moved, renamed, or deleted.

## P3-5 Paperclip image build order → `Makefile` (comment)

- `build` target now carries the P3-5 ordering comment: build
  `paperclip:official-local` FIRST or compose silently reuses a stale base;
  cross-references `docker/Dockerfile` + compose header. `make -n build`
  prints the comment + `docker compose build`.

## Stage-2 nit → `NOTES.md:14` 2.0.31 → 2.0.32

- Currency claim updated. Deliberately left: `NOTES.md:29`'s
  `@opencode/cli@2.0.31` (historical record of the version actually tested
  during the v1→v2 spike — dated prose, not a currency claim).

## Test results (must-keep-green set + P3 proofs)

- `bash scripts/test-shim.sh` → **39 passed, 0 failed** (32 Stage-2 + 7 P3-1).
- `bash scripts/smoke-test.sh --check-only` → **233 passed, 0 failed,
  3 skipped** (unchanged — no gate touched).
- `shellcheck` on all `scripts/*.sh` → zero warnings.
- `bash scripts/seed-company.sh --dry-run` → 7 payloads, skip false;
  `BUDGET_DIRECTOR_USD=abc` → exit 1, single-line descriptive error.
- `bash scripts/seed-50-fleet.sh --dry-run` → **51 docs, empty stderr, no
  WARNING** (cap == sum, unchanged).
- `docker compose config` (both files): exit 0 on default + all 8
  profile selections; negative probe (secrets unset) still fails naming the
  exact missing var (P0-6 gate intact).
- `make test` (live mode, stack down) → 233 passed / same 2 environmental
  fails as Stage-2 baseline (`postgres not healthy`, `paperclip not
  responding`) — no new failures.
- `AGENTS.md` shim counts corrected 28 → 39 (two spots; Stage 2 had moved
  the suite to 32 without updating them).

## Files changed (uncommitted, Stage 3 only)

- `scripts/backup-db.sh` (P2-2), `scripts/test-shim.sh` (P3-1),
  `scripts/seed-company.sh` (P3-2 traceback fix, P3-4 scope note),
  `scripts/seed-50-fleet.sh` (P3-4 scope note)
- `docker-compose.yml` (P2-3 caps/security-opt, P2-5 comment)
- `SUPPORTING_SERVICES.md` (P2-1 cadence, P2-4 guard), `Makefile` (P3-5),
  `NOTES.md` (nit), `AGENTS.md` (counts), `REMEDIATION_LOG.md` (this stage)

## Self-audit notes (Stage 3)

- Fail-closed kept: backup refuses double-collision; retention deletes only
  computed-oldest; no `|| true`/`TODO`/dummy returns added; no tags bumped
  (P2-1) or floated; no secrets touched; scripts keep `--help`/`--dry-run`
  + `set -euo pipefail`; deny tails untouched.
- Live-verification debt carried (unchanged from Stage 2): postgres under
  dropped caps, no-new-privileges under real entrypoints, read-only-root
  feasibility, image build, proxy/tailscale health.
- No commits, no merges, no subagents used.

---

# Stage 4 Remediation Log — Wave 2 Sandbox escapes (P0-2, P0-3, P0-4, P0-5 + P1-8 secrets)

**Worktree:** `/home/john/Projects/Heretek-Crew/.worktrees/wave2` (branch `remediate/wave2-sandbox-escapes`)
**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md` P0-2/P0-3/P0-4/P0-5 + P1-8, `PROMPT_REMEDIATION_HANDOFF.md` §2 Wave 2
**Status:** all Wave 2 items closed, verified empirically. Changes left UNCOMMITTED for QA/Drift-Guard.

## Empirical tool-surface enumeration (no guessing; commands + results)

- Harness: `cd /tmp/opencode/harness-probe && npm pack @heretek-ai/opencode-harness@1.0.7`
  (Dockerfile line-58 version) → `heretek-ai-opencode-harness-1.0.7.tgz` (114 files).
  `dist/index.js` exports `HARNESS_TOOL_NAMES` (5: file_hash_read, file_hash_edit,
  ast_structural_search, ast_structural_rewrite, ui_geometry_audit) and
  `EXTENDED_HARNESS_TOOL_NAMES` (14 = those 5 + repo_map, blast_radius, file_outline,
  symbol_references, rename_symbol, verify_scoped, architecture_audit,
  checkpoint_create, checkpoint_rollback). The live path (`default export
  OpenCodeV2Plugin.setup` → `setupOpenCodeV2Harness` → `buildExtendedHarnessTools`)
  registers all **14** — the smoke manifest pins those 14. README confirms
  "wires all 14 direct tools". Direct tools register with `codemode: false`;
  8 pinned companions re-register under the `tools.harness.*` namespace.
- Git MCP: `npm pack @cyanheads/git-mcp-server@2.15.3` → dist bundle
  `allToolDefinitions` = 28 tools; read set = the 8 carrying
  `readOnlyHint: true` (git_blame, git_changelog_analyze, git_diff, git_log,
  git_reflog, git_show, git_status, git_wrapup_instructions). The other 20
  (push/commit/rebase/checkout/merge/reset/worktree/...) stay denied.
- Filesystem MCP: `server-filesystem@1.0.0` `dist/server.js` `registerTool`
  calls = 14 tools (10 read: read_file/read_text_file/read_media_file/
  read_multiple_files/list_directory/list_directory_with_sizes/directory_tree/
  search_files/get_file_info/list_allowed_directories; 4 write: write_file,
  edit_file, create_directory, move_file).
- Postgres MCP: `server-postgres@0.6.2` exposes exactly one tool, `query`,
  self-enforcing `BEGIN TRANSACTION READ ONLY` + ROLLBACK.
- Kubernetes MCP: `pip download mcp-server-kubernetes==0.1.6` wheel →
  5 tools: kubectl_describe, kubectl_get_by_name,
  kubectl_get_by_kind_in_namespace, kubectl_previous_logs (read) +
  kubectl_exec_into_pod (exec primitive, denied). NOTE: no `create_pod`-style
  tool exists in the pinned version — the audit PoC name was illustrative of
  the class; the real exec primitive (`kubectl_exec_into_pod`) is now denied.
- Docker MCP: `pip download docker-mcp==0.2.0` wheel → 4 tools:
  list-containers + get-logs (read) vs create-container + deploy-compose
  (write, denied).
- AWS MCP: `npm pack aws-mcp@1.0.2` → 3 tools: run-aws-code (arbitrary-AWS-code
  primitive, denied at this layer), list-credentials, select-profile (read).
  Write containment for AWS is enforced at the resource layer (read-only IAM
  policy on the configured profile — permission lists are advisory-only,
  AGENTS.md §4).

## P0-2/P0-3: namespace scoping (51 role files)

- `harness_*` allow-all → 14 per-tool allows + `harness_*` deny tail in all
  51 files (50 fleet + programmer). Before→after: 51 bare allows → 0;
  714 per-tool allows + 51 deny tails.
- `k8s-orchestrator`: `kubernetes_kubectl_get*/describe*/previous_logs*`
  allows, `kubernetes_kubectl_exec*` + `kubernetes_*` denies;
  `docker_list*/get*` allows, `docker_create*/deploy*` + `docker_*` denies.
- `dba-specialist`: `postgres_query*` allow + `postgres_*` deny (psql shell
  deny retained).
- `cloud-platform-eng` + `cloud-sec-auditor`: `aws_list*/select*` allows,
  `aws_run*` + `aws_*` denies.
- `mlops-serving-eng`: `docker_*` allow → `docker_list*/get*` + deny tail.
- `git_*` (24 roles) → 8 read-verb allows + `git_*` deny tail each
  (192 allows + 24 denies, zero write verbs). NO role retains `git_push` via
  MCP: no role ever held a push shell allow (only git-drift-coord held
  force-with-lease, now removed); local `commit`/`checkout` stay on
  dependency-patcher's existing shell allows; every push is human-gated.
- `filesystem_*`: binary-reverse-eng + firmware-sec-analyst re-rooted
  `/paperclip/workspaces` → `/paperclip/workspaces/binaries` (the `:ro`
  sample mount shared with ghidra/radare2) with read-verb allows +
  write-verb denies + tail; brand-copy-spec's server + allow removed
  (docs role; reads via git MCP, writes via fs:write). Two adjacent gaps the
  new fsroot gate caught (graphics-shader-eng, tech-artist-pipeline declared
  shared-root filesystem servers with NO matching allow — dead config):
  servers removed, charters updated. Before→after: 3 bare allows → 0.
- Every touched file keeps its dialect terminal deny (50 fleet `shell`,
  programmer `shell`, qa/tester legacy `bash` untouched); 56/56 tails present.
- `scripts/generate-50-roles.py`: new `scope_mcp_permissions()` table +
  harness/filesystem-root/git-drift normalizations (+ fixed the bare
  `"opencode-harness"` plugins-append wart so regen cannot regress P0-1).
  Proof: regen with `--root` into scratch → permissions identical to disk
  for all 50 roles (0 mismatches), RE roots + brand/graphic/artist server
  removals reproduced.

## Provisioning (P0-2/P1-8): read-only PG role + URLs + tokens + kubeconfig

- `scripts/postgres-init-readonly-role.sh` (new, executable, `--dry-run` +
  `--help`, shellcheck-clean): initdb hook creating `paperclip_reader`
  (SELECT-only GRANTs + `CONNECTION LIMIT 5` +
  `default_transaction_read_only = on`; secret via `psql -v`, never
  interpolated; refuses `CHANGE_ME__`). `--dry-run` prints the SQL without a
  live DB (used by the smoke gate).
- `.env.example`: `POSTGRES_READER_PASSWORD`, `POSTGRES_READONLY_URL`
  (paperclip_reader user required), `GITHUB_TOKEN` (scoped read-only PAT for
  the 7 github-backed roles), `KUBECONFIG_READONLY_PATH`
  (`./secrets/kubeconfig-readonly`) — all `CHANGE_ME__`/documented.
- `docker-compose.yml`: postgres env `POSTGRES_READER_PASSWORD :?` + initdb
  hook `:ro` mount; paperclip env `POSTGRES_READONLY_URL :?` +
  `GITHUB_TOKEN :?`; kubeconfig bind `${KUBECONFIG_READONLY_PATH :?}:...:ro`.
  No `:-` defaults on any of the three.
- `scripts/seed-50-fleet.sh`: `require_provisioned_secrets` preflight runs on
  dry-run AND live — rejects missing/placeholder `POSTGRES_READONLY_URL`,
  rejects non-`paperclip_reader` (superuser) URLs by shape, rejects
  missing/placeholder `GITHUB_TOKEN`, requires the kubeconfig path to be a
  regular file. Values never echoed.
- `.gitignore`: `secrets/*` (+ `!secrets/.gitkeep`); empty `secrets/.gitkeep`.
- Proof: absent → exit 1 with all three messages; superuser URL → exit 1;
  dummy-present → exit 0 with 51 payloads, budget total == cap.

## P0-5: git-drift-coord disarmed

- Removed shell allows `git worktree*`, `git rebase*`,
  `git push --force-with-lease*` (the `git push --force *` deny stays as
  defense-in-depth); `git_*` MCP → 8 read verbs + deny tail; no push allow of
  any form remains (gate asserts). Charter rewritten to detect-and-report
  (§§1/3/4/7): drift detection on status/branch/merge-base/diff/log,
  reports to `docs/ops/**`, every mutation human-executed with pushes gated
  by `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET` (config = deny entries +
  existing compose secret env; no mock).

## P0-4: negative probes + advisory-only documentation

- `smoke-test.sh §3b`: reference argv-aware matcher (any of `;&|`$><()\n`
  → deny) refuses `git status; id`, `npm test && id`, `curl -s http://x; id`
  (all 3 must deny); every one of the 192 shell/bash allows asserted to be a
  single-command prefix (no chaining metachar baked in); per-probe INFO lines
  show which naive-prefix allow each probe WOULD match (e.g.
  `git status; id` → `git status*`), documenting why allows are advisory-only.
- AGENTS.md §4 already carried both limitation notes (prefix-matcher +
  MCP-bypass, Stage 2) — no edit needed; role charters repeat the
  resource-layer rule where it binds (k8s/dba/cloud/aws/mlops).

## Test results (must-keep-green set + Wave 2 proofs)

- `bash scripts/smoke-test.sh --check-only` → **244 passed, 0 failed,
  3 skipped** (233 baseline → 244: +11 Wave 2 gates, zero regressions).
- `bash scripts/test-shim.sh` → **39 passed, 0 failed** (unchanged).
- `shellcheck -S warning scripts/*.sh` → zero warnings; `bash -n` all OK.
- `bash scripts/seed-company.sh --dry-run` → 7 payloads, skip false (untouched).
- `bash scripts/seed-50-fleet.sh --dry-run` → exit 1 absent/superuser-URL,
  exit 0 + 51 payloads with dummies (cap == sum, no WARNING).
- `grep -rn ':latest'` → only two pre-existing prose comments (policy text,
  not pins); `grep -L 'deny'` → all 56 tails present.
- `docker compose config` exit 0: default, prebuilt, web-research, devsec,
  ai-gateway, observability, mobile, core+ci, qa-testing+core,
  proxy+tailscale. `qa-testing` ALONE still fails on the documented
  pre-existing runner→proxy profile pairing (Stage 2 P1-6, sidecars file
  untouched — not a Wave 2 regression).
- `make test` (live mode, stack down) → 244 passed / same 2 environmental
  fails as every prior baseline (`postgres not healthy`, `paperclip not
  responding`) — no new failures; full green needs `make up` (live stage).

## Files changed (uncommitted, Wave 2 only)

- 51× `roles/*/opencode/opencode.json` (namespace scoping; +programmer
  `plugins: ["@heretek-ai/opencode-harness"]` to match its harness allows;
  -filesystem servers in brand-copy/graphics/tech-artist)
- `scripts/generate-50-roles.py` (scope table + normalizations + plugins fix)
- `scripts/postgres-init-readonly-role.sh` (new initdb hook)
- `scripts/seed-50-fleet.sh` (provisioning preflight + header docs)
- `scripts/smoke-test.sh` (§2 dummies + provisioning asserts + §3b
  manifest/namespace/root/drift/negative-probe gates + §4 seed dummies +
  harness NOTE rewrite)
- `docker-compose.yml` (reader password, initdb mount, readonly URL, github
  token, kubeconfig ro volume), `.env.example` (4 vars), `.gitignore`
  (secrets/), `secrets/.gitkeep` (new)
- 9 charters: git-drift-coord (posture), binary-reverse-eng + firmware
  (re-root), brand-copy/graphics-shader/tech-artist (server removal),
  k8s-orchestrator + cloud-platform-eng + cloud-sec-auditor +
  mlops-serving-eng (containment notes), dba-specialist (provisioning note)

## Self-audit notes (Wave 2)

- Fail-closed kept: namespace deny tails everywhere; initdb hook + compose
  :? + seed preflight triple-gate provisioning (URL user-shape enforced);
  reference matcher denies chained probes; no `|| true`/`TODO`/dummy returns
  added; no floating tags (harness 1.0.7 re-pinned by manifest, MCP pins
  untouched); no secrets in repo (placeholders + `__smoke_only__` dummies
  only, never echoed); scripts keep `--help`/`--dry-run` + `set -euo pipefail`.
- Tracked residuals (not blocking, recorded honestly): the runtime
  enforcer's exact `<server>_<tool>` vs bare-`<tool>` mapping is still
  unverified — allows use the namespaced form + deny tails so both mappings
  fail closed (same caveat as Stage 2); `github_*` allow-all in 7 roles is
  NOT tool-scoped this wave (token scoping + approval gating are the
  controls; needs enforcer contract + follow-up); `ollama_*`/`r2_*`/`rea_*`/
  `codebase-memory_*`/`context7_*` wildcards untouched (outside Wave 2
  scope); live verifications still need `make up` (harness tool
  registration, read-only-role boot on fresh volume, kubeconfig mount,
  deny-tail runtime probe); existing (non-fresh) pgdata volumes need the
  manual GRANT step from the hook's `--dry-run` output.
- No commits, no merges, no subagents used.

---

# Stage 5 Remediation Log — Wave 3 Claims + topology (P1-1, P1-2, P1-3, P1-9, P1-11)

**Worktree:** `/home/john/Projects/Heretek-Crew/.worktrees/wave3` (branch `remediate/wave3-claims-topology`)
**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md` P1-1/P1-2/P1-3/P1-9/P1-11 + P2-1, `PROMPT_REMEDIATION_HANDOFF.md` §2 Wave 3
**Status:** all Wave 3 items closed, verified empirically. Changes left UNCOMMITTED for QA/Drift-Guard.

## P1-1: budget $90 gap → catalog Total line was wrong (one-line diff)

- Re-summed BOTH sources with python3: seed `role_budget_cents()` printf
  values = **50 rows, 1,270,000¢ ($12,700.00)**; catalog table `$` column =
  **50 rows, 1,270,000¢ ($12,700.00)**. The two authoritative tables AGREE;
  only the catalog's Total prose line (`$12,790.00`) disagreed.
- Fix (one-line diff): `roles-catalog/ROLE_CATALOG_50.md:119`
  `$12,790.00` → `$12,700.00`. Consistency: `README.md` budget note
  rewritten (discrepancy-documentation → reconciled state, WARNING-on-drift
  only), `GEMINI.md` budget-cap line corrected to $12,700.00. Historical
  audit/prompt files (`AUDIT_REPORT_FINDINGS.md`, `PROMPT_*.md`,
  `REMEDIATION_LOG.md` prior stages) intentionally untouched.
- Proof: seed `--dry-run` → `total fleet budget: 1270000 cents ...
  (cap 1270000 cents)`, stderr empty (no WARNING); smoke §4 asserts
  total==cap with no WARNING (green).

## P1-2: sidecar network merge break → managed network, both files (option: drop external)

- `docker-compose.sidecars.yml` NETWORKS block: `external: true` →
  `name: heretek` + `driver: bridge` (+ comment recording why). No
  `external:` remains in any compose file.
- `docker-compose.yml` NETWORKS block: added `name: heretek` so the base
  stack alone and the merged sidecar stack share ONE Docker network
  literally named `heretek` (previously base-alone would use
  `heretek-crew_heretek` while merged used external `heretek`).
- `SUPPORTING_SERVICES.md` mirrored compose snippet updated identically
  (it carried the same `external: true`). No Makefile/README create-step
  needed (nothing is external anymore); README already names the network
  `heretek` in its topology diagram.
- Proof: `config -q` exit 0 on default, prebuilt, web-research, devsec,
  ai-gateway, observability, mobile, core+ci, qa-testing+core,
  proxy+tailscale; rendered merged network = `{name: heretek, driver:
  bridge}`.

## P1-3: CI-runner contradiction → option (a), read-only observer (one coherent story)

- Decision: (a) document runner as quarantined read-only observer, CI via
  host `act`. Rationale: non-goal forbids weakening `POST/BUILD/EXEC=0`;
  option (b) would add a full-socket attack path next to agent workloads.
- `local-ci-runner` comment rewritten: inspect/list/diagnose ONLY through
  the GET-only proxy; mutating `act` jobs run on the HOST daemon, never
  from inside the container; explicit ban on re-adding proxy writes or a
  socket mount here (P1-12 pointer).
- `docker-socket-proxy` comment rewritten: GET-only BY DESIGN (removed the
  `Verify CI still functions with GET-only access` claim — it cannot, and
  no longer pretends to); points at the runner comment for the observer
  pattern; restates the read-only posture is never weakened to "fix" CI.
- `SUPPORTING_SERVICES.md` §12 item 4 rewritten: was `All CI or test-spawn
  requests pass through the socket proxy` (contradicted the decision) →
  now states proxy-is-GET-only, runner-is-observer, mutating CI on host act.
- Proof: `config -q` exit 0 on core+ci (and qa-testing+core); repo-wide grep
  for `Verify CI`/`GET-only` shows only the new honest wording; no comment
  claims CI-mutating work passes through the proxy.

## P1-9: prebuilt tag → retarget to publishable semver + honest quickstart (no invented digest)

- Evidence (fail-closed, nothing invented): anonymous `docker manifest
  inspect` of BOTH `:v1.0.0` and `:1.0.0` → `manifest unknown`; `git tag`
  empty; push impossible from this env.
- Key finding beyond the audit text: the workflow
  (`.github/workflows/docker-publish.yml`, docker/metadata-action `semver`
  on `refs/tags/v*`) mints `1.0.0` / `1.0` / `latest` / `sha-<sha>` from a
  `v1.0.0` git tag — it NEVER mints `:v1.0.0`. The old pin was
  unpublishable by construction, so `git tag v1.0.0 && git push` alone
  would NOT have fixed it. Retarget (chosen path): pin `:v1.0.0` →
  `:1.0.0` in `docker-compose.prebuilt.yml` + `docker-compose.override.yml.example`;
  header rewritten with the exact maintainer release step, login + manifest
  verify step, and `build locally until published` guidance. Exact tag pin
  kept; no digest invented.
- `README.md` Option A rewritten: was `official image published to GHCR
  (...:v1.0.0)` (false — nothing published) → now states the release
  precondition, the verify command, and the fail-closed pull behavior.
- Smoke pin gate updated to assert `:1.0.0` present AND `:v1.0.0` absent
  (regression-proof against drift back).
- Proof: prebuilt `config -q` exit 0; smoke pin gate green; `grep v1.0.0`
  across README/prebuilt/override/Makefile/.github shows only the release
  instruction and the `:v1.0.0`-never-minted rationale.

## P1-11 + P2-1: 6 legacy roles deleted as superseded → 50 roles, single dialect

- Decision: DELETE (not migrate). All 6 map cleanly onto fleet roles
  (director→exec-director; pm→product-director+tpm-scrum-lead;
  programmer→language engineers 19–26; tester/qa→e2e-browser-qa +
  api-contract-tester + release-qa-officer; designer→ui-ux-designer +
  design-system-eng + brand-copy-spec); migration would leave 56 dirs and
  fail the `ls roles/ = 50` criterion. Mapping recorded in
  `scripts/seed-50-fleet.sh` scope note + `README.md` supersession table.
- Deleted: `roles/{designer,director,pm,programmer,qa,tester}/` (24 files)
  + `scripts/seed-company.sh` (410 lines — seeded exactly the deleted
  roles; an empty/retargeted seeder would be a stub).
- Consistent updates (no dangling refs): `scripts/smoke-test.sh` (§1 legacy
  existence loop removed; §3 prose fleet-only; §3b programmer probe
  GENERALIZED to a fleet-wide allow-all + terminal-deny scan of all 50;
  §3b skip-permissions gate narrowed to seed-50; qa/tester narrowing gate
  removed with rationale comment — closed by deletion, zero `bash`-action
  permissions remain; §4 seed-company block removed; live-flow hints
  `make seed` → `make seed-50`; COMPANY_NAME default → `Heretek
  Autonomous Fleet`); `Makefile` (`seed` target + SEED_SCRIPT removed,
  flow comments → `make seed-50`); `README.md` (intro, pin table,
  quickstarts, ops table, Roles section + supersession map, add-role,
  seed-override, fleet intro, Playwright rows, security-model skip=False
  rewrite, layout); `AGENTS.md` (layout, seed commands, single-dialect
  PoLP); `CLAUDE.md`/`GEMINI.md` (seed-company dry-run lines removed).
  Historical logs/prompts (`REMEDIATION_LOG.md` prior stages,
  `AUDIT_REPORT_FINDINGS.md`, `PROMPT_*.md`, `NOTES.md`,
  `EVALUATION_AWESOME_OPENCODE.md`) intentionally untouched.
- Proof: `ls roles/ | wc -l` = **50**; `grep -rl '"action": "bash"'` = 0
  files; all 50 terminal perms are `shell * deny`; dangling-ref grep over
  scripts/Makefile/compose/workflows shows only intentional explanatory
  comments + `make seed-50` hints; smoke `--check-only` green.

## Test results (must-keep-green set + Wave 3 proofs)

- `bash scripts/test-shim.sh` → **39 passed, 0 failed** (unchanged).
- `bash scripts/smoke-test.sh --check-only` → **209 passed, 0 failed,
  3 skipped** (244 baseline → 209: −35 = −12 legacy §1 existence loop
  (6 roles × 2 checks) −18 §3 per-role checks (6 roles × 3: valid +
  AGENTS.md + agent md) −2 §1 seed-company.sh list entries
  (REQUIRED_FILES existence + executable) −1 §4 seed-company dry-run
  block −2 qa/tester narrowing gate −1 programmer probe +1 fleet-wide
  probe (probe swap nets 0); zero regressions — every removed check is
  accounted for by a deletion).
- `shellcheck -S warning scripts/*.sh` → zero warnings; `bash -n` all OK.
- `bash scripts/seed-50-fleet.sh --dry-run` → 51 docs, total == cap,
  empty stderr.
- `docker compose config -q` exit 0: default, prebuilt, web-research,
  devsec, ai-gateway, observability, mobile, core+ci, qa-testing+core,
  proxy+tailscale.
- `grep -rn ':latest'` → only the pre-existing piston prose comment
  (policy text, not a pin); `grep -L 'deny'` → none (all 50 tails present).
- `make test` (live mode, stack down) → 209 passed / same 2 environmental
  fails as every prior baseline (`postgres not healthy`, `paperclip not
  responding`) — no new failures; full green needs `make up` (live stage).

## Files changed (uncommitted, Wave 3 only)

- `roles-catalog/ROLE_CATALOG_50.md` (P1-1 one-line Total fix)
- `docker-compose.sidecars.yml` (P1-2 network; P1-3 proxy+runner comments)
- `docker-compose.yml` (P1-2 network name)
- `docker-compose.prebuilt.yml`, `docker-compose.override.yml.example`
  (P1-9 retarget + release docs)
- `roles/{designer,director,pm,programmer,qa,tester}/` deleted (P1-11,
  24 files), `scripts/seed-company.sh` deleted (P1-11)
- `scripts/smoke-test.sh` (§1/§3/§3b/§4/live-hint/COMPANY_NAME/pin gate)
- `scripts/seed-50-fleet.sh` (scope note + supersession map)
- `Makefile` (seed target removal, flow comments)
- `README.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`,
  `SUPPORTING_SERVICES.md` (doc consistency per finding)
- `REMEDIATION_LOG.md` (this entry)

## Self-audit notes (Wave 3)

- Fail-closed kept: managed-network default (`up` creates what `config`
  references); proxy posture untouched (comments only, `POST/BUILD/EXEC=0`
  still asserted by smoke); prebuilt keeps an exact pin with a verify step
  (no invented digest, pull fails closed); deletions remove capability
  rather than adding it; no `|| true`/`TODO`/dummy returns added (remaining
  `|| true` are pre-existing grep-heredoc/live-curl guards); no secrets
  touched; scripts keep `--help`/`--dry-run` + `set -euo pipefail`.
- Chose DELETE over MIGRATE for P1-11 with the count criterion as the
  decider (migration cannot reach 50); chose network-option-A (managed)
  over create-step docs (fewer moving parts, no boot-order dependency);
  chose CI-option-(a) (observer) over dedicated socket (no new host-escape
  path); chose retarget-over-push for P1-9 with the semver-minting proof
  (push alone would not have produced `:v1.0.0`).
- Residuals: live `make up` sweep (network adoption on hosts with a stale
  manually-created `heretek` network; proxy/runner behavior; prebuilt pull
  after a real `v1.0.0` push) still needs the live stage.
- No commits, no merges, no subagents used.

---

# Wave 3 REWORK cycle 1/3 — QA FAIL items (5) + P1-2 bonus gate

**Worktree:** `/home/john/Projects/Heretek-Crew/.worktrees/wave3` (branch `remediate/wave3-claims-topology`)
**Date:** 2026-10-17 | **Source:** QA FAIL on 5 narrow items (everything else PASS)
**Status:** 5 items + bonus fixed, verified empirically. Changes left UNCOMMITTED. No commits.

1. `scripts/dispatch-pipeline.sh:148` — live log line named deleted legacy
   role `tester`. Fixed to `e2e-browser-qa (Automation)` (exists on disk:
   `roles/e2e-browser-qa/`; charter Title `End-to-End Browser Automation
   Engineer`, so `(Automation)` still describes the purpose). File header
   `:10` updated identically. Precise grep
   (`\btester\b|Programmer|\bPM\b`) over the file: clean.
2. `scripts/smoke-test.sh` live §10 — `names = {"Programmer", "PM"}`
   replaced with exact live-API display names from
   `scripts/seed-50-fleet.sh role_display_name()`: `{"TypeScript / Node
   Fullstack Engineer", "End-to-End Browser Automation Engineer"}` (the
   seed's `name` = display string verbatim). Any-agent fallback + comment
   retained. Live-only; gate unaffected.
3. `ROLE_COUNT == 50` gate added at the §3 discovery block (fail-closed
   `bad` on any mismatch, covering 0/49/51). Scratch proof (51st dir added
   to a /tmp copy, worktree untouched): `[FAIL] expected exactly 50 fleet
   role directories under roles/, found 51`, SMOKE FAIL.
4. `NOTES.md:273` — prebuilt pin `:v1.0.0` corrected to `:1.0.0` with
   unpublished/auth-required status matching the
   `docker-compose.prebuilt.yml` header. Minimal one-line edit.
5. Stage 5 arithmetic corrected (accounting only, no gate change): 244→209
   (−35) = −12 legacy §1 existence loop (6×2) −18 §3 per-role (6×3) −2 §1
   seed-company.sh list entries (REQUIRED_FILES + executable) −1 §4
   seed-company block −2 qa/tester narrowing gate −1 programmer probe +1
   fleet-wide probe (net 0). The published Stage 5 entry above had omitted
   the two §1 list entries (−33 claimed vs −35 actual); fixed in place.
BONUS (QA P1-2): `external:` YAML-key-anchored gate added next to the pin
   gate (comments mentioning `external: true` do not trip it). Scratch
   proof: injected `external: true` → `[FAIL] found 'external:' network
   key ... docker-compose.yml:267`, SMOKE FAIL. Worktree files have zero
   real `external:` keys (3 prose-comment mentions only), gate green.

Test results: `smoke --check-only` → **211 passed, 0 failed, 3 skipped**
(209 + 1 ROLE_COUNT + 1 external:); `test-shim.sh` → 39/39;
`shellcheck -S warning scripts/*.sh` clean; `bash -n` all OK;
`seed-50-fleet.sh --dry-run` → cap == sum; dispatch `--dry-run` shows the
new role line; `git status` shows modifications only, no commits.

---

# Stage 6 Remediation Log — Wave 4 Hardening + version bumps (P1-4, P1-5, P1-6, P1-7, P1-10, P1-12, P2, P2-7/P2-8)

**Worktree:** `/home/john/Projects/Heretek-Crew/.worktrees/wave4` (branch `remediate/wave4-hardening-versions`)
**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md` + coordinator recon pre-conditions (re-verified empirically below)
**Status:** all Wave 4 items closed or honestly documented as unverifiable/tracked. Changes left UNCOMMITTED for QA/Drift-Guard. No commits, no merges, no subagents used.

## Live-registry verification (BEFORE committing to tags — command + output)

| Image | Probe | Result |
|---|---|---|
| `redis:7.4.11-alpine` | Hub tag API `.../library/redis/tags/7.4.11-alpine` → `200`, amd64 digest `sha256:ca0acbb1…` | VERIFIED |
| `semgrep/semgrep:1.181.0` | Hub tags `ordering=last_updated` → `1.181.0` newest (non-canary) | VERIFIED |
| `qdrant/qdrant:v1.19.2` | Hub tag API → `200`, amd64 digest `sha256:0e8273b9…` | VERIFIED |
| `neo4j:5.26.32-community-trixie` | Hub tag API → `200`; `5.26.30-community-trixie` also exists (9 `5.26.30*` tags) — newest 5.26.x patch `5.26.32` taken per `5.26.30+` brief | VERIFIED |
| `jaegertracing/jaeger:2.22.0` | Hub tags → `2.22.0` newest; tag API → `200` | VERIFIED (`:2.22` brief → exact `:2.22.0`) |
| `mcp-server-qdrant==0.8.1` | PyPI `.../mcp-server-qdrant/json` → version `0.8.1` (latest), requires `qdrant-client>=1.12.0` — compatible with server v1.19 | VERIFIED, kept, not downgraded |
| `server-github@2025.4.8` | already at target in all 7 roles | CONFIRMED, not regressed |
| `@executeautomation/playwright-mcp-server` | npm dist-tags → `latest: 1.0.12` (fleet pin current, 5 consumers) | CONFIRMED current |
| `@playwright/mcp` | npm dist-tags → `latest: 0.0.83` — a DIFFERENT, fleet-unused package | DISCREPANCY documented, no migration invented |
| `@prevalentware/opencode-goal-plugin` | npm dist-tags → `latest: 0.1.64`; `grep -rln` → exactly 1 role (`exec-director`) | DIRECTOR-ONLY confirmed + smoke-asserted |
| minio digest | `skopeo inspect docker://quay.io/minio/minio:RELEASE.2024-11-07…` → `unauthorized`; quay API → `401` (no creds in env) | UNVERIFIABLE honestly; exact tag kept, AGPL noted |
| piston vendor | GHCR package API → `401 Requires authentication`; push impossible | UNPUBLISHABLE from here honestly; release step documented |

## P1-4: redis ×2 → 7.4.11-alpine + requirepass (`docker-compose.sidecars.yml`, `.env.example`)

- Both images → `redis:7.4.11-alpine`; `command` gains `--requirepass ${REDIS_PASSWORD:?...}` (fail-closed); healthchecks → `redis-cli -a $${REDIS_PASSWORD:?} ping | grep -q PONG`; `SEARXNG_REDIS_URL` + `REDIS_URL`/`REDIS_RATE_LIMIT_URL` carry `:${REDIS_PASSWORD:?...}@` (no bare `redis://`, no defaults); `.env.example` gains `REDIS_PASSWORD=CHANGE_ME__…` with URL-safe-charset note.
- Proof: rendered config shows `--requirepass` ×2 and `redis://:__smoke_only__@…` URLs; unset-secret negative probe fails naming the var (compose `:?`); all 10 profile combos `config -q` exit 0.

## P1-10: bumps (compose + `SUPPORTING_SERVICES.md` mirrors + prose tags)

- `semgrep:1.97.0→1.181.0`, `qdrant:v1.12.5→v1.19.2` (+`QDRANT__SERVICE__API_KEY` enforcement; `vector-rag-spec` MCP sends `QDRANT_API_KEY=${QDRANT_API_KEY}` — catalog + disk), `neo4j:5.26.0-community-bullseye→5.26.32-community-trixie`, `jaegertracing/all-in-one:1.63.0→jaegertracing/jaeger:2.22.0` (v1-era `COLLECTOR_OTLP_ENABLED` retained with a verify-on-first-up note), minio exact tag + AGPLv3 note + re-verified auth-gate, piston digest + maintainer vendoring release step (no invented digest).
- Proof: smoke §3a asserts each new pin present + each predecessor absent on `image:` lines (comments exempt by design); `config -q` green on all combos.

## P1-5/P1-7: write+exec synergy + glob anchoring (9 roles, catalog + disk + charters)

- Anchored fleet-wide (audit of ALL fs:write globs): `*lock*`→`**/package-lock.json`+`**/pnpm-lock.yaml` (dependency-patcher; `Cargo.lock`/`package.json`/`pyproject.toml`/`go.mod`/`go.sum` already exact), `*config*`→`**/*.config.js`+`**/*.config.ts` (fe-perf-eng), `*lint*`→`**/.eslintrc.json`+`**/eslint.config.js` (static-analysis-lead), `*.md`→`docs/**/*.md` (tech-docs-lead), `go.*`→`go.mod`+`go.sum` (go-backend-eng), `Cargo.*`→`Cargo.toml`+`Cargo.lock` (rust-systems-spec). Remaining `go.*`-style leading-literal globs (`playwright.config.*`, `build.gradle*`) are cwd-scoped and left, documented in the lint rule.
- Split documentation: `sabotage-qa-tester` raw toolchain exec (`cargo mutants*`, `npx stryker run*`, `npm test tests/chaos*`, `cargo test chaos*`) replaced with exact-host piston pins (`curl -s http://piston:2000/api/v2/runtimes*`, `curl -s -X POST http://piston:2000/api/v2/execute*`); skill procedure + charter rewritten (mutation jobs submitted to piston, never raw on host). Remaining verifier-only exec (`cargo test*`, `go test*`, `pytest*`) retained with exact-path pins as charter-mandated verification; mutating builds directed to piston/local-ci-runner per §E.2/§12 — each split recorded here.
- Enforcement: smoke glob-specificity lint (fs:write-only scope; `**/`-anchored, exact filenames, leading-literal globs, deny-tail `*`, and shell allows all exempt) + identical `die()` in `generate-50-roles.py::normalize_config`.
- Proof: regen into scratch → 0 permission mismatches, 0 full-file diffs across all 50; mutation probes (`*evil*` in disk → smoke FAIL naming role+glob; `*lock*` in catalog → generator exit 1) both fail closed, then restored; smoke green after restore.

## P1-6/P1-12: curl removal, segmentation, auth, Makefile guard, runner

- Removed `curl -s http://*` (mlops-serving-eng) and `curl -sI*` (sre-incident-eng); charters now route diagnostics through ollama/docker and prometheus MCP (§4). Only sanctioned curl shape left: sabotage's piston exact-host pins.
- Segmentation (minimal viable, boot-safe): `heretek-devsec` (ghidra+radare2) + `heretek-mobile` (docker-android) isolated; paperclip joins both via compose-merge extension (star topology preserved). Rest stays on shared `heretek` deliberately — full per-category split would break the firecrawl mesh and runner→proxy path without a live stack to verify; tracked, not chased.
- Makefile `guard-profiles` refuses `mobile`+`devsec`/`web-research` co-scheduling (fail-closed exit 1; existing targets untouched) + `sidecars-up SIDECAR_PROFILES=…` entrypoint. Runner: `./workspaces:ro` + `./workspaces/scratch:/scratch:rw`.
- Proof: rendered paperclip nets = heretek+devsec+mobile; runner volumes show `read_only: true` + rw scratch; `make guard-profiles SIDECAR_PROFILES="mobile devsec"` → error + exit 1, `"mobile,web-research"` → same, `"web-research"`/`"mobile"` alone → exit 0; smoke asserts guard text + nets + ro/scratch.

## P2: provisioner header, REPO_ROOT, --session, resource table, age backups, sabotage pin

- `dispatch-pipeline.sh` header rewritten (provisioner/tracer, not orchestrator); `REPO_ROOT+cd` added to it and `worktree-manager.sh`; manager invoked via `${REPO_ROOT}`; redundant `mkdir -p` after worktree create dropped (P2-2).
- `--session ses-` assumption: CLOSED as non-issue — repo-wide grep finds zero `ses-` references; installed `opencode v2.0.30` documents `--session` as free-form ("to continue, or to create if it does not exist"); shim passes through verbatim (smoke §5). Live-stack ticket flow still needs `make up` (tracked live gate, stack down here).
- `SUPPORTING_SERVICES.md`: per-profile `cpus`/`mem_limit` reservation table (summed from compose — web-research 9.2/13.5g … qa-testing 10.7/15.75g heaviest; base 3.0/5g extra) + minimum-host guidance; taxonomy service lists corrected (hound/piston/mitmplugin/semgrep/runner membership); §1b version-lag closed; §12 segmentation/auth/runner items; P2-7/P2-8 scope note; minio AGPL note; §11 authoritative-source disclaimer.
- Backups: `BACKUP_AGE_RECIPIENT` opt-in `age -r` encryption (`.sql.gz.age`; fail-closed on missing binary/bad shape; retention covers both suffixes) + restore `.sql.gz.age`/`.sql.age` support via `BACKUP_AGE_IDENTITY` (gated before the destructive prompt). `age` chosen as the single at-rest mechanism (no gpg shell-out).
- Proof: `--dry-run` from `/tmp` exit 0 (REPO_ROOT anchoring); age round-trip (`SELECT 1;` → gzip → age → decrypt → gunzip) byte-exact; restore without identity → fail-closed error; with unreadable identity → fail-closed error; `shellcheck` + `bash -n` clean; `--help` documents new vars.

## P2-7/P2-8: pins + scope (see table above; `SUPPORTING_SERVICES.md` note + smoke gates)

- Seed preflight deliberately NOT extended: `REDIS_PASSWORD`/`QDRANT_API_KEY` are compose-level service credentials (already `:?`-gated at `config`/`up`), not MCP/agent credentials — the seed gate stays scoped to its three provisioning secrets.

## Test results (must-keep-green set + Wave 4 proofs)

- `bash scripts/test-shim.sh` → **39 passed, 0 failed** (unchanged).
- `bash scripts/smoke-test.sh --check-only` → **234 passed, 0 failed, 3 skipped** (was 211 on this branch: +19 §3a Wave 4 pin/auth/scope gates, +1 glob lint, +3 from dummy-env/profile coverage; scratch mutation run: 233/1 FAIL on injected `*evil*`, restored to 234/0).
- `shellcheck -S warning scripts/*.sh` → zero warnings; `bash -n` all OK.
- `bash scripts/seed-50-fleet.sh --dry-run` → 51 docs, total == cap, no WARNING.
- `docker compose config -q` exit 0: default, prebuilt, web-research, devsec, ai-gateway, observability, mobile, core+ci, qa-testing+core, proxy+tailscale.
- `grep -rn ':latest'` on compose/Dockerfile → clean (prose comments only); `grep -L deny` → all 50 tails; no secrets committed/echoed (dummies only); no invented digests/versions.
- `make test` (live mode, stack down) → same 2 environmental fails as every prior baseline (`postgres not healthy`, `paperclip not responding`) plus check-only-equivalent otherwise — full green needs `make up` (live stage).

## Files changed (uncommitted, Wave 4 only — 37 files)

- `docker-compose.sidecars.yml` (P1-4 ×2 + auth, P1-10 ×6, P1-12 nets + runner + paperclip extension)
- `.env.example` (REDIS_PASSWORD, QDRANT_API_KEY), `Makefile` (guard-profiles + sidecars-up)
- `roles-catalog/*.md` (01/03/04/05/06/08/09 permission + skill + env edits)
- 10× `roles/*/opencode/opencode.json` (9 perm edits + vector-rag qdrant env)
- 9× `roles/*/AGENTS.md` (write-scope/verify-toolchain lines) + sabotage SKILL.md
- `scripts/smoke-test.sh` (§3a + glob lint + dummy env), `scripts/generate-50-roles.py` (generation-time glob lint)
- `scripts/dispatch-pipeline.sh` (header + REPO_ROOT + mkdir drop), `scripts/worktree-manager.sh` (REPO_ROOT)
- `scripts/backup-db.sh` + `scripts/restore-db.sh` (age at-rest)
- `SUPPORTING_SERVICES.md` (pins, resource table, §12, scope notes), `REMEDIATION_LOG.md` (this stage)

## Self-audit notes (Wave 4)

- Fail-closed kept: `:?` secrets, authed healthchecks, guard exit 1, lint `die()`/FAIL, age opt-in that aborts rather than falling back to plaintext, no `|| true`/`TODO`/dummy returns, no floating tags, deny tails 50/50, no secrets in repo.
- Honest non-closures (tracked, not faked): minio digest (quay 401 re-proven), piston vendoring (GHCR 401, release step documented), full per-category segmentation (boot-risk, minimal viable shipped), live verifications (`make up` matrix, jaeger-v2 first boot, redis-auth client interop under real traffic, age backup against a live DB, `--session` live ticket flow).
- No commits, no merges, no subagents used.

---

# Wave A Remediation Log — P0-2 read-only harness strip + P1-7 fs:read deny-first (P2-1 claim note)

**Worktree:** `/home/john/Projects/Heretek-Crew` (no worktree — `git status` was clean; branch `main`)
**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md` P0-2/P1-7 + P2-1 fragment
**Status:** complete, verified empirically. Changes left UNCOMMITTED for QA/Drift-Guard.
Full report: `docs/reports/wave-a-implementation.md`.

## P0-2: 16 read-only roles stripped of 4 mutating harness tools (51 files)

- Predicate: every `fs:write` allow confined to report-output scopes (`docs/**`,
  `sbom/**`, `deploy/security/**` seccomp profiles — declarative policy outputs).
  Yields 16 roles incl. all 6 mandated (`exec-director`, `product-director`,
  `threat-modeler`, `compliance-auditor`, `tech-docs-lead`, `ux-research-analyst`);
  `threat-modeler` ("Never writes application code") + `compliance-auditor`
  (delegates code changes) qualify despite non-`docs/` scopes. All other 35
  roles write tests/source/schemas/migrations/configs/assets → keep 14.
- Each of the 16: 4 allows removed, 4 exact denies added (audit JSON verbatim)
  after the `harness_*` deny tail; 10 read-only allows + tails preserved.
- `scripts/generate-50-roles.py`: `HARNESS_MUTATING_TOOLS`,
  `READONLY_HARNESS_STRIPPED` (16, explicit + self-checking `die` on drift),
  `strip_mutating_harness_tools()` (idempotent) in `normalize_config`.
  `ai-red-teamer` transformed by hand with the identical imported functions
  (generator covers catalog Roles 01–50 only).

## P1-7: fs:read denies first in 51/51 files

- The 4 `.env` read-denies moved to permissions indices 0–3 in every role file
  (fail-closed under first-match AND deny-override). `fs:write` ordering untouched.
- Generator: `FS_READ_ENV_DENIES` + `order_fs_read_denies_first()` (ENSURES the
  canonical denies — the catalog fences predate them — then orders deny-first).

## P2-1 fragment + smoke gates

- No in-repo file states the inverted `{harness_*, allow}` claim (prompt-only
  text); smoke header NOTE rewritten to the true shape + P0-1-blocked live-matrix
  note (no live enforcement claimed; P0-1 `dist/index.js` untouched — upstream npm).
- `smoke-test.sh`: manifest gate branched (14 full / 10 read-only + 4 denies,
  deny-tail preserved) + 2 new fail-closed gates (read-only set drift pin +
  mutating-tool ban; fs:read ordering).

## Test results

- `smoke-test.sh --check-only` → **497 passed, 0 failed, 3 skipped**
  (stashed-HEAD baseline 495/0/3 → +2 new gates, zero regressions).
- `shellcheck` clean; `test-shim.sh` 39/0; `spec-gate.sh` 7/0; JSON valid 51/51;
  `grep -L deny` → 0; `ls roles/` = 51; tails/`small_model`/`compaction`/`timeout`
  asserted programmatically on all 51.
- Watched-fail probes: injected mutating allow → both gates FAIL (exit 1);
  reordered fs:read → ordering gate FAILs (exit 1); both restored byte-identical.
- Generator parity: scratch regen reproduces harness + fs:read sections exactly
  for all 51 roles (scratch-only EXPECTED_IDS patch for Role 51; see report §6).

## Pre-existing issues found (not introduced — separate waves)

- Generator dies at HEAD: catalog holds Role 51 but EXPECTED_IDS lists 50
  (`role set mismatch`, proven via `git show HEAD:` copy) — P1-4 decision.
- Catalog lacks all `.env` denies (fs:read AND fs:write) present on disk;
  ai-red-teamer `git_*` read verbs likewise hand-only — catalog-sync wave.
- No commits, no merges, no subagents used.

---

# Wave C Remediation Log — P0-5/P0-6 + P1-2/P1-3/P1-4/P1-12/P1-13/P1-14

**Worktree:** `/home/john/Projects/Heretek-Crew` (no worktree — base clean at Wave B `09e1e6a`; branch `main`)
**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md` + task envelope (TARGETS + ACCEPTANCE)
**Status:** all Wave C items closed or honestly recorded as tracked residuals, verified empirically. Changes left UNCOMMITTED for QA/Drift-Guard. No commits, no merges, no subagents used.
Full report: `docs/reports/wave-c-implementation.md`.

## Registry evidence (live, before any edit)

- `npm view opencode-rea version` → `E404 Not Found` (P0-5 reproduced).
- `npm view @prevalentware/opencode-goal-plugin version` → `0.1.64` (pinned).
- `npm view @morluto/rea-mcp version` → `E404 Not Found` (P1-12 removal path).
- `npm pack rea-agents@6.5.0` → real package ("one CLI and MCP server", bin `rea`/`rea-agents`) but MCP registers via interactive `setup` — no verified headless stdio argv, so migration would invent an invocation (stub). Removal chosen, fail-closed.
- Forks at npm latest (no migration owed): `@executeautomation/playwright-mcp-server` 1.0.12, `@playwright/mcp` 0.0.83 (different package line), `@upstash/context7-mcp` 4.4.2, `@modelcontextprotocol/server-postgres` 0.6.2, `@cyanheads/git-mcp-server` 2.15.3.
- `pip index versions`: 9/10 uvx pins resolve at pinned versions; `kafka-mcp-server` → "No matching distribution" (doubly dead with its absent sidecar — recorded residual, kept infra-pending).
- Local `curl 8.22.0` supports `--fail-with-body` (script floor: curl >= 7.76, noted in-code).

## P0-5: phantom plugin removed, goal-plugin installed, publish gate added

- `roles/binary-reverse-eng/opencode/opencode.json`: `"opencode-rea"` dropped from `plugins`; `rea` MCP server block deleted (`rea_*` allows stay as dormant re-activation scope). Charter §4/§6 + catalog Role 41 §3/§5/§6 fence + generator `INTEGRATION_NOTES` carry the removal note with re-add criteria (exact pin when upstream publishes/documents).
- `docker/Dockerfile`: `@prevalentware/opencode-goal-plugin@0.1.64` added (pin comment + `ENV OPENCODE_GOAL_PLUGIN_VERSION` + global install + `npm ls` assert).
- `.github/workflows/docker-publish.yml`: step 3 asserts harness+mem+goal-plugin; new 3b plugin-resolution gate extracts exact `plugins` arrays (jq, not grep) from the checkout and asserts each via `npm ls -g` in the built image. (One self-caught breakage: an embedded multi-line `python3 -c` terminated the `run: |` literal block — caught by `yaml.safe_load`, rewritten with jq, re-proven.)

## P0-6: no digest invented; latest removed; HERETEK_IMAGE constrained

- `type=raw,value=latest` line DELETED (stronger than a scoped exception) with in-file rationale; workflow mints `1.0.0`/`1.0`/`sha-*` only. Stale mint-list prose updated in prebuilt header + smoke comment.
- `docker-compose.prebuilt.yml` header: local-build routing retained + digest procedure (tag → manifest-inspect → replace pin) + `HERETEK_IMAGE` override constraint (exact `:1.0.0` or digest only, never floating). Mirrored in `README.md` Option A + `.env.example` (via scripted replacement — `.env*` edit guard).

## P1-2: dead wiring pinned as infra-pending + allowlist gate

- 8 `(role, server)` pairs (ollama, prometheus×2, kafka, clickhouse, k6, docker×2 without `DOCKER_HOST`) noted in catalog §3 + all 7 disk charters. Smoke gate asserts flagged == allowlist exactly (absent-host env match + `k6` + `docker`-without-`DOCKER_HOST` detectors).

## P1-3: seeder fail-closed (proven against a live 500/422 fixture)

- `api()` `--fail-with-body`; health `-f`; PATCH body capture + `|| exit 1`; `find_*` parse/shape failures exit 1. Fixture proof: old argv rc=0 on 500 (bug reproduced) vs new rc=22 with body on stderr.

## P1-4: ai-red-teamer promoted (52 payloads, $13,000.00)

- Seeder: ROLE_LIST +1, budget 30000¢, `system-architect` parent, `security` paperclip role, display/title entries, cap → 1300000. Dry-run: 52 docs, total == cap, empty stderr, payload verified (`security`/30000/`<system-architect-id>`/XDG/skip-false).
- Generator: EXPECTED_IDS + REPORTS_TO + cap + count strings; four convergence fixes (small_model/compaction, fs:write denies, skill roots, timeout) so scratch `--root` regen reproduces ALL 51 `opencode.json` byte-identically (fixes the dies-at-HEAD mismatch AND the Wave A catalog-drift notes for these fields).
- Catalog Total → $13,000.00/51 agents; README/AGENTS/Makefile/NOTES counts + budget prose; smoke §4 → 52 payloads; catalog-derived role-dir-count assertion unchanged (51==51).
- Charter prose NOT regenerated in-repo (disk is hand-richer; full run would regress exec-director skills/workflow lines, mlops containment, ai-red-teamer prose+5th skill) — targeted disk edits only (`NN/50`→`NN/51` + note insertions); residual + warning recorded in the generator docstring.

## P1-12: pins closed out (zero exceptions)

- Exception sets deleted (generator branches + smoke `EXCEPTIONS`/`seen_exception`). Fork/PyPI verification recorded in the smoke header comment. kafka-mcp PyPI-404 recorded as the sole tracked residual.

## P1-13/P1-14: piston plan, android resourcing, hound decision

- Piston: numbered vendoring plan in `SUPPORTING_SERVICES.md` E.2; digest kept, never `:latest`.
- Android: 4.0 CPU / 8g + host-requirement warning + dual-probe healthcheck (adb OR noVNC, both verified in rendered config); resource table updated (mobile 4.0/8.00g, fleet total ~46 GB).
- Hound: tracked decision (livegrep/zoekt preferred, else vendor; digest frozen meanwhile) in compose + D.3, incl. the :6080 profile-overlap note.

## Test results (must-keep-green set + Wave C proofs)

- `bash scripts/smoke-test.sh --check-only` → **514 passed, 0 failed, 3 skipped** (513 Wave-B-era → 514: +3 new gates +1 count update, net of the pin-gate rewrite; zero regressions).
- `bash scripts/test-shim.sh` → **45 passed, 0 failed** (untouched).
- `shellcheck -S warning scripts/*.sh` → zero warnings; `bash -n` all OK.
- `bash scripts/seed-50-fleet.sh --dry-run` → 52 docs, total == cap, empty stderr.
- `bash scripts/spec-gate.sh --check-only` → 7/0.
- `docker compose config -q` exit 0: default, prebuilt, web-research, devsec, ai-gateway, observability, mobile, core+ci, qa-testing+core, proxy+tailscale (dummy secrets; unset negative probe still fails naming the var).
- Watched-fail probes: unpinned+dead injection → pin + dead-MCP gates FAIL; `opencode-rea` re-added → plugin gate FAILs naming it; live `value=latest` appended → no-latest gate FAILs; garbage parse → exit 1. All restored byte-identical.
- `make test` (live mode, stack down) → same 2 environmental fails as every prior baseline (`postgres not healthy`, `paperclip not responding`) — full green needs `make up` (live stage).

## Files changed (uncommitted, Wave C only — 120 files)

- `roles/binary-reverse-eng/opencode/opencode.json` + `AGENTS.md` (P0-5/P1-12 removal)
- 7 dead-MCP charters + 100 mechanical `NN/50`→`NN/51` charter/agent-md bumps
- `docker/Dockerfile`, `.github/workflows/docker-publish.yml`, `docker-compose.prebuilt.yml`, `docker-compose.sidecars.yml`, `.env.example`
- `scripts/seed-50-fleet.sh`, `scripts/generate-50-roles.py`, `scripts/smoke-test.sh`
- `roles-catalog/05|06|07|08_*.md`, `ROLE_CATALOG_50.md`, `README.md`, `AGENTS.md`, `Makefile`, `NOTES.md`, `SUPPORTING_SERVICES.md`
- `docs/reports/wave-c-implementation.md` (new), `REMEDIATION_LOG.md` (this entry)

## Self-audit notes (Wave C)

- Fail-closed kept throughout (see stage report §5); no `|| true`/`TODO`/dummy returns added; no floating tags (one tag REMOVED); deny tails 51/51; no secrets in repo.
- Not done / residuals: live image build + publish-gate execution, prebuilt pull post-`v1.0.0`, charter-prose catalog back-sync, kafka-mcp package+sidecar, piston vendoring + hound migration (maintainer), full segmentation, `redis://redis:6379` hostname (unfiled by the audit — flagged, unchanged).
- No commits, no merges, no subagents used.

---

# Wave D Remediation Log — Final Remediation (P0-1, P0-3, P1-1, P1-5, P1-6, P1-8, P2-5–P2-9, P3-1–P3-5)

**Worktree:** `/home/john/Projects/Heretek-Crew` (no worktree — base clean at Wave C `d7c7aca`; branch `main`)
**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md` + task envelope (TARGETS + ACCEPTANCE)
**Status:** all Wave D items closed or honestly recorded as tracked residuals, verified empirically. Changes left UNCOMMITTED for QA/Drift-Guard. No commits, no merges, no subagents used.
Full report: `docs/reports/wave-d-implementation.md`.

## What changed (by finding)

- **P0-1:** upstream `pick()` diff + bump plan in `docker/Dockerfile` + `NOTES.md` (nothing invented — dist is upstream npm); pin stays 1.0.7, Domain 4 labeled load-broken; new §10b live-only gate (`HARNESS_LIVE_GATE=1`) + probe fixture `scripts/fixtures/harness-probe-opencode.json`; check-only carries two documented SKIP notes.
- **P0-3:** kubeconfig mount kept `:ro` + MCP-env structural plan; §4 seed-payload env allowlist gate (no superuser/provider keys — green); 4 secret-material `fs:read` denies × 51 via generator + scratch-regen promotion (disk == generator, zero drift) + fleet-wide smoke gate.
- **P1-1/P3-2:** `adb connect*` → loopback + docker-android allowlist (catalog + disk + charter + smoke gate); sabotage piston pins kept exact-host + advisory note; enforcer identity/version + live-probe steps in `AGENTS.md` §4.
- **P1-5:** r2/ghidra/piston fronting plans + paperclip-as-bridge residual (`SUPPORTING_SERVICES.md` §12.7, per-service compose notes); firecrawl loopback-only decision + gate; `POST/BUILD/EXEC=0` untouched.
- **P1-6/P3-5:** Domain 8 claims corrected to read-only-observer (both SUPPORTING mirrors + value prop); `:2375` GET-recon accepted risk; `DOCKER_HOST` declared in both docker MCP servers (catalog + disk + smoke gate; dead-MCP 9→7).
- **P1-8:** Paperclip source-commit pin procedure; Claim 3.1 labeled config-advice, live-unverified; canary steps in §10b SKIP note.
- **P2-5:** base-digest plan; §8 live UID==1000 gate (not-running vs wrong-user distinguished); `--force` rationale comment.
- **P2-6:** `guard-proxy` + `proxy-up` (all four directions verified) + compose/`.env.example`/AGENTS/smoke routing.
- **P2-7:** password-file plan + READONLY-only payload gate; `workspaces/scratch/.gitkeep` tracked (outputs ignored — both verified); signing secret `:?` + gate.
- **P2-8:** digest/minor plans as comments (no blind bumps); hound host `:6081` (mirrors + gate); rabbitmq env auth (guest retired, first-boot caveat, gate); quarterly watchlist in §1b.
- **P2-9:** fetch-once + double ROLE_DIR guard (shell + python `sys.argv` assert; `ROLE_DIR=wrong-role` → exit 1) + smoke gate.
- **P3-1:** `stat -L` device+inode fallback + test 21 (46/46; old-code trace proved the miss at depth 0).
- **P3-3/P3-4:** rabbitmq rotation done; Caddyfile tracked as optional.

## Test results (must-keep-green set + Wave D proofs)

- `bash scripts/test-shim.sh` → **46 passed, 0 failed**.
- `bash scripts/smoke-test.sh --check-only` → **526 passed, 0 failed, 5 skipped** (3 environmental + 2 live-gate notes).
- `bash scripts/spec-gate.sh --check-only` → 7/7. `shellcheck scripts/*.sh` → zero warnings.
- `bash scripts/seed-50-fleet.sh --dry-run` → 52 payloads, total == cap, empty stderr; ROLE_DIR hazard probe → exit 1.
- Mutation probes (restored green): secrets-deny removal → FAIL; bare adb → FAIL; DOCKER_HOST removal → 2 FAILs.
- `docker compose config` → exit 0 on default, prebuilt, web-research, devsec, ai-gateway, observability, mobile, core+ci, qa-testing+core, proxy+tailscale. qa-testing-alone failure verified identical on stashed baseline (pre-existing pairing, not a regression).
- Generator↔disk zero drift (scratch `--root` regen, before and after).
- `make test` (live, stack down) → 526 passed / 3 environmental FAILs (all "stack not running" — full green needs `make up`).

## Self-audit notes (Wave D)

- Fail-closed kept: guards exit non-zero with descriptive errors; no `|| true`/`TODO`/dummies; deny tails 51/51 re-verified programmatically; no `:latest` introduced; no secrets (dummies/placeholders only).
- Honestly unclaimed: P0-1 load-broken, 3.1 + scrub live-unverified, prefix semantics assumed, fronting/digests tracked-not-built. Residuals needing live stack/registry/auth listed in the stage report §4.
- Mid-work scare: a `git stash`/`pop` baseline probe echoed a transient AGENTS.md revert in the file watcher — verified immediately (stash list empty, all 4 Wave D markers present, pop restored everything). No edits lost.
- No commits, no merges, no subagents used.

---

# Wave E Stage 1 Remediation Log — P0 Critical (P0-1, P0-2, P0-3, P0-4)

**Worktree:** `/tmp/opencode/heretek-wave-e` (branch `wave-e-audit-remediation`)
**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md` P0-1…P0-4 (lines 12-53) + remediation order lines 186-192
**Status:** all 4 P0 verified closed (3 pre-existing closures re-proven + 1 residual honestly labeled this stage). Changes left UNCOMMITTED for QA/Drift-Guard. No proof contradicted the audit; no product decision blocked progress.

## P0-1: harness 1.0.7 DIES on load → verified, not invented (no repo patch)

- `docker/Dockerfile:33-53` already documents the empty-string `rootDir` root cause + `pick()` diff + bump plan + live-visibility gate reference — read in full, accurate, no correction needed.
- `scripts/smoke-test.sh` §10b (`:1725-1745`) asserts a real agent turn invoking `file_hash_read` must succeed under `HARNESS_LIVE_GATE=1` (FAILs on the `rootDir must be` Die / `not available`), never just `npm ls` — verified present.
- `OPENCODE_HARNESS_VERSION` exact `1.0.7` (ENV + install + comment) — verified, no float.
- Live registry proof this stage: `npm view @heretek-ai/opencode-harness versions` → `[ '0.0.0-stage', '1.0.0', '1.0.2', '1.0.3', '1.0.4', '1.0.7' ]` — **no fixed successor published; upstream bump BLOCKED (nothing to bump to)**. Pin stays exact; Domain 4 stays labeled load-broken.
- Files changed: none (docs already correct).

## P0-2: Claim 3.3 read-only bypass → verified closed on disk + generator + gate

- 6/6 read-only roles (`exec-director`, `product-director`, `threat-modeler`, `compliance-auditor`, `tech-docs-lead`, `ux-research-analyst`): 10 read-only harness allows each, 4/4 mutating denies each placed AFTER the `harness_*` deny tail, zero allows for the 4 (python JSON parse + grep showing only `"effect": "deny"`).
- Generator encodes the split (`HARNESS_MUTATING_TOOLS`, 16-role `READONLY_HARNESS_STRIPPED` superset, `strip_mutating_harness_tools()`, `is_readonly_charter()` drift pins); scratch `--root` regen → 51 roles, 0 permission mismatches (byte-identical).
- Smoke gate: harness-manifest (14/10 + deny tails) + read-only-set drift pin (on-disk == 16 exactly) + mutating-allow ban — green inside the 526.
- Files changed: none (closure from prior waves re-proven).

## P0-3: XDG isolates config only → verified (a) bound kept + plan tracked (b) honestly labeled (c) 51/51 denies ordered

- (a) kubeconfig `:ro` bind intact (`docker-compose.yml:170`); FD-passed-MCP-env structural plan comment verified (`:156-170`). k8s-orchestrator unbroken (compose renders).
- (b) `AGENTS.md` §1 invariant 1 (`:20-24`) + `NOTES.md` Wave D (`:363-375`) label Claim 3.1 config-advice live-unverified + child-env scrub pending canary — no live-pass claim anywhere.
- (c) python JSON parse: 51/51 carry all 4 secret-material `fs:read` denies above every allow (0 violations); generator `FS_READ_ENV_DENIES` + `order_fs_read_denies_first()`; smoke §3b presence + ordering gate green.
- Files changed: none (closure from prior waves re-proven).

## P0-4: piston RCE-as-a-service → residual honestly labeled (2 comment-only edits)

- sabotage-qa-tester exact-host piston curl pins untouched (`:73,:78`); ghidra `:1337` / radare2 `:9090` paperclip-as-bridge residual verified present; firecrawl loopback-only + `USE_DB_AUTHENTICATION=true` plan verified present (smoke §3a green).
- `docker-compose.sidecars.yml` piston comment +7 lines: stays on shared `heretek` net (live network move deferred pending `make up` reachability verification) + never-co-schedule devsec/qa-testing advisory — no behavioral change (image/profiles/expose/networks byte-identical).
- `Makefile` +10-line co-scheduling note after `sidecars-up` (advisory, NOT an enforced guard — devsec+core is normal ops; existing guard text byte-identical so smoke gates stay green).
- Compose renders exit 0 on `qa-testing+core` and `devsec+core` with dummy env; fail-closes without `.env`.

## Test results (must-keep-green set + Wave E Stage 1 proofs)

- python3 JSON parse: 51/51 `{shell,*,deny}` terminal tails; 51/51 fs:read deny-first; 6/6 read-only roles 4-deny/0-allow.
- `bash scripts/smoke-test.sh --check-only` → **526 passed, 0 failed, 5 skipped**.
- `bash scripts/test-shim.sh` → **46 passed, 0 failed**. `shellcheck scripts/*.sh` → zero warnings. `bash scripts/spec-gate.sh --check-only` → **7 passed, 0 failed**.
- `bash scripts/seed-50-fleet.sh --dry-run` (smoke dummies) → 52 docs, total 1300000 == cap, empty stderr; absent secrets → exit 1 per var.
- `git status --short` → only `M Makefile`, `M docker-compose.sidecars.yml`, `?? docs/reports/wave-e-stage1-implementation.md` (+ this log); no `:latest` (prose-only hits), no TODO/dummy, no secrets.

## Self-audit notes (Wave E Stage 1)

- Fail-closed kept: both edits are comments/notes; zero enforcement, pin, permission, or network deltas (smoke count unchanged 526 → 526).
- Tracked, not started: piston vendor build, shared-secret proxy front, `HARNESS_LIVE_GATE=1` + canary + scrub live runs.
- No commits, no merges, no subagents used.

---

# Wave E Stage 2 Remediation Log — P1 High (P1-1 through P1-8)

**Worktree:** `/tmp/opencode/heretek-wave-e` (branch `wave-e-audit-remediation`)
**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md` P1-1…P1-8 (lines 56-98) + remediation order lines 186-192
**Status:** all P1-1…P1-8 closed or verified-present, tests re-proven empirically. Changes left UNCOMMITTED for QA/Drift-Guard. No proof contradicted the audit; one doc-drift beyond the audit text found and fixed (k8s-orchestrator docker-MCP charter note stale since Wave D P1-6). No stoppage needed (no product decision blocked progress; six tracked residuals recorded, none started).

## P1-1: shell prefix-patterns → verified + one sentence (AGENTS.md)

- Enforcer identity + version, prefix-semantics assumption, and the four live probes (`git status; id`, `git status$(id)`, `git status||id`, `npm test -- --unknown-flag`) verified already present in `AGENTS.md` §4. **Added:** never cite `smoke-test.sh` §3/§3b as enforcement proof (JSON shapes only). `adb connect*` re-verified narrowed (android-mobile-spec exactly loopback + docker-android, no bare fleet-wide; smoke adb gate green). Docs-only — no argv-aware rewrite without a live stack.

## P1-2: MCP namespace bypass → verified + charter de-staled (roles/k8s-orchestrator/AGENTS.md)

- dba GRANTs (`paperclip_reader` SELECT-only SQL) + k8s read-only ClusterRole binding verified in charters with the full provisioning chain (initdb hook, compose `:?`, seed preflight). Namespace deny tails verified where the pattern is established (harness 51, git 25, docker 2, filesystem 2, kubernetes/postgres/aws). Extension to playwright/chrome-devtools/mobile/r2/redis/kafka/qdrant deliberately NOT invented (no in-tree per-tool enumeration; needs the runtime tool-name contract — tracked product decision). `DOCKER_HOST=tcp://docker-socket-proxy:2375` re-verified in both docker MCP roles. **Fixed:** k8s-orchestrator charter docker-MCP note still said "no DOCKER_HOST wired / infra-pending" while the config has carried it since Wave D P1-6 (smoke dead-MCP gate already documents the exit from the dead list) — rewritten to the active read-only-observer posture.

## P1-3: socket-proxy GET-recon → tracked plan comment + prompt version fix

- `tecnativa/docker-socket-proxy:0.3.0` with `POST/BUILD/EXEC/VOLUMES/NETWORKS=0` + `CONTAINERS/IMAGES/INFO/VERSION=1`, expose-only `:2375`, verified. **Added:** dedicated `heretek-ci` net / source-IP-allowlist tracked plan comment (move deferred pending `make up` verification; never publish `:2375`, never weaken writes). **Fixed:** `PROMPT_ADVERSARIAL_FLEET_AUDIT.md` `0.1.1` → `0.3.0` (Claim 8.2 + Domain 11.8); `SUPPORTING_SERVICES.md` already `0.3.0`.

## P1-4: ports + firecrawl → verified + full loopback gate (scripts/smoke-test.sh)

- Paperclip `127.0.0.1:3100` + 14 sidecar loopback binds verified; caddy 80/443 profile-gated with `guard-proxy` (private exposure + non-placeholder secret) + compose `:?` + in-file notes (value-comparison refusal not expressible in compose — documented never-bypass, same as Wave D P2-6). Firecrawl `USE_DB_AUTHENTICATION=false`-with-rationale + path-to-`true` + loopback-only verified. **Added:** smoke gate asserting the full 15-bind set and failing on any non-loopback publish outside caddy 80/443.

## P1-5: secret hygiene → verified + GO-key advisory (scripts/opencode-shim.sh)

- No committed secrets (`git ls-files`: only `secrets/.gitkeep`); `DATABASE_URL` server-side with password-file plan comment; `POSTGRES_READONLY_URL` agent-exclusive (preflight rejects superuser); seed has no `set -x`/value echo; kubeconfig FD plan + ClusterRole + fs denies cross-reffed to P0-3. **Added:** GO-key silent-fallback advisory comment (convenience, not a boundary; no-clobber pinned by test-shim §20; no opt-in gate — would break unattended runs).

## P1-6: fs:read ordering → re-verified + live negative steps (scripts/smoke-test.sh)

- 51/51 deny-first, 0 violations; generator untouched (no drift). **Added:** `.env` live negative probe (fs:read AND filesystem MCP, both must DENY) to the §10b live-gated SKIP text; static §3b stays the in-repo gate.

## P1-7: dispatch claims → prompt correction + wording fix (PROMPT + scripts/dispatch-pipeline.sh)

- Header/exit-0 verified (dry-run exits 0). **Fixed:** prompt Claims 7.1/7.2 rewritten to provisioner-tracer semantics; three dry-run `Emitted …` lines → `MANUAL assignment (no API call, nothing emitted)`. Phase-5 host-`act` text already correct (prior wave).

## P1-8: Domain 8 inversion → prompt correction (PROMPT_ADVERSARIAL_FLEET_AUDIT.md)

- SUPPORTING_SERVICES.md + sidecar comments verified read-only-observer. **Fixed:** prompt Claims 8.1/8.2 rewritten (8.2 carries the `0.3.0` fix). Pins verified: socket-proxy `0.3.0`, piston digest-pinned (`v2.0.0` never existed — already commented in-file).

## Test results (must-keep-green set + Stage 2 proofs)

- `bash scripts/smoke-test.sh --check-only` → **527 passed, 0 failed, 5 skipped** (526 baseline + 1 loopback gate).
- `bash scripts/test-shim.sh` → **46 passed, 0 failed**. `shellcheck -S warning scripts/*.sh` → zero warnings. `bash scripts/spec-gate.sh --check-only` → **7 passed, 0 failed**.
- python3: 51/51 shell deny-tails, 51/51 deny-first, DOCKER_HOST ×2, namespace tails as above, dead-MCP gate green.
- `bash scripts/seed-50-fleet.sh --dry-run` → **52 docs, total 1300000 == cap 1300000, empty stderr**; non-regular kubeconfig → exit 1.
- `docker compose config` exit 0: default, core+ci, devsec+core, web-research+core, mobile+core, proxy+tailscale. `bash scripts/dispatch-pipeline.sh --dry-run` → exit 0, corrected wording.
- `git status --short` → only intended files (7 Stage-2 edits + Stage-1 carryover + 2 doc files); no `:latest` code pins, no secrets, no TODO.

## Self-audit notes (Wave E Stage 2)

- Fail-closed kept: 4/7 edits comments-only; claim fixes point at the honest implementation; the one new gate fails closed on drift. No `|| true`/TODO/dummy/empty-catch added; deny tails preserved; no floating tags; scripts keep `set -euo pipefail` + `--dry-run`/`--help`.
- Tracked residuals (not blocking): argv-aware exec, per-namespace MCP denies for six namespaces, piston move + secret front, DATABASE_URL password-file, GO-key opt-in, Domain 11 prompt table beyond socket-proxy, all live-stack gates (`HARNESS_LIVE_GATE=1`, canary, scrub, `.env` negative).
- No commits, no merges, no subagents used.

---

# Wave E Stage 3 Remediation Log — P1 Supply-Chain & Wiring (P1-9 through P1-15)

**Worktree:** `/tmp/opencode/heretek-wave-e` (branch `wave-e-audit-remediation`)
**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md` lines 99-132
**Status:** all P1-9…P1-15 closed or verified-present, tests re-proven empirically.
Changes left UNCOMMITTED for QA/Drift-Guard. No proof contradicted the audit;
the dirty-archive probe confirmed the reported litter class on the old path
(staging-fail cleanup existed, remove-fail litter did not) and the fix closes it.
No stoppage needed (no product decision blocked progress).

## P1-9: seeder verified + prompt sync + live rerun SKIP → prompt, smoke §4

- Verified (python JSON parse of dry-run with provisioned dummies): `ROLE_LIST`
  = 51, 52 docs (1 company + 51), skip-false ×51, XDG ×51, heartbeats
  49×(false,0) + exec-director (true,1800) + tpm-scrum-lead (true,3600),
  budget 1300000¢ == cap, empty stderr.
- **Fixed** prompt Claims 5.1 (seed-50-fleet.sh only — seed-company.sh deleted
  Wave 3 P1-11), 5.2 (51 roles), 5.3 (1,300,000¢/$13,000), 5.4 (49 of 51).
- **Added** smoke §4 live rerun-diff SKIP (seed twice against `make up`,
  assert rerun creates 0 agents).

## P1-10: archive litter + collision → worktree-manager.sh, prompt, smoke §5b

- `cmd_archive`: same-second rerun diverts to `-<ts>-$RANDOM` (second
  collision aborts); evidence stages to `.tmp-<ticket>-<ts>-$RANDOM` and is
  `mv`-renamed into place only after `git worktree remove` succeeds; a
  failed remove deletes the staged temp (no orphan archive dir).
- Branch stays `ticket-<id>` dash; removal never `--force`; branch retained.
- **Fixed** prompt Claims 6.1 (dash) / 6.2 (temp-stage + RANDOM, "force-removing"
  dropped). **Added** two smoke gates (RANDOM+temp-stage; dash + no-`--force`).
- Probes: `../evil` → exit 2; clean archive → 4-file evidence, temp gone,
  branch retained; dirty archive → exit 1, worktree/branch/dirty-file intact,
  zero litter; re-archive → success; all artifacts cleaned.

## P1-11: Claim 3.1 code-not-in-repo → verified present (no change)

- Dockerfile `PAPERCLIP_SOURCE_COMMIT` placeholder + rev-parse procedure,
  NOTES.md Wave D procedure + canary requirement, AGENTS.md §1
  config-advice/live-unverified label, smoke §10b canary SKIP. No invention.

## P1-12: root-build + gosu + mutable base → verified + plan comment

- `USER root` only (deliberate volume repair), inherited `gosu node`
  (UID 1000, smoke §8 doc + live `id -u` gate), `/roles` 755 + `:ro`,
  `PAPERCLIP_BASE_IMAGE` digest-pin plan in compose. **Added** explicit
  `read_only:true` + tmpfs tracked-plan wording (comment only).

## P1-13: hound/piston/minio → verified present (no bumps)

- Hound digest + vendor/migrate decision; piston exact digest (latest-only
  upstream, no `:latest` used) + self-vendoring DECISION-NEEDED + release
  steps; minio exact RELEASE + digest-PENDING + 2026.x/localstack note.

## P1-14: seven dead wirings → catalog §4.3 + mlops charter fix (docs only)

- Smoke allowlist green (7 = ollama, prometheus×2, redis, kafka, clickhouse,
  k6; docker blocks left in Wave D P1-6). No declarations added/deleted.
- **Fixed** stale mlops docker note → active read-only-observer (mirrors k8s,
  Stage 2 fixed only k8s). **Added** catalog §4.3 table (the "catalog §3
  notes" the smoke comment cited did not exist).

## P1-15: unpinned MCP + drift → verified clean (no change)

- Zero live `@morluto/rea-mcp` (historical prose only); all npx `pkg@ver` +
  uvx `pkg==ver` (gate green); fork-vs-canonical in smoke header (all ==
  live latest); zero `:latest` code pins (prose hits only, gate-covered).

## Test results (must-keep-green set + Stage 3 proofs)

- `bash scripts/smoke-test.sh --check-only` → **529 passed, 0 failed,
  6 skipped** (527 baseline + 2 P1-10 gates + 1 P1-9 SKIP, zero regressions).
- `bash scripts/test-shim.sh` → **46 passed, 0 failed**; `shellcheck`
  zero warnings; `bash scripts/spec-gate.sh --check-only` → **7/7**.
- Seed dry-run → 52 docs, total == cap, empty stderr. Compose configs exit 0
  (default, core+ci, prebuilt). Worktree probes above, artifacts cleaned.
- Sweeps: no `:latest` code pins, no secrets, no TODO/dummy/`|| true` added.

## Files changed (uncommitted, Stage 3 only)

- `scripts/worktree-manager.sh` (P1-10), `scripts/smoke-test.sh` (§4 SKIP,
  §5b gates), `PROMPT_ADVERSARIAL_FLEET_AUDIT.md` (5.x + 6.x claims),
  `roles/mlops-serving-eng/AGENTS.md` (P1-14), `roles-catalog/ROLE_CATALOG_50.md`
  (§4.3), `docker-compose.yml` (P1-12 comment), `docs/reports/wave-e-stage3-implementation.md`
  (new), `REMEDIATION_LOG.md` (this entry).

## Self-audit notes (Stage 3)

- Fail-closed kept: archive aborts on double-collision/staging-fail/
  remove-fail; claim fixes point at honest implementation; new gates fail on
  drift; live probes stay SKIPs. No `|| true`/TODO/dummy added; deny tails,
  pins, ports, networks untouched; scripts keep `set -euo pipefail` +
  `--dry-run`/`--help`.
- Tracked residuals (not blocking): live rerun diff, piston move + front,
  password-file, hound/piston/minio vendoring, dead-MCP build-vs-delete,
  Domain 11 table beyond socket-proxy, all live-stack gates.
- No commits, no merges, no subagents used.

---

# Wave E Stage 4 Remediation Log — P2 Medium + P3 Low (P2-1…P2-16, P3-1…P3-10)

**Worktree:** `/tmp/opencode/heretek-wave-e` (branch `wave-e-audit-remediation`)
**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md` lines 135-168 (cleared lines 171-178 not re-filed)
**Status:** all P2/P3 closed or verified-present, tests re-proven empirically.
Changes left UNCOMMITTED for QA/Drift-Guard. No proof contradicted the audit;
the TDD red run confirmed 4 of the 8 new P2-1 probes failed pre-fix (8i,
2× whitespace, dir-126) while 4 passed as behavior pins (8h/8j/8k/8l).
No stoppage needed (network available — every digest resolved live via
registry Docker-Content-Digest headers, nothing invented offline).

## P2-1: shim variant edges → code + 8 tests (TDD red 50/4 → green 54/0)

- `scripts/opencode-shim.sh`: empty `--variant=` no longer clobbers a prior
  non-empty variant; header rule-2 documents the normalized dash-leading
  rule (space-form = flag boundary, `=`-form = explicit value, merges);
  `resolve_real_bin` requires `-f` + `-x` on all three paths (dir → 127);
  whitespace-only API/GO keys count as empty both sides.
- `scripts/test-shim.sh` 46 → 54 (§8h/8i/8j/8k/8l, §20b dir-127, §20
  whitespace ×2). `shellcheck` clean.

## P2-3/P2-5/P2-6/P2-8/P2-9: live-resolved tag@digest pins (no invention)

- postgres `17.11-alpine@sha256:b0f956…` (17-alpine ≡ 17.11-alpine, zero
  change) + Dockerfile comment; ghidra `12.1.4@sha256:b24791…` (ordered
  major bump, wrong "one minor" comment fixed, dual :1337/pgrep probe);
  mitmproxy `11.0.2@sha256:92ab9e…` + 12.x plan (`12.2.3` live);
  firecrawl `2.10.19@sha256:50446c…` + plan; act
  `act-22.04@sha256:f5f5c2…` + 24.04 plan (`act-24.04` digest recorded).
  Mailpit (`v1.31.6`) / wiremock (`3.13.2-alpine`) stay quarterly comments.
- Smoke: 5 digest asserts + 5 predecessor-absence asserts (image-lines
  only — provenance comments exempt).

## P2-10/P2-12/P2-14: new automated gates (all fail-closed / SKIP, never fake-pass)

- P2-10 budget-matrix gate (per-service caps asserted, per-profile
  expected totals + full 32.6 CPU pinned, drift prints recomputed values).
- P2-12 `§8b` backup→restore round-trip (`BACKUP_ROUNDTRIP_LIVE=1`
  opt-in, `--file`+`--yes` CLI path, scratch dir) + check-only SKIP.
- P2-14 workflow static gate (translation + plugin-load + arm64 steps).
- P3-8 `.gitkeep` tracked gate.

## P2-2/P2-4/P2-11/P2-13/P2-16 + P3-3…P3-10: verified present, changed only to add

- Valueless-`--dir` preservation, Paperclip SHA procedure, android 4/8g +
  dual probe, prebuilt semver + no-latest + HERETEK_IMAGE constraint,
  publish fixture/plugin-load/arm64 gates, seed fetch-once + ROLE_DIR
  double guard, rabbitmq env creds, Caddyfile plan, DOCKER_HOST ×2,
  sabotage piston advisory, device+inode fallback, signing `:?`,
  `--force` rationale — all re-proven. Added only: P3-1 nuq/playwright
  comments, P3-2 two no-op `true` healthchecks, P2-15 redis-7.4-LTS
  decision + neo4j-OOM + gotenberg-logs notes.
- `SUPPORTING_SERVICES.md`: mirrored pins synced, watchlist rewritten
  with `[RESOLVED]` markers + verified-live quarterly targets.
- `AGENTS.md`: suite count 46→54 (two spots).

## Test results (must-keep-green set + Stage 4 proofs)

- `bash scripts/test-shim.sh` → **54 passed, 0 failed**; `bash
  scripts/smoke-test.sh --check-only` → **542 passed, 0 failed,
  7 skipped** (529 + 13 new gates, zero regressions); `shellcheck`
  zero warnings; `bash scripts/spec-gate.sh --check-only` → **7/7**.
- Seed dry-run → 52 docs, total == cap, empty stderr. Compose configs
  exit 0 (default, prebuilt, web-research, devsec, devsec+core, mobile,
  core+ci, qa-testing+core, proxy+tailscale); all 5 tag@digest pins render.
- Sweeps: no `:latest` code pins, no secrets, no TODO/dummy/`|| true` added.

## Files changed (uncommitted, Stage 4 only)

- `scripts/opencode-shim.sh`, `scripts/test-shim.sh` (P2-1),
  `scripts/smoke-test.sh` (pins, budget, round-trip, publish, gitkeep gates)
- `docker-compose.yml` (P2-3), `docker-compose.sidecars.yml` (P2-5/6/7/8/9/15,
  P3-1/2), `docker/Dockerfile` (P2-3 comment), `SUPPORTING_SERVICES.md`
  (mirrors + watchlist), `AGENTS.md` (counts),
  `docs/reports/wave-e-stage4-implementation.md` (new), `REMEDIATION_LOG.md`
  (this entry).

## Self-audit notes (Stage 4)

- Fail-closed kept: variant/keys/binary-resolution fixes err loud, never
  silent; digests enforce while tags document; gates fail on drift, live
  work stays opt-in SKIPs. No `|| true`/TODO/dummy added; deny tails,
  ports, networks, permissions, workflows untouched; scripts keep
  `set -euo pipefail` + `--dry-run`/`--help`.
- Tracked residuals (not blocking): ghidra-:1337/mitmproxy-12/act-24.04/
  mailpit/wiremock live-boot verifications, piston move + front,
  password-file, hound/piston/minio vendoring, dead-MCP build-vs-delete,
  full round-trip + harness + canary + scrub live runs (all need `make up`).
- No commits, no merges, no subagents used.

---

# Audit Remediation Pass — P0 + P1 (+P2/P3) (branch `fix/audit-remediation-p0-p1`)

**Date:** 2026-10-17 | **Source of truth:** `AUDIT_REPORT_FINDINGS.md` (superseding 13:05 report)
**Scope:** P0-1..P0-9, P1-1..P1-15, P2-1/2/4/5/6/7/8/10/11/13/14, P3-1/2/4/5.
Deferred-by-design (log-only, no code change): P1-2, P1-4, P1-7, P1-11/12/13 (topology),
P1-14, P2-3/9/15/16, P2-14, P3-5/6/7/8/10/11/12, P0-2/3/4/6 (upstream/design-blocked).
**Status:** implemented + statically verified. Changes UNCOMMITTED for QA/Drift-Guard.

## P0 — Critical

### P0-1 Shim `--dir` preserve injects workspace path (FIXED)
- Files: `scripts/opencode-shim.sh:22-33` (rule-1 comment), `:201-214` (consume iff absolute on-disk dir); `scripts/test-shim.sh` §3/§5/§5a/§5b/§5c/§15a0; `scripts/smoke-test.sh` §5 (consume + preserve cases, header comment).
- Proof: `OPENCODE_REAL_BIN=/tmp/rec.sh bash scripts/opencode-shim.sh run --format json --dir /tmp/ws --model opencode/gemini --variant high "hello"` (with `/tmp/ws` existing) → `run --format json --model opencode/gemini#high --auto hello` — NO stray `/tmp/ws`. Non-existent/relative/non-dir tokens still preserved (fail-closed toward prompt preservation).
- Tests: `bash scripts/test-shim.sh` → **57 passed, 0 failed** (54 + 3 new P0-1 cases); smoke §5 asserts both consume and preserve paths.

### P0-2 Harness 1.0.7 `rootDir must be non-empty` (UPSTREAM-BLOCKED, logged)
- No pin change: bumping without a fixed successor would float the fleet onto an unverified single-vendor release (5 versions in 22h). Treats all `harness_*` allows as dead config until upstream ships `pick()`-fixed successor; then bump pin + re-run live tool-visibility gate (§10b). Blocker entry recorded here, not claimed fixed.

### P0-3 DATABASE_URL survival unproven (LIVE-CANARY-BLOCKED, static gates kept)
- Sanitize layer EXISTS (correct citations `execute.ts:55-65`, `server-utils.ts:3513-3531`); `DATABASE_URL`/provider keys NOT in either block-list → survival unproven. Static in-repo gates (seed `adapterConfig.env` allowlist assert, §10b skip) unchanged and green. Live canary command added to smoke §4 comment: in a live agent turn `printenv | grep -c DATABASE_URL` MUST be `0`; if ≥1, scrub server env + rotate secrets. Needs `make up` + seeded fleet.

### P0-4 dangerouslySkipPermissions default TRUE (UPSTREAM-BLOCKED, logged)
- Correct lines `runtime-config.ts:110,153,207`. Seeded agents carry `False` (smoke asserts zero `True` remains); any UI/API-created agent without the flag gets full allow. Fix belongs upstream (flip default to `false`); in-repo action: forbid manual creation, audit `list-agents | jq '.[] | select(.adapterConfig.dangerouslySkipPermissions != false)'`. Needs live stack.

### P0-5 Prefix-match shell allows bypassable (DESIGN-ACCEPTED, static gates kept)
- `fnmatch` triple-True confirmed by audit; enforcer semantics unpinned upstream. Static gates already present and green: §3b negative prefix-chain probes (reference matcher denies `git status; id`, `npm test && id`, `curl -s http://x; id`; every shell allow verified single-command prefix) + AGENTS.md §4 advisory-only note. Live probes (`git status; id`, `git status$(id)`, `git status||id`, `npm test -- --unknown-flag` through an agent turn) still required — need `make up`.

### P0-6 Piston shared-net unauth RCE (DESIGN-BLOCKED, logged)
- No topology break: `:2000` expose-only on shared net with exact-host advisory curl pins. Structural fix (shared-secret sidecar proxy on isolated net, profile-gating, never co-schedule qa/devsec with untrusted) is a product/hardening decision requiring live reachability verification — recorded here, not claimed fixed.

### P0-7 android-mobile-spec MCP typo (FIXED)
- `roles/android-mobile-spec/opencode/opencode.json:297` `@mobile-next/mobile-mcp@0.1.2` → `@mobilenext/mobile-mcp@1.0.11` (`npm view` → `1.0.11`; old scope E404). Synced `AGENTS.md:33,53`, `README.md:270`, `roles-catalog/04_specialized_language_engineers.md:905`, `ROLE_CATALOG_50.md:93`.
- Proof: `grep -rn "mobile-next" roles/` → clean (only historical `AUDIT_REPORT_FINDINGS.md` + scaffold prompt retain the old string intentionally); `python3 -c json.load` valid.

### P0-8 Five dead MCP backends (FIXED via deletion, P2-8)
- Deleted dead server blocks + tool allows (no unpinned replacement services invented): `analytics-metrics-eng` (clickhouse + `clickhouse_*`), `cache-streaming-eng` (redis + kafka + `redis_*`/`kafka_*`; servers now `{}`), `mlops-serving-eng` (ollama + `ollama_*`; docker MCP kept), `observability-eng` + `sre-incident-eng` (prometheus + `prometheus_*` each). Per-role `AGENTS.md` §4 notes rewritten from infra-pending to REMOVED. Residual fs path scopes (`migrations/clickhouse/**`, `deploy/kafka/**`, `deploy/prometheus/**`) kept — harmless directory scopes, no live backend. Smoke dead-MCP allowlist now pins only `("load-stress-tester","k6")`.
- Proof: `grep -rn "CLICKHOUSE_URL|KAFKA_BROKERS|OLLAMA_HOST|PROMETHEUS_URL|clickhouse_*|kafka_*|ollama_*|prometheus_*|redis_*" roles/*/opencode/opencode.json` → zero hits; 51/51 JSON valid; deny tails intact.

### P0-9 35 roles hold mutating harness allows (FIXED fleet-wide)
- Flipped `harness_file_hash_edit` / `harness_ast_structural_rewrite` / `harness_rename_symbol` / `harness_checkpoint_rollback` from allow→deny in all 35 residual roles (exact-block replace, formatting preserved), mirroring the exec-director deny pattern. Read-only tool allows + `harness_*` deny tails untouched.
- Proof: per-role loop → **0 roles with allow / 51 roles with deny** (was 35/16); 51/51 JSON valid; shell deny-tail last in 51/51.
- Smoke §3b gates rewritten to the remediated expectation (prior gates encoded the vulnerable 14-tool state): manifest gate now requires the 10-tool read-only manifest + 4 explicit mutating denies + `harness_*` tail in ALL 51 plugin roles; mutating ban is fleet-wide while the fs:write-confinement drift pin stays at its 16-role set (`FS_READONLY_ROLES`). Both gates PASS.

## P1 — High

- **P1-1 Firecrawl `/health` 404 (FIXED):** `sidecars:241` → `wget -qO- http://127.0.0.1:3002/e2e-test || exit 1` (upstream routes `/`, `/v0/health/*`, `/e2e-test`; no `/health`).
- **P1-2 Prebuilt `:1.0.0` unpublished (HUMAN ACTION, no code change):** needs `git tag v1.0.0 && git push origin v1.0.0` by a human with push rights + digest replacement. Not publishable from here.
- **P1-3 socket-proxy 2y stale (FIXED):** `:0.3.0` → `:0.5.0` (Hub tag verified live 2026-10-17; env contract CONTAINERS/IMAGES/INFO/VERSION/POST/BUILD/EXEC/VOLUMES/NETWORKS/AUTH unchanged). Re-run GET-only deny probe on first core-profile boot.
- **P1-4 MinIO undeployable (BLOCKED, pin kept):** `quay.io/minio/minio:RELEASE.2024-11-07…` retained exact (quay anonymous manifest 401, no credentials in env — digest unresolvable from here). Replacement plan: evaluate `localstack/localstack:<tag>@sha256:<digest>` at the next bump cycle (AGPL exit included); do NOT swap blind without a resolved digest.
- **P1-5 Paperclip base unreproducible (FIXED):** `docker/Dockerfile:21` placeholder → `PAPERCLIP_SOURCE_COMMIT=73659c6b27c1d97226f2da9ca39f256eefddac66` (verified `git -C /tmp/paperclip rev-parse HEAD` → same). Smoke asserts 40-hex recorded + placeholder absent (PASS).
- **P1-6 Hound archived rationale false (FIXED):** `etsy/hound` RENAMED to `hound-search/hound` (`archived: false`, pushed 2026-09-10) — corrected in `SUPPORTING_SERVICES.md` tracked-decision note + `sidecars:446-460` comment. Migration to livegrep/zoekt stays OPTIONAL quarterly.
- **P1-7 Piston digest-of-latest (VENDOR NOTE, no blind bump):** upstream publishes only `latest`; in-repo pin is digest-of-latest `sha256:2f66…` (no `:latest` tag used — policy-compliant). Vendor plan stands: maintainer builds piston from a pinned release tag, pushes `ghcr.io/heretek-ai/piston:<semver>`, replaces digest after `docker manifest inspect`. Needs network + push rights; not doable from here.
- **P1-8 Ghidra :1337 / Radare2 :9090 unauth (GUARD COMMENT, no topology break):** added P1-8 guard block at Category C header (expose-only, isolated `heretek-devsec`, no untrusted co-scheduling until shared-secret proxy). Secret-proxy fronting is the tracked structural plan.
- **P1-9 harness_* wildcard order (VERIFIED, no change needed):** post-P0-9, all harness entries fleet-wide are read-allows + denies (same-effect denies: wildcard-before-specifics in the 16 original deny roles; specifics-before-wildcard in the 35 flipped roles). No allow is shadowed under either first-match or deny-override semantics — the §3b manifest gate (10 allows + 4 denies + tail, 51/51 PASS) pins this.
- **P1-10 threat-modeler over-broad (FIXED, minimal diff):** dropped `fs:write deploy/security/**` (threat models stay under `docs/security/threat-models/**`); `github_*` allow → `github_get_*` + `github_search_*` + `github_list_*` allows + `github_*` deny (server is `@modelcontextprotocol/server-github@2025.4.8`). Shell deny-tail preserved; `AGENTS.md` write-confinement step synced. Compliance-auditor `github_*` noted but untouched (minimal diff per scope).
- **P1-11 Caddy 0.0.0.0:80/443 (COMMENT, no topology change):** extended `docker-compose.yml` exposure note with the compose-level `test $EXPOSURE = private && exec caddy…` plan — deferred (caddy has no shell entrypoint hook without an image change); `make proxy-up` guard + note stay the gate.
- **P1-12 Superuser DATABASE_URL inspect-readable (COMMENT, no topology change):** password-file/secret plan already documented at `docker-compose.yml:104-112` (URL assembled from fail-closed `:?` guards; agent access via `POSTGRES_READONLY_URL` only; seed payloads asserted key-free). Rotation to Docker secrets stays tracked.
- **P1-13 GET-recon open whole net (COMMENT, no topology change):** dedicated `heretek-ci` net / source-allowlist plan already documented at `sidecars:531-536` (live network move deferred pending `make up` reachability verification). POST/BUILD/EXEC=0 posture untouched.
- **P1-14 Offensive shell allows (NOTE, no broad removal):** installer/offensive-harness allows (garak/pyrit/promptfoo, npm/cargo/go, piston curl) are role-essential surfaces — removing them breaks the roles. Remediation is approval-gated installs + ephemeral sandboxes at runtime (tracked); npm ci-only migration owned by dependency-patcher on the quarterly cycle.
- **P1-15 restore-db.sh `--file` mismatch (FIXED):** arg loop converted `for`→`while` with `shift`; accepts `--file path` (missing/flag value → exit 2) alongside `--file=*`. Proof: `--file backups/x.sql.gz` → exit 1 file-gate (`dump file not found`), NOT parse exit 2; bare `--file` → exit 2; `--bogus` → exit 2. Smoke §5b asserts both (PASS).

## P2 / P3

- **P2-1 stale budget comment (FIXED):** `seed-50-fleet.sh:337` → `Sum = 1300000 cents ($13,000.00 USD)` (matches `:45/:99/:113` + dry-run `total 1300000 == cap`).
- **P2-2 dispatch-pipeline no ticket validation (FIXED):** `require_ticket_id` (`^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$`, mirrors worktree-manager.sh:39-45) enforced post-parse. Proof: `../evil`, `/tmp/wt-abs` → exit 2; `tkt-123` + default timestamp id → exit 0.
- **P2-3 unverified probes (DEFERRED):** first-boot `docker ps/logs` verification needs `make up`; no blind bumps from here.
- **P2-4 searxng (BUMPED, verified):** digest `13de…` (tag 2025.12.19) → `sha256:79180616…` (tag `2026.10.17-2a6fc07be`, newest Hub tag, skopeo-resolved live).
- **P2-5 firecrawl 2.11 (SKIPPED, blocker):** GHCR tags list contains NO `2.11*` (latest `2.10.x`) — nothing verified to bump to; pin stays `2.10.19@5044…`.
- **P2-6 browserless + litellm (BUMPED, verified):** `ghcr.io/browserless/chromium:v2.24.2` → `v2.26.0@sha256:8990…` (tag verified in GHCR list incl. v2.26.1; digest skopeo-resolved); `ghcr.io/berriai/litellm@eb14…` (main-v1.54.0) → `:main-v1.60.0@sha256:56ad…` (tag in GHCR list; digest skopeo-resolved). **mitmproxy NOT bumped:** 11.0.2→12.x is a major-proxy behavior change gated on the quarterly cycle + first-boot healthcheck re-verify (needs `make up`); file rationale stands.
- **P2-7 phantom wirings (FIXED in docs):** `docker/` ships only `Dockerfile` — deleted 4 phantom volume lines from `SUPPORTING_SERVICES.md` blocks (searxng `settings.yml`, hound `config.json`, wiremock `mappings/`, litellm `config.yaml`) with P2-7 removal notes + real-impact annotations (limiter/formats, repo-index, runtime `__admin/mappings`, DB-stored models); crawl4ai block marked STATUS specified-but-NOT-composed (served by firecrawl). Decision: delete-doc-block over vendor+mount (vendoring unreviewed configs invents behavior). §11 mirrored excerpts untouched (explicitly illustrative per authoritative-source note).
- **P2-8 dead MCP envs (FIXED — see P0-8).** Per-role choice logged: delete dead env refs + allows (no services invented). `load-stress-tester/k6` kept (CLI tool, not a dead backend).
- **P2-9 jaeger v2 env (DEFERRED):** `COLLECTOR_OTLP_ENABLED` harmless-if-ignored; needs first-boot `docker logs jaeger` (needs `make up`).
- **P2-10 playwright (FIXED):** `firecrawl-playwright` `MAX_CONCURRENT_PAGES` 10→5 + `shm_size: 1gb` (key already used by browserless — valid).
- **P2-11 mocks lag (SKIPPED per quarterly plan):** mailpit v1.21.8 / wiremock 3.10.0-alpine bumps stay on the dependency-patcher quarterly cycle (file comments); mitmproxy first is blocked by the P2-6 major-bump rationale above.
- **P2-12 XDG provenance (FIXED static part):** Dockerfile commit recorded (P1-5) + 40-hex smoke assert; `printenv` canary stays live-gated (P0-3).
- **P2-13 backup plaintext default (FIXED fail-closed):** `backup-db.sh` requires `BACKUP_AGE_RECIPIENT` unless `--plaintext-ok` / `BACKUP_PLAINTEXT_OK=1` (gate before any dump bytes; CLI opt-in is OR-logic so it can never weaken a `.env` recipient). `.env.example` documents both knobs (commented placeholders, no secrets). Smoke §5b asserts refusal (exit 1 + message) and opt-in pass-through; live round-trip passes `--plaintext-ok` explicitly.
- **P2-14 fs:read `**` (ACCEPTED RISK, no mass change):** scoping 51 `fs:read **` allows to per-role dirs would break cross-role reads (catalog/codebase navigation) with no live enforcement matrix to validate against; secret paths stay deny-first (smoke §3b deny-first gate green under both semantics). Revisit with the live allow/deny matrix.
- **P2-15 firecrawl USE_DB_AUTH=false (KEEP, documented):** loopback-only `:3002` binding contains it; flipping needs a firecrawl user/secret bootstrap that does not exist upstream (would fail closed at boot). Smoke §3a pins the loopback publish.
- **P2-16 privileged android + tailscale caps (KEEP):** profile-gated (`mobile`/`tailscale`, never default) + Makefile co-scheduling guard — accepted, no change.
- **P3-1 backup .env wording (SYNCED):** header step 1 now names every consumed key; sourcing site carries the P3-1 restricted-parser note.
- **P3-2 NOTES counts (FIXED):** `46/46` → `57/57` (54 audit-era + 3 new P0-1 cases; verified `test-shim.sh` tail).
- **P3-3 grep count artifact:** §3a/§3b counts are exact-match pins with drift-fail semantics (fail-closed on change), not brittle artifacts — kept.
- **P3-4 gotenberg (BUMPED, verified):** `8.37.0` → `8.38.1` (Hub tag verified live).
- **P3-5 node:24 minor float (LOG ONLY):** digest unknown offline — resolving `node:24.x-trixie-slim@sha256:` needs skopeo against the build host's arch matrix at build time; recorded for the Dockerfile owner, no invented digest.
- **P3-6 redis 7.4 LTS / P3-7 act-22.04 EOL-2027 / P3-8 android pin / P3-9 dba GRANT shape / P3-10 loopback mocks / P3-11 mitmproxy block_global / P3-12 rootless `id -u==1000`:** no change per audit (deliberate/calendar/live-gated); live items need `make build` + `make up`.

## Verification (this pass)

- `bash scripts/test-shim.sh` → **57 passed, 0 failed**.
- `bash scripts/smoke-test.sh --check-only` → **555 passed, 0 failed** (exit 0; skips are live-gated).
- `shellcheck scripts/*.sh` → zero NEW warnings (3 pre-existing SC2016 infos in smoke-test.sh, identical on clean tree via stash comparison).
- `POSTGRES_READONLY_URL=… GITHUB_TOKEN=… KUBECONFIG_READONLY_PATH=… bash scripts/seed-50-fleet.sh --dry-run` → exit 0, 52 payloads, `total 1300000 == cap`, empty stderr.
- `python3 json.load` over all 51 edited `opencode.json` → valid; shell deny-tail last in 51/51.
- `docker compose config` (dummy secrets): merged + `core+ci`, `core+qa-testing`, `web-research+devsec`, `proxy`, `tailscale` profiles → exit 0. Single `--profile qa-testing`/`ci` fail on `local-ci-runner → docker-socket-proxy` dependency — PRE-EXISTING (clean tree identical; documented invocation always pairs `core`).
- `make test` (full smoke, stack down) → 548 passed, 3 failed, 4 skipped — the 3 failures are live-only (`postgres not healthy`, `paperclip not running`, `:3100` unreachable; no `make up` in this env), unrelated to this diff.
- Registry proofs (live 2026-10-17): `npm view @mobilenext/mobile-mcp version` → `1.0.11`; GHCR tag lists (firecrawl: no 2.11; browserless: v2.26.0+v2.26.1; litellm: main-v1.60.0); `skopeo inspect` digests for searxng/browserless/litellm/gotenberg/socket-proxy-0.5.0; Hub `gotenberg:8.38.1` count=9, `mitmproxy:12.2.3` exists (deliberately not taken), `tecnativa/docker-socket-proxy:0.5.0` count=1.

## Product decisions requiring human call (explicit)

1. Piston vendoring (`ghcr.io/heretek-ai/piston:<semver>`) + `:2000` secret-proxy fronting (P0-6/P1-7).
2. MinIO→localstack replacement incl. AGPL exit (P1-4).
3. Publishing `ghcr.io/heretek-ai/heretek-crew:1.0.0` (`git tag v1.0.0 && git push`, P1-2).
4. Upstream fixes: harness `pick()` successor pin (P0-2), `dangerouslySkipPermissions` default false (P0-4), shell-enforcer argv semantics + live matrix (P0-5), child-env scrub block-list (P0-3).
5. Live runs needing `make up`: XDG/canary, harness visibility, UID==1000, jaeger/playwright/radare2/hound/ghidra first-boot probes, round-trip, 4 prefix-bypass probes.
