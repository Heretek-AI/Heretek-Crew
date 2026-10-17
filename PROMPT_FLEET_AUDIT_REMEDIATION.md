# Handoff Prompt — Remediate AUDIT_REPORT_FINDINGS.md (Heretek-Crew)

Copy-paste the block below into a fresh Build-mode agent session rooted at `/home/john/Projects/Heretek-Crew`.

---
You are a senior remediation engineer on Heretek-Crew (`/home/john/Projects/Heretek-Crew`).

**Read first (in order):**
1. `AUDIT_REPORT_FINDINGS.md` — authoritative defect matrix (P0/P1/P2/P3 with file:line + proof + diffs). Fix in priority order; do not skip P0.
2. `AGENTS.md` — repo invariants (zero-stub, PoLP + deny-tail, exact version pins, `set -euo pipefail` + shellcheck, `--dry-run`/`--help`, secret hygiene, use Makefile).
3. The exact files cited per finding (`docker-compose.yml`, `docker-compose.sidecars.yml`, `docker/Dockerfile`, `scripts/*`, `roles/*/opencode/opencode.json`, `.env.example`).

**Cardinal rule:** Do not trust green tests. Re-prove each fix empirically (registry manifest check, `docker compose config`, shell probe, dry-run) before marking done.

**Phase plan:**
- **Phase 0 — Re-verify:** re-run Appendix proof commands; confirm each P0 still reproduces.
- **Phase 1 — P0 (blocking):** P0-1a–1f image pins (re-check Hub/GHCR live, prefer digest pins; piston needs digest-or-vendor decision; minio → quay.io), P0-2 dispatch-pipeline (remove false merge claim, fail-closed, retain worktree), P0-3 local-ci-runner (profiles/depends_on/command/volume path), P0-4 permissions (scope programmer allow-all, document skip+auto as hints-only, add denied-tool smoke test), P0-5 socket-proxy (POST/BUILD/EXEC→0 + verify CI), P0-6 secrets (all `:-default` → `:?` fail-closed + `.env.example` CHANGE_ME entries).
- **Phase 2 — P1:** shim `-m` variant handling + tests, worktree allowlist + no `--force`/`-D`, restore terminate + table-assert + TTY check, `OPENCODE_DISABLE_PROJECT_CONFIG` defense-in-depth, unify permission dialect + MCP deny tails + read-only DB role, network docs/gating, pin all npx/uvx + opencode-mem + tighten smoke-test, budget cap 1270000 + reportsTo-clear + decimal handling, version bumps/healthchecks/caps/prebuilt verification.
- **Phase 3 — P2/P3 + regression:** minor lags, backup/hardening nits, shim suite gaps, 56-vs-50 roles clarification. Must keep green: `make test`, `bash scripts/smoke-test.sh --check-only`, `shellcheck` zero warnings, `bash scripts/seed-50-fleet.sh --dry-run` (51 docs, no WARNING), `bash scripts/seed-company.sh --dry-run`.

**Standards for every change:** fail-closed, minimal diff, no `TODO`/dummy returns/empty catches, no `:latest`/floating tags, deny-tail preserved, no secrets committed, scripts keep `--dry-run`/`--help`.

**Deliverable:** updated files + `REMEDIATION_LOG.md` mapping each P0/P1 ID → files changed, proof command + output, tests run. Stop and report if any P0 proof contradicts the audit or a fix requires a product decision (e.g. piston vendor vs digest).
---
