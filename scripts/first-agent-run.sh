#!/usr/bin/env bash
#
# first-agent-run.sh — prove the first FULL agent turn end-to-end on Muse Spark.
#
# Target: exec-director (paused at wave start) via resume -> wakeup(on_demand/
# manual) -> poll heartbeat-runs to a terminal state with log + provider-trace
# evidence -> restore the pre-run paused state. Fallback idle agents
# (tech-docs-lead, system-architect) cover the case where exec-director cannot
# be used; the fallback path skips resume/re-pause and records that fact.
#
# This script performs NO fleet mutation: no seed, no PATCH of any agent, no
# model/env/skill/instruction/tool change. The only state-changing calls are
# the lifecycle proof itself (resume, wakeup, and — only when the live OpenAPI
# confirms the route — pause to restore). Reads are GETs; writes are the
# resume/wakeup/pause lifecycle trio plus heartbeat-run polling.
#
# Usage:
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... bash scripts/first-agent-run.sh [--dry-run] [--help] [--only <role>] [--environment <envId>]
#
#   --dry-run     Print the resume->wakeup->poll->re-pause plan with the exact
#                 request templates (agent ids, company id, model string) for
#                 the selected role without performing ANY network calls. No
#                 PAPERCLIP_TOKEN is required. Safe against a dead
#                 PAPERCLIP_URL: not a single byte is sent.
#   --only        Restrict the run to one allowlisted role (also accepts
#                 --only=<role> and comma-separated lists restricted to the
#                 allowlist). Allowlist: exec-director (default target, paused
#                 at wave start), tech-docs-lead + system-architect (idle
#                 fallbacks). Unknown role dirs fail closed with exit 2.
#   --environment Run the wakeup inside this Paperclip environment (UUID).
#                 When omitted, the environmentId key is OMITTED from the
#                 wakeup body and the server uses the agent default.
#   --help, -h    Print this usage guide and exit.
#
# Environment (all optional unless noted):
#   PAPERCLIP_URL             Base URL of the Paperclip server.
#                             Default: http://localhost:3100 (MUST be localhost,
#                             not 127.0.0.1 — see wave gotchas).
#   PAPERCLIP_TOKEN           Board API token for Authorization: Bearer auth.
#                             Falls back to ADMIN_API_KEY. Required unless
#                             --dry-run is passed.
#   ADMIN_API_KEY             Fallback for PAPERCLIP_TOKEN.
#   COMPANY_NAME              Fleet company used to resolve agent ids.
#                             Default: "Heretek Autonomous Fleet"
#   HEALTH_TIMEOUT_SEC        How long to wait for Paperclip health.
#                             Default: 120
#   POLL_TIMEOUT_SEC          How long to poll heartbeat-runs for a terminal
#                             run state before giving up. Default: 900
#   POLL_INTERVAL_SEC         Seconds between poll attempts. Default: 10
#   EVIDENCE_DIR              Directory receiving the evidence report and the
#                             JSON sidecar plus the per-run evidence bundle.
#                             Default: <repo>/docs/reports
#
# Upstream API contracts (verified against live openapi.json 2026-10-18):
#   1. List: GET /api/companies/:companyId/agents (resolves role->agent id).
#   2. Detail: GET /api/agents/:id returns the agent row incl. status and
#      adapterConfig.model (model proof: must equal TARGET_MODEL or the run
#      aborts BEFORE any lifecycle call — fail closed, never mutate).
#   3. Resume: POST /api/agents/:id/resume with NO body (only when the
#      recorded status is exactly "paused"); followed by a re-GET that must
#      show a non-paused status (expected "idle") or the run aborts.
#   4. Wakeup: POST /api/agents/:id/wakeup with {source:"on_demand",
#      triggerDetail:"manual", reason, forceFreshSession:true (REQUIRED for a
#      clean proof), idempotencyKey (fresh per attempt), environmentId only
#      when --environment is passed} -> HTTP 202 receipt. A queued/deferred
#      receipt may carry no run id yet, so the poll below matches by receipt
#      run id when present and otherwise by the newest run for the agent.
#   5. Poll: GET /api/companies/:companyId/heartbeat-runs?agentId=:id&limit=10
#      until the matching run reaches a terminal state
#      (success/failed/cancelled family) or POLL_TIMEOUT_SEC expires. On a
#      failed run whose log/trace carries "models_discovery_failed", the
#      wakeup is retried ONCE with a fresh idempotencyKey, then polling
#      continues under the original deadline.
#   6. Evidence: GET /api/heartbeat-runs/:runId plus /log, /events and
#      /provider-trace. Excerpts are truncated to 50 lines each in the
#      report summary; full bodies land in the evidence bundle directory.
#   7. Restore: when this run resumed the agent from paused, the script
#      re-reads the LIVE openapi.json at runtime and attempts
#      POST /api/agents/:id/pause ONLY when the path is confirmed present.
#      When absent (or the openapi fetch fails), the agent is LEFT idle and
#      the report records an explicit follow-up — the pause shape is never
#      guessed. A final re-GET records the closing status either way.
#   8. Drift check: the closing re-GET must still show TARGET_MODEL; any
#      model drift fails the run (without mutating anything to fix it).
#
# Idempotency: every wakeup attempt carries a fresh idempotencyKey (uuidgen
# when available, else a date+random suffix); the script re-GETs after every
# lifecycle call and verifies the transition instead of assuming it.
#
# Secret hygiene: the token travels only as an Authorization header and is
# never printed (logs say "Authorization: Bearer ***" when auth is mentioned
# at all); wakeup/resume/pause bodies carry no secret values; server response
# bodies are stored verbatim but never scanned for secrets to print — only
# ids, names, statuses, counts, timestamps and check codes are logged.
#
# Exit codes: 0 the full turn completed (terminal run observed, evidence
# written, pre-run paused state restored or the deviation recorded with a
# follow-up); 1 a fail-closed preflight tripped, a transition did not verify,
# the poll timed out, or model drift was observed; 2 CLI misuse (unknown
# argument, bad --only value, bad --environment value, bad timeout value).
#
# Examples:
#   bash scripts/first-agent-run.sh --dry-run
#   bash scripts/first-agent-run.sh --dry-run --only tech-docs-lead
#   PAPERCLIP_URL=http://localhost:3100 PAPERCLIP_TOKEN=xxx bash scripts/first-agent-run.sh
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... bash scripts/first-agent-run.sh --only system-architect --environment 00000000-0000-0000-0000-000000000000
#
set -euo pipefail

PAPERCLIP_URL="${PAPERCLIP_URL:-http://localhost:3100}"
PAPERCLIP_TOKEN="${PAPERCLIP_TOKEN:-${ADMIN_API_KEY:-}}"
COMPANY_NAME="${COMPANY_NAME:-Heretek Autonomous Fleet}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-120}"
POLL_TIMEOUT_SEC="${POLL_TIMEOUT_SEC:-900}"
POLL_INTERVAL_SEC="${POLL_INTERVAL_SEC:-10}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
EVIDENCE_DIR="${EVIDENCE_DIR:-${REPO_ROOT}/docs/reports}"

# Wave-pinned proof targets (expected values; live ids are still resolved via
# the API and recorded — never assumed — but the dry-run plan prints these).
TARGET_MODEL="opencode-go/muse-spark-1.3-contributor"
KNOWN_COMPANY_ID="d2f411ef-0b17-467f-8540-a17c603859d9"
KNOWN_EXEC_DIRECTOR_ID="b2211b6f-98f7-4e07-bb34-125ecc55cf25"
WAKEUP_REASON="first functional test of full agent turn on Muse Spark (wave first-agent-run)"

# Allowlisted roles for this proof wave: exec-director is the primary target
# (paused at wave start; resume/re-pause path), tech-docs-lead and
# system-architect are idle fallbacks (no resume/re-pause needed).
ALLOW_ROLES=(
  exec-director tech-docs-lead system-architect
)

role_display_name() {
  case "$1" in
    exec-director) echo "Director / CEO-Delegate" ;;
    tech-docs-lead) echo "Technical Documentation Lead" ;;
    system-architect) echo "System Architect" ;;
    *) echo "$1" ;;
  esac
}

is_allowed_role() {
  local candidate="$1" role
  for role in "${ALLOW_ROLES[@]}"; do
    if [ "${role}" = "${candidate}" ]; then
      return 0
    fi
  done
  return 1
}

known_agent_id() {
  case "$1" in
    exec-director) echo "${KNOWN_EXEC_DIRECTOR_ID}" ;;
    *) echo "(resolved live via GET /api/companies/:companyId/agents)" ;;
  esac
}

DRY_RUN="false"
ONLY_RAW="exec-director"
ENV_ID=""
ENV_SET="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN="true"; shift ;;
    --help|-h)
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --only)
      if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
        echo "error: --only requires a non-empty value, e.g. --only exec-director (see --help)" >&2
        exit 2
      fi
      case "$2" in
        -*)
          echo "error: --only requires a non-empty value, e.g. --only exec-director (see --help)" >&2
          exit 2
          ;;
      esac
      ONLY_RAW="$2"; shift 2 ;;
    --only=*)
      ONLY_RAW="${1#--only=}"; shift ;;
    --environment)
      if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
        echo "error: --environment requires a non-empty environment id (UUID), e.g. --environment 00000000-0000-0000-0000-000000000000 (see --help)" >&2
        exit 2
      fi
      case "$2" in
        -*)
          echo "error: --environment requires a non-empty environment id (UUID), e.g. --environment 00000000-0000-0000-0000-000000000000 (see --help)" >&2
          exit 2
          ;;
      esac
      ENV_ID="$2"; ENV_SET="true"; shift 2 ;;
    --environment=*)
      ENV_ID="${1#--environment=}"; ENV_SET="true"; shift ;;
    --)
      shift
      if [ "$#" -gt 0 ]; then
        echo "error: unknown argument '$1' (see --help)" >&2
        exit 2
      fi
      break ;;
    -*|"")
      echo "error: unknown argument '$1' (see --help)" >&2
      exit 2
      ;;
    *)
      echo "error: unknown argument '$1' (see --help)" >&2
      exit 2
      ;;
  esac
done

if [ "${DRY_RUN}" != "true" ] && [ -z "${PAPERCLIP_TOKEN}" ]; then
  echo "error: PAPERCLIP_TOKEN (or ADMIN_API_KEY) must be set" >&2
  exit 1
fi

if [ -z "${PAPERCLIP_URL}" ]; then
  echo "error: PAPERCLIP_URL must be set (default http://localhost:3100)" >&2
  exit 1
fi

# The wakeup schema types environmentId as a UUID; an explicitly passed
# non-UUID can never validate server-side, so reject it here fail-closed
# before any network call.
if [ "${ENV_SET}" = "true" ]; then
  if [ -z "${ENV_ID}" ]; then
    echo "error: --environment requires a non-empty environment id (UUID) (see --help)" >&2
    exit 2
  fi
  if ! printf '%s' "${ENV_ID}" | grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; then
    echo "error: --environment value '${ENV_ID}' is not a UUID (see --help)" >&2
    exit 2
  fi
fi

for timeout_var in HEALTH_TIMEOUT_SEC POLL_TIMEOUT_SEC POLL_INTERVAL_SEC; do
  timeout_val="$(eval "printf '%s' \"\${${timeout_var}}\"")"
  if ! printf '%s' "${timeout_val}" | grep -Eq '^[1-9][0-9]*$'; then
    echo "error: ${timeout_var} must be a positive integer (got '${timeout_val}') (see --help)" >&2
    exit 2
  fi
done

# Build the target role list from the wave allowlist, validating fail-closed.
TARGET_ROLES=()
ONLY_NORM="$(printf '%s' "${ONLY_RAW}" | tr ',' ' ')"
WANTS=()
read -ra WANTS <<< "${ONLY_NORM}"
if [ "${#WANTS[@]}" -eq 0 ]; then
  echo "error: --only requires a non-empty role list, e.g. --only exec-director (see --help)" >&2
  exit 2
fi
for want in "${WANTS[@]}"; do
  if ! is_allowed_role "${want}"; then
    echo "error: unknown role '${want}' in --only (allowlist for this wave: ${ALLOW_ROLES[*]}; see --help)" >&2
    exit 2
  fi
done
for role in "${ALLOW_ROLES[@]}"; do
  for want in "${WANTS[@]}"; do
    if [ "${role}" = "${want}" ]; then
      TARGET_ROLES+=("${role}")
      break
    fi
  done
done

log() { printf '[first-agent-run] %s\n' "$*"; }
ok() { printf '[first-agent-run] OK: %s\n' "$*"; }
bad() { printf '[first-agent-run] ERROR: %s\n' "$*" >&2; }

# --dry-run exits here, BEFORE curl/python3 are required and before any
# network call could occur: every statement above is pure local computation
# (arg parsing, constant targets). Any curl invocation while DRY_RUN=true is
# a bug — gate all api() calls live-only.
if [ "${DRY_RUN}" = "true" ]; then
  log "--dry-run: first full agent turn plan (no network calls)"
  log "server: ${PAPERCLIP_URL} (untouched in dry-run; safe against a dead URL)"
  log "company: '${COMPANY_NAME}' (expected id ${KNOWN_COMPANY_ID}; resolved live via GET /api/companies)"
  log "model proof: every target agent must read back adapterConfig.model == '${TARGET_MODEL}' before any lifecycle call, or the run aborts without mutating anything"
  if [ "${ENV_SET}" = "true" ]; then
    log "environment: every wakeup body would carry environmentId '${ENV_ID}' (explicit target)"
  else
    log "environment: environmentId key omitted from every wakeup body (server uses the agent default)"
  fi
  for role in "${TARGET_ROLES[@]}"; do
    name="$(role_display_name "${role}")"
    log "--- role '${role}' (agent '${name}', expected id $(known_agent_id "${role}")) ---"
    log "step 1: GET ${PAPERCLIP_URL}/api/companies/<companyId>/agents -> resolve agent id for '${name}', record status/model"
    log "step 2: GET ${PAPERCLIP_URL}/api/agents/<agentId> -> record model/env shape; abort unless model == '${TARGET_MODEL}'"
    if [ "${role}" = "exec-director" ]; then
      log "step 3: status paused -> POST ${PAPERCLIP_URL}/api/agents/<agentId>/resume (empty body), then re-GET to verify idle; any other status skips resume and is recorded"
    else
      log "step 3: idle fallback — no resume expected; if status is paused the run aborts fail-closed (re-pause scope is exec-director only)"
    fi
    log "step 4: POST ${PAPERCLIP_URL}/api/agents/<agentId>/wakeup with body:"
    if [ "${ENV_SET}" = "true" ]; then
      log '{"source": "on_demand", "triggerDetail": "manual", "reason": "'"${WAKEUP_REASON}"'", "forceFreshSession": true, "idempotencyKey": "<fresh-uuid>", "environmentId": "'"${ENV_ID}"'"}'
    else
      log '{"source": "on_demand", "triggerDetail": "manual", "reason": "'"${WAKEUP_REASON}"'", "forceFreshSession": true, "idempotencyKey": "<fresh-uuid>"}'
    fi
    log "step 5: poll GET ${PAPERCLIP_URL}/api/companies/<companyId>/heartbeat-runs?agentId=<agentId>&limit=10 every ${POLL_INTERVAL_SEC}s up to ${POLL_TIMEOUT_SEC}s until the receipt run reaches terminal (success/failed/cancelled family); on models_discovery_failed retry the wakeup ONCE with a fresh idempotencyKey"
    log "step 6: GET ${PAPERCLIP_URL}/api/heartbeat-runs/<runId> + /log + /events + /provider-trace (50-line excerpts in report, full bodies to evidence bundle)"
    if [ "${role}" = "exec-director" ]; then
      log "step 7: restore — re-read live openapi.json for POST /api/agents/{id}/pause; present -> pause + re-GET verify paused; absent -> LEAVE idle + explicit follow-up in evidence (never guess the shape)"
    else
      log "step 7: restore — not applicable (no resume performed); final re-GET records closing status"
    fi
    log "step 8: write ${EVIDENCE_DIR}/first-agent-run-evidence.md + JSON sidecar first-agent-run-evidence.${role}.json (runId, timestamps, transitions, model proof, restore proof)"
  done
  log "dry-run summary: ${#TARGET_ROLES[@]} role(s) would be proven end-to-end; zero network calls attempted"
  exit 0
fi

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 1; }

# Temp files live under the worktree (see /tmp inode-exhaustion gotcha), are
# removed on exit, and never carry secrets (ids/statuses/bodies only).
RUN_TMP_BASE="${REPO_ROOT}/.tmp-run"
mkdir -p "${RUN_TMP_BASE}"
TMPDIR_WORK="$(mktemp -d "${RUN_TMP_BASE}/first-agent-run.XXXXXX")"
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

# api METHOD PATH [BODY_FILE] -> prints response body to stdout.
# Same contract as scripts/seed-50-fleet.sh and enrich-fleet-verify.sh:
# --fail-with-body (curl >= 7.76) makes every HTTP error (4xx/5xx) exit
# nonzero WITH the body on stderr — errors are never swallowed and statuses never masked:
# callers guard each call and fail closed, and preflights run under
# `set -e`. The token travels only in the Authorization header and is never
# logged (see log lines: "Authorization: Bearer ***").
api() {
  local method="$1" path="$2" body_file="${3:-}"
  local args=(-sS -m 30 --fail-with-body -H "Content-Type: application/json" -H "Authorization: Bearer ${PAPERCLIP_TOKEN}")
  if [ -n "${body_file}" ]; then
    args+=(-d "@${body_file}")
  fi
  curl "${args[@]}" -X "${method}" "${PAPERCLIP_URL}${path}"
}

find_company_id() {
  # Prints the company id matching $COMPANY_NAME in a list response, else "".
  # Fail-closed (mirrors seed-50-fleet.sh): an unparseable body or an
  # unexpected shape exits NONZERO instead of masquerading as "" = "not found".
  COMPANY_NAME="${COMPANY_NAME}" python3 -c '
import json, os, sys
raw = sys.stdin.read()
try:
    doc = json.loads(raw)
except Exception:
    sys.exit(1)
items = doc.get("companies", doc) if isinstance(doc, dict) else doc
if not isinstance(items, list):
    sys.exit(1)
for c in items:
    if isinstance(c, dict) and c.get("name") == os.environ["COMPANY_NAME"]:
        print(c.get("id", ""))
        break
'
}

find_agent() {
  # Prints "<id>\t<status>\t<model>" for agent named $1, else "".
  # Fail-closed: parse failure or unexpected shape exits nonzero, never
  # "" = "not found". The model is read from adapterConfig.model when it is
  # a string, else "" (the detail GET is authoritative for the model proof).
  AGENT_NAME="$1" python3 -c '
import json, os, sys
raw = sys.stdin.read()
try:
    doc = json.loads(raw)
except Exception:
    sys.exit(1)
items = doc.get("agents", doc) if isinstance(doc, dict) else doc
if not isinstance(items, list):
    sys.exit(1)
for a in items:
    if isinstance(a, dict) and a.get("name") == os.environ["AGENT_NAME"]:
        cfg = a.get("adapterConfig")
        model = cfg.get("model") if isinstance(cfg, dict) else ""
        if not isinstance(model, str):
            model = ""
        status = a.get("status")
        if not isinstance(status, str):
            status = "" if status is None else str(status)
        print(str(a.get("id", "")) + "\t" + status + "\t" + model)
        break
'
}

agent_detail_extract() {
  # $1 = GET /api/agents/:id detail JSON. Prints "<id>\t<status>\t<model>".
  # Accepts {agent,...}/{data,...} wrappers defensively. Exits NONZERO on
  # unparseable bodies or a missing id (fail-closed: never proceed against
  # an unknown agent).
  python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        doc = json.load(fh)
except Exception as exc:
    sys.stderr.write("error: agent detail response is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
if not isinstance(doc, dict):
    sys.stderr.write("error: agent detail response has unexpected shape (expected object)\n")
    sys.exit(1)
body = doc
for key in ("agent", "data"):
    inner = doc.get(key)
    if isinstance(inner, dict) and ("adapterConfig" in inner or "status" in inner or "id" in inner):
        body = inner
        break
aid = body.get("id")
if not isinstance(aid, str) or not aid:
    sys.stderr.write("error: agent detail response carries no agent id\n")
    sys.exit(1)
status = body.get("status")
if not isinstance(status, str):
    status = "" if status is None else str(status)
model = ""
cfg = body.get("adapterConfig")
if isinstance(cfg, dict):
    m = cfg.get("model")
    if isinstance(m, str):
        model = m
print("%s\t%s\t%s" % (aid, status, model))
' "$1"
}

gen_idempotency_key() {
  # Fresh idempotency key per wakeup attempt: uuidgen when available, else a
  # timestamp+pid+random suffix. Never empty (fail-closed: callers abort on
  # an empty key rather than sending a replayable body).
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    printf 'first-agent-run-%s-%s-%s' "$(date -u +%Y%m%dT%H%M%SZ)" "$$" "${RANDOM}${RANDOM}"
  fi
}

build_wakeup_payload() {
  # $1 = output payload path, $2 = idempotency key. Writes the wakeup body:
  # source on_demand + triggerDetail manual + reason + forceFreshSession true
  # + idempotencyKey, plus environmentId ONLY when --environment was passed.
  # No secret values travel in this body. Exits NONZERO on an empty key.
  OUT_PATH="$1" IDEMPOTENCY_KEY="$2" REQ_ENV="${ENV_ID}" python3 -c '
import json, os, sys
out_path = os.environ["OUT_PATH"]
idem = os.environ.get("IDEMPOTENCY_KEY", "")
if not idem:
    sys.stderr.write("error: refusing to build a wakeup body with an empty idempotencyKey\n")
    sys.exit(1)
payload = {
    "source": "on_demand",
    "triggerDetail": "manual",
    "reason": os.environ.get("WAKEUP_REASON", "first functional test"),
    "forceFreshSession": True,
    "idempotencyKey": idem,
}
req_env = os.environ.get("REQ_ENV", "")
if req_env:
    payload["environmentId"] = req_env
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
'
}

receipt_run_id() {
  # $1 = POST wakeup 202 receipt JSON. Prints the run id when the receipt
  # carries one (runId/run_id/run{id}/receipt{id}/data{id}/result{id}/id),
  # else prints nothing. A queued/deferred receipt legitimately carries no
  # run id yet — that is "" with exit 0. Unparseable bodies exit NONZERO
  # (fail-closed: never poll against a phantom receipt).
  python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        doc = json.load(fh)
except Exception as exc:
    sys.stderr.write("error: wakeup receipt is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
def find_id(obj, depth=0):
    if depth > 3 or not isinstance(obj, dict):
        return ""
    for key in ("runId", "run_id", "heartbeatRunId"):
        val = obj.get(key)
        if isinstance(val, str) and val:
            return val
    for key in ("run", "receipt", "data", "result"):
        val = obj.get(key)
        if isinstance(val, dict):
            found = find_id(val, depth + 1)
            if found:
                return found
    val = obj.get("id")
    if isinstance(val, str) and val:
        return val
    return ""
print(find_id(doc) if isinstance(doc, dict) else "")
' "$1"
}

find_run_in_list() {
  # Reads a GET heartbeat-runs list body on stdin; $1 is the wanted run id
  # (may be empty), $2 the agent id. Prints "<id>\t<status>\t<createdAt>" of
  # the matching run (by id when wanted, else the newest run for the agent),
  # else prints nothing. Unparseable bodies exit NONZERO (fail-closed: never
  # mistake a 500 page for "no run yet").
  WANT_ID="$1" AGENT_ID="$2" python3 -c '
import json, os, sys
raw = sys.stdin.read()
try:
    doc = json.loads(raw)
except Exception:
    sys.exit(1)
items = doc
if isinstance(doc, dict):
    for wrapper in ("runs", "data", "items", "heartbeatRuns"):
        inner = doc.get(wrapper)
        if isinstance(inner, list):
            items = inner
            break
if not isinstance(items, list):
    sys.exit(1)
want = os.environ.get("WANT_ID", "")
agent = os.environ.get("AGENT_ID", "")
def run_agent(run):
    for key in ("agentId", "agent_id"):
        val = run.get(key)
        if isinstance(val, str) and val:
            return val
    inner = run.get("agent")
    if isinstance(inner, dict):
        val = inner.get("id")
        if isinstance(val, str):
            return val
    return ""
def run_status(run):
    for key in ("status", "state"):
        val = run.get(key)
        if isinstance(val, str) and val:
            return val.lower()
    return "unknown"
def run_created(run):
    for key in ("createdAt", "created_at", "startedAt", "started_at"):
        val = run.get(key)
        if isinstance(val, str) and val:
            return val
    return ""
cands = []
for run in items:
    if not isinstance(run, dict):
        continue
    rid = run.get("id")
    if not isinstance(rid, str) or not rid:
        continue
    if agent and run_agent(run) and run_agent(run) != agent:
        continue
    cands.append(run)
if want:
    for run in cands:
        if run.get("id") == want:
            print("%s\t%s\t%s" % (want, run_status(run), run_created(run)))
            break
else:
    if cands:
        cands.sort(key=run_created, reverse=True)
        run = cands[0]
        print("%s\t%s\t%s" % (run.get("id"), run_status(run), run_created(run)))
'
}

run_status_of() {
  # $1 = GET /api/heartbeat-runs/:runId body. Prints the lowercased
  # status/state ("unknown" when absent). Unparseable bodies exit NONZERO.
  python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        doc = json.load(fh)
except Exception as exc:
    sys.stderr.write("error: heartbeat-run response is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
body = doc
if isinstance(doc, dict):
    for key in ("run", "data"):
        inner = doc.get(key)
        if isinstance(inner, dict) and ("status" in inner or "state" in inner):
            body = inner
            break
status = ""
if isinstance(body, dict):
    for key in ("status", "state"):
        val = body.get(key)
        if isinstance(val, str) and val:
            status = val.lower()
            break
print(status if status else "unknown")
' "$1"
}

is_terminal_status() {
  # Terminal run states per the wave contract (success/failed/cancelled
  # family; lapse variants included so a lapsed run never spins to timeout).
  # Includes `succeeded` (server-observed terminal 2026-10-18: run
  # e1e7bbff-ea1a-42d8-87f9-68c8fdc36187 for tech-docs-lead reached
  # `succeeded`) plus the `succeed` spelling variant for robustness.
  # Non-terminal states (running/queued/pending) are deliberately absent.
  case "$1" in
    success|succeed|succeeded|successful|completed|complete|failed|failure|error|timed_out|cancelled|canceled|expired) return 0 ;;
    *) return 1 ;;
  esac
}

openapi_has_pause() {
  # Prints "true" only when the LIVE openapi.json confirms
  # POST /api/agents/{id}/pause; prints "false" on any fetch/parse problem
  # (fail-closed toward LEAVE-idle + follow-up, never toward guessing).
  # Always exits 0 — callers branch on the printed word.
  local spec_file="${TMPDIR_WORK}/openapi-live.json"
  if ! curl -sS -m 30 -o "${spec_file}" "${PAPERCLIP_URL}/api/openapi.json" 2>/dev/null; then
    echo "false"
    return 0
  fi
  if PAPERCLIP_SPEC="${spec_file}" python3 -c '
import json, os, sys
try:
    with open(os.environ["PAPERCLIP_SPEC"], "r", encoding="utf-8") as fh:
        doc = json.load(fh)
except Exception:
    sys.exit(1)
paths = doc.get("paths")
if not isinstance(paths, dict):
    sys.exit(1)
entry = paths.get("/api/agents/{id}/pause")
if not isinstance(entry, dict) or "post" not in entry:
    sys.exit(1)
' 2>/dev/null; then
    echo "true"
  else
    echo "false"
  fi
  return 0
}

excerpt_lines() {
  # $1 = file, $2 = line count. Prints the first N lines, or a marker when
  # the file is missing/empty (never fails — evidence best-effort only).
  if [ -f "$1" ] && [ -s "$1" ]; then
    head -n "$2" "$1"
  else
    printf '(no content captured for %s)\n' "$(basename "$1")"
  fi
}

export WAKEUP_REASON

log "waiting for Paperclip health at ${PAPERCLIP_URL} (timeout ${HEALTH_TIMEOUT_SEC}s)"
deadline=$((SECONDS + HEALTH_TIMEOUT_SEC))
while true; do
  # -f so ANY HTTP error (incl. 500) counts as unhealthy.
  if curl -sS -f -m 5 -o /dev/null "${PAPERCLIP_URL}/api/health"; then
    break
  fi
  if [ "${SECONDS}" -ge "${deadline}" ]; then
    echo "error: Paperclip did not become healthy in ${HEALTH_TIMEOUT_SEC}s" >&2
    exit 1
  fi
  sleep 3
done
log "auth: requests carry Authorization: Bearer *** (token never logged)"

log "resolving company '${COMPANY_NAME}'"
companies_body="${TMPDIR_WORK}/companies.json"
api GET "/api/companies" > "${companies_body}"
COMPANY_ID=""
if ! COMPANY_ID="$(find_company_id < "${companies_body}")"; then
  echo "error: company list response is unparseable; aborting (server body above)" >&2
  exit 1
fi
if [ -z "${COMPANY_ID}" ]; then
  echo "error: company '${COMPANY_NAME}' not found — seed the fleet first (this script never seeds)" >&2
  exit 1
fi
log "company exists: ${COMPANY_ID}"

# The agent list is fetched ONCE up front (mirrors seed-50-fleet.sh):
# refreshed only when a lookup misses, so correctness never depends on
# cache freshness.
api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"

if [ "${ENV_SET}" = "true" ]; then
  log "wakeup will target environment ${ENV_ID} (explicit target)"
else
  log "no --environment: environmentId omitted from the wakeup body (server uses the agent default)"
fi

mkdir -p "${EVIDENCE_DIR}"
TIMELINE="${TMPDIR_WORK}/timeline.txt"
: > "${TIMELINE}"
stamp() { date -u +%FT%TZ; }
timeline() { printf '%s %s\n' "$(stamp)" "$*" >> "${TIMELINE}"; }

FAILED_COUNT=0
for role in "${TARGET_ROLES[@]}"; do
  name="$(role_display_name "${role}")"
  log "=== proving role '${role}' (agent '${name}') ==="

  # ---- Resolve + model proof (read-only; abort BEFORE any lifecycle). ----
  existing=""
  if ! existing="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"; then
    bad "role '${role}': agent list is unparseable; aborting role"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  if [ -z "${existing}" ]; then
    if ! api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"; then
      bad "role '${role}': agent list refresh failed; aborting role"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      continue
    fi
    if ! existing="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"; then
      bad "role '${role}': agent list is unparseable after refresh; aborting role"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      continue
    fi
  fi
  if [ -z "${existing}" ]; then
    bad "role '${role}': agent '${name}' not found; aborting role (this script never seeds)"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  agent_id="$(printf '%s' "${existing}" | cut -f1)"
  list_status="$(printf '%s' "${existing}" | cut -f2)"
  if [ -z "${agent_id}" ]; then
    bad "role '${role}': agent '${name}' resolved without an id; aborting role"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi

  if ! api GET "/api/agents/${agent_id}" > "${TMPDIR_WORK}/detail-${role}.json"; then
    bad "role '${role}': agent detail read failed; aborting role"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  detail=""
  if ! detail="$(agent_detail_extract "${TMPDIR_WORK}/detail-${role}.json")"; then
    bad "role '${role}': agent detail is unparseable; aborting role"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  pre_status="$(printf '%s' "${detail}" | cut -f2)"
  pre_model="$(printf '%s' "${detail}" | cut -f3)"
  [ -n "${pre_status}" ] || pre_status="${list_status}"
  log "role '${role}': pre-run status='${pre_status}' model='${pre_model}'"
  timeline "${role} pre-run status=${pre_status} model=${pre_model} agent=${agent_id}"
  if [ "${pre_model}" != "${TARGET_MODEL}" ]; then
    bad "role '${role}': model drift (got '${pre_model}', want '${TARGET_MODEL}'); aborting role WITHOUT mutating anything"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  ok "role '${role}': model proof holds (${TARGET_MODEL})"

  # ---- Resume when paused (exec-director path). ----
  RESUMED="false"
  RESUME_TS=""
  POST_RESUME_STATUS=""
  if [ "${pre_status}" = "paused" ]; then
    if [ "${role}" != "exec-director" ]; then
      bad "role '${role}': fallback idle agent is paused (expected idle); aborting role fail-closed — re-pause scope is exec-director only"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      continue
    fi
    log "role '${role}': resuming paused agent"
    if ! api POST "/api/agents/${agent_id}/resume" > "${TMPDIR_WORK}/resume-${role}.json"; then
      bad "role '${role}': resume request failed (server response above); aborting role"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      continue
    fi
    RESUME_TS="$(stamp)"
    timeline "${role} resume POST at ${RESUME_TS}"
    if ! api GET "/api/agents/${agent_id}" > "${TMPDIR_WORK}/detail-resumed-${role}.json"; then
      bad "role '${role}': post-resume re-read failed; aborting role"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      continue
    fi
    resumed_detail=""
    if ! resumed_detail="$(agent_detail_extract "${TMPDIR_WORK}/detail-resumed-${role}.json")"; then
      bad "role '${role}': post-resume detail is unparseable; aborting role"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      continue
    fi
    POST_RESUME_STATUS="$(printf '%s' "${resumed_detail}" | cut -f2)"
    if [ "${POST_RESUME_STATUS}" = "paused" ] || [ -z "${POST_RESUME_STATUS}" ]; then
      bad "role '${role}': resume did not verify (status='${POST_RESUME_STATUS}'); aborting role"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      continue
    fi
    RESUMED="true"
    ok "role '${role}': resumed paused->${POST_RESUME_STATUS} at ${RESUME_TS}"
    timeline "${role} resumed paused->${POST_RESUME_STATUS}"
  else
    log "role '${role}': no resume needed (status='${pre_status}')"
    timeline "${role} no resume (status=${pre_status})"
  fi

  # ---- Wakeup (idempotent per attempt via fresh idempotencyKey). ----
  WAKEUP_TS=""
  IDEM_KEY=""
  RECEIPT_RUN=""
  RETRIED="false"
  if ! IDEM_KEY="$(gen_idempotency_key)"; then
    bad "role '${role}': failed to generate an idempotencyKey; aborting role"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  if [ -z "${IDEM_KEY}" ]; then
    bad "role '${role}': empty idempotencyKey generated; aborting role rather than sending a replayable body"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  if ! build_wakeup_payload "${TMPDIR_WORK}/wakeup-${role}.json" "${IDEM_KEY}"; then
    bad "role '${role}': failed to build the wakeup payload; aborting role"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  log "role '${role}': waking up (source=on_demand triggerDetail=manual forceFreshSession=true idempotencyKey=${IDEM_KEY})"
  if ! api POST "/api/agents/${agent_id}/wakeup" "${TMPDIR_WORK}/wakeup-${role}.json" > "${TMPDIR_WORK}/receipt-${role}.json"; then
    bad "role '${role}': wakeup request failed (server response above); aborting role"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  WAKEUP_TS="$(stamp)"
  timeline "${role} wakeup 202 at ${WAKEUP_TS} idempotencyKey=${IDEM_KEY}"
  if ! RECEIPT_RUN="$(receipt_run_id "${TMPDIR_WORK}/receipt-${role}.json")"; then
    bad "role '${role}': wakeup receipt is unparseable; aborting role"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  if [ -n "${RECEIPT_RUN}" ]; then
    log "role '${role}': wakeup receipt references run ${RECEIPT_RUN}"
    timeline "${role} receipt run=${RECEIPT_RUN}"
  else
    log "role '${role}': wakeup receipt carries no run id yet (queued/deferred) — polling newest run for the agent"
    timeline "${role} receipt queued/deferred (no run id yet)"
  fi

  # ---- Poll heartbeat-runs to a terminal state. ----
  FINAL_RUN=""
  FINAL_STATUS=""
  poll_deadline=$((SECONDS + POLL_TIMEOUT_SEC))
  while true; do
    if ! api GET "/api/companies/${COMPANY_ID}/heartbeat-runs?agentId=${agent_id}&limit=10" > "${TMPDIR_WORK}/runs-${role}.json"; then
      bad "role '${role}': heartbeat-runs poll failed; aborting role"
      FINAL_RUN=""
      FINAL_STATUS=""
      break
    fi
    found=""
    if ! found="$(find_run_in_list "${RECEIPT_RUN}" "${agent_id}" < "${TMPDIR_WORK}/runs-${role}.json")"; then
      bad "role '${role}': heartbeat-runs list is unparseable; aborting role"
      FINAL_RUN=""
      FINAL_STATUS=""
      break
    fi
    if [ -n "${found}" ]; then
      FINAL_RUN="$(printf '%s' "${found}" | cut -f1)"
      FINAL_STATUS="$(printf '%s' "${found}" | cut -f2)"
      if [ -z "${RECEIPT_RUN}" ]; then
        RECEIPT_RUN="${FINAL_RUN}"
        timeline "${role} tracking run=${FINAL_RUN} (newest for agent)"
      fi
      if is_terminal_status "${FINAL_STATUS}"; then
        timeline "${role} terminal status=${FINAL_STATUS} run=${FINAL_RUN}"
        break
      fi
    fi
    if [ "${SECONDS}" -ge "${poll_deadline}" ]; then
      bad "role '${role}': poll timed out after ${POLL_TIMEOUT_SEC}s (last run='${FINAL_RUN:-none}' status='${FINAL_STATUS:-none}'); aborting role"
      FINAL_RUN="${FINAL_RUN:-}"
      FINAL_STATUS="${FINAL_STATUS:-timeout}"
      break
    fi
    sleep "${POLL_INTERVAL_SEC}"
  done
  if [ -z "${FINAL_RUN}" ] || [ "${FINAL_STATUS}" = "timeout" ] || [ -z "${FINAL_STATUS}" ]; then
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  log "role '${role}': run ${FINAL_RUN} reached '${FINAL_STATUS}'"
  TERMINAL_TS="$(stamp)"
  timeline "${role} terminal ${FINAL_STATUS} at ${TERMINAL_TS}"

  # ---- Evidence capture (best-effort reads; missing bodies fail the role). ----
  EVID_OK="true"
  api GET "/api/heartbeat-runs/${FINAL_RUN}" > "${TMPDIR_WORK}/run-${role}.json" || EVID_OK="false"
  api GET "/api/heartbeat-runs/${FINAL_RUN}/log" > "${TMPDIR_WORK}/runlog-${role}.json" || EVID_OK="false"
  api GET "/api/heartbeat-runs/${FINAL_RUN}/events" > "${TMPDIR_WORK}/events-${role}.json" || EVID_OK="false"
  api GET "/api/heartbeat-runs/${FINAL_RUN}/provider-trace" > "${TMPDIR_WORK}/trace-${role}.json" || EVID_OK="false"
  if [ "${EVID_OK}" != "true" ]; then
    bad "role '${role}': evidence capture failed; aborting role"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  detail_status=""
  detail_status="$(run_status_of "${TMPDIR_WORK}/run-${role}.json")" || detail_status="unknown"
  log "role '${role}': evidence captured (run status='${detail_status}')"

  # ---- models_discovery_failed: single retry with a fresh idempotencyKey. ----
  if [ "${FINAL_STATUS}" = "failed" ] || [ "${FINAL_STATUS}" = "failure" ] || [ "${FINAL_STATUS}" = "error" ]; then
    if grep -q "models_discovery_failed" "${TMPDIR_WORK}/run-${role}.json" "${TMPDIR_WORK}/runlog-${role}.json" "${TMPDIR_WORK}/trace-${role}.json" 2>/dev/null; then
      if [ "${RETRIED}" = "false" ]; then
        log "role '${role}': probe flakiness marker models_discovery_failed observed — retrying wakeup ONCE with a fresh idempotencyKey"
        timeline "${role} models_discovery_failed observed; single retry"
        RETRIED="true"
        if ! IDEM_RETRY="$(gen_idempotency_key)" || [ -z "${IDEM_RETRY}" ]; then
          bad "role '${role}': retry key generation failed; keeping the original failed evidence"
        else
          if build_wakeup_payload "${TMPDIR_WORK}/wakeup-retry-${role}.json" "${IDEM_RETRY}" \
            && api POST "/api/agents/${agent_id}/wakeup" "${TMPDIR_WORK}/wakeup-retry-${role}.json" > "${TMPDIR_WORK}/receipt-retry-${role}.json"; then
            timeline "${role} retry wakeup 202 at $(stamp) idempotencyKey=${IDEM_RETRY}"
            if RECEIPT_RETRY_RUN="$(receipt_run_id "${TMPDIR_WORK}/receipt-retry-${role}.json")"; then
              [ -n "${RECEIPT_RETRY_RUN}" ] && RECEIPT_RUN="${RECEIPT_RETRY_RUN}"
              while true; do
                if ! api GET "/api/companies/${COMPANY_ID}/heartbeat-runs?agentId=${agent_id}&limit=10" > "${TMPDIR_WORK}/runs-${role}.json"; then
                  bad "role '${role}': retry poll failed; keeping the original failed evidence"
                  break
                fi
                found=""
                if ! found="$(find_run_in_list "${RECEIPT_RUN}" "${agent_id}" < "${TMPDIR_WORK}/runs-${role}.json")"; then
                  bad "role '${role}': retry poll list unparseable; keeping the original failed evidence"
                  break
                fi
                if [ -n "${found}" ]; then
                  FINAL_RUN="$(printf '%s' "${found}" | cut -f1)"
                  FINAL_STATUS="$(printf '%s' "${found}" | cut -f2)"
                  if is_terminal_status "${FINAL_STATUS}"; then
                    timeline "${role} retry terminal status=${FINAL_STATUS} run=${FINAL_RUN}"
                    break
                  fi
                fi
                if [ "${SECONDS}" -ge "${poll_deadline}" ]; then
                  bad "role '${role}': retry poll timed out; keeping the original failed evidence"
                  break
                fi
                sleep "${POLL_INTERVAL_SEC}"
              done
              REFRESH_OK="true"
              if ! api GET "/api/heartbeat-runs/${FINAL_RUN}" > "${TMPDIR_WORK}/run-${role}.json"; then REFRESH_OK="false"; fi
              if ! api GET "/api/heartbeat-runs/${FINAL_RUN}/log" > "${TMPDIR_WORK}/runlog-${role}.json"; then REFRESH_OK="false"; fi
              if ! api GET "/api/heartbeat-runs/${FINAL_RUN}/events" > "${TMPDIR_WORK}/events-${role}.json"; then REFRESH_OK="false"; fi
              if ! api GET "/api/heartbeat-runs/${FINAL_RUN}/provider-trace" > "${TMPDIR_WORK}/trace-${role}.json"; then REFRESH_OK="false"; fi
              if [ "${REFRESH_OK}" = "false" ]; then
                log "role '${role}': post-retry evidence refresh incomplete — earlier evidence retained, gaps recorded"
                timeline "${role} post-retry evidence refresh incomplete"
              fi
              log "role '${role}': post-retry run ${FINAL_RUN} status='${FINAL_STATUS}'"
            fi
          else
            bad "role '${role}': retry wakeup failed; keeping the original failed evidence"
          fi
        fi
      else
        log "role '${role}': models_discovery_failed persists after the single retry — reporting as observed"
      fi
    fi
  fi

  # ---- Restore the pre-run paused state (exec-director only). ----
  PAUSE_TS=""
  POST_PAUSE_STATUS=""
  RESTORE_NOTE=""
  if [ "${RESUMED}" = "true" ]; then
    if [ "$(openapi_has_pause)" = "true" ]; then
      log "role '${role}': live openapi confirms POST /api/agents/{id}/pause — restoring paused state"
      if api POST "/api/agents/${agent_id}/pause" > "${TMPDIR_WORK}/pause-${role}.json"; then
        PAUSE_TS="$(stamp)"
        timeline "${role} pause POST at ${PAUSE_TS}"
        if api GET "/api/agents/${agent_id}" > "${TMPDIR_WORK}/detail-paused-${role}.json"; then
          paused_detail=""
          if paused_detail="$(agent_detail_extract "${TMPDIR_WORK}/detail-paused-${role}.json")"; then
            POST_PAUSE_STATUS="$(printf '%s' "${paused_detail}" | cut -f2)"
          fi
        fi
        if [ "${POST_PAUSE_STATUS}" = "paused" ]; then
          ok "role '${role}': paused state restored at ${PAUSE_TS}"
          timeline "${role} restored to paused"
        else
          RESTORE_NOTE="re-pause POST accepted but closing status reads '${POST_PAUSE_STATUS:-unknown}' — FOLLOW-UP: confirm exec-director scheduling state via the WebUI before the next wave."
          bad "role '${role}': ${RESTORE_NOTE}"
        fi
      else
        RESTORE_NOTE="re-pause POST failed (server response above) — agent LEFT '${POST_RESUME_STATUS:-unknown}' — FOLLOW-UP: re-pause exec-director manually via the WebUI and record the timestamp in the evidence report."
        bad "role '${role}': ${RESTORE_NOTE}"
      fi
    else
      RESTORE_NOTE="live openapi does NOT confirm POST /api/agents/{id}/pause (or the spec fetch failed) — agent LEFT idle by design, shape never guessed — FOLLOW-UP: re-pause exec-director manually via the WebUI and record the timestamp in the evidence report."
      bad "role '${role}': ${RESTORE_NOTE}"
      timeline "${role} pause path unconfirmed; left idle + follow-up recorded"
    fi
  else
    log "role '${role}': no restore needed (no resume was performed)"
  fi

  # ---- Closing re-GET: final status + fleet drift check (read-only). ----
  if ! api GET "/api/agents/${agent_id}" > "${TMPDIR_WORK}/detail-final-${role}.json"; then
    bad "role '${role}': closing re-read failed; aborting role"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  final_detail=""
  if ! final_detail="$(agent_detail_extract "${TMPDIR_WORK}/detail-final-${role}.json")"; then
    bad "role '${role}': closing detail is unparseable; aborting role"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  FINAL_AGENT_STATUS="$(printf '%s' "${final_detail}" | cut -f2)"
  FINAL_MODEL="$(printf '%s' "${final_detail}" | cut -f3)"
  FINAL_TS="$(stamp)"
  timeline "${role} closing status=${FINAL_AGENT_STATUS} model=${FINAL_MODEL}"
  if [ "${FINAL_MODEL}" != "${TARGET_MODEL}" ]; then
    bad "role '${role}': fleet drift observed at close (model='${FINAL_MODEL}', want '${TARGET_MODEL}'); NOT fixing it here — recorded for follow-up"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  ok "role '${role}': closing status='${FINAL_AGENT_STATUS}' model='${FINAL_MODEL}' (no drift)"

  # ---- Evidence bundle + report + JSON sidecar. ----
  BUNDLE_DIR="${EVIDENCE_DIR}/first-agent-run-evidence.d/${role}"
  mkdir -p "${BUNDLE_DIR}"
  cp "${TMPDIR_WORK}/run-${role}.json" "${BUNDLE_DIR}/run.json"
  cp "${TMPDIR_WORK}/runlog-${role}.json" "${BUNDLE_DIR}/log.json"
  cp "${TMPDIR_WORK}/events-${role}.json" "${BUNDLE_DIR}/events.json"
  cp "${TMPDIR_WORK}/trace-${role}.json" "${BUNDLE_DIR}/provider-trace.json"
  cp "${TMPDIR_WORK}/receipt-${role}.json" "${BUNDLE_DIR}/wakeup-receipt.json"
  cp "${TIMELINE}" "${BUNDLE_DIR}/timeline.txt"

  REPORT="${EVIDENCE_DIR}/first-agent-run-evidence.md"
  SIDECAR="${EVIDENCE_DIR}/first-agent-run-evidence.${role}.json"
  {
    printf '# First-Agent-Run Evidence (live)\n\n'
    printf 'Role: %s (agent %s, id %s)\n\n' "${role}" "${name}" "${agent_id}"
    printf 'Company: %s (id %s)\n\n' "${COMPANY_NAME}" "${COMPANY_ID}"
    printf 'Model proof: pre=%s closing=%s (required %s)\n\n' "${pre_model}" "${FINAL_MODEL}" "${TARGET_MODEL}"
    printf '## Transitions\n\n'
    printf -- '- pre-run status: %s\n' "${pre_status}"
    if [ "${RESUMED}" = "true" ]; then
      printf -- '- resumed paused->%s at %s\n' "${POST_RESUME_STATUS}" "${RESUME_TS}"
    else
      printf -- '- resume: not performed (pre-run status %s)\n' "${pre_status}"
    fi
    printf -- '- wakeup 202 at %s (idempotencyKey %s)\n' "${WAKEUP_TS}" "${IDEM_KEY}"
    printf -- '- run %s terminal %s at %s (single retry used: %s)\n' "${FINAL_RUN}" "${FINAL_STATUS}" "${TERMINAL_TS}" "${RETRIED}"
    if [ -n "${PAUSE_TS}" ]; then
      printf -- '- re-pause POST at %s, closing agent status %s\n' "${PAUSE_TS}" "${POST_PAUSE_STATUS}"
    elif [ -n "${RESTORE_NOTE}" ]; then
      printf -- '- restore: %s\n' "${RESTORE_NOTE}"
    else
      printf -- '- restore: not applicable; closing agent status %s at %s\n' "${FINAL_AGENT_STATUS}" "${FINAL_TS}"
    fi
    printf '\n## Poll timeline\n\n\x60\x60\x60\n'
    cat "${TIMELINE}"
    printf '\x60\x60\x60\n\n## Log excerpt (first 50 lines)\n\n\x60\x60\x60\n'
    excerpt_lines "${TMPDIR_WORK}/runlog-${role}.json" 50
    printf '\n\x60\x60\x60\n\n## Provider-trace excerpt (first 50 lines)\n\n\x60\x60\x60\n'
    excerpt_lines "${TMPDIR_WORK}/trace-${role}.json" 50
    printf '\n\x60\x60\x60\n\n## Events excerpt (first 50 lines)\n\n\x60\x60\x60\n'
    excerpt_lines "${TMPDIR_WORK}/events-${role}.json" 50
    printf '\n\x60\x60\x60\n\nFull bodies: %s (run.json, log.json, events.json, provider-trace.json, wakeup-receipt.json, timeline.txt). JSON sidecar: %s.\n' "${BUNDLE_DIR}" "${SIDECAR}"
  } > "${REPORT}"
  RUN_FILE="${TMPDIR_WORK}/run-${role}.json" LOG_FILE="${TMPDIR_WORK}/runlog-${role}.json" EVENTS_FILE="${TMPDIR_WORK}/events-${role}.json" TRACE_FILE="${TMPDIR_WORK}/trace-${role}.json" \
    ROLE_OUT="${role}" AGENT_OUT="${name}" AGENT_ID_OUT="${agent_id}" COMPANY_OUT="${COMPANY_ID}" \
    PRE_STATUS_OUT="${pre_status}" PRE_MODEL_OUT="${pre_model}" RESUMED_OUT="${RESUMED}" RESUME_TS_OUT="${RESUME_TS}" \
    POST_RESUME_OUT="${POST_RESUME_STATUS}" WAKEUP_TS_OUT="${WAKEUP_TS}" IDEM_OUT="${IDEM_KEY}" RUN_ID_OUT="${FINAL_RUN}" \
    RUN_STATUS_OUT="${FINAL_STATUS}" TERMINAL_TS_OUT="${TERMINAL_TS}" RETRIED_OUT="${RETRIED}" PAUSE_TS_OUT="${PAUSE_TS}" \
    POST_PAUSE_OUT="${POST_PAUSE_STATUS}" RESTORE_NOTE_OUT="${RESTORE_NOTE}" FINAL_STATUS_OUT="${FINAL_AGENT_STATUS}" \
    FINAL_MODEL_OUT="${FINAL_MODEL}" FINAL_TS_OUT="${FINAL_TS}" TARGET_MODEL_OUT="${TARGET_MODEL}" SIDECAR_OUT="${SIDECAR}" python3 -c '
import json, os
def load(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return None
sidecar = {
    "role": os.environ.get("ROLE_OUT", ""),
    "agentName": os.environ.get("AGENT_OUT", ""),
    "agentId": os.environ.get("AGENT_ID_OUT", ""),
    "companyId": os.environ.get("COMPANY_OUT", ""),
    "targetModel": os.environ.get("TARGET_MODEL_OUT", ""),
    "preRun": {"status": os.environ.get("PRE_STATUS_OUT", ""), "model": os.environ.get("PRE_MODEL_OUT", "")},
    "resume": {"performed": os.environ.get("RESUMED_OUT", "") == "true", "at": os.environ.get("RESUME_TS_OUT", ""), "postStatus": os.environ.get("POST_RESUME_OUT", "")},
    "wakeup": {"at": os.environ.get("WAKEUP_TS_OUT", ""), "idempotencyKey": os.environ.get("IDEM_OUT", "")},
    "run": {"id": os.environ.get("RUN_ID_OUT", ""), "terminalStatus": os.environ.get("RUN_STATUS_OUT", ""), "terminalAt": os.environ.get("TERMINAL_TS_OUT", ""), "retriedOnce": os.environ.get("RETRIED_OUT", "") == "true"},
    "restore": {"pauseAt": os.environ.get("PAUSE_TS_OUT", ""), "postPauseStatus": os.environ.get("POST_PAUSE_OUT", ""), "note": os.environ.get("RESTORE_NOTE_OUT", "")},
    "closing": {"status": os.environ.get("FINAL_STATUS_OUT", ""), "model": os.environ.get("FINAL_MODEL_OUT", ""), "at": os.environ.get("FINAL_TS_OUT", "")},
    "bodies": {
        "run": load(os.environ.get("RUN_FILE", "")),
        "log": load(os.environ.get("LOG_FILE", "")),
        "events": load(os.environ.get("EVENTS_FILE", "")),
        "providerTrace": load(os.environ.get("TRACE_FILE", "")),
    },
}
with open(os.environ["SIDECAR_OUT"], "w", encoding="utf-8") as fh:
    json.dump(sidecar, fh, indent=2)
'
  ok "role '${role}': evidence written to ${REPORT} + ${SIDECAR} (bundle ${BUNDLE_DIR})"
done

if [ "${FAILED_COUNT}" -gt 0 ]; then
  bad "first-agent-run FAILED for ${FAILED_COUNT} role(s)"
  exit 1
fi
ok "first-agent-run complete"
