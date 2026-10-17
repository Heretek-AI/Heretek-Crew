# Wave E Stage 1 Implementation Report — P0 Critical Remediation (P0-1, P0-2, P0-3, P0-4)

**Stage ID:** Wave E Stage 1 (P0 Critical) — `AUDIT_REPORT_FINDINGS.md` lines 12-53 + remediation order lines 186-192
**Date:** 2026-10-17 | **Branch:** `wave-e-audit-remediation` (worktree `/tmp/opencode/heretek-wave-e`)
**Source of truth:** `AUDIT_REPORT_FINDINGS.md` + task envelope (TARGETS + ACCEPTANCE verbatim)
**Status:** complete, verified empirically. Changes left UNCOMMITTED for QA/Drift-Guard. No commits, no merges, no subagents used.

## 1. Summary of deliverables

- **P0-1 (harness 1.0.7 DIES on load):** verified, NOT invented. `docker/Dockerfile:33-53`
  documents the empty-string `rootDir` root cause + `pick()` diff + bump plan + live-visibility
  gate reference (unchanged, accurate — no doc edit needed). `scripts/smoke-test.sh` §10b live
  gate stages `scripts/fixtures/harness-probe-opencode.json` as XDG config and runs one real
  `opencode run` turn invoking `file_hash_read`, FAILing on the `rootDir must be` Die /
  `not available` signature, gated on `HARNESS_LIVE_GATE=1` (verified present `:1725-1745`,
  SKIPs never fake-passes in check-only). `OPENCODE_HARNESS_VERSION` stays exact `1.0.7`
  (ENV + install + comment, `:35,:71,:101`). Live registry check this stage:
  `npm view @heretek-ai/opencode-harness versions` → `[ '0.0.0-stage', '1.0.0', '1.0.2',
  '1.0.3', '1.0.4', '1.0.7' ]` — **no fixed successor published; upstream bump reported
  blocked (nothing to bump to)**, pin stays exact, Domain 4 primitives remain labeled
  load-broken, never working.
- **P0-2 (Claim 3.3 read-only bypass):** verified closed. All 6 read-only-charter roles
  (`exec-director`, `product-director`, `threat-modeler`, `compliance-auditor`,
  `tech-docs-lead`, `ux-research-analyst`) ALLOW only the 10 read-only harness tools and
  DENY the 4 mutating tools (`harness_file_hash_edit`, `harness_ast_structural_rewrite`,
  `harness_rename_symbol`, `harness_checkpoint_rollback`) with explicit deny entries AFTER
  the `harness_*` deny tail (python JSON parse: 6/6 zero allows, 4/4 denies each; grep shows
  only `"effect": "deny"` on those 4). Generator `scripts/generate-50-roles.py` encodes the
  split (`HARNESS_MUTATING_TOOLS` + 16-role `READONLY_HARNESS_STRIPPED` superset +
  `strip_mutating_harness_tools()` + `is_readonly_charter()` drift pins); regen via
  `--root` into scratch reproduces disk permissions **byte-identically (51 roles,
  0 mismatches)**. Smoke gate present and green: harness-manifest gate (14 full / 10
  read-only + deny tails) + read-only-set drift pin (on-disk set must equal pinned 16
  exactly) + mutating-allow ban (fail-closed).
- **P0-3 (XDG isolates config only):** (a) kubeconfig `:ro` bind kept (k8s-orchestrator
  unbroken) + FD-passed-MCP-env structural plan comment verified present
  (`docker-compose.yml:156-170`); (b) `AGENTS.md` §1 invariant 1 (`:20-24`) + `NOTES.md`
  Wave D entry (`:363-375`) label Claim 3.1 config-advice, live-unverified until the canary
  live test (plant canary `opencode.json` + `.opencode/`, run one agent turn, assert
  ignored) + child-env scrub (no `DATABASE_URL`/`POSTGRES_PASSWORD`/`BETTER_AUTH_SECRET`/
  provider keys) passes — no live-pass claim exists anywhere (verified, no edit needed);
  (c) all 51 roles carry the 4 secret-material `fs:read` denies (`**/secrets/**`,
  `**/kubeconfig*`, `**/*.pem`, `**/id_rsa*`) ABOVE every `fs:read` allow (python JSON
  parse: 51/51 presence + ordering, 0 violations); generator `FS_READ_ENV_DENIES` +
  `order_fs_read_denies_first()` encodes it; smoke §3b asserts presence + ordering
  fleet-wide (green).
- **P0-4 (piston RCE-as-a-service):** sabotage-qa-tester intended exact-host pins untouched
  (`curl -s http://piston:2000/api/v2/runtimes*`, `curl -s -X POST
  http://piston:2000/api/v2/execute*`, `:73,:78`). Piston block already documented the
  unauthenticated `/api/v2/execute` risk + sandbox-only layer + fronting plan
  (shared-secret proxy / per-request tokens into sabotage-qa-tester only); **this stage
  adds the tracked honest residual** (stays on shared `heretek` net — live network move
  deferred pending `make up` reachability verification — + never-co-schedule
  devsec/qa-testing advisory) rather than a risky untested move. Ghidra `:1337` / radare2
  `:9090` paperclip-as-bridge residual verified present (`:339-348`, `:379-388`).
  Firecrawl loopback-only (`127.0.0.1:3002:3002`) + `USE_DB_AUTHENTICATION=true` hardening
  path verified present (`:199-208`); smoke §3a asserts the loopback bind (green).
  **Makefile co-scheduling note added** (advisory, not an enforced guard — devsec+core is
  normal ops; enforcement would break it; ghidra/radare2 `heretek-devsec` isolation +
  profile gating remain the control).

## 2. Files created / modified

- `docker-compose.sidecars.yml` — piston comment +7 lines (Wave E Stage 1 shared-net residual
  + co-scheduling advisory; no behavioral change: image, profiles, expose, networks untouched).
- `Makefile` — co-scheduling note +10 lines after `sidecars-up` (comment-only; no new
  enforcement target; existing `guard-profiles`/`guard-proxy` text byte-identical so smoke
  gates `:298-303,:725-727` stay green).
- `docs/reports/wave-e-stage1-implementation.md` — this report (new).
- `REMEDIATION_LOG.md` — Wave E Stage 1 entry appended (new section, prior Waves untouched).

Untouched by design (verified already-correct, re-proven empirically): `docker/Dockerfile`,
`docker-compose.yml`, `scripts/generate-50-roles.py`, `scripts/smoke-test.sh`,
`scripts/seed-50-fleet.sh`, all 51 `roles/*/opencode/opencode.json`.

## 3. Test results (acceptance criteria, all pass in worktree)

- python3 JSON parse: **51/51** roles end with `{shell,*,deny}` as last entry (0 bad);
  **51/51** fs:read denies (incl. 4 secret-material) precede allows (0 violations);
  **6/6** read-only roles deny the 4 mutating harness tools with zero allows.
- `bash scripts/smoke-test.sh --check-only` → **526 passed, 0 failed, 5 skipped** (exit 0).
- `bash scripts/test-shim.sh` → **46 passed, 0 failed** (exit 0).
- `shellcheck scripts/*.sh` → zero warnings (exit 0).
- `bash scripts/spec-gate.sh --check-only` → **7 passed, 0 failed** (exit 0).
- `bash scripts/seed-50-fleet.sh --dry-run` with smoke dummy env → **51 agent payloads +
  1 company = 52 docs, total 1300000 == cap 1300000, empty stderr**; without provisioned
  secrets → exit 1 naming each missing var (fail-closed preflight intact).
- Generator regen (`--root` scratch + catalog copy) → **51 roles, 0 permission mismatches**.
- `docker compose config` with dummy env → exit 0 on `qa-testing+core` and `devsec+core`;
  without `.env` → fail-closed naming the exact missing var.
- `git status --short` → only `M Makefile`, `M docker-compose.sidecars.yml` (+ the two
  doc files); no secrets, no `:latest` introduced (`:latest` hits are pre-existing prose
  comments filtered by the smoke pin gate), no TODO/dummy/empty-catch
  (`return True` hits are legitimate `is_readonly_charter` logic + charter prose).

## 4. Self-audit notes

- Fail-closed everywhere: no enforcement semantics changed; both edits are comments/notes
  that strengthen honest labeling without moving any live boundary (piston net, Makefile
  guards, role permissions, pins all byte-identical outside the two comment blocks).
- Minimal diff: 17 added comment lines total across 2 ops files; zero behavioral delta
  (compose renders exit 0 on all probed profiles; smoke count unchanged at 526).
- No proof contradicted the audit; one live registry fact refined P0-1 (successor
  unpublished — bump blocked, recorded above, not a product decision).
- Product decisions still tracked (not started): piston vendor/self-build to
  `ghcr.io/heretek-ai/piston:<semver>`, shared-secret proxy front for `:2000/:1337/:9090`,
  live-stack gates (`HARNESS_LIVE_GATE=1` tool-visibility + XDG canary + child-env scrub).
- No commits, no merges, no subagents used. Changes left uncommitted for QA/Drift-Guard.
