#!/usr/bin/env bash
#
# seed-company.sh — idempotently seed "Acme Autonomous Corp" and its 6-agent
# fleet (Director, PM, Programmer, Tester, QA, Designer) into Paperclip.
#
# Usage:
#   ./scripts/seed-company.sh [--dry-run] [--help]
#
#   --dry-run   Print the exact JSON payloads that would be POSTed (company +
#               6 agents) without performing any network calls.
#
# Environment (all optional unless noted):
#   PAPERCLIP_URL             Base URL of the Paperclip server.
#                             Default: http://127.0.0.1:3100
#   PAPERCLIP_TOKEN           Board API token for Authorization: Bearer auth.
#                             Falls back to ADMIN_API_KEY. Required unless
#                             --dry-run is passed.
#   ADMIN_API_KEY             Fallback for PAPERCLIP_TOKEN.
#   COMPANY_NAME              Default: "Acme Autonomous Corp"
#   MODEL_DEFAULT             Default model for programmer/tester/qa/designer.
#                             Default: anthropic/claude-sonnet-4-5
#   MODEL_DIRECTOR            Default: ${MODEL_DEFAULT}
#   MODEL_PM                  Default: ${MODEL_DEFAULT}
#   BUDGET_DIRECTOR_USD       Monthly budget cap, USD. Default: 100
#   BUDGET_DEFAULT_USD        Monthly budget cap for non-director agents, USD.
#                             Default: 50
#   TIMER_DIRECTOR_SEC        Scheduler heartbeat interval for the Director.
#                             0 disables. Default: 1800 (30m)
#   TIMER_PM_SEC              Scheduler heartbeat interval for the PM.
#                             0 disables. Default: 3600 (1h)
#   HEALTH_TIMEOUT_SEC        How long to wait for Paperclip health.
#                             Default: 120
#
# Paperclip REST API assumptions (verified against /tmp/paperclip sources):
#   * Routes are mounted under /api (see server/src/routes/*.ts, e.g.
#     companies.ts `router.post("/", ...)` and agents.ts
#     `router.post("/companies/:companyId/agents", validate(createAgentSchema))`).
#   * Auth is a board API key sent as `Authorization: Bearer <token>`.
#   * Agent creation follows createAgentSchema (packages/shared/src/validators/
#     agent.ts): {name, role, adapterType, adapterConfig, runtimeConfig,
#     budgetMonthlyCents (integer CENTS), reportsTo (agent UUID)}.
#   * opencode_local adapterConfig keys (packages/adapters/opencode-local/src/
#     index.ts): {model (required, provider/model), env (map, optional),
#     dangerouslySkipPermissions (bool, default true)}.
#   * Per-role isolation: adapterConfig.env.XDG_CONFIG_HOME=/roles/<role> is
#     picked up by prepareOpenCodeRuntimeConfig, which copies
#     $XDG_CONFIG_HOME/opencode into the runtime temp dir (NOTES.md §4).
#   * runtimeConfig.heartbeat normalized server-side to
#     {enabled, intervalSec, maxConcurrentRuns}; wakeOnAssignment/wakeOnMention
#     are passed through the runtimeConfig catchall (agentRuntimeConfigSchema
#     has .catchall(z.unknown())) so on-demand wakes stay enabled even if a
#     future server ignores unknown keys (fail-closed: the script asserts the
#     echoed config contains them).
# If any assumption breaks against your Paperclip build, --dry-run output shows
# the intended payloads to adapt.
#
set -euo pipefail

PAPERCLIP_URL="${PAPERCLIP_URL:-http://127.0.0.1:3100}"
PAPERCLIP_TOKEN="${PAPERCLIP_TOKEN:-${ADMIN_API_KEY:-}}"
COMPANY_NAME="${COMPANY_NAME:-Acme Autonomous Corp}"
MODEL_DEFAULT="${MODEL_DEFAULT:-anthropic/claude-sonnet-4-5}"
MODEL_DIRECTOR="${MODEL_DIRECTOR:-${MODEL_DEFAULT}}"
MODEL_PM="${MODEL_PM:-${MODEL_DEFAULT}}"
BUDGET_DIRECTOR_USD="${BUDGET_DIRECTOR_USD:-100}"
BUDGET_DEFAULT_USD="${BUDGET_DEFAULT_USD:-50}"
TIMER_DIRECTOR_SEC="${TIMER_DIRECTOR_SEC:-1800}"
TIMER_PM_SEC="${TIMER_PM_SEC:-3600}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-120}"

DRY_RUN="false"
for arg in "$@"; do
  case "${arg}" in
    --dry-run) DRY_RUN="true" ;;
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

if [ "${DRY_RUN}" != "true" ] && [ -z "${PAPERCLIP_TOKEN}" ]; then
  echo "error: PAPERCLIP_TOKEN (or ADMIN_API_KEY) must be set" >&2
  exit 1
fi

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 1; }

TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

log() { printf '[seed] %s\n' "$*"; }

# api METHOD PATH [BODY_FILE] -> prints response body to stdout.
api() {
  local method="$1" path="$2" body_file="${3:-}"
  local args=(-sS -m 30 -H "Content-Type: application/json" -H "Authorization: Bearer ${PAPERCLIP_TOKEN}")
  if [ -n "${body_file}" ]; then
    args+=(-d "@${body_file}")
  fi
  curl "${args[@]}" -X "${method}" "${PAPERCLIP_URL}${path}"
}

# JSON list helpers over stdin are defined below (find_company_id/find_agent).

ROLE_LIST=(director pm programmer tester qa designer)

# Static per-role metadata: Paperclip role enum values come from AGENT_ROLES
# (packages/shared/src/constants.ts): ceo|cto|cmo|cfo|security|engineer|
# designer|pm|qa|devops|researcher|general.
role_paperclip_role() {
  case "$1" in
    director) echo "ceo" ;;
    pm) echo "pm" ;;
    programmer|tester) echo "engineer" ;;
    qa) echo "qa" ;;
    designer) echo "designer" ;;
    *) echo "general" ;;
  esac
}

role_display_name() {
  case "$1" in
    director) echo "Director" ;;
    pm) echo "PM" ;;
    programmer) echo "Programmer" ;;
    tester) echo "Tester" ;;
    qa) echo "QA" ;;
    designer) echo "Designer" ;;
  esac
}

role_title() {
  case "$1" in
    director) echo "Chief Executive" ;;
    pm) echo "Product Manager" ;;
    programmer) echo "Software Engineer" ;;
    tester) echo "Automated Tester" ;;
    qa) echo "Release QA Officer" ;;
    designer) echo "UI/UX Designer" ;;
  esac
}

role_model() {
  case "$1" in
    director) printf '%s' "${MODEL_DIRECTOR}" ;;
    pm) printf '%s' "${MODEL_PM}" ;;
    *) printf '%s' "${MODEL_DEFAULT}" ;;
  esac
}

role_budget_cents() {
  case "$1" in
    director) printf '%s' "$((BUDGET_DIRECTOR_USD * 100))" ;;
    *) printf '%s' "$((BUDGET_DEFAULT_USD * 100))" ;;
  esac
}

role_timer_sec() {
  case "$1" in
    director) printf '%s' "${TIMER_DIRECTOR_SEC}" ;;
    pm) printf '%s' "${TIMER_PM_SEC}" ;;
    *) printf '0' ;;
  esac
}

# build_agent_payload ROLE REPORTS_TO_UUID_OR_EMPTY -> writes JSON to stdout.
build_agent_payload() {
  local role="$1" reports_to="$2"
  local timer_sec
  timer_sec="$(role_timer_sec "${role}")"
  local heartbeat_enabled="false"
  if [ "${timer_sec}" != "0" ]; then
    heartbeat_enabled="true"
  fi
  ROLE_DIR="$1" \
  ROLE_NAME="$(role_display_name "${role}")" \
  ROLE_ENUM="$(role_paperclip_role "${role}")" \
  ROLE_TITLE="$(role_title "${role}")" \
  ROLE_MODEL="$(role_model "${role}")" \
  ROLE_BUDGET_CENTS="$(role_budget_cents "${role}")" \
  ROLE_TIMER_SEC="${timer_sec}" \
  ROLE_HEARTBEAT_ENABLED="${heartbeat_enabled}" \
  ROLE_REPORTS_TO="${reports_to}" \
  python3 -c '
import json, os
timer = int(os.environ["ROLE_TIMER_SEC"])
payload = {
    "name": os.environ["ROLE_NAME"],
    "role": os.environ["ROLE_ENUM"],
    "title": os.environ["ROLE_TITLE"],
    "adapterType": "opencode_local",
    "adapterConfig": {
        "model": os.environ["ROLE_MODEL"],
        "env": {"XDG_CONFIG_HOME": "/roles/" + os.environ["ROLE_DIR"]},
        "dangerouslySkipPermissions": True,
    },
    "runtimeConfig": {
        "heartbeat": {
            "enabled": os.environ["ROLE_HEARTBEAT_ENABLED"] == "true",
            "intervalSec": timer,
            "maxConcurrentRuns": 1,
            "wakeOnAssignment": True,
            "wakeOnMention": True,
        }
    },
    "budgetMonthlyCents": int(os.environ["ROLE_BUDGET_CENTS"]),
}
if os.environ["ROLE_REPORTS_TO"]:
    payload["reportsTo"] = os.environ["ROLE_REPORTS_TO"]
print(json.dumps(payload, indent=2))
'
}

# Role dir names are lowercase by construction (director, pm, ...); the
# display names ("PM", "QA") are never used for filesystem paths.

find_company_id() {
  # Prints the company id matching $COMPANY_NAME in a list response, else "".
  COMPANY_NAME="${COMPANY_NAME}" python3 -c '
import json, os, sys
raw = sys.stdin.read()
try:
    doc = json.loads(raw)
except Exception:
    sys.exit(0)
items = doc.get("companies", doc) if isinstance(doc, dict) else doc
if not isinstance(items, list):
    sys.exit(0)
for c in items:
    if isinstance(c, dict) and c.get("name") == os.environ["COMPANY_NAME"]:
        print(c.get("id", ""))
        break
'
}

find_agent() {
  # Prints "<id>\t<reportsTo>\t<budgetMonthlyCents>" for agent named $1, else "".
  AGENT_NAME="$1" python3 -c '
import json, os, sys
raw = sys.stdin.read()
try:
    doc = json.loads(raw)
except Exception:
    sys.exit(0)
items = doc.get("agents", doc) if isinstance(doc, dict) else doc
if not isinstance(items, list):
    sys.exit(0)
for a in items:
    if isinstance(a, dict) and a.get("name") == os.environ["AGENT_NAME"]:
        print(str(a.get("id", "")) + "\t" + str(a.get("reportsTo") or "") + "\t" + str(a.get("budgetMonthlyCents", "")))
        break
'
}

if [ "${DRY_RUN}" = "true" ]; then
  log "--dry-run: payloads that would be POSTed (no network calls)"
  printf '{"name": "%s"}\n' "${COMPANY_NAME}"
  for role in "${ROLE_LIST[@]}"; do
    # reportsTo UUIDs are unknown until creation; dry-run uses placeholders
    # showing the intended org-chart wiring.
    case "${role}" in
      director) reports_to="" ;; # reports to human board; no reportsTo key
      pm) reports_to="<director-id>" ;;
      *) reports_to="<pm-id>" ;;
    esac
    build_agent_payload "${role}" "${reports_to}"
  done
  exit 0
fi

log "waiting for Paperclip health at ${PAPERCLIP_URL} (timeout ${HEALTH_TIMEOUT_SEC}s)"
deadline=$((SECONDS + HEALTH_TIMEOUT_SEC))
while true; do
  if curl -sS -m 5 -o /dev/null "${PAPERCLIP_URL}/api/health"; then
    break
  fi
  if [ "${SECONDS}" -ge "${deadline}" ]; then
    echo "error: Paperclip did not become healthy in ${HEALTH_TIMEOUT_SEC}s" >&2
    exit 1
  fi
  sleep 3
done

log "resolving company '${COMPANY_NAME}'"
companies_body="${TMPDIR_WORK}/companies.json"
api GET "/api/companies" > "${companies_body}"
COMPANY_ID="$(find_company_id < "${companies_body}")"
if [ -z "${COMPANY_ID}" ]; then
  log "company not found; creating '${COMPANY_NAME}'"
  COMPANY_NAME="${COMPANY_NAME}" python3 -c 'import json, os; print(json.dumps({"name": os.environ["COMPANY_NAME"]}))' > "${TMPDIR_WORK}/company-create.json"
  api POST "/api/companies" "${TMPDIR_WORK}/company-create.json" > "${TMPDIR_WORK}/company.json"
  COMPANY_ID="$(python3 -c 'import json; print(json.load(open("'"${TMPDIR_WORK}"'/company.json")).get("id", ""))')"
  if [ -z "${COMPANY_ID}" ]; then
    echo "error: company creation did not return an id" >&2
    cat "${TMPDIR_WORK}/company.json" >&2
    exit 1
  fi
  log "created company ${COMPANY_ID}"
else
  log "company exists: ${COMPANY_ID}"
fi

# Pass 1: ensure all 6 agents exist (reportsTo wired in pass 2, when every id
# is known — keeps the script idempotent and order-independent).
for role in "${ROLE_LIST[@]}"; do
  name="$(role_display_name "${role}")"
  api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"
  existing="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"
  if [ -n "${existing}" ]; then
    log "agent '${name}' exists; skipping create"
  else
    log "creating agent '${name}'"
    build_agent_payload "${role}" "" > "${TMPDIR_WORK}/agent-${role}.json"
    api POST "/api/companies/${COMPANY_ID}/agents" "${TMPDIR_WORK}/agent-${role}.json" > "${TMPDIR_WORK}/agent-${role}.resp.json"
    created_id="$(python3 -c 'import json; print(json.load(open("'"${TMPDIR_WORK}"'/agent-'"${role}"'.resp.json")).get("id", ""))')"
    if [ -z "${created_id}" ]; then
      echo "error: agent '${name}' creation did not return an id" >&2
      cat "${TMPDIR_WORK}/agent-${role}.resp.json" >&2
      exit 1
    fi
    log "created agent '${name}' (${created_id})"
  fi
done

# Resolve ids for org-chart wiring.
api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"
DIRECTOR_ID="$(find_agent "Director" < "${TMPDIR_WORK}/agents.json" | cut -f1)"
PM_ID="$(find_agent "PM" < "${TMPDIR_WORK}/agents.json" | cut -f1)"
if [ -z "${DIRECTOR_ID}" ] || [ -z "${PM_ID}" ]; then
  echo "error: could not resolve Director/PM ids for org-chart wiring" >&2
  exit 1
fi

# Pass 2: enforce reportsTo + budget (idempotent: PATCH only on drift).
for role in "${ROLE_LIST[@]}"; do
  name="$(role_display_name "${role}")"
  current="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"
  agent_id="$(printf '%s' "${current}" | cut -f1)"
  current_reports="$(printf '%s' "${current}" | cut -f2)"
  current_budget="$(printf '%s' "${current}" | cut -f3)"
  want_reports=""
  case "${role}" in
    pm) want_reports="${DIRECTOR_ID}" ;;
    programmer|tester|qa|designer) want_reports="${PM_ID}" ;;
  esac
  want_budget="$(role_budget_cents "${role}")"
  if [ "${current_reports}" != "${want_reports}" ] || [ "${current_budget}" != "${want_budget}" ]; then
    log "updating '${name}': reportsTo=${want_reports:-none} budgetMonthlyCents=${want_budget}"
    PATCH_REPORTS_TO="${want_reports}" PATCH_BUDGET="${want_budget}" python3 -c '
import json, os
payload = {"budgetMonthlyCents": int(os.environ["PATCH_BUDGET"])}
if os.environ["PATCH_REPORTS_TO"]:
    payload["reportsTo"] = os.environ["PATCH_REPORTS_TO"]
print(json.dumps(payload))
' > "${TMPDIR_WORK}/patch-${role}.json"
    api PATCH "/api/agents/${agent_id}" "${TMPDIR_WORK}/patch-${role}.json" > /dev/null
  else
    log "agent '${name}' already correctly wired; no update"
  fi
done

log "seed complete: company '${COMPANY_NAME}' (${COMPANY_ID}) with 6 agents"
log "org chart: Director -> PM -> {Programmer, Tester, QA, Designer}"
