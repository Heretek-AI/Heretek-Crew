# Wave C Implementation Report — P0-5/P0-6 + P1-2/P1-3/P1-4/P1-12/P1-13/P1-14

**Stage ID:** Wave C (AUDIT_REPORT_FINDINGS.md P0-5, P0-6, P1-2, P1-3, P1-4, P1-12, P1-13, P1-14)
**Date:** 2026-10-17 | **Branch state:** uncommitted on `main` (base clean at Wave B `09e1e6a`)
**Source of truth:** `AUDIT_REPORT_FINDINGS.md` + task envelope (TARGETS + ACCEPTANCE verbatim)
**Status:** complete, verified empirically. Changes left UNCOMMITTED for QA/Drift-Guard. No commits, no merges, no subagents used.

## 1. Summary of deliverables

- **P0-5 (phantom plugin):** `opencode-rea` REMOVED from `binary-reverse-eng`
  plugins (npm `E404`, verified live 2026-10-17 — unpublishable artifacts
  cannot be pinned). `@prevalentware/opencode-goal-plugin@0.1.64` (npm
  dist-tag `latest`, verified live) added to `docker/Dockerfile` (pin
  comment + `ENV` + global install + `npm ls` assert). Publish workflow
  gains a plugin-resolution gate asserting EVERY `plugins` string in any
  `roles/*/opencode/opencode.json` resolves via `npm ls -g` in the built
  image (fail-closed on the next `opencode-rea` class).
- **P0-6 (unpublishable prebuilt):** no digest invented. `:latest` raw tag
  REMOVED from `docker-publish.yml` (stronger than a scoped exception;
  removal rationale recorded in-file) — the workflow now mints
  `1.0.0`/`1.0`/`sha-*` only. Prebuilt header + README + `.env.example`
  route operators to local build until published and constrain
  `HERETEK_IMAGE` to the exact `:1.0.0` pin or digest pins only.
- **P1-2 (dead MCP wiring):** all 8 dead server blocks (6 packages across
  7 role files + 2 `docker-mcp` blocks with no `DOCKER_HOST`) marked
  role-ready/infra-pending in catalog §3 + disk charters; new smoke
  dead-MCP allowlist gate fails on drift either way (new dead server, or
  pending server gaining infra without leaving the list).
- **P1-3 (seeder fail-closed):** `api()` uses `--fail-with-body` (curl
  ≥ 7.76); health check uses `-f` (a 500 no longer counts as healthy);
  Pass-2 PATCH captures the response body and `|| exit 1` with
  body-on-error; `find_company_id`/`find_agent` JSON-parse failures and
  unexpected shapes exit nonzero instead of masquerading as `""`.
- **P1-4 (fleet promotion):** `ai-red-teamer` promoted from pending to
  seeded — `ROLE_LIST` 51, `role_budget_cents` +30000¢, hierarchy
  (`system-architect` parent; `security` paperclip role; display/title
  entries), cap `1270000` → `1300000`¢ ($13,000.00), count gates 50→51
  roles / 51→52 payloads, catalog Total line corrected. The role-dir-count
  assertion (catalog-derived, 51==51) already existed and stays. The
  WARNING path is reconciled (sum == cap, stderr empty); the branch is
  retained for env-override drift only.
- **P1-12 (supply-chain pins):** `@morluto/rea-mcp` server block REMOVED
  fleet-wide (npm `E404`; published successor `rea-agents@6.5.0` registers
  via interactive `setup` with no verified headless stdio argv —
  inventing one would be a stub). Pin-exception sets deleted in generator
  + smoke (zero exceptions tolerated). Forks justified at npm latest
  (playwright 1.0.12, context7 4.4.2, git-mcp 2.15.3, postgres 0.6.2;
  canonical `@playwright/mcp@0.0.83` is a different package line).
  PyPI spot-verified (`pip index versions`): redis 0.1.1, k8s 0.1.6,
  qdrant 0.8.1, k6 2.2.0, clickhouse 0.7.0, docker-mcp 0.2.0, r2mcp 0.2.5,
  prometheus 1.6.2, duckdb 1.1.0. Residual (honest):
  `kafka-mcp-server` is NOT on PyPI (pip 404) AND its sidecar is absent —
  doubly dead, kept infra-pending under the allowlist (recorded in smoke
  header + charter note).
- **P1-13 (piston):** digest kept, never `:latest`. Numbered maintainer
  vendoring plan added to `SUPPORTING_SERVICES.md` E.2 (clone → pinned
  source ref → build/tag/push `ghcr.io/heretek-ai/piston:<semver>` →
  manifest-inspect → replace digest); compose comment retains the same
  release step.
- **P1-14 (android/hound):** emulator `cpus 2.0→4.0`, `mem 4g→8g` with
  host-requirement warning (fails closed via healthcheck on small hosts);
  healthcheck is now dual-probe (`adb devices` OR noVNC `:6080`, since
  `adb` on PATH is unverified upstream). Hound tracked decision recorded
  in compose + `SUPPORTING_SERVICES.md` D.3 (migrate to livegrep/zoekt
  preferred; vendor otherwise; digest frozen meanwhile).
- **Generator:** `ai-red-teamer` added to `EXPECTED_IDS` + `REPORTS_TO`
  (fixes the dies-at-HEAD `role set mismatch`), cap 1300000, plus four
  convergence fixes so output reproduces disk: canonical `small_model` +
  `compaction` emission/position, `fs:write` `.env` denies before the
  tail, dual skill roots, `timeout: 5000` default. Proven: scratch regen
  (`--root` overlay) reproduces ALL 51 `opencode.json` byte-identically.
  Charter prose is NOT regenerated in-repo (disk charters are
  hand-richer; a full run would regress them) — targeted disk edits
  applied instead; residual recorded in the generator docstring.

## 2. Registry evidence (commands + outputs, 2026-10-17)

- `npm view opencode-rea version` → `E404 Not Found` (plugin removed).
- `npm view @prevalentware/opencode-goal-plugin version` → `0.1.64`
  (pinned in Dockerfile).
- `npm view @morluto/rea-mcp version` → `E404 Not Found` (server removed).
- `npm view rea-agents version` → `6.5.0` ("one CLI and MCP server",
  registers via interactive `setup` — no verified headless stdio argv,
  hence removal rather than migration).
- `npm view` forks: `@executeautomation/playwright-mcp-server` 1.0.12
  (== pin), `@playwright/mcp` 0.0.83 (different line),
  `@upstash/context7-mcp` 4.4.2, `@modelcontextprotocol/server-postgres`
  0.6.2, `@cyanheads/git-mcp-server` 2.15.3 (all == pins).
- `pip index versions`: 9/10 pins resolve at pinned versions;
  `kafka-mcp-server` → "No matching distribution" (recorded residual).
- `curl 8.22.0` local: `--fail-with-body` supported (script requires
  curl ≥ 7.76, noted in-code).

## 3. Files created/modified (119 modified, 1 created, uncommitted)

- `roles/binary-reverse-eng/opencode/opencode.json` (plugin + `rea`
  server removed)
- `roles/binary-reverse-eng/AGENTS.md` (§4 REA removal + §6 plugin note)
- 8× dead-MCP charters (`mlops-serving-eng`, `observability-eng`,
  `sre-incident-eng`, `cache-streaming-eng`, `analytics-metrics-eng`,
  `load-stress-tester`, `k8s-orchestrator` — infra-pending notes)
- 50× `roles/*/AGENTS.md` + 50× `roles/*/.opencode/agents/*.md`
  (`NN/50` → `NN/51` only; ai-red-teamer already `/51`)
- `docker/Dockerfile` (goal-plugin pin/install/assert)
- `.github/workflows/docker-publish.yml` (`:latest` removed + rationale;
  plugin-resolution gate; goal-plugin assert)
- `docker-compose.prebuilt.yml` (HERETEK_IMAGE digest-only constraint)
- `docker-compose.sidecars.yml` (android 4.0/8g + dual healthcheck +
  host warning; hound decision)
- `scripts/seed-50-fleet.sh` (P1-3 fail-closed + P1-4 promotion)
- `scripts/generate-50-roles.py` (promotion + convergence + residual note)
- `scripts/smoke-test.sh` (pin gate zero-exception + 3 new gates + §4
  52-payload counts + mint-list comment)
- `roles-catalog/05|06|07|08_*.md` (8 infra-pending notes; Role 41
  REA/plugin removal incl. §6 fence; Role 51 fence `git_*` bare allow
  for table expansion), `ROLE_CATALOG_50.md` (Total $13,000.00/51)
- `README.md`, `AGENTS.md`, `Makefile`, `NOTES.md`, `.env.example`,
  `SUPPORTING_SERVICES.md` (counts, budget, HERETEK_IMAGE, piston/hound)
- This report: `docs/reports/wave-c-implementation.md` (new)

## 4. Test results (proof commands + outputs)

- `bash scripts/smoke-test.sh --check-only` → **514 passed, 0 failed,
  3 skipped** (Wave B baseline 513/0/3-era → +4 new gates
  [pin-zero-exception rewrite, dead-MCP, plugin-install, no-latest] +1
  §4 count update, zero regressions).
- `bash scripts/test-shim.sh` → **45 passed, 0 failed** (untouched).
- `shellcheck -S warning scripts/*.sh` → zero warnings; `bash -n` all OK.
- `bash scripts/seed-50-fleet.sh --dry-run` (dummy creds) → **52 docs**,
  `total ... 1300000 cents ... (cap 1300000 cents)`, **empty stderr**
  (no WARNING); ai-red-teamer payload: `security` / 30000¢ /
  `reportsTo <system-architect-id>` / XDG + `skip false`.
- `bash scripts/spec-gate.sh --check-only` → 7/0.
- `docker compose config -q` exit 0: default, prebuilt, web-research,
  devsec, ai-gateway, observability, mobile, core+ci, qa-testing+core,
  proxy+tailscale (dummy secrets; unset-secrets negative probe still
  fails naming the var). Rendered android: cpus 4.0 / mem 8g / dual
  healthcheck present.
- Generator parity: scratch `--root` regen → all 51 `opencode.json`
  byte-identical to disk (incl. ai-red-teamer after the fence fix).
- Watched-fail probes (each restored byte-identical afterwards):
  injected unpinned `evil-unpinned-pkg` + dead env → pin gate AND
  dead-MCP gate FAIL (exit 1, role named); re-added `opencode-rea`
  plugin → plugin gate FAILs naming it + Dockerfile set; appended live
  `value=latest` → no-latest gate FAILs; garbage body through
  find-agent/find-company parse → exit 1; live 500/PATCH-422 fixture
  server → old `curl` rc=0 (false-healthy, bug reproduced) vs new
  `-f`/`--fail-with-body` rc=22 with body on stderr.
- YAML validity of the edited workflow proven via `yaml.safe_load`
  (an earlier revision broke the `run: |` literal block with an
  unindented embedded script — caught by the parse check, rewritten
  with jq, re-proven).

## 5. Self-audit notes

- Fail-closed kept: unpublished artifacts removed, not wished into
  pins; no digest/tag invented (prebuilt stays an exact tag + verify
  step); gates fail on drift either way; seeder aborts with bodies on
  stderr; no `|| true`/TODO/dummy returns added; deny tails untouched
  (smoke §3 scans all 51); scripts keep `set -euo pipefail` +
  `--dry-run`/`--help`; no secrets in repo (dummies only, never echoed).
- Minimal diffs: role JSON changed only where the finding required
  (1 file); charter line-3 count bumps are mechanical; catalog edits
  mirror disk notes; historical files (`AUDIT_REPORT_FINDINGS.md`,
  `REMEDIATION_LOG.md` prior stages, `PROMPT_*.md`) untouched.
- Decisions: REMOVAL over vendoring for `opencode-rea`/`@morluto/rea-mcp`
  (nothing to vendor — both 404; rea-agents has no headless argv);
  `:latest` REMOVAL over scoped exception (exception would enshrine the
  mutable tag the invariant forbids); PROMOTION over quarantine for
  `ai-red-teamer` (catalog + Total line + prior residuals all anticipate
  it; quarantine would orphan Role 51 spec + charter); infra-pending +
  allowlist over sidecar construction for P1-2 (6 new pinned sidecars
  without a live stack to verify is the riskier change).
- NOT done / residuals (tracked, honest): live image build + publish
  gates (needs network/push rights + `paperclip:official-local`);
  prebuilt pull after a real `v1.0.0` push; charter-prose catalog
  back-sync before any full in-repo generator run (docstring warns);
  kafka-mcp doubly-dead package+sidecar; piston vendoring + hound
  migration (maintainer actions); full per-category segmentation;
  `redis://redis:6379` hostname (same dead class as P1-2, unfiled by
  the audit — flagged here, not changed).
- No commits, no merges, no subagents used.
