# Wave D Implementation Report — Final Remediation (P0-1, P0-3, P1-1, P1-5, P1-6, P1-8, P2-5–P2-9, P3-1–P3-5)

**Stage ID:** Wave D (final) — `AUDIT_REPORT_FINDINGS.md` P0-1/P0-3, P1-1/P1-5/P1-6/P1-8, P2-5/P2-6/P2-7/P2-8/P2-9, P3-1/P3-2/P3-3/P3-4/P3-5
**Date:** 2026-10-17 | **Branch state:** uncommitted on `main` (base clean at Wave C `d7c7aca`)
**Source of truth:** `AUDIT_REPORT_FINDINGS.md` + task envelope (TARGETS + ACCEPTANCE verbatim)
**Status:** complete, verified empirically. Changes left UNCOMMITTED for QA/Drift-Guard. No commits, no merges, no subagents used.

## 1. Summary of deliverables

- **P0-1 (harness rootDir kill):** documented, NOT invented. Upstream one-spot
  `pick()` diff + bump plan recorded in `docker/Dockerfile` (pin comment)
  and `NOTES.md` (Wave D log); pin stays exact `1.0.7` (no float); Domain 4
  primitives labeled load-broken, never working. New live-only gate
  (`smoke-test.sh` §10b, `HARNESS_LIVE_GATE=1`): stages the new probe
  fixture `scripts/fixtures/harness-probe-opencode.json` as XDG config,
  runs one real `opencode run` turn invoking `file_hash_read`, FAILs on
  the `rootDir must be` Die / `not available` signature, SKIPs (never
  fake-passes) without the flag, binary, or model auth. Check-only mode
  records two documented SKIP notes (P0-1 probe + P1-8 canary steps).
- **P0-3 (shared UID/filesystem):** (a) kubeconfig bind kept `:ro`
  (k8s-orchestrator unbroken) + move-to-MCP-env structural plan recorded
  in `docker-compose.yml`; (b) seed-payload env allowlist gate (smoke §4:
  `DATABASE_URL`/`POSTGRES_PASSWORD`/`BETTER_AUTH_SECRET`/all provider
  keys must never appear in dry-run payloads — green); upstream
  inheritance scrub labeled live-unverified (canary note); (c) four
  secret-material `fs:read` denies (`**/secrets/**`, `**/kubeconfig*`,
  `**/*.pem`, `**/id_rsa*`) added ahead of every allow in all 51 roles
  via `generate-50-roles.py` `FS_READ_ENV_DENIES` + scratch-regen
  promotion (byte-verified: disk == generator output, zero drift) +
  fleet-wide smoke presence gate.
- **P1-1/P3-2 (shell advisory + adb/piston scoping):** bare
  `adb connect*` replaced with the loopback + in-compose allowlist
  (`127.0.0.1*`, `localhost*`, `docker-android*`) in catalog fence +
  disk + charter note; sabotage piston `curl` pins kept exact-host +
  advisory-only note in charter; `AGENTS.md` §4 records enforcer identity
  + version (`@opencode/cli@2.0.32` + Paperclip `opencode-local`,
  `/tmp/paperclip`) with live-probe steps
  (`git status; id`, `$(id)`, `||id`, `npm test -- --unknown-flag`).
  Smoke adb gate fails on any bare `adb connect*` fleet-wide.
- **P1-5 (unauthenticated RCE services):** `POST/BUILD/EXEC=0` never
  weakened (gate green). Fronting plan (shared-secret proxy / per-request
  tokens into needing roles only) recorded per-service in
  `docker-compose.sidecars.yml` + `SUPPORTING_SERVICES.md` §12.7 with the
  honest residual: segmentation contains sidecar-initiated movement, NOT
  agent-initiated (paperclip-as-bridge by design). Firecrawl keeps
  `USE_DB_AUTHENTICATION=false` ONLY under the loopback `:3002` publish
  (smoke asserts `127.0.0.1:3002:3002`, no all-interfaces) with the
  `=true`+secret hardening path documented in-file.
- **P1-6/P3-5 (Domain 8 + DOCKER_HOST):** stale "permits container
  creation" claims corrected to read-only-observer in both
  `SUPPORTING_SERVICES.md` mirrored blocks (env now
  `POST/BUILD/EXEC/AUTH=0`); `expose:2375` GET-recon recorded as accepted
  risk; `k8s-orchestrator` + `mlops-serving-eng` docker MCP servers
  declare `DOCKER_HOST=tcp://docker-socket-proxy:2375` explicitly
  (catalog fences + disk via regen) with a smoke gate pinning the exact
  value and role set; dead-MCP allowlist shrinks 9→7. Dispatch phase-5
  verified already-correct (Wave B).
- **P1-8 (XDG enforcement unaudited):** Paperclip source-commit pin
  procedure recorded (`docker/Dockerfile` +
  `NOTES.md`); Claim 3.1 labeled config-advice, live-unverified
  (`AGENTS.md` invariant 1); canary live-test steps in the §10b SKIP note.
- **P2-5 (non-root unverifiable):** base-digest plan recorded
  (source-commit pin, digest constraint if the base ever moves to a
  registry); live boot assertion added (smoke §8: `docker compose exec
  paperclip id -u` == 1000, distinguishing not-running from wrong-user);
  `--force` kept with an explicit pinned-set rationale comment.
- **P2-6 (proxy honor-system):** `make proxy-up` + `guard-proxy` refuse
  `--profile proxy` unless `PAPERCLIP_DEPLOYMENT_EXPOSURE=private` AND
  `BETTER_AUTH_SECRET` is real (verified refusals: unset/public/
  placeholder; verified pass: private+real). Compose exposure note,
  `.env.example` header, `AGENTS.md`, and a smoke presence gate all route
  to the guard — raw `docker compose --profile proxy up` is documented
  as bypass, never used.
- **P2-7 (secret residuals):** (1) password-file/Docker-secret plan +
  READONLY-only payload gate (same §4 gate as P0-3b); (2) new tracked
  `workspaces/scratch/.gitkeep` (+ `.gitignore` negations so the
  placeholder is tracked while runtime outputs stay ignored — verified
  both directions); (3) `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET` fail-closed
  (`:-` → `:?`) + smoke render gate + dummy-env update.
- **P2-8 (versions/arch):** no blind bumps. Digest/minor plans recorded
  as comments (postgres `17.<x>`+digest, firecrawl digest+`#tag`,
  ghidra `:11.3+`+digest+`:1337` probe); hound host port remapped
  `6080`→`6081` (container `:6080` unchanged; android noVNC keeps host
  `:6080`; mirrored `SUPPORTING_SERVICES.md` blocks + overlap note
  updated; smoke block-scoped gate); rabbitmq `RABBITMQ_USER/PASSWORD`
  env-provided (`:?`, first-boot-only noted, `NUQ_RABBITMQ_URL` carries
  `user:pass`, `.env.example` entries, smoke auth gate) + 1g watchlist
  note; full quarterly watchlist (dual-redis split, gotenberg confirm,
  neo4j OOM, jaeger boot-verify, minio/localstack AGPL, wiremock/mailpit/
  act lags, sleep-infinity healthchecks) in `SUPPORTING_SERVICES.md` §1b.
- **P2-9 (seed perf + hazard):** Pass-1 fetches the agent list ONCE
  (refresh on miss + after create; steady state = 1 LIST); `ROLE_DIR`
  hazard guarded twice (ambient-env shell check + python env-chain
  `sys.argv` assert — probe with `ROLE_DIR=wrong-role` exits 1 with the
  descriptive error); smoke presence gate pins both.
- **P3-1 (shim recursion guard):** `stat -L -c '%d:%i'` device+inode
  fallback when `realpath` is absent (`-L` dereferences aliases —
  caught during test: bare `stat` reports the link itself); regression
  test 21 (realpath hidden via stripped `PATH`, `$BASH` spawn, symlink
  self-alias → exit 127 + message). `test-shim.sh` 46/46.
- **P3-3/P3-4:** rabbitmq guest retired (see P2-8); Caddyfile tracked as
  the optional auditable path (compose comment).

## 2. Files created/modified

- Created: `scripts/fixtures/harness-probe-opencode.json`,
  `workspaces/scratch/.gitkeep`, `docs/reports/wave-d-implementation.md` (this file).
- Modified: `docker/Dockerfile` (P0-1 diff+bump, P1-8 commit pin,
  `--force` rationale, UID-gate ref), `docker-compose.yml` (base-digest
  plan, password-file plan, kubeconfig MCP-env plan, signing `:?`,
  proxy-guard note, Caddyfile note, postgres minor plan),
  `docker-compose.sidecars.yml` (rabbitmq env auth + authed NUQ URL,
  firecrawl auth decision + digest plan, ghidra/r2/piston fronting
  plans, socket-proxy `:2375` residual, hound `:6081`),
  `scripts/seed-50-fleet.sh` (ROLE_DIR guard ×2, fetch-once),
  `scripts/smoke-test.sh` (header P0-1 note, §2 signing/proxy gates, §3a
  rabbitmq/firecrawl/hound gates, §3b secret-denies/adb/DOCKER_HOST/
  P2-9 gates, dead-MCP 9→7, §4 env-allowlist gate, §8 UID gate, §10b
  live gate + check-only SKIP notes),
  `scripts/opencode-shim.sh` + `scripts/test-shim.sh` (P3-1 + test 21),
  `scripts/generate-50-roles.py` (`FS_READ_ENV_DENIES` ×8),
  `roles-catalog/04…` (adb allowlist), `05…` + `08…` (DOCKER_HOST),
  51× `roles/*/opencode/opencode.json` (4 denies; +adb/+DOCKER_HOST
  where applicable — generator-promoted, zero drift),
  `roles/android-mobile-spec/AGENTS.md` + `roles/sabotage-qa-tester/AGENTS.md`
  (scoping notes), `AGENTS.md` (3.1 live-unverified, enforcer
  semantics+version+probes, secret-denies + DOCKER_HOST invariants,
  proxy-up routing, 46-count), `SUPPORTING_SERVICES.md` (E.1/E-mirror
  GET-only correction, §12.7 bridge residual, §12.8 rabbitmq rotation,
  hound mirrors + remap note, §1b quarterly watchlist), `NOTES.md`
  (Wave D log: P0-1 diff, P1-8 pin, secret-plane decisions, verified
  facts), `.env.example` (base-digest, proxy preflight, rabbitmq,
  signing fail-closed — via scripted replacement, `.env*` edit guard),
  `Makefile` (`guard-proxy` + `proxy-up`), `.gitignore` (scratch
  placeholder tracked / outputs ignored), `REMEDIATION_LOG.md` (Wave D entry).

## 3. Test results

- `bash scripts/test-shim.sh` → **46 passed, 0 failed** (45 baseline + P3-1).
- `bash scripts/smoke-test.sh --check-only` → **526 passed, 0 failed,
  5 skipped** (pre-Wave-D baseline 495-era counts grew through Waves
  A–C; +Wave-D gates, zero regressions; skips are the 3 environmental +
  2 documented live-gate notes).
- `bash scripts/spec-gate.sh --check-only` → 7/7 (via smoke §3d, also standalone).
- `shellcheck scripts/*.sh` → zero warnings (two new intentional
  `SC2016` literal-match disables follow the established pattern).
- `bash scripts/seed-50-fleet.sh --dry-run` → 52 payloads, total ==
  cap, empty stderr; `ROLE_DIR=wrong-role` → exit 1 descriptive error.
- Mutation probes (all fail closed, all restored green): secrets-deny
  removal → 1 FAIL; bare `adb connect*` → adb FAIL; `DOCKER_HOST`
  removal → dead-MCP + dockerhost FAILs (2).
- `docker compose config` → exit 0: default, prebuilt, web-research,
  devsec, ai-gateway, observability, mobile, core+ci, qa-testing+core,
  proxy+tailscale. `qa-testing` ALONE fails on the documented
  pre-existing runner→proxy pairing — verified identical on the stashed
  baseline (not a Wave D regression).
- Generator↔disk: scratch `--root` regen reproduces all 51
  `opencode.json` byte-identically (zero drift, before and after).
- `make guard-proxy`: refuses unset/public exposure/placeholder secret;
  passes private+real (all four directions verified).
- `make test` (live mode, stack down) → 526 passed / 3 environmental
  FAILs (postgres down, paperclip down ⇒ UID unverifiable, HTTP down) —
  full green needs `make up` (live stage).

## 4. Self-audit notes

- Fail-closed everywhere: guards exit 1/127 with descriptive errors; no
  `|| true`, no TODOs, no dummy returns; deny tails intact on all 51
  (programmatically re-verified); no floating tags (no `:latest`
  introduced — smoke pin gates green); no secrets in repo (only
  `__smoke_only__` dummies + `CHANGE_ME__` placeholders, never echoed).
- Nothing claimed beyond evidence: P0-1 load-broken (not fixed),
  Claim 3.1 + child-env scrub live-unverified, enforcer semantics
  assumed-prefix, piston/firecrawl/r2/ghidra fronting tracked (not
  built), postgres/firecrawl/ghidra digests planned (not resolved —
  registry verification is the documented precondition).
- Residuals requiring live stack / registry / auth: §10b probe
  (`HARNESS_LIVE_GATE=1` + model auth), canary isolation turn,
  argv-aware enforcer matrix, UID==1000 boot, rabbitmq first-boot +
  `rabbitmqctl` rotation on existing volumes, `:1337`/`:1337`-class
  healthcheck strengthening, digest resolutions, `v1.0.0` publication.
- No commits, no merges, no subagents used. Changes left UNCOMMITTED.
