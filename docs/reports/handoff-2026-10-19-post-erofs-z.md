# HANDOFF — Heretek-Crew post-EROFS/:z, fleet checklist green (2026-10-19)

## Role

You are continuing work on Heretek-Crew (`/home/john/Projects/Heretek-Crew`), a self-hosted Paperclip + OpenCode v2 autonomous agent fleet. Read `AGENTS.md` first — its invariants (zero-stub, least privilege, `set -euo pipefail`, shellcheck zero warnings, `--dry-run`/`--help` on state-changing scripts, no `:latest`) are non-negotiable. Production changes go through the triad: `agency-programmer` → `agency-qa` → `agency-drift-guard`, in a git worktree, merged `--ff-only`, then pushed.

## Current state (verified)

- Repo main = `5d18da3`, pushed (0 unpushed), clean except untracked `docker-compose.override.yml` (operator's local prebuilt-image override — leave it) + untracked `heretek-rigs/` (operator's, appeared this session — leave it).
- Stack healthy: `heretek-crew-paperclip-1`, `heretek-crew-postgres-1` (both Up). Image `ghcr.io/heretek-ai/heretek-crew:sha-7cf1847` via `HERETEK_IMAGE`.
- EROFS/:z wave DONE on main: `1bf2adf` (tmpfs+ro restores+:z) → `bbf3e5d` (ordered long-syntax + smoke §2b gate, Drift PASS) → `c549544` (mode decimal-trap `1777`→`0o1777`, Drift PASS) → `85a28e5` + `5d18da3` (evidence). Live container proof: `stat` 1777 `drwxrwxrwt`, `docker exec -u node touch service.json.tmp` OK, `df` 16M, file ro preserved, tmpfs 51 / filebinds 51, `ls -Z` `system_u:container_file_t` (Enforcing, no chcon).
- Fleet config (live, in Paperclip DB — do not change): Company Heretek Autonomous Fleet = `d2f411ef-0b17-467f-8540-a17c603859d9`. 51/51 agents model `opencode-go/muse-spark-1.3-contributor`; `OPENCODE_GO_API_KEY` = `secret_ref` active; `PAPERCLIP_OPENCODE_SMALL_MODEL=opencode-go/glm-5.3-flash`.
- Agent statuses: 48 idle + 3 budget-paused (exec-director + tpm-scrum-lead + tech-docs-lead, all `holds=['budget']` — DO NOT clear, DO NOT resume budget-held agents). `system-architect` closing status `running` after proof turns (was `idle`) — verify it settles.
- Prior billed proofs: `2bd708c9` (14530/203 reported) + `da3c48bc` (15374/497 reported), both `system-architect` succeeded, no EROFS (vs `12be42ed` 0-token EROFS death). `enrich-fleet-verify`: 51 pass, 0 failed.
- Issues: #1 (:z) CLOSED, #4 (EROFS) CLOSED this wave. OPEN: #2 (cut `v1.0.0` tag so prebuilt `:1.0.0` pin resolves — `git tag v1.0.0 && git push origin v1.0.0`, wait Publish, `manifest inspect`) and #3 (fleet operational checklist — provider half proven on Go key; remainder is exec-director smoke end-to-end, budget-blocked).
- Gates: `spec-gate.sh --check-only` 7/7, smoke §2b EROFS gate PASS, `shellcheck` clean, `test-shim` 57/57 (note: AGENTS.md still cites 54/54 — doc drift, one-line fix candidate). Smoke `--check-only` overall 548/1: sole FAIL is pre-existing environmental `backup --plaintext-ok` (succeeds with live stack, expects no stack) — gate-fix candidate so check-only is green with stack up.
- Stale worktree `~/.local/share/opencode/worktree/094e37/audit-remediation-wave` (`bed36bf`) — unrelated, leave it.

## Blocker context (no longer blocking, record only)

Every probe previously failed `opencode_models_discovery_failed` + `hello_probe_failed` via `FileSystem.writeFile (/roles/…/service.json.tmp): EROFS` on `./roles:/roles:ro` (line 158). Fixed as above. Mode trap lesson: YAML decimal `1777` = octal `3361` (node write denied); `0o1777` renders `1023` = octal `1777` correct; string `"1777"` rejected by compose schema (uint32).

## Out of scope / prohibitions

No `v1.0.0` tag unless explicitly tasked (#2). No verify-script retry feature. No `roles/` content edits without a wave. NEVER run `seed-50-fleet.sh` (reverts models to `anthropic/claude-sonnet-4-5`). No secret rotate (Go key live — DO NOT re-rotate). No clearing budget holds. No `up --force-recreate` from a worktree (host paths differ — live recreate only from main checkout with real `.env`).

## Fleet configuration (live, in Paperclip DB — do not change)

Agent token: `~/.paperclip/auth.json` → `credentials["http://localhost:3100"].token`. Read programmatically, never print it.

Scripts (all shellcheck-clean, all `--dry-run`/`--help`/`--only`): `scripts/enrich-fleet-verify.sh`, `scripts/enrich-fleet-model-env.sh` (`--dry-run` ONLY — live ensure needs a plaintext key you must never handle), `scripts/first-agent-run.sh` (allowlist: exec-director default target + tech-docs-lead + system-architect idle fallbacks; paused fallback aborts fail-closed; exec-director resume is a 200-no-op under its budget hold).

## Verified-correct API shapes (don't re-derive)

`GET /api/companies/:cid/agents` (51 list) · `GET /api/agents/:id` · `POST /api/agents/:id/wakeup` `{source:on_demand, triggerDetail:manual, reason, forceFreshSession:true, idempotencyKey}` → 202 · `GET /api/companies/:cid/heartbeat-runs?agentId=&limit=` (poll) · `GET /api/heartbeat-runs/:id` + `/log` + `/events` + `/provider-trace`. `is_terminal_status` includes `succeed|succeeded`.

## Operational gotchas

- Key hygiene: a Go-pattern key was pasted into chat twice this session and the operator said "revoke at the end" — assume exposed until rotation is confirmed. NEVER accept/handle/print/write secret values; future keys arrive via env (`.env`, gitignored) only. This wave needs NO key. Verify rotation happened before trusting old material.
- SELinux: Enforcing; `:z` on all host binds is the durable fix (no chcon step needed — `ls -Z` shows `system_u:container_file_t` post-recreate).
- `/tmp` inodes: use `TMPDIR=<repo>/.tmp-run`, delete afterwards. Origin trust: use `http://localhost:3100`, not `127.0.0.1`. Port 49374: orphaned `opencode.exe serve` → find via `/proc/net/tcp` hex `C0DE`, kill, retry.
- Tech-docs-lead + exec-director + tpm remain budget-paused: either leave (default) or document; never resume a budget-held agent to force a turn — use idle `system-architect` fallback for registry/write proofs.

## Suggested next waves (pick one)

- A. #2 tag wave (no triad needed): `git tag v1.0.0 && git push origin v1.0.0`, wait Publish → GHCR, `docker manifest inspect …:1.0.0`, verify prebuilt pull with stock `.env.example`.
- B. Cleanup wave (triad, compose+scripts only): fix `backup --plaintext-ok` gate to pass with live stack + update AGENTS.md 54→57 + confirm `system-architect` settled to idle.
- C. #3 amendment (no key handling): rewrite the stale `OPENCODE_API_KEY`/shared-connection checklist to the proven Go `secret_ref` reality, OR park it on the budget decision for the exec-director smoke.

## Health / close-loop commands

```bash
cd /home/john/Projects/Heretek-Crew
TOKEN=$(python3 -c "import json;print(json.load(open('$HOME/.paperclip/auth.json'))['credentials']['http://localhost:3100']['token'])")
mkdir -p .tmp-run && TMPDIR=$PWD/.tmp-run PAPERCLIP_URL=http://localhost:3100 PAPERCLIP_TOKEN="$TOKEN" bash scripts/enrich-fleet-verify.sh 2>&1 | tail -n 3   # expect 51 pass, 0 failed
TMPDIR=$PWD/.tmp-run PAPERCLIP_URL=http://localhost:3100 PAPERCLIP_TOKEN="$TOKEN" bash scripts/first-agent-run.sh --only system-architect 2>&1 | tail -n 3   # expect exit 0, new succeeded runId with billed tokens (tech-docs-lead stays budget-paused — do not force it)
rm -rf .tmp-run
```
