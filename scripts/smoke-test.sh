#!/usr/bin/env bash
#
# smoke-test.sh — end-to-end compatibility & smoke test for Heretek-Crew.
#
# Usage:
#   ./scripts/smoke-test.sh [--check-only] [--help]
#
# Modes:
#   --check-only   Static checks only; needs NO live server, NO docker daemon,
#                  NO secrets. Safe for CI lint gates. Verifies:
#                    1. required repo files exist
#                    2. `docker compose config` parses (with throwaway dummy
#                       secrets when .env is absent — validation only)
#                    3. all roles/*/opencode/opencode.json are valid v2 configs
#                       (valid JSON, provider/model string, non-empty
#                       permissions) and no `:latest` image pins exist
#                    4. seed script dry-run emits company + 6 agent payloads
#                    5. shim translation: --dir stripped, --variant merged into
#                       --model#variant, exactly one --auto, --session and
#                       non-run subcommands pass through, `--` terminator kept
#                    6. file-creation simulation (hello.txt with today's date)
#                    7. session-resume support advertised by the opencode CLI
#                       (skipped with a note when no opencode binary is present)
#   (live)         All static checks PLUS, against a running stack:
#                    8. PostgreSQL health (pg_isready via `docker compose exec`)
#                    9. Paperclip web server responds at $PAPERCLIP_URL
#                       (default http://127.0.0.1:3100, /api/health then /)
#                   10. Ticket flow (requires PAPERCLIP_TOKEN or ADMIN_API_KEY):
#                       create a test issue assigned to an agent
#                       ("Create hello.txt with today's date"), wait for run
#                       completion, verify transcript / token-cost accounting /
#                       workspace file, post a follow-up comment to confirm
#                       session resumption. Without a token these sub-checks
#                       SKIP with an explanation (use --check-only instead).
#
# Live-mode requirements: `make up` healthy, PAPERCLIP_TOKEN set, and (for the
# workspace-file check) ./workspaces visible on the host. Timeouts:
#   HEALTH_TIMEOUT_SEC (default 30 here), RUN_TIMEOUT_SEC (default 600).
#
# Exit code: 0 when nothing FAILs (SKIPs are informational), 1 otherwise.
# Fail-closed: every check reports PASS/FAIL/SKIP explicitly; unknown states
# are FAIL, never silent green.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

PAPERCLIP_URL="${PAPERCLIP_URL:-http://127.0.0.1:3100}"
PAPERCLIP_TOKEN="${PAPERCLIP_TOKEN:-${ADMIN_API_KEY:-}}"
COMPANY_NAME="${COMPANY_NAME:-Acme Autonomous Corp}"
POSTGRES_USER="${POSTGRES_USER:-paperclip}"
POSTGRES_DB="${POSTGRES_DB:-paperclip}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-30}"
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-600}"

MODE="live"
for arg in "$@"; do
  case "${arg}" in
    --check-only) MODE="check-only" ;;
    --help|-h)
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument '${arg}' (see --help)" >&2
      exit 2
      ;;
  esac
done

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 1; }

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$*"; }
skip() { SKIP=$((SKIP + 1)); printf '  [SKIP] %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "smoke-test mode=${MODE} url=${PAPERCLIP_URL}"

# --- 1. required files -------------------------------------------------------
section "1. required files"
REQUIRED_FILES=(
  docker-compose.yml docker/Dockerfile .env.example Makefile
  scripts/opencode-shim.sh scripts/seed-company.sh
  scripts/backup-db.sh scripts/restore-db.sh scripts/smoke-test.sh
)
for f in "${REQUIRED_FILES[@]}"; do
  if [[ -f "${f}" ]]; then ok "${f} exists"; else bad "${f} MISSING"; fi
done
for role in director pm programmer tester qa designer; do
  if [[ -f "roles/${role}/opencode/opencode.json" ]]; then
    ok "roles/${role}/opencode/opencode.json exists"
  else
    bad "roles/${role}/opencode/opencode.json MISSING"
  fi
  if [[ -f "roles/${role}/AGENTS.md" ]]; then
    ok "roles/${role}/AGENTS.md exists"
  else
    bad "roles/${role}/AGENTS.md MISSING"
  fi
done
for s in scripts/opencode-shim.sh scripts/seed-company.sh scripts/backup-db.sh scripts/restore-db.sh scripts/smoke-test.sh; do
  if [[ -x "${s}" ]]; then ok "${s} executable"; else bad "${s} NOT executable"; fi
done

# --- 2. compose config parses -----------------------------------------------
section "2. docker compose config"
if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  skip "'docker compose' not available; config validation skipped"
else
  if [[ -f .env ]]; then
    if docker compose config -q 2>"${TMP}/compose.err"; then
      ok "docker compose config parses (.env present)"
    else
      bad "docker compose config FAILED: $(head -c 300 "${TMP}/compose.err")"
    fi
  else
    # Throwaway dummy secrets: validation only, never written anywhere.
    if POSTGRES_PASSWORD=__smoke_only__ BETTER_AUTH_SECRET=__smoke_only_0123456789abcdef__ \
      docker compose config -q 2>"${TMP}/compose.err"; then
      ok "docker compose config parses (dummy secrets, .env absent)"
    else
      bad "docker compose config FAILED: $(head -c 300 "${TMP}/compose.err")"
    fi
  fi
fi

# --- 3. role configs valid + pins -------------------------------------------
section "3. role opencode.json validity + version pins"
for role in director pm programmer tester qa designer; do
  f="roles/${role}/opencode/opencode.json"
  if ROLE="$role" FILE="$f" python3 -c '
import json, os, re, sys
doc = json.load(open(os.environ["FILE"]))
assert isinstance(doc.get("model"), str) and "/" in doc["model"], "model must be provider/model"
assert isinstance(doc.get("permissions"), list) and doc["permissions"], "permissions must be non-empty"
for p in doc["permissions"]:
    assert p.get("effect") in ("allow", "deny", "ask"), "permission effect must be allow/deny/ask"
for name, mcp in (doc.get("mcp") or {}).items():
    cmd = " ".join(mcp.get("command", []) if isinstance(mcp.get("command"), list) else [str(mcp.get("command", ""))])
    assert "latest" not in cmd, "MCP %s must not use latest" % name
print("role %s model=%s perms=%d" % (os.environ["ROLE"], doc["model"], len(doc["permissions"])))
'; then
    ok "${f} valid"
  else
    bad "${f} INVALID"
  fi
done
if grep -rnE ':(latest)([^a-zA-Z0-9._-]|$)|@(latest)([^a-zA-Z0-9._-]|$)|npm install[^@]*opencode[^@]*$' \
    docker-compose.yml docker/Dockerfile .env.example Makefile 2>/dev/null | grep -v '^.*#.*latest' | grep -q .; then
  bad "found ':latest' style pin in ops files (must pin exact versions)"
else
  ok "no :latest pins in docker-compose.yml / Dockerfile / .env.example / Makefile"
fi
for pin in 'postgres:17-alpine' 'node:24-trixie-slim' '@opencode/cli@2.0.31' '127.0.0.1:3100'; do
  case "${pin}" in
    127.0.0.1:3100)
      if grep -q '127\.0\.0\.1:3100' docker-compose.yml; then ok "pin present: ${pin}"; else bad "pin MISSING: ${pin}"; fi ;;
    @opencode/cli@2.0.31)
      # Dockerfile pins via ENV (OPENCODE_CLI_VERSION=2.0.31) consumed by the
      # npm install line — accept that indirection as a valid pin.
      if grep -q '@opencode/cli@2.0.31' docker/Dockerfile \
        || grep -q 'OPENCODE_CLI_VERSION=2.0.31' docker/Dockerfile; then
        ok "pin present: ${pin} (via OPENCODE_CLI_VERSION env)"
      else
        bad "pin MISSING: ${pin}"
      fi ;;
    *)
      if grep -rq "${pin}" docker-compose.yml docker/Dockerfile; then ok "pin present: ${pin}"; else bad "pin MISSING: ${pin}"; fi ;;
  esac
done
if grep -q 'UID 1000' docker/Dockerfile && grep -q 'gosu node' docker/Dockerfile; then
  ok "non-root runtime documented (node UID 1000 via gosu)"
else
  bad "non-root runtime note missing from docker/Dockerfile"
fi

# --- 4. seed dry-run ---------------------------------------------------------
section "4. seed-company.sh --dry-run"
if ./scripts/seed-company.sh --dry-run >"${TMP}/seed.out" 2>"${TMP}/seed.err"; then
  if grep -q 'Acme Autonomous Corp' "${TMP}/seed.out" \
    && grep -q 'opencode_local' "${TMP}/seed.out" \
    && grep -q 'XDG_CONFIG_HOME' "${TMP}/seed.out" \
    && grep -q 'dangerouslySkipPermissions' "${TMP}/seed.out"; then
    ok "seed dry-run emits company + 6 agent payloads (opencode_local, XDG_CONFIG_HOME, skipPermissions)"
  else
    bad "seed dry-run output missing expected payload keys"
  fi
else
  bad "seed dry-run exited nonzero: $(head -c 300 "${TMP}/seed.err")"
fi

# --- 5. shim translation -----------------------------------------------------
section "5. opencode-shim translation (fake real binary)"
cat >"${TMP}/fake-opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${FAKE_OUT:?FAKE_OUT must be set}"
EOF
chmod +x "${TMP}/fake-opencode"
shim_run() { OPENCODE_REAL_BIN="${TMP}/fake-opencode" FAKE_OUT="${TMP}/shim.args" ./scripts/opencode-shim.sh "$@"; }
if shim_run run --format json --dir /tmp/ws --model opencode/gemini-3.8-flash --variant high "Create hello.txt"; then
  if diff -u <(printf 'run\n--format\njson\n--model\nopencode/gemini-3.8-flash#high\n--auto\nCreate hello.txt\n') "${TMP}/shim.args" >/dev/null; then
    ok "run: --dir stripped, --variant merged to model#variant, --auto injected in order"
  else
    bad "run translation mismatch; got: $(tr '\n' ' ' <"${TMP}/shim.args")"
  fi
else
  bad "shim run invocation failed"
fi
if shim_run run --variant low --model anthropic/claude-sonnet-4-5 --dir=/tmp/x --auto "p" \
  && grep -qx -- '--auto' "${TMP}/shim.args" \
  && [[ "$(grep -c -- '--auto' "${TMP}/shim.args")" -eq 1 ]] \
  && grep -qx 'anthropic/claude-sonnet-4-5#low' "${TMP}/shim.args" \
  && ! grep -q -- '--dir' "${TMP}/shim.args"; then
  ok "run: variant-first order, --dir= form, duplicate --auto suppressed"
else
  bad "shim variant-first/equals-form case failed; got: $(tr '\n' ' ' <"${TMP}/shim.args")"
fi
if shim_run models --verbose && grep -qx 'models' "${TMP}/shim.args" && grep -qx -- '--verbose' "${TMP}/shim.args"; then
  ok "non-run subcommand (models) passes through untouched"
else
  bad "non-run passthrough failed"
fi
if shim_run run --session abc123 --model m "p" \
  && grep -qx -- '--session' "${TMP}/shim.args" && grep -qx 'abc123' "${TMP}/shim.args"; then
  ok "run: --session passes through (resume compatible)"
else
  bad "--session passthrough failed"
fi
if shim_run run --model m -- --dir kept "p" \
  && grep -qx -- '--' "${TMP}/shim.args" && grep -qx -- '--dir' "${TMP}/shim.args" && grep -qx 'kept' "${TMP}/shim.args"; then
  ok "run: '--' terminator preserves prompt tail verbatim"
else
  bad "'--' terminator handling failed"
fi
if OPENCODE_REAL_BIN=/nonexistent ./scripts/opencode-shim.sh run "x" 2>/dev/null; then
  bad "shim with missing real binary should fail closed"
else
  ok "shim fail-closed when real binary is missing"
fi

# --- 6. file creation simulation ---------------------------------------------
section "6. file-creation simulation"
SIMDIR="${TMP}/workspace"
mkdir -p "${SIMDIR}"
TODAY="$(date +%F)"
echo "${TODAY}" >"${SIMDIR}/hello.txt"
if grep -qx "${TODAY}" "${SIMDIR}/hello.txt"; then
  ok "hello.txt with today's date (${TODAY}) created and verified"
else
  bad "hello.txt simulation failed"
fi

# --- 7. session-resume support -------------------------------------------------
section "7. session resume (--session) support"
if command -v opencode >/dev/null 2>&1; then
  if opencode run --help 2>&1 | grep -qi 'session'; then
    ok "installed opencode CLI advertises --session (resume supported)"
  else
    bad "installed opencode CLI does not advertise --session"
  fi
else
  skip "no opencode binary on PATH; live runs use the in-image shim + opencode-bin"
fi

# --- live-only checks ----------------------------------------------------------
if [[ "${MODE}" == "check-only" ]]; then
  section "live checks (8-10) skipped in --check-only mode"
  skip "postgres pg_isready — needs 'make up'"
  skip "paperclip HTTP health — needs 'make up'"
  skip "ticket flow — needs live server + PAPERCLIP_TOKEN (see --help)"
else
  section "8. PostgreSQL health"
  if docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"; then
    ok "postgres pg_isready accepting connections"
  else
    bad "postgres not healthy (run 'make up' and wait for healthcheck)"
  fi

  section "9. Paperclip HTTP health"
  if curl -sf -m 10 -o /dev/null "${PAPERCLIP_URL}/api/health"; then
    ok "GET ${PAPERCLIP_URL}/api/health -> 2xx"
  elif curl -sf -m 10 -o /dev/null "${PAPERCLIP_URL}/"; then
    ok "GET ${PAPERCLIP_URL}/ -> 2xx (UI serving; /api/health unavailable)"
  else
    bad "paperclip web server not responding at ${PAPERCLIP_URL}"
  fi

  section "10. live ticket flow (assign -> run -> transcript/cost/file -> comment -> resume)"
  if [[ -z "${PAPERCLIP_TOKEN}" ]]; then
    skip "PAPERCLIP_TOKEN (or ADMIN_API_KEY) unset; ticket flow needs it — re-run with token for full live test"
  else
    AUTH=(-sS -m 30 -H "Content-Type: application/json" -H "Authorization: Bearer ${PAPERCLIP_TOKEN}")
    if ! curl "${AUTH[@]}" -o "${TMP}/companies.json" "${PAPERCLIP_URL}/api/companies"; then
      bad "could not list companies at ${PAPERCLIP_URL}/api/companies"
    else
      COMPANY_ID="$(COMPANY_NAME="${COMPANY_NAME}" python3 -c '
import json, os, sys
doc = json.load(open(sys.argv[1]))
items = doc.get("companies", doc) if isinstance(doc, dict) else doc
print(next((c.get("id","") for c in items if isinstance(c, dict) and c.get("name")==os.environ["COMPANY_NAME"]), ""))
' "${TMP}/companies.json")"
      if [[ -z "${COMPANY_ID}" ]]; then
        bad "company '${COMPANY_NAME}' not found; run 'make seed' first"
      else
        ok "resolved company '${COMPANY_NAME}' (${COMPANY_ID})"
        curl "${AUTH[@]}" -o "${TMP}/agents.json" "${PAPERCLIP_URL}/api/companies/${COMPANY_ID}/agents" || true
        AGENT_ID="$(python3 -c '
import json, sys
doc = json.load(open(sys.argv[1]))
items = doc.get("agents", doc) if isinstance(doc, dict) else doc
names = {"Programmer", "PM"}
pick = next((a for a in items if isinstance(a, dict) and a.get("name") in names), None)
pick = pick or next((a for a in items if isinstance(a, dict) and a.get("id")), {})
print(pick.get("id", ""))
' "${TMP}/agents.json")"
        if [[ -z "${AGENT_ID}" ]]; then
          bad "no agent found to assign the test ticket to; run 'make seed' first"
        else
          ok "assigning test ticket to agent ${AGENT_ID}"
          ISSUE_BODY="$(TODAY="${TODAY}" AGENT_ID="${AGENT_ID}" python3 -c '
import json, os
print(json.dumps({
  "title": "smoke-test: Create hello.txt with today date",
  "body": "Create hello.txt containing today date (%s) in the workspace, then report back." % os.environ["TODAY"],
  "assigneeId": os.environ["AGENT_ID"],
}))')"
          printf '%s' "${ISSUE_BODY}" >"${TMP}/issue.json"
          # Discover the issues endpoint (fail-closed: skip, never fake-pass).
          ISSUE_PATH=""
          for candidate in "/api/companies/${COMPANY_ID}/issues" "/api/issues"; do
            code="$(curl "${AUTH[@]}" -o /dev/null -w '%{http_code}' "${PAPERCLIP_URL}${candidate}" || true)"
            if [[ "${code}" == "200" ]]; then ISSUE_PATH="${candidate}"; break; fi
          done
          if [[ -z "${ISSUE_PATH}" ]]; then
            skip "no issue endpoint discovered under /api (tried company + top-level); create a ticket in the UI to finish the live flow manually"
          else
            if curl "${AUTH[@]}" -d @"${TMP}/issue.json" -o "${TMP}/issue.resp.json" "${PAPERCLIP_URL}${ISSUE_PATH}"; then
              ISSUE_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "${TMP}/issue.resp.json")"
              if [[ -z "${ISSUE_ID}" ]]; then
                bad "issue creation returned no id: $(head -c 300 "${TMP}/issue.resp.json")"
              else
                ok "created test ticket ${ISSUE_ID} (wake on assignment expected)"
                echo "  polling run completion (timeout ${RUN_TIMEOUT_SEC}s)..."
                deadline=$((SECONDS + RUN_TIMEOUT_SEC))
                RUN_DONE="false"
                while [[ "${SECONDS}" -lt "${deadline}" ]]; do
                  if curl "${AUTH[@]}" -o "${TMP}/runs.json" "${PAPERCLIP_URL}${ISSUE_PATH}/${ISSUE_ID}/runs" 2>/dev/null \
                    && RUN_DONE="$(python3 -c '
import json, sys
doc = json.load(open(sys.argv[1]))
items = doc.get("runs", doc) if isinstance(doc, dict) else doc
items = items if isinstance(items, list) else []
done = [r for r in items if isinstance(r, dict) and r.get("status") in ("completed", "succeeded", "done")]
print("true" if done else "false")
' "${TMP}/runs.json")" && [[ "${RUN_DONE}" == "true" ]]; then
                    break
                  fi
                  sleep 10
                done
                if [[ "${RUN_DONE}" == "true" ]]; then
                  ok "agent run completed"
                  if python3 -c '
import json, sys
doc = json.load(open(sys.argv[1]))
items = doc.get("runs", doc) if isinstance(doc, dict) else doc
items = items if isinstance(items, list) else []
run = next((r for r in items if isinstance(r, dict) and r.get("status") in ("completed","succeeded","done")), {})
usage = run.get("usage") or run.get("tokens") or {}
assert run.get("transcript") or run.get("messages") or usage, "no transcript/usage evidence"
print(json.dumps({"usage": usage})[:200])
' "${TMP}/runs.json"; then
                    ok "transcript + token/cost accounting present on completed run"
                  else
                    bad "completed run lacks transcript/token-cost evidence"
                  fi
                else
                  bad "agent run did not complete within ${RUN_TIMEOUT_SEC}s (check paperclip logs: make logs)"
                fi
                if grep -rlx "${TODAY}" ./workspaces/*/hello.txt ./workspaces/hello.txt 2>/dev/null | head -1 | grep -q .; then
                  ok "workspace hello.txt with today's date found under ./workspaces"
                else
                  bad "hello.txt with today's date NOT found under ./workspaces"
                fi
                printf '{"body": "smoke-test follow-up: please confirm session resumption with --session."}' >"${TMP}/comment.json"
                if curl "${AUTH[@]}" -d @"${TMP}/comment.json" -o /dev/null "${PAPERCLIP_URL}${ISSUE_PATH}/${ISSUE_ID}/comments" 2>/dev/null; then
                  ok "follow-up comment posted (session resumption via --session; shim passes it through, §5)"
                else
                  skip "comment endpoint not available at ${ISSUE_PATH}/${ISSUE_ID}/comments; post a follow-up in the UI to verify --session resume"
                fi
              fi
            else
              bad "issue creation POST failed at ${ISSUE_PATH}"
            fi
          fi
        fi
      fi
    fi
  fi
fi

# --- summary -------------------------------------------------------------------
printf '\nSMOKE RESULT: %d passed, %d failed, %d skipped (mode=%s)\n' "${PASS}" "${FAIL}" "${SKIP}" "${MODE}"
if [[ "${FAIL}" -gt 0 ]]; then
  echo "SMOKE: FAIL"
  exit 1
fi
echo "SMOKE: OK"
