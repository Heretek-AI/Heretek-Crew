# Wave E Stage 4 Implementation Report — P2 Medium + P3 Low Remediation (P2-1…P2-16, P3-1…P3-10)

**Stage ID:** Wave E Stage 4 (P2/P3) — `AUDIT_REPORT_FINDINGS.md` lines 135-168 + cleared lines 171-178 (not re-filed)
**Date:** 2026-10-17 | **Branch:** `wave-e-audit-remediation` (worktree `/tmp/opencode/heretek-wave-e`)
**Source of truth:** `AUDIT_REPORT_FINDINGS.md` + task envelope (TARGETS + ACCEPTANCE verbatim)
**Status:** complete, verified empirically. Changes left UNCOMMITTED for QA/Drift-Guard. No commits, no merges, no subagents used.
**Base preserved:** Wave E Stage 1–3 uncommitted changes intact — this stage builds on top (Stage 3's 6 edited files + prior carryover all still present; counts re-proven, not trusted).
**Network:** available in this env — all digests below resolved live via registry `Docker-Content-Digest` headers (Hub anonymous token flow, GHCR anonymous token flow), never invented offline, never `:latest`.

## 1. Summary of deliverables (per finding)

- **P2-1 (shim `--variant` edges):** code fixed + 8 tests, TDD red→green. Empty `--variant=` no longer clobbers a prior non-empty variant (last empty dropped, prior kept); dash-leading handling normalized by form and pinned (space-form `--variant -high` = flag boundary, token passes through for the real binary to reject loudly; `--variant=-high` = explicit value, merges); `resolve_real_bin` requires `-f` alongside `-x` (a +x directory now exits clean 127, not 126); whitespace-only `OPENCODE_API_KEY`/`OPENCODE_GO_API_KEY` count as empty on both sides (neither blocks the fallback nor exports a whitespace key). Red proof before the fix: 50 passed / 4 failed (8i, 2× whitespace, dir-126); after: **54/54**.
- **P2-2 (valueless `--dir` swallows prompt):** verified already-closed — shim drops only the flag and preserves the token (`test-shim` 15a0 + acceptance case), smoke §5 re-asserts. No change.
- **P2-3 (postgres floating minor):** PINNED live — `17-alpine` == `17.11-alpine` (both tags' `Docker-Content-Digest` identical: `sha256:b0f956…`) → `postgres:17.11-alpine@sha256:b0f956…`, zero behavior change, quarterly bump plan in-file. Dockerfile pin comment synced.
- **P2-4 (Paperclip pseudo-tag):** verified present — SHA procedure (`PAPERCLIP_SOURCE_COMMIT` + rev-parse) in Dockerfile + NOTES.md, semver/digest preference in compose. No tag invented. No change.
- **P2-5 (ghidra major behind):** BUMPED live — `11.2` → `12.1.4@sha256:b24791…` (Hub 12.1.4 verified live; the only ordered major bump this stage). Factually-wrong "one minor behind" comment corrected; healthcheck strengthened to dual probe (`:1337` first, `pgrep -f ghidra` fallback — strictly stronger, no previously-healthy state can newly fail); `:1337` liveness verify recorded for first devsec boot.
- **P2-6 (mitmproxy major behind):** digest-pinned current (`11.0.2@sha256:92ab9e…`, zero behavior change) + quarterly 12.x plan citing verified-live `12.2.3` (major-proxy behavior NOT claimed from here).
- **P2-7 (mailpit/wiremock behind):** quarterly plan comments citing verified-live targets (`v1.31.6`, `3.13.2-alpine`); no blind bumps (test-mock severity).
- **P2-8 (firecrawl mutable):** PINNED live — `2.10.19@sha256:50446c…` (tag@digest, tag kept as provenance) + quarterly plan; opaque `nuq-postgres` / `playwright-service` digests annotated (P3-1).
- **P2-9 (`act` floating + EOL):** PINNED live — `act-22.04@sha256:f5f5c2…` + 24.04 migration plan citing verified-live `act-24.04` digest (re-resolve at migration time; host-`act` re-verify; proxy stays GET-only).
- **P2-10 (32.6-CPU budget unasserted):** NEW smoke gate — asserts every image-bearing service carries `cpus`+`mem_limit`, pins the effective per-profile matrix (always-on 3.0/5120MB + profile; full stack 32.6 CPU / 51840MB), fails closed on any resourcing/profile drift with recomputed values. Co-scheduling premise (profile gating + Makefile mobile guard) documented in-gate.
- **P2-11 (android resourcing + healthcheck):** verified present — 4.0 CPU / 8g + host-requirement warning + dual `adb`/`noVNC :6080` probe. No change.
- **P2-12 (backup/restore):** verified present — CLI snapshot across `.env` sourcing, `*.age` in listing, `-${RANDOM}.sql.gz[.age]` collision form (== the ordered `OUTFILE` shape), smoke §5b gates green. ADDED the ordered backup→restore round-trip live gate (`§8b`, opt-in `BACKUP_ROUNDTRIP_LIVE=1`, `--file`+`--yes` CLI-flag path, scratch `BACKUP_DIR`); SKIPs in check-only (7th SKIP).
- **P2-13 (prebuilt + latest):** verified present — no `latest` minted (smoke gate), `:1.0.0` semver pin, `v1.0.0` tag procedure + digest-pin plan + `HERETEK_IMAGE` digest-only constraint in-file. No change.
- **P2-14 (publish gate):** verified present — fixture argv gate (`#variant` + exactly-one `--auto`, no `--dir` leak), harness plugin-load gate (fails on the empty-string `Die`), pre-push `linux/arm64` QEMU smoke. ADDED a smoke static gate pinning all three in the workflow (a gate deletion now fails closed).
- **P2-15 (redis/rabbit/jaeger residue):** recorded — 7.4 LTS deliberate (CVE-2025-49844 fixed; 8.x needs client-compat first) + per-service-passwords-at-rotation on `searxng-redis`; rabbitmq 1g consideration + jaeger `COLLECTOR_OTLP` boot-verify already in-file (re-verified); neo4j heap-tight OOM-monitor note added; hound `:6081` vs android `:6080` re-verified (smoke gate green); gotenberg `--chromium-restart-after` log-confirm note added.
- **P2-16 (seed O(n²) + ROLE_DIR):** verified present — fetch-once with miss-refresh + post-create refresh; ambient-`ROLE_DIR` pre-guard + in-python `ROLE_DIR == iterated role` assert (double guard). No change.
- **P3-1..P3-10:** P3-1 digest comments added (nuq/playwright); P3-2 no-op `true` healthchecks added to `semgrep` + `local-ci-runner`; P3-3 guest→env creds re-verified (smoke gate green); P3-4 Caddyfile tracked comment re-verified; P3-5 `DOCKER_HOST` ×2 re-verified; P3-6 sabotage piston advisory re-verified (charter carries the exact-host-pin + sandbox-only-enforcement note); P3-7 `stat -L` device+inode fallback re-verified (+ test); P3-8 `.gitkeep` re-verified + NEW tracked-gate; P3-9 signing-secret `:?` re-verified (smoke gate green); P3-10 `--force` rationale re-verified (Dockerfile). Nothing duplicated.
- **CLEARED (lines 171-178):** not re-filed, not regressed — shim core 2.1–2.6 still green inside the 54; loopback/caddy/tailscale/socket-proxy posture gates green; zero `:latest` code pins; zero committed secrets.
- **Docs sync:** `SUPPORTING_SERVICES.md` mirrored pins updated (firecrawl/mitmproxy/ghidra tag@digest) + watchlist rewritten with `[RESOLVED]` markers and verified-live quarterly targets; `AGENTS.md` suite count 46→54.

## 2. Files created / modified

- `scripts/opencode-shim.sh` — P2-1: empty-`--variant=` no-clobber, `-f` file guards, whitespace-trimmed key fallback, header rule-2 doc. No other rewrite rule touched.
- `scripts/test-shim.sh` — 46 → 54: §8h (dup variant last-wins), §8i (trailing empty keeps prior), §8j (empty-then-value merges), §8k/§8l (dash-leading both forms), §20b (directory override → 127), §20 whitespace ×2.
- `docker-compose.yml` — P2-3 postgres `17.11-alpine@sha256:b0f956…` + plan comment; header pin line synced.
- `docker-compose.sidecars.yml` — P2-5 ghidra bump + dual healthcheck; P2-6 mitmproxy digest + plan; P2-7 mailpit/wiremock plans; P2-8 firecrawl digest; P3-1 nuq/playwright comments; P2-9 act digest + plan; P2-15 redis decision + neo4j/gotenberg notes; P3-2 two no-op healthchecks.
- `scripts/smoke-test.sh` — postgres pin update; 5 digest-pin asserts + 5 predecessor-absence asserts; P2-14 workflow-gate assert; P3-8 gitkeep tracked assert; P2-10 budget-matrix gate; §8b P2-12 round-trip live gate + check-only SKIP.
- `docker/Dockerfile` — postgres pin comment synced (P2-3). `--force` rationale, harness plan untouched.
- `SUPPORTING_SERVICES.md` — mirrored pins + watchlist `[RESOLVED]` rewrite.
- `AGENTS.md` — suite count 46→54 (two spots).
- `docs/reports/wave-e-stage4-implementation.md` — this report (new).
- `REMEDIATION_LOG.md` — Wave E Stage 4 entry appended (prior Waves + Stages 1–3 untouched).

Untouched by design (verified already-correct, re-proven empirically): `scripts/seed-50-fleet.sh`, `scripts/generate-50-roles.py`, `scripts/backup-db.sh`, `scripts/restore-db.sh`, `scripts/worktree-manager.sh`, `scripts/dispatch-pipeline.sh`, `scripts/spec-gate.sh`, `docker-compose.prebuilt.yml`, `.github/workflows/docker-publish.yml`, `.github/workflows/ci.yml`, `Makefile`, `README.md`, `.env.example`, all 51 `roles/*/opencode/opencode.json`, `PROMPT_ADVERSARIAL_FLEET_AUDIT.md`, `NOTES.md`.

## 3. Test results (acceptance criteria, all pass in worktree)

- `bash scripts/test-shim.sh` → **54 passed, 0 failed** (exit 0; 46 Stage-3 baseline + 8 new P2-1; TDD red 50/4 pre-fix → green 54/0 post-fix).
- `bash scripts/smoke-test.sh --check-only` → **542 passed, 0 failed, 7 skipped** (exit 0; 529 Stage-3 baseline + 13 new gates, zero regressions; 7th SKIP = P2-12 round-trip).
- `shellcheck -S warning scripts/*.sh` → zero warnings (exit 0). `bash -n` clean on both edited scripts.
- `bash scripts/spec-gate.sh --check-only` → **7 passed, 0 failed** (exit 0).
- `bash scripts/seed-50-fleet.sh --dry-run` (provisioned dummies) → **52 `"name"` keys, total 1300000 == cap 1300000, empty stderr**, exit 0.
- `docker compose config -q` → exit 0 on `default`, prebuilt, `web-research`, `devsec`, `devsec+core`, `mobile`, `core+ci`, `qa-testing+core`, `proxy+tailscale`; all 5 new tag@digest pins render verbatim.
- Registry proofs (all live, 2026-10-17): postgres `17-alpine` ≡ `17.11-alpine` ≡ `sha256:b0f956…`; ghidra `12.1.4` ≡ `sha256:b24791…`; mitmproxy `11.0.2` ≡ `sha256:92ab9e…`, `12.2.3` exists; firecrawl `2.10.19` ≡ `sha256:50446c…`; `act-22.04` ≡ `sha256:f5f5c2…`, `act-24.04` ≡ `sha256:62d572…`; mailpit `v1.31.6`, wiremock `3.13.2-alpine` exist. Method: registry `Docker-Content-Digest` response headers (canonical, not recomputed hashes).
- Sweeps: no `:latest`/`@latest` code pins (only pre-existing prose comments covered by the pin gate); no committed secrets (`secrets/` holds only `.gitkeep`); no TODO/dummy/`|| true`/empty-catch added; `git status --short` shows only intended files.
- `git status --short` → only `M AGENTS.md`, `M SUPPORTING_SERVICES.md`, `M docker-compose.sidecars.yml`, `M docker-compose.yml`, `M docker/Dockerfile`, `M scripts/opencode-shim.sh`, `M scripts/smoke-test.sh`, `M scripts/test-shim.sh` (+ Stage 1–3 carryover, + 4 stage reports) — no other files touched.

## 4. Self-audit notes

- Fail-closed everywhere: empty variant never silently lost; dash-leading space-form never silently merged (loud downstream error instead); directory binary → clean 127; whitespace keys never exported; digest pins are tag@digest (digest enforces, tag documents); budget/round-trip/publish gates fail on drift and SKIP (never fake-pass) without a live stack; quarterly bumps stay comments pointing at verified-live targets.
- Minimal diff: one real behavior fix (shim variant merge), one ordered major bump (ghidra, per task), four zero-change digest pins, one strictly-stronger healthcheck, two no-op healthchecks, comments + gates otherwise; zero behavioral delta to seeds, roles, networks, ports, permissions, workflows.
- Deliberately NOT done (recorded, not regressed): ghidra `:1337` liveness + mitmproxy 12.x behavior + act-24.04 migration + mailpit/wiremock bumps (all need live-boot verification on their profiles); piston network move + secret-proxy front; `DATABASE_URL` password-file migration; hound/piston/minio vendoring moves; dead-MCP sidecar builds vs declaration deletes; full `BACKUP_ROUNDTRIP_LIVE=1` + `HARNESS_LIVE_GATE=1` + canary + scrub live runs (all need `make up`).
- No commits, no merges, no subagents used. Changes left uncommitted for QA/Drift-Guard.
