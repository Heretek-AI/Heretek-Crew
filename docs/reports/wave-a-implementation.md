# Wave A Implementation Report — P0-2 read-only harness strip + P1-7 fs:read deny-first (P2-1 claim note)

**Stage ID:** Wave A (AUDIT_REPORT_FINDINGS.md P0-2, P1-7, P2-1-fragment)
**Date:** 2026-10-17 | **Branch state:** uncommitted on `main` (ahead of origin/main by 1 commit — pre-existing)
**Source of truth:** `AUDIT_REPORT_FINDINGS.md` §§ P0-2, P1-7, P2-1 + task envelope
**Status:** complete, verified empirically. Changes left UNCOMMITTED for QA/Drift-Guard.

## 1. Summary of deliverables

- **P0-2:** 16 read-only-charter roles stripped of the 4 file-mutating harness
  allows (`harness_file_hash_edit`, `harness_ast_structural_rewrite`,
  `harness_rename_symbol`, `harness_checkpoint_rollback`); each now carries
  the 4 exact-deny entries from the audit fix + the other 10 read-only
  harness allows + the `harness_*` deny tail. 35 builder roles keep all 14.
- **P1-7:** all 51 role files reordered so the 4 `fs:read` `.env` denies sit
  at indices 0–3, above any `fs:read` allow (fail-closed under both
  first-match and deny-override semantics). `fs:write` ordering untouched.
- **P2-1 fragment:** no claim-text file in-repo states the inverted
  `{harness_*, allow}` wording (audit prompt text lives outside the repo);
  `smoke-test.sh` header NOTE rewritten to state the true shape (14
  per-tool allows + `harness_*` deny; 10 + 4 denies for read-only) and to
  record that a live allow/deny matrix is blocked on P0-1 (upstream npm).
- **Generator:** `scripts/generate-50-roles.py` reproduces both changes
  (`strip_mutating_harness_tools()` + `order_fs_read_denies_first()` in
  `normalize_config`); proven by scratch regen diff (harness + fs:read
  sections identical to disk for all 51 roles).
- **Smoke:** existing manifest gate branched by role class (14 full /
  10 read-only, deny-tail preserved); 2 new fail-closed gates (read-only
  set drift pin + mutating-tool ban; fs:read ordering).

## 2. Read-only set (16 roles — includes all 6 mandated)

`ai-red-teamer`, `appsec-engineer`, `binary-reverse-eng`,
`cloud-sec-auditor`, `compliance-auditor`, `exec-director`,
`firmware-sec-analyst`, `git-drift-coord`, `product-director`,
`release-qa-officer`, `sre-incident-eng`, `system-architect`,
`tech-docs-lead`, `threat-modeler`, `tpm-scrum-lead`,
`ux-research-analyst`

Predicate: every `fs:write` allow confined to report-output scopes
(`docs/**`, `sbom/**`, `deploy/security/**` seccomp profiles —
declarative policy outputs, not application code). `threat-modeler`
("Never writes application code") and `compliance-auditor` ("Delegates
dependency replacements to `dependency-patcher`") qualify despite
non-`docs/` scopes; every other role writes tests, source, schemas,
migrations, configs, or assets and legitimately keeps the 14.

## 3. Files created/modified (53, uncommitted)

- 51× `roles/*/opencode/opencode.json` (16 stripped + reordered; 35 reordered only)
- `scripts/generate-50-roles.py` (+HARNESS_MUTATING_TOOLS,
  READONLY_WRITE_PREFIXES, READONLY_HARNESS_STRIPPED,
  FS_READ_ENV_DENIES, `is_readonly_charter()`,
  `strip_mutating_harness_tools()`, `order_fs_read_denies_first()`)
- `scripts/smoke-test.sh` (branched manifest gate + 2 new gates + header/NOTE updates)
- This report: `docs/reports/wave-a-implementation.md` (new)

## 4. Test results (proof commands + outputs)

- `bash scripts/smoke-test.sh --check-only` → **497 passed, 0 failed,
  3 skipped** (baseline on stashed HEAD: 495/0/3 → +2 new gates, zero regressions).
- New gates green: `harness manifest enforced (14 full / 10 read-only)`,
  `read-only harness strip enforced (16 pinned roles)`,
  `fs:read deny-first ordering`.
- `shellcheck scripts/*.sh` → zero warnings. `test-shim.sh` → 39/0.
  `spec-gate.sh --check-only` → 7/0.
- JSON valid on all 51 role files; `grep -L deny` → 0 missing;
  `ls roles/` = 51; terminal `shell * deny` last + `small_model` /
  `compaction` / `timeout: 5000` asserted programmatically on all 51.
- Watched-fail probes: injected `harness_file_hash_edit` allow into
  `exec-director` → BOTH gates FAIL (exit 1, exact role named); moved an
  `fs:read` allow above denies in `dba-specialist` → ordering gate FAILs
  (`allow at index 0 precedes deny at index 4`, exit 1). Both restored
  byte-identical afterwards.
- Generator parity: scratch regen (with a scratch-only
  `EXPECTED_IDS`+`REPORTS_TO` patch for Role 51) → permissions identical
  to disk except pre-existing catalog drift only.

## 5. Self-audit notes

- Fail-closed kept: generator `die()`s on read-only drift (non-report
  `fs:write` allow) and on missing `harness_*` anchor; smoke `bad()` on
  any set drift, any mutating allow, any ordering violation; no `|| true`
  / TODO / dummy / empty-catch added (7 TODO hits all pre-existing
  zero-stub machinery); no floating versions; no secrets touched; scripts
  keep `set -euo pipefail` + `--dry-run`/`--help`.
- Minimal diff: role files changed only in the permissions array
  (round-trip `json.dumps indent=2` verified byte-identical elsewhere);
  deny tails preserved; `fs:write` ordering untouched.
- ai-red-teamer transformed by hand with the identical imported functions
  (generator covers catalog Roles 01–50 only) — noted in code + §6.
- NOT done (out of scope, tracked): P0-1 `dist/index.js` (upstream npm);
  no live-enforcement claim (static gates only + explicit P0-1-blocked note).

## 6. Pre-existing issues found (not introduced, not fixed — separate waves)

1. **Generator already dies at HEAD:** catalog `07_…md` contains Role 51
   (`ai-red-teamer`) but `EXPECTED_IDS` lists 50 → `role set mismatch`
   (proven with `git show HEAD:…` copy). P1-4 product decision (promote /
   quarantine Role 51 incl. budgets); left untouched deliberately.
2. **Catalog lacks all `.env` denies** (fs:read AND fs:write) present
   on disk — prior "regen == disk" claims overstated. The new generator
   code ENSURES the canonical fs:read denies (regen now converges toward
   disk); fs:write denies + ai-red-teamer `git_*` read verbs remain
   hand-only catalog drift for a catalog-sync wave.
3. **Regen budget WARNING:** scratch regen with Role 51 sums 1,300,000¢
   vs 1,270,000¢ cap — same P1-4 promotion arithmetic.

## 7. Residual risk (honest)

Static gates cannot prove the runtime enforcer consults `fs:write`
scoping or honors `harness_*` denies — enforcement lives in
`@heretek-ai/opencode-harness@1.0.7` + Paperclip `/tmp/paperclip`,
outside this repo. Claim 3.3 ("cannot execute code modification tools")
for the 16 roles is statically gated as of this wave; live proof awaits
the P0-1 fix + a live allow/deny matrix. No commits, no merges, no
subagents used.
