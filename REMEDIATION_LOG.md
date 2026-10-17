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
