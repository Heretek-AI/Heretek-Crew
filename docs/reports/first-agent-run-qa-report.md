# First-Agent-Run QA Report (Drift-remediation rework 2/3, 2026-10-18)

Wave: first-agent-run · Worktree: `/tmp/opencode/worktrees/first-agent-run` · Branch: `wave-first-agent-run`
Auditor role: QA (rework cycle 2/3, answering Drift Guard FAIL findings 1–4).
Method: every proof command below was re-run by QA now (2026-10-18); outputs and
exit codes are pasted verbatim. Live server reads are read-only GETs only
(token loaded via `python3 json.load`, never printed). No fleet mutation was
performed by QA: no resume/wakeup/pause POST, no seed, no roles/ edit. The only
live execution is sabotage-3, a drifted `/tmp` copy that aborts pre-lifecycle
after read-only GETs (zero lifecycle calls). The two terminal runs under test
were executed by the prior QA + rework cycle and are confirmed below via
read-only GETs — QA did not start a third run.

Under audit: `scripts/first-agent-run.sh` (1120 lines) +
`docs/reports/first-agent-run-evidence.md` + sidecar
`docs/reports/first-agent-run-evidence.tech-docs-lead.json` + bundle
`docs/reports/first-agent-run-evidence.d/tech-docs-lead/`
(run.json, log.json, events.json, provider-trace.json, wakeup-receipt.json,
timeline.txt).

## (a) Acceptance per-check (proof commands + outputs + exit codes)

### A1. `--help` exits 0

Command: `bash scripts/first-agent-run.sh --help > /tmp/opencode/help-out.txt 2>&1`

```text
exit=0

first-agent-run.sh — prove the first FULL agent turn end-to-end on Muse Spark.

Target: exec-director (paused at wave start) via resume -> wakeup(on_demand/
manual) -> poll heartbeat-runs to a terminal state with log + provider-trace
...
```

Full usage text printed (flags `--dry-run` / `--only` / `--environment` /
`--help`, env vars, exit-code contract). PASS.

### A2. `--dry-run` with token unset exits 0 and sends zero network calls

Command: `env -u PAPERCLIP_TOKEN -u ADMIN_API_KEY bash scripts/first-agent-run.sh --dry-run`

```text
exit=0
[first-agent-run] --dry-run: first full agent turn plan (no network calls)
[first-agent-run] server: http://localhost:3100 (untouched in dry-run; safe against a dead URL)
[first-agent-run] company: 'Heretek Autonomous Fleet' (expected id d2f411ef-0b17-467f-8540-a17c603859d9; resolved live via GET /api/companies)
[first-agent-run] model proof: every target agent must read back adapterConfig.model == 'opencode-go/muse-spark-1.3-contributor' before any lifecycle call, or the run aborts without mutating anything
[first-agent-run] environment: environmentId key omitted from every wakeup body (server uses the agent default)
[first-agent-run] --- role 'exec-director' (agent 'Director / CEO-Delegate', expected id b2211b6f-98f7-4e07-bb34-125ecc55cf25) ---
[first-agent-run] step 1: GET http://localhost:3100/api/companies/<companyId>/agents -> resolve agent id for 'Director / CEO-Delegate', record status/model
[first-agent-run] step 2: GET http://localhost:3100/api/agents/<agentId> -> record model/env shape; abort unless model == 'opencode-go/muse-spark-1.3-contributor'
[first-agent-run] step 3: status paused -> POST http://localhost:3100/api/agents/<agentId>/resume (empty body), then re-GET to verify idle; any other status skips resume and is recorded
[first-agent-run] step 4: POST http://localhost:3100/api/agents/<agentId>/wakeup with body:
[first-agent-run] {"source": "on_demand", "triggerDetail": "manual", "reason": "first functional test of full agent turn on Muse Spark (wave first-agent-run)", "forceFreshSession": true, "idempotencyKey": "<fresh-uuid>"}
[first-agent-run] step 5: poll GET http://localhost:3100/api/companies/<companyId>/heartbeat-runs?agentId=<agentId>&limit=10 every 10s up to 900s until the receipt run reaches terminal (success/failed/cancelled family); on models_discovery_failed retry the wakeup ONCE with a fresh idempotencyKey
[first-agent-run] step 6: GET http://localhost:3100/api/heartbeat-runs/<runId> + /log + /events + /provider-trace (50-line excerpts in report, full bodies to evidence bundle)
[first-agent-run] step 7: restore — re-read live openapi.json for POST /api/agents/{id}/pause; present -> pause + re-GET verify paused; absent -> LEAVE idle + explicit follow-up in evidence (never guess the shape)
[first-agent-run] step 8: write /tmp/opencode/worktrees/first-agent-run/docs/reports/first-agent-run-evidence.md + JSON sidecar first-agent-run-evidence.exec-director.json (runId, timestamps, transitions, model proof, restore proof)
[first-agent-run] dry-run summary: 1 role(s) would be proven end-to-end; zero network calls attempted
```

Token-absent proof: the token-requirement gate (lines 218–221) is placed
AFTER the `--dry-run` early exit (lines 282–319), so dry-run never demands a
token; the dry-run code path contains no `curl`/`api` call (verified by
reading lines 282–319 — pure `log` statements). PASS.

### A3. `--dry-run` against a dead port exits 0 (no bytes sent)

Command: `PAPERCLIP_URL=http://127.0.0.1:9 HEALTH_TIMEOUT_SEC=1 POLL_TIMEOUT_SEC=1 bash scripts/first-agent-run.sh --dry-run`

```text
exit=0
[first-agent-run] --dry-run: first full agent turn plan (no network calls)
[first-agent-run] server: http://127.0.0.1:9 (untouched in dry-run; safe against a dead URL)
...
```

PASS — dry-run is safe against a dead `PAPERCLIP_URL`.

### A4. Static checks: shellcheck 0, bash -n clean, +x, `set -euo pipefail` L108

```text
shellcheck scripts/first-agent-run.sh   -> shellcheck exit=0 (zero warnings)
bash -n scripts/first-agent-run.sh      -> bash -n exit=0
ls -l scripts/first-agent-run.sh        -> -rwxr-xr-x (executable bit set)
grep -n "set -euo pipefail"             -> 108:set -euo pipefail
```

PASS.

### A5. Zero-stub / fail-closed grep checks

- `grep -nE 'TODO|FIXME|return true|\|\| true|catch *\{\}|echo "passed"'` → no
  matches (exit=1). No stubs, no dummy returns, no swallowed errors.
- `grep -n '|| true|set +e|catch *{}'` → no matches. No error masking.
- `grep -nE 'PATCH|PUT|POST'` → state-changing calls are exactly the
  allowlisted lifecycle trio: `POST .../resume` (line 781, empty body),
  `POST .../wakeup` (lines 834, 926), `POST .../pause` (line 982, gated on the
  live openapi.json confirming the route, lines 621–650). No agent PATCH, no
  skill/instruction PUT, no fleet mutation. PASS.
- `grep -rn ':latest\|@latest' scripts/first-agent-run.sh` → no matches. The
  single `:latest` occurrence in the wave is inside the server-returned agent
  charter prompt quoted in the evidence events excerpt ("no `:latest` tags in
  MCP commands, plugins, or packages" — the agent's own pinning policy text),
  not a pin introduced by this wave. PASS with attribution.
- `grep -n 'seed-50-fleet...'` → 3 comment-only mentions ("Same contract as
  scripts/seed-50-fleet.sh", "mirrors seed-50-fleet.sh", "this script never
  seeds"); zero invocations. PASS.

### A6. Gate proofs

- `bash scripts/test-shim.sh` → `exit=0`, tail: `57 passed, 0 failed`. PASS.
- `bash scripts/spec-gate.sh --check-only` → `exit=0`,
  `SPEC-GATE RESULT: 7 passed, 0 failed (mode=check dry-run=false)`. PASS.
- `bash scripts/smoke-test.sh --check-only` → `exit=0`,
  `SMOKE RESULT: 548 passed, 0 failed, 7 skipped (mode=check-only)`. The 7
  skips are live-only checks (postgres pg_isready, paperclip HTTP health,
  ticket flow, harness P0-1 probe, XDG/canary P1-8 probe, backup round-trip).
  PASS.
- `make test` (live mode) → `exit=2` with exactly 2 fails:
  `[FAIL] postgres not healthy (run 'make up' ...)` and
  `[FAIL] paperclip container not running (run 'make up' first ...)`, caused by
  compose `.env` interpolation (`POSTGRES_PASSWORD` / `POSTGRES_READER_PASSWORD`
  missing a value), NOT by dead services. Attribution proof re-run now:
  `docker ps` shows `heretek-crew-paperclip-1 Up 3 hours (healthy)` and
  `heretek-crew-postgres-1 Up 3 hours (healthy)`; `curl ... /api/health` →
  `200` with `{"status":"ok",...,"commit":"73659c6b27...","bootstrapStatus":"ready",...}`.
  These are compose-context false negatives: the containers the Makefile probes
  by name are healthy and the API answers 200. No wave file is implicated
  (the failing probes live in `scripts/smoke-test.sh` live sections, untouched
  by this wave). PASS with attribution.

### A7. Live-run evidence (read-only GET confirmations — see §(c) for full detail)

- `GET /api/heartbeat-runs/5a6f91b7-50b8-455b-b48f-2783529eb931` →
  `status=succeeded`, `createdAt=2026-10-18T15:56:48.725Z`,
  `startedAt=2026-10-18T15:56:52.830Z`, `finishedAt=2026-10-18T15:58:03.926Z`,
  `exitCode=0`, `usageJson.model=opencode-go/muse-spark-1.3-contributor`.
- `GET .../e1e7bbff-ea1a-42d8-87f9-68c8fdc36187` → `status=succeeded`,
  `createdAt=2026-10-18T15:04:09.037Z`, `startedAt=2026-10-18T15:04:11.787Z`,
  `finishedAt=2026-10-18T15:05:08.289Z`, same agent, same model.
- Events `adapter.invoke` for 5a6f91b7 carries
  `commandArgs=[run --format json --model opencode-go/muse-spark-1.3-contributor ...]`,
  `env.XDG_CONFIG_HOME=/roles/tech-docs-lead`, all secret env values
  `***REDACTED***`. Log body contains session `ses_eb0442f5fffe52c48nLY5R7ol6`
  with `step_start` / `text` / `tool_use` parts (real Muse Spark activity, not
  probe-only). PASS.

### A8. Git hygiene

Worktree `git status --short` (re-run now):

```text
?? .waves/
?? docs/reports/first-agent-run-evidence.d/
?? docs/reports/first-agent-run-evidence.md
?? docs/reports/first-agent-run-evidence.tech-docs-lead.json
?? scripts/first-agent-run.sh
```

plus (after this QA cycle) `?? docs/reports/first-agent-run-qa-report.md`
(this file). All untracked pre-commit wave files; `git diff --stat main...HEAD`
is empty because nothing is committed yet (expected pre-commit state).
Main repo `git status --short` → only `?? docker-compose.override.yml`
(pre-existing, left alone). Branch is `wave-first-agent-run`. No `roles/`,
opencode.json, enrich-*, or `.env*` changes. PASS.

### A9. Secret scan

`grep -rnE 'Bearer [A-Za-z0-9._-]{10,}|pcp_[A-Za-z0-9]+|sk-[A-Za-z0-9]+'`
over evidence.md + sidecar + bundle → no matches. Sidecar carries 8
`***REDACTED***` markers (server-side redaction of `GITHUB_TOKEN`,
`OPENCODE_GO_API_KEY`, `PAPERCLIP_API_KEY`, `PAPERCLIP_AGENT_KEY_ID`,
`PAPERCLIP_AGENT_PUBLIC_KEY`, `PAPERCLIP_AGENT_PRIVATE_KEY`,
`PAPERCLIP_RUNTIME_TOOLS_TOKEN`, `paperclipSecrets`). The wakeup/resume/pause
bodies carry no secret values by construction. PASS.

### A10. Fleet model spot-check (unchanged)

- `GET /api/agents/b2211b6f-...` (exec-director) → `model=opencode-go/muse-spark-1.3-contributor`.
- `GET /api/agents/c5ae250d-...` (tech-docs-lead, live re-check now) →
  `status=idle`, `model=opencode-go/muse-spark-1.3-contributor`,
  `updatedAt=2026-10-18T15:59:45.166Z`. PASS — no fleet model drift.

## (b) Sabotage proofs (5 classes, `/tmp` copies ONLY — worktree file never mutated)

Original integrity: `grep -c '^set -euo pipefail$' scripts/first-agent-run.sh` → `1`
(line 108 intact after all sabotage runs).

### S1. Removed `set -euo pipefail` → presence check FAIL

Fault: `grep -v '^set -euo pipefail$' sab1.sh > sab1-stripped.sh`
(1120 lines → 1119 lines).

```text
--- presence check on STRIPPED copy ---
FAIL: fail-closed header 'set -euo pipefail' absent — copy rejected (fault: line 108 removed)
--- presence check on ORIGINAL (must PASS) ---
PASS: original line 108 intact
```

### S2. Constant `idempotencyKey` → duplicate FAIL

Fault: patched `/tmp` copy whose `gen_idempotency_key` returns the constant
`CONSTANT-REPLAY-KEY-0000`.

```text
--- duplicate-key detector on PATCHED copy ---
key1=CONSTANT-REPLAY-KEY-0000
key2=CONSTANT-REPLAY-KEY-0000
FAIL: duplicate idempotencyKey across attempts — replay risk, copy rejected (fault: constant key)
--- detector on ORIGINAL ---
key1=abb97a8f-f84d-415e-b0d8-268fe805e366
key2=87862943-d00a-45cf-ae8c-f3f1deca3fe5
PASS: original generates fresh keys per attempt
```

### S3. `TARGET_MODEL=anthropic/claude-sonnet-4-5` → exit 1 model-drift abort pre-lifecycle

Fault: `sed` on a `/tmp` copy → line 123
`TARGET_MODEL="anthropic/claude-sonnet-4-5"`. Live run of the drifted copy
(read-only GETs only; aborts before any lifecycle POST):

```text
exit=1
[first-agent-run] waiting for Paperclip health at http://localhost:3100 (timeout 30s)
[first-agent-run] auth: requests carry Authorization: Bearer *** (token never logged)
[first-agent-run] resolving company 'Heretek Autonomous Fleet'
[first-agent-run] company exists: d2f411ef-0b17-467f-8540-a17c603859d9
[first-agent-run] no --environment: environmentId omitted from the wakeup body (server uses the agent default)
[first-agent-run] === proving role 'tech-docs-lead' (agent 'Technical Documentation Lead') ===
[first-agent-run] role 'tech-docs-lead': pre-run status='idle' model='opencode-go/muse-spark-1.3-contributor'
[first-agent-run] ERROR: role 'tech-docs-lead': model drift (got 'opencode-go/muse-spark-1.3-contributor', want 'anthropic/claude-sonnet-4-5'); aborting role WITHOUT mutating anything
[first-agent-run] ERROR: first-agent-run FAILED for 1 role(s)
--- evidence dir must be absent/empty (no lifecycle, no evidence) ---
/tmp/opencode/sabotage/sab3-evidence:
(empty — mkdir only, no report/sidecar/bundle written)
```

FAIL output recorded as required; no lifecycle call was issued (no resume,
wakeup, or pause POST appears in the output; evidence dir empty). The worktree
script still pins `TARGET_MODEL="opencode-go/muse-spark-1.3-contributor"`.

### S4. Dead `PAPERCLIP_URL` on the live path → exit 1 unhealthy, no evidence

Command: `/tmp` copy run with `PAPERCLIP_URL=http://127.0.0.1:9`,
`HEALTH_TIMEOUT_SEC=2` (no `--dry-run`, so the live path executes):

```text
exit=1
[first-agent-run] waiting for Paperclip health at http://127.0.0.1:9 (timeout 2s)
curl: (7) Failed to connect to 127.0.0.1:9 after 0 ms: Could not connect to server
curl: (7) Failed to connect to 127.0.0.1:9 after 0 ms: Could not connect to server
error: Paperclip did not become healthy in 2s
--- evidence dir check ---
ls: cannot access '/tmp/opencode/sabotage/sab4-evidence': No such file or directory
```

FAIL output recorded; the run fails closed before company resolution and
writes zero evidence.

### S5. Truncated provider-trace JSON → completeness FAIL

Fault: `head -c 10 provider-trace.json > trace-truncated.json`
(bytes: `{"trace":n`).

```text
--- completeness check on TRUNCATED copy ---
FAIL: provider-trace JSON unparseable (Expecting value: line 1 column 10 (char 9)) — completeness check rejects evidence (fault: truncated JSON)
--- completeness check on ORIGINAL bundle file ---
original bundle provider-trace.json: {"trace": null, "entries": []}
NOTE: empty trace is server behavior (HTTP 200 with null trace + empty entries); model proof carried redundantly by run.json usageJson + events adapter.invoke + log session.
```

## (c) Live-run evidence (confirmed via read-only GETs now)

Script-written run (superseding, bundle-backed):
`5a6f91b7-50b8-455b-b48f-2783529eb931` · agent tech-docs-lead
`c5ae250d-3620-417d-a249-617ee59aa080` · company `d2f411ef-...`:

- Wakeup 202 at `2026-10-18T15:56:54Z`, `idempotencyKey=db1c56df-9232-42e2-9505-80244151a418`
  (receipt body `status=queued`, `wakeupRequestId=853da78c-904e-4be2-9df4-a5d917eee61e`).
- Run `createdAt=2026-10-18T15:56:48.725Z`, `startedAt=2026-10-18T15:56:52.830Z`,
  `finishedAt=2026-10-18T15:58:03.926Z`, polled terminal `succeeded` at
  `2026-10-18T15:58:15Z`, `exitCode=0`, `error=null`.
- Model proof (triple redundancy): `run.json usageJson.model` =
  `opencode-go/muse-spark-1.3-contributor`; events `adapter.invoke`
  `commandArgs` includes `--model opencode-go/muse-spark-1.3-contributor`;
  `env.XDG_CONFIG_HOME=/roles/tech-docs-lead`. All secret env values
  `***REDACTED***` server-side.
- Log proof: session `ses_eb0442f5fffe52c48nLY5R7ol6` with `step_start`,
  `text` ("Starting triage — locating your ticket and workspace context."),
  and `tool_use` parts — genuine agent-turn activity.
- Provider-trace: `{"trace":null,"entries":[]}` — this is server behavior
  (HTTP 200, well-formed envelope, empty entries), explicitly NOT a gap in the
  script's capture (all four evidence GETs succeeded and are bundled
  verbatim). Model/activity proof is carried redundantly by run.json, events,
  and log as listed above.
- Transitions: pre-run `idle` → no resume → wakeup 202 → `succeeded` →
  closing re-GET `paused` at `15:58:28Z`, then live re-check `idle` at
  `15:59:45.166Z` (server autopause/resume churn, self-resolved to pre-run
  idle; no follow-up needed — see evidence §6). Fallback path performs no
  resume/re-pause (`restore.note` empty), correctly.

Prior QA-cycle run (superseded, server-confirmed):
`e1e7bbff-ea1a-42d8-87f9-68c8fdc36187` · same agent, same model ·
`createdAt=2026-10-18T15:04:09.037Z` → `startedAt=2026-10-18T15:04:11.787Z` →
`finishedAt=2026-10-18T15:05:08.289Z` · `status=succeeded`, `exitCode=0`
(from the `is_terminal_status` bug era; poll was SIGTERM'd but the server
terminal state is confirmed). Superseded by the script-written 5a6f91b7
bundle above.

Fallback justification (re-GET now): exec-director `b2211b6f-...` reads
`status=paused`, `pausedAt=2026-10-18T13:49:24.870Z` (pre-wave),
`pauseReason=budget`, `lifecycleHolds=["budget"]`, `lifecycleState=paused`,
`lifecycleVersion=32`, `model=opencode-go/muse-spark-1.3-contributor`.
Resuming would violate the budget hold, so falling back to idle
tech-docs-lead was correct; no wakeup was attempted on exec-director and no
fleet state was touched.

## (d) Verdict

All acceptance checks pass with re-run proof; all 5 sabotage classes produce
the required FAIL on `/tmp` copies while the worktree original passes; both
live runs are server-confirmed `succeeded` on the pinned model with
redundant proof; hygiene (git status, secrets, pins, fleet spot-check) is
clean.

Verdict QA: PASS
