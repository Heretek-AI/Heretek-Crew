#!/usr/bin/env bash
#
# enrich-fleet-verify.sh — verify the S1+S2+S3 fleet enrichment end to end and
# report per-agent PASS / BLOCKED-NO-CREDS / FAIL, without writing anything
# except the probe invocations themselves.
#
# STAGE S4 (verify + report only): Pass A re-reads each agent's server state
# with read-only GETs (instructions bundle hash vs local AGENTS.md, desired
# skill keys vs local skill slugs, effective tool summary non-empty) and marks
# agents failing any readiness check SKIP-NOT-READY with an explicit reason —
# they are excluded from the probe pass. Pass B POSTs one test-environment
# probe per ready agent. Pass C classifies each probe result with the exact
# upstream pass gate and prints a per-role summary table.
#
# This script performs NO persistent writes: no PUT/POST creates, updates,
# binds, or syncs of any kind. The ONLY non-GET calls are the per-agent
# POST .../adapters/:type/test-environment probes, which resolve secrets
# read-only and return an AdapterEnvironmentTestResult without persisting
# anything (routes/agents.ts:3329-3336 res.json({ ...result, status, checks })).
#
# Usage:
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... bash scripts/enrich-fleet-verify.sh [--dry-run] [--help] [--only <role>[,<role>...]] [--environment <envId>]
#
#   --dry-run     Print the per-role readiness/probe plan (local charter byte
#                 counts + sha256, local skill slugs with derived expected
#                 keys, exact probe request template) without performing ANY
#                 network calls. No PAPERCLIP_TOKEN is required. Safe against
#                 a dead PAPERCLIP_URL: not a single byte is sent.
#   --only        Restrict the run to a comma-separated subset of role dirs,
#                 e.g. --only dba-specialist or --only dba-specialist,k8s-orchestrator
#                 (also accepts --only=<list>). Unknown role dirs fail closed.
#   --environment Probe inside this Paperclip environment (UUID). When omitted,
#                 the environmentId key is OMITTED from every probe body and
#                 the server tests each agent's saved default
#                 (routes/agents.ts: omission selects savedAgent default).
#   --help, -h    Print this usage guide and exit.
#
# Environment (all optional unless noted):
#   PAPERCLIP_URL             Base URL of the Paperclip server.
#                             Default: http://127.0.0.1:3100
#   PAPERCLIP_TOKEN           Board API token for Authorization: Bearer auth.
#                             Falls back to ADMIN_API_KEY. Required unless
#                             --dry-run is passed.
#   ADMIN_API_KEY             Fallback for PAPERCLIP_TOKEN.
#   COMPANY_NAME              Fleet company used to resolve agent ids.
#                             Default: "Heretek Autonomous Fleet"
#   HEALTH_TIMEOUT_SEC        How long to wait for Paperclip health.
#                             Default: 120
#   ROLES_DIR                 Directory holding the per-role charters and skill
#                             trees (read-only; used as the expected state).
#                             Default: <repo>/roles (resolved from this script's path).
#
# Upstream API contracts (verified against /tmp/paperclip @73659c6 — re-verify
# here before any live run if the checkout moved):
#   1. Probe: POST /api/companies/:companyId/adapters/:type/test-environment
#      (server/src/routes/agents.ts:3091-3094) with testAdapterEnvironmentSchema
#      (packages/shared/src/validators/agent.ts:260-289): adapterConfig
#      (optional, defaults to {}), environmentId (optional UUID-or-null),
#      agentId (optional UUID), runner/aiConnection/testCredentials optional.
#      Mirrors the NewAgentSetup flow: runTest (ui/src/components/new-agent/
#      NewAgentSetup.tsx:464-501) -> testAgentSetup (ui/src/lib/test-agent-setup
#      .ts:7-40, always sends adapterConfig + agentId + environmentId) ->
#      agentsApi.testEnvironment (ui/src/api/agents.ts:251-266).
#   2. Readiness: GET /api/agents/:id/instructions-bundle (S1 entry hash),
#      GET /api/agents/:id/skills (S2 desiredSkillEntries/desiredSkills keys),
#      GET /api/companies/:companyId/tools/profiles/effective/agents/:agentId
#      (S3 ToolProfileEffectiveSummary: allowedTools/allowedToolNames).
#   3. Agent source: GET /api/agents/:id (routes/agents.ts:4002) returns
#      buildAgentDetail with the agent row (adapterType, adapterConfig
#      redacted for display, runtimeConfig, defaultEnvironmentId).
#   4. Expected skill keys: services/company-skills.ts deriveCanonicalSkillKey
#      (:696-699): managed_local sourceKind -> `company/<companyId>/<slug>`.
#      Derived locally from the server-learned company id; a key that does not
#      match means S2 did not bind it (SKIP-NOT-READY, never guessed-away).
#
# Probe payload decision (adapterConfig forwarded VERBATIM from GET agent):
#   Omitting adapterConfig does NOT fall back to the stored config. The route
#   defaults it to {} (routes/agents.ts:3102: req.body?.adapterConfig ?? {}),
#   and restoreRedactedAgentEnv (routes/agents.ts:2894-2914) only fills
#   REDACTED placeholders inside the REQUESTED env from the saved config —
#   with no requested env it returns the request unchanged (:2900 early
#   return). So `{}` would probe an empty config. Instead this script GETs
#   each ready agent, forwards its CURRENT adapterConfig verbatim plus agentId
#   (redacted values are restored server-side for the same adapter type,
#   routes/agents.ts:3143-3151), omits runner so the saved-execution path is
#   retained (routes/agents.ts:3152-3156: runner undefined + same adapterType
#   + same harness -> retainsSavedExecution), and sends environmentId only
#   when --environment is passed (omission -> saved default).
#
# Classification (mirrors assertHarnessTestPassed exactly,
# server/src/services/agent-harness-verification.ts:16-30):
#   PASS            := any check with level "info" AND (code matching
#                      /hello_probe_(passed|succeeded)$/ OR code exactly
#                      "ai_connection_api_key_reverified"). The api_key method
#                      path emits ai_connection_api_key_reverified via
#                      validateAiKey (agent-environment-test.ts:510) and it
#                      counts as pass WITHOUT a hello probe (:22).
#   BLOCKED-NO-CREDS := not PASS, and any check with code exactly
#                      "adapter_auth_missing" (ADAPTER_AUTH_MISSING_CHECK_CODE,
#                      packages/shared/src/adapter-auth-check-code.ts:12) OR
#                      matching /_hello_probe_auth_required$/ (:20-21). This is
#                      EXPECTED until provider credentials land (issue #3):
#                      without a binding/creds the hello probe runs against
#                      real opencode and needs working provider auth in env.
#   FAIL            := anything else (including warn-with-hello_probe but no
#                      pass, which the upstream gate also rejects as
#                      "incomplete"). Check codes are listed in the detail.
#
# Exit codes: 0 zero FAIL and zero SKIP-NOT-READY (BLOCKED-NO-CREDS is
# allowed and reported as a count + list); 1 one or more FAILed or skipped
# roles (counts printed) or a fail-closed preflight tripped; 2 CLI misuse
# (unknown argument, bad --only value, bad --environment value).
# A SKIP-NOT-READY role fails the exit because that role could not be
# verified at all — reporting success would be permissive, not fail-closed.
#
# Secret hygiene: only names/keys/ids/counts/check-codes/statuses are logged
# (check MESSAGES are never printed — they may carry paths or env material;
# adapterConfig bodies are never printed — only the fact they were forwarded
# verbatim); the token is only ever sent as an Authorization header.
#
# Examples:
#   bash scripts/enrich-fleet-verify.sh --dry-run
#   PAPERCLIP_URL=http://127.0.0.1:3100 PAPERCLIP_TOKEN=xxx bash scripts/enrich-fleet-verify.sh
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... bash scripts/enrich-fleet-verify.sh --only dba-specialist
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... bash scripts/enrich-fleet-verify.sh --environment 00000000-0000-0000-0000-000000000000
#
set -euo pipefail

PAPERCLIP_URL="${PAPERCLIP_URL:-http://127.0.0.1:3100}"
PAPERCLIP_TOKEN="${PAPERCLIP_TOKEN:-${ADMIN_API_KEY:-}}"
COMPANY_NAME="${COMPANY_NAME:-Heretek Autonomous Fleet}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-120}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
ROLES_DIR="${ROLES_DIR:-${REPO_ROOT}/roles}"

# Canonical 51 role IDs in catalog order (Roles 01-51; Role 51
# ai-red-teamer promoted Wave C P1-4 — see ROLE_CATALOG_50.md Total line).
# Copied verbatim from scripts/seed-50-fleet.sh: the role->display-name
# mapping MUST stay identical so agent lookups resolve the seeded fleet.
ROLE_LIST=(
  exec-director product-director tpm-scrum-lead system-architect tech-docs-lead
  ux-research-analyst game-systems-dev graphics-shader-eng engine-systems-eng
  game-ai-dev physics-sim-eng tech-artist-pipeline ui-ux-designer
  design-system-eng a11y-specialist fe-perf-eng mobile-web-eng brand-copy-spec
  rust-systems-spec go-backend-eng python-backend-spec ts-node-fullstack
  cpp-lowlevel-eng java-kotlin-eng ios-mobile-spec android-mobile-spec
  cloud-platform-eng k8s-orchestrator sre-incident-eng observability-eng
  dba-specialist cache-streaming-eng e2e-browser-qa api-contract-tester
  load-stress-tester sabotage-qa-tester static-analysis-lead release-qa-officer
  appsec-engineer cloud-sec-auditor binary-reverse-eng firmware-sec-analyst
  threat-modeler compliance-auditor data-pipeline-eng vector-rag-spec
  mlops-serving-eng analytics-metrics-eng dependency-patcher git-drift-coord
  ai-red-teamer
)

# Display names are the catalog Role headers (roles-catalog/0*.md) and double
# as the Paperclip agent `name` used for idempotent lookup.
# Copied verbatim from scripts/seed-50-fleet.sh — do not reinvent names.
role_display_name() {
  case "$1" in
    exec-director) echo "Director / CEO-Delegate" ;;
    product-director) echo "Product Director / Head of Product" ;;
    tpm-scrum-lead) echo "Technical Product Manager / Scrum Lead" ;;
    system-architect) echo "System Architect" ;;
    tech-docs-lead) echo "Technical Documentation Lead" ;;
    ux-research-analyst) echo "User Research & Feedback Analyst" ;;
    game-systems-dev) echo "Game Systems & Gameplay Programmer" ;;
    graphics-shader-eng) echo "Graphics & Shader Engineer" ;;
    engine-systems-eng) echo "Engine & Systems Programmer" ;;
    game-ai-dev) echo "Game AI Programmer" ;;
    physics-sim-eng) echo "Physics & Simulation Engineer" ;;
    tech-artist-pipeline) echo "Technical Artist & Asset Pipeline Lead" ;;
    ui-ux-designer) echo "UI/UX Designer & Prototyper" ;;
    design-system-eng) echo "Design System Engineer" ;;
    a11y-specialist) echo "Accessibility (a11y) & Usability Specialist" ;;
    fe-perf-eng) echo "Frontend Performance Engineer" ;;
    mobile-web-eng) echo "Mobile Web & Responsive Layout Engineer" ;;
    brand-copy-spec) echo "Brand & Creative Copy Specialist" ;;
    rust-systems-spec) echo "Rust Systems Specialist" ;;
    go-backend-eng) echo "Go Backend Engineer" ;;
    python-backend-spec) echo "Python Backend & Systems Specialist" ;;
    ts-node-fullstack) echo "TypeScript / Node Fullstack Engineer" ;;
    cpp-lowlevel-eng) echo "C++ Systems & Low-Level Engineer" ;;
    java-kotlin-eng) echo "Java / Kotlin Enterprise Engineer" ;;
    ios-mobile-spec) echo "Mobile iOS Specialist" ;;
    android-mobile-spec) echo "Mobile Android Specialist" ;;
    cloud-platform-eng) echo "Cloud Platform Engineer" ;;
    k8s-orchestrator) echo "Kubernetes & Container Orchestrator" ;;
    sre-incident-eng) echo "Site Reliability Engineer" ;;
    observability-eng) echo "Observability & Telemetry Engineer" ;;
    dba-specialist) echo "Database Administrator" ;;
    cache-streaming-eng) echo "Cache & Streaming Systems Engineer" ;;
    e2e-browser-qa) echo "End-to-End Browser Automation Engineer" ;;
    api-contract-tester) echo "API & Contract Testing Specialist" ;;
    load-stress-tester) echo "Load & Performance Stress Tester" ;;
    sabotage-qa-tester) echo "Adversarial Red-Proof Sabotage Tester" ;;
    static-analysis-lead) echo "Code Style & Static Analysis Lead" ;;
    release-qa-officer) echo "Release QA & Acceptance Sign-off Officer" ;;
    appsec-engineer) echo "Application Security (AppSec) Engineer" ;;
    cloud-sec-auditor) echo "Cloud Security & IAM Auditor" ;;
    binary-reverse-eng) echo "Binary & Protocol Reverse Engineer" ;;
    firmware-sec-analyst) echo "Firmware & Embedded Security Analyst" ;;
    threat-modeler) echo "Threat Modeling & Hardening Engineer" ;;
    compliance-auditor) echo "Compliance & License Auditor" ;;
    data-pipeline-eng) echo "Data Pipeline & ETL Engineer" ;;
    vector-rag-spec) echo "Vector Search & RAG Specialist" ;;
    mlops-serving-eng) echo "MLOps & Model Serving Engineer" ;;
    analytics-metrics-eng) echo "Analytics & Metrics Engineer" ;;
    dependency-patcher) echo "Dependency & CVE Patching Steward" ;;
    git-drift-coord) echo "Git & Worktree Drift Coordinator" ;;
    ai-red-teamer) echo "Adversarial AI Red-Teamer" ;;
    *) echo "$1" ;;
  esac
}

is_known_role() {
  local candidate="$1" role
  for role in "${ROLE_LIST[@]}"; do
    if [ "${role}" = "${candidate}" ]; then
      return 0
    fi
  done
  return 1
}

DRY_RUN="false"
ONLY_RAW=""
ONLY_SET="false"
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
        echo "error: --only requires a non-empty value, e.g. --only dba-specialist (see --help)" >&2
        exit 2
      fi
      case "$2" in
        -*)
          echo "error: --only requires a non-empty value, e.g. --only dba-specialist (see --help)" >&2
          exit 2
          ;;
      esac
      ONLY_RAW="$2"; ONLY_SET="true"; shift 2 ;;
    --only=*)
      ONLY_RAW="${1#--only=}"; ONLY_SET="true"; shift ;;
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
  echo "error: PAPERCLIP_URL must be set (default http://127.0.0.1:3100)" >&2
  exit 1
fi

# The probe schema types environmentId as a UUID (validators/agent.ts); an
# explicitly passed non-UUID can never validate server-side, so reject it
# here fail-closed before any network call.
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

# Build the target role list (catalog order), validating any --only filter
# fail-closed against the canonical ROLE_LIST.
TARGET_ROLES=()
if [ "${ONLY_SET}" = "false" ]; then
  TARGET_ROLES=("${ROLE_LIST[@]}")
else
  ONLY_NORM="$(printf '%s' "${ONLY_RAW}" | tr ',' ' ')"
  WANTS=()
  read -ra WANTS <<< "${ONLY_NORM}"
  if [ "${#WANTS[@]}" -eq 0 ]; then
    echo "error: --only requires a non-empty role list, e.g. --only dba-specialist (see --help)" >&2
    exit 2
  fi
  for want in "${WANTS[@]}"; do
    if ! is_known_role "${want}"; then
      echo "error: unknown role '${want}' in --only (valid role dirs: ${ROLE_LIST[*]}; see roles/)" >&2
      exit 2
    fi
  done
  for role in "${ROLE_LIST[@]}"; do
    for want in "${WANTS[@]}"; do
      if [ "${role}" = "${want}" ]; then
        TARGET_ROLES+=("${role}")
        break
      fi
    done
  done
fi

command -v sha256sum >/dev/null 2>&1 || { echo "error: sha256sum is required" >&2; exit 1; }

log() { printf '[enrich-verify] %s\n' "$*"; }
ok() { printf '[enrich-verify] OK: %s\n' "$*"; }
bad() { printf '[enrich-verify] ERROR: %s\n' "$*" >&2; }

# List the skill slugs (dir basenames) for a role, one per line, sorted.
# Fails (nonzero) when the role has no skills dir or no SKILL.md files.
role_skill_slugs() {
  local role="$1" skills_dir="${ROLES_DIR}/$1/.opencode/skills"
  local found=0 dir slug
  if [ ! -d "${skills_dir}" ]; then
    return 1
  fi
  for dir in "${skills_dir}"/*/; do
    [ -d "${dir}" ] || continue
    [ -f "${dir}/SKILL.md" ] || continue
    slug="$(basename "${dir}")"
    printf '%s\n' "${slug}"
    found=1
  done
  [ "${found}" = "1" ]
}

# --dry-run exits here, BEFORE curl/python3 are required and before any
# network call could occur: every statement above and below this block is
# pure local computation (arg parsing, file reads, hashes). Any curl
# invocation while DRY_RUN=true is a bug — gate all api() calls live-only.
if [ "${DRY_RUN}" = "true" ]; then
  log "--dry-run: per-role verify/probe plan (no network calls)"
  if [ "${ENV_SET}" = "true" ]; then
    log "environment: every probe body would carry environmentId '${ENV_ID}' (explicit target)"
  else
    log "environment: environmentId key omitted from every probe body (server tests each agent's saved default)"
  fi
  log "probe template: POST /api/companies/<companyId>/adapters/<adapterType>/test-environment"
  log 'probe body template: {"adapterConfig": <verbatim from GET /api/agents/<agentId> — redacted values restored server-side>, "agentId": "<agentId>"[, "environmentId": "<env>"]}'
  log 'pass gate (mirrors assertHarnessTestPassed): info hello_probe_(passed|succeeded)$ OR ai_connection_api_key_reverified -> PASS; adapter_auth_missing | _hello_probe_auth_required$ -> BLOCKED-NO-CREDS; else FAIL'
  for role in "${TARGET_ROLES[@]}"; do
    name="$(role_display_name "${role}")"
    local_file="${ROLES_DIR}/${role}/AGENTS.md"
    if [ -f "${local_file}" ]; then
      local_bytes="$(wc -c < "${local_file}" | tr -d '[:space:]')"
      local_sha="$(sha256sum "${local_file}" | cut -d' ' -f1)"
      log "role '${role}' (agent '${name}'): pass A would compare bundle entry hash vs local AGENTS.md (${local_bytes} bytes, sha256:${local_sha})"
    else
      log "role '${role}' (agent '${name}'): pass A input MISSING (no local charter at roles/${role}/AGENTS.md) — would SKIP-NOT-READY live"
    fi
    if slugs="$(role_skill_slugs "${role}")"; then
      nslugs="$(printf '%s\n' "${slugs}" | wc -l | tr -d '[:space:]')"
      log "role '${role}': pass A would require ${nslugs} desired skill key(s): $(printf '%s' "${slugs}" | sed 's|^|company/<companyId>/|; s|$||' | paste -sd' ' -)"
    else
      log "role '${role}': pass A input MISSING (no skills under roles/${role}/.opencode/skills/*/SKILL.md) — would SKIP-NOT-READY live"
    fi
    log "role '${role}': pass A would require non-empty effective tool summary; pass B would GET /api/agents/<agentId> (adapterType + verbatim adapterConfig) then POST the probe above"
  done
  log "dry-run summary: ${#TARGET_ROLES[@]} role(s) would be readiness-checked (S1 hash + S2 keys + S3 effective) then probed; zero network calls attempted"
  exit 0
fi

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 1; }

TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

# api METHOD PATH [BODY_FILE] -> prints response body to stdout.
# Same contract as scripts/seed-50-fleet.sh: --fail-with-body (curl >= 7.76)
# makes every HTTP error (4xx/5xx) exit nonzero WITH the body on stderr —
# no `|| true`, no status swallowing: per-role callers guard each call and
# record a role outcome, and preflights run under `set -e` fail-closed.
api() {
  local method="$1" path="$2" body_file="${3:-}"
  local args=(-sS -m 60 --fail-with-body -H "Content-Type: application/json" -H "Authorization: Bearer ${PAPERCLIP_TOKEN}")
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
  # Prints "<id>\t<reportsTo>\t<budgetMonthlyCents>" for agent named $1, else "".
  # Fail-closed (mirrors seed-50-fleet.sh): parse failure or unexpected
  # shape exits nonzero, never "" = "not found".
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
        print(str(a.get("id", "")) + "\t" + str(a.get("reportsTo") or "") + "\t" + str(a.get("budgetMonthlyCents", "")))
        break
'
}

bundle_inspect() {
  # $1 = instructions-bundle JSON file. Prints
  # "<entryFile>\t<baseRevisionId or empty>\t<serverSha or empty>\t<true|false>".
  # found=true only when the entry carries content (hashed here) or an
  # explicit hash field. Unparseable bodies exit NONZERO (fail-closed:
  # never "empty bundle, write null revision" on a 500 page).
  python3 -c '
import hashlib, json, sys
raw = open(sys.argv[1], "r", encoding="utf-8").read()
try:
    doc = json.loads(raw)
except Exception as exc:
    sys.stderr.write("error: instructions-bundle response is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
if not isinstance(doc, dict):
    sys.stderr.write("error: instructions-bundle response has unexpected shape (not an object)\n")
    sys.exit(1)
body = doc
for key in ("bundle", "data"):
    inner = doc.get(key)
    if isinstance(inner, dict) and ("entryFile" in inner or "entryPath" in inner or "files" in inner):
        body = inner
        break
entry = body.get("entryFile") or body.get("entryPath") or body.get("entry") or "AGENTS.md"
rev = body.get("headRevisionId") or body.get("headRevision") or body.get("revisionId") or body.get("baseRevisionId") or ""
if isinstance(rev, dict):
    rev = rev.get("id", "")
rev = "" if rev is None else str(rev)
files = body.get("files")
if isinstance(files, dict):
    files = list(files.values())
if not isinstance(files, list):
    files = []
server_sha = ""
found = "false"
for item in files:
    if not isinstance(item, dict):
        continue
    path = str(item.get("path", "") or "")
    if path == entry or path == ("./" + entry) or path.rsplit("/", 1)[-1] == entry.rsplit("/", 1)[-1]:
        content = item.get("content")
        if isinstance(content, str):
            server_sha = hashlib.sha256(content.encode("utf-8")).hexdigest()
            found = "true"
        else:
            for hk in ("sha256", "hash", "contentHash", "content_sha256"):
                hv = item.get(hk)
                if isinstance(hv, str) and hv:
                    server_sha = hv
                    found = "true"
                    break
        break
if found == "false":
    for key in ("entryContent", "content", "headContent"):
        if isinstance(body.get(key), str):
            server_sha = hashlib.sha256(body[key].encode("utf-8")).hexdigest()
            found = "true"
            break
print("%s\t%s\t%s\t%s" % (entry, rev, server_sha, found))
' "$1"
}

agent_desired_keys() {
  # $1 = agent skills snapshot (GET /api/agents/:id/skills). Prints the set
  # of desired skill keys, one per line, deduplicated. Exits NONZERO on
  # unparseable bodies (fail-closed).
  python3 -c '
import json, sys
raw = open(sys.argv[1], "r", encoding="utf-8").read()
try:
    doc = json.loads(raw)
except Exception as exc:
    sys.stderr.write("error: agent skills response is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
if not isinstance(doc, dict):
    sys.stderr.write("error: agent skills response has unexpected shape (expected object)\n")
    sys.exit(1)
keys = []
for entry in doc.get("desiredSkillEntries") or []:
    if isinstance(entry, dict) and isinstance(entry.get("key"), str) and entry["key"]:
        keys.append(entry["key"])
for value in doc.get("desiredSkills") or []:
    if isinstance(value, str) and value:
        keys.append(value)
    elif isinstance(value, dict) and isinstance(value.get("key"), str) and value["key"]:
        keys.append(value["key"])
seen = set()
for key in keys:
    if key not in seen:
        seen.add(key)
        print(key)
' "$1"
}

effective_counts() {
  # $1 = effective-summary body. Prints
  # "allowedToolsCount\tallowedToolNamesCount\tprofileCount". Exits NONZERO
  # on unparseable bodies (fail-closed: never treat a 500 page as "empty").
  python3 -c '
import json, sys
raw = open(sys.argv[1], "r", encoding="utf-8").read()
try:
    doc = json.loads(raw)
except Exception as exc:
    sys.stderr.write("error: effective summary response is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
if not isinstance(doc, dict):
    sys.stderr.write("error: effective summary response has unexpected shape (expected object)\n")
    sys.exit(1)
for key in ("allowedTools", "allowedToolNames", "profiles"):
    value = doc.get(key)
    if value is not None and not isinstance(value, list):
        sys.stderr.write("error: effective summary field %r has unexpected shape (expected array)\n" % (key,))
        sys.exit(1)
print("%d\t%d\t%d" % (
    len(doc.get("allowedTools") or []),
    len(doc.get("allowedToolNames") or []),
    len(doc.get("profiles") or []),
))
' "$1"
}

agent_probe_source() {
  # $1 = GET /api/agents/:id detail JSON, $2 = output path for adapterConfig.
  # Prints "<adapterType>\t<defaultEnvironmentId or empty>" and writes the
  # agent's CURRENT adapterConfig object VERBATIM to $2 (redacted display
  # values included — the server restores them for the same adapter type;
  # routes/agents.ts:2894-2914,3143-3151). Exits NONZERO when adapterType is
  # missing/empty or adapterConfig is not an object (fail-closed: without a
  # verbatim config there is no stored-config fallback to probe with —
  # routes/agents.ts:3102 defaults an omitted adapterConfig to {}).
  python3 -c '
import json, sys
raw = open(sys.argv[1], "r", encoding="utf-8").read()
try:
    doc = json.loads(raw)
except Exception as exc:
    sys.stderr.write("error: agent detail response is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
body = doc
if isinstance(doc, dict):
    for key in ("agent", "data"):
        inner = doc.get(key)
        if isinstance(inner, dict) and ("adapterType" in inner or "adapterConfig" in inner):
            body = inner
            break
if not isinstance(body, dict):
    sys.stderr.write("error: agent detail response has unexpected shape (expected object)\n")
    sys.exit(1)
atype = body.get("adapterType")
cfg = body.get("adapterConfig")
denv = body.get("defaultEnvironmentId")
if not isinstance(atype, str) or not atype:
    sys.stderr.write("error: agent detail is missing adapterType\n")
    sys.exit(1)
if not isinstance(cfg, dict):
    sys.stderr.write("error: agent detail adapterConfig is not an object\n")
    sys.exit(1)
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    json.dump(cfg, fh)
print("%s\t%s" % (atype, denv if isinstance(denv, str) and denv else ""))
' "$1" "$2"
}

build_probe_payload() {
  # $1 = adapterConfig JSON file (verbatim from agent detail),
  # $2 = agent id, $3 = output payload path.
  # Mirrors the UI payload shape (ui/src/lib/test-agent-setup.ts: payload
  # always carries adapterConfig + agentId; environmentId only when the
  # caller selected one — here: only with --environment, so omission selects
  # the saved default server-side). runner/aiConnection/testCredentials are
  # deliberately absent: no prospective switch, no managed override, no
  # one-shot keys to inject.
  CFG_PATH="$1" AGENT_ID="$2" OUT_PATH="$3" python3 -c '
import json, os
with open(os.environ["CFG_PATH"], "r", encoding="utf-8") as fh:
    cfg = json.load(fh)
if not isinstance(cfg, dict):
    raise SystemExit("error: adapterConfig file is not an object")
payload = {"adapterConfig": cfg, "agentId": os.environ["AGENT_ID"]}
req_env = os.environ.get("REQ_ENV", "")
if req_env:
    payload["environmentId"] = req_env
with open(os.environ["OUT_PATH"], "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
'
}

classify_result() {
  # $1 = AdapterEnvironmentTestResult JSON file. Prints
  # "<STATUS>\t<detail>" where STATUS is PASS, BLOCKED-NO-CREDS, or FAIL,
  # mirroring assertHarnessTestPassed
  # (server/src/services/agent-harness-verification.ts:16-30). Detail carries
  # check CODES (and levels) only — never messages (secret hygiene).
  # Exits NONZERO on unparseable bodies (caller records FAIL, fail-closed).
  python3 -c '
import json, re, sys
raw = open(sys.argv[1], "r", encoding="utf-8").read()
try:
    doc = json.loads(raw)
except Exception as exc:
    sys.stderr.write("error: probe result is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
if not isinstance(doc, dict):
    sys.stderr.write("error: probe result has unexpected shape (expected object)\n")
    sys.exit(1)
status = doc.get("status", "")
checks = doc.get("checks")
if not isinstance(checks, list):
    sys.stderr.write("error: probe result checks have unexpected shape (expected array)\n")
    sys.exit(1)
def code_of(check):
    return check.get("code", "") if isinstance(check, dict) else ""
def level_of(check):
    return check.get("level", "") if isinstance(check, dict) else ""
verifying = sorted(set(
    code_of(c) for c in checks
    if level_of(c) == "info" and (
        re.search(r"hello_probe_(passed|succeeded)$", str(code_of(c))) is not None
        or code_of(c) == "ai_connection_api_key_reverified"
    )
))
if verifying:
    print("PASS\tverified via %s" % (",".join(verifying)))
    sys.exit(0)
auth = sorted(set(
    code_of(c) for c in checks
    if code_of(c) == "adapter_auth_missing"
    or re.search(r"_hello_probe_auth_required$", str(code_of(c))) is not None
))
if auth:
    print("BLOCKED-NO-CREDS\tauth-required check(s): %s" % (",".join(auth)))
    sys.exit(0)
codes = ",".join(
    "%s(%s)" % (code_of(c), level_of(c)) for c in checks if isinstance(c, dict) and code_of(c)
)
print("FAIL\tstatus=%s checks=%s" % (status if isinstance(status, str) else "?", codes if codes else "(none)"))
' "$1"
}

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

log "resolving company '${COMPANY_NAME}'"
companies_body="${TMPDIR_WORK}/companies.json"
api GET "/api/companies" > "${companies_body}"
COMPANY_ID=""
if ! COMPANY_ID="$(find_company_id < "${companies_body}")"; then
  echo "error: company list response is unparseable; aborting (server body above)" >&2
  exit 1
fi
if [ -z "${COMPANY_ID}" ]; then
  echo "error: company '${COMPANY_NAME}' not found — seed the fleet first with scripts/seed-50-fleet.sh" >&2
  exit 1
fi
log "company exists: ${COMPANY_ID}"

# The agent list is fetched ONCE up front and reused from the cache
# (mirrors seed-50-fleet.sh): refreshed only when a lookup misses, so
# steady-state runs cost exactly one LIST and correctness never depends
# on cache freshness.
api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"

if [ "${ENV_SET}" = "true" ]; then
  log "probing inside environment ${ENV_ID} (explicit target)"
else
  log "no --environment: environmentId omitted from probe bodies (server tests each agent's saved default)"
fi

# Per-role result records, kept in catalog order for the summary table.
REC_ROLE=()
REC_STATUS=()
REC_DETAIL=()
record() {
  REC_ROLE+=("$1")
  REC_STATUS+=("$2")
  REC_DETAIL+=("$3")
}

total=0
npass=0
nblocked=0
nfailed=0
nskipped=0
FAILED_LIST=""
SKIPPED_LIST=""
BLOCKED_LIST=""
for role in "${TARGET_ROLES[@]}"; do
  total=$((total + 1))
  name="$(role_display_name "${role}")"

  # ---- Pass A inputs (local expected state). ----
  local_file="${ROLES_DIR}/${role}/AGENTS.md"
  if [ ! -f "${local_file}" ]; then
    bad "role '${role}': SKIP-NOT-READY (no local charter at roles/${role}/AGENTS.md)"
    record "${role}" "SKIP-NOT-READY" "no local charter at roles/${role}/AGENTS.md"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi
  local_sha="$(sha256sum "${local_file}" | cut -d' ' -f1)"
  if ! slugs="$(role_skill_slugs "${role}")"; then
    bad "role '${role}': SKIP-NOT-READY (no skills under roles/${role}/.opencode/skills/*/SKILL.md)"
    record "${role}" "SKIP-NOT-READY" "no local skills under roles/${role}/.opencode/skills/*/SKILL.md"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi
  mapfile -t role_slugs <<< "${slugs}"

  # ---- Pass A: resolve the agent (read-only). ----
  existing=""
  if ! existing="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"; then
    bad "role '${role}': SKIP-NOT-READY (agent list is unparseable)"
    record "${role}" "SKIP-NOT-READY" "agent list unparseable"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi
  if [ -z "${existing}" ]; then
    # Miss against a possibly stale cache: refresh once before concluding
    # the agent is absent.
    if ! api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"; then
      bad "role '${role}': SKIP-NOT-READY (agent list refresh failed)"
      record "${role}" "SKIP-NOT-READY" "agent list refresh failed"
      nskipped=$((nskipped + 1))
      SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
      continue
    fi
    if ! existing="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"; then
      bad "role '${role}': SKIP-NOT-READY (agent list is unparseable after refresh)"
      record "${role}" "SKIP-NOT-READY" "agent list unparseable after refresh"
      nskipped=$((nskipped + 1))
      SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
      continue
    fi
  fi
  if [ -z "${existing}" ]; then
    bad "role '${role}': SKIP-NOT-READY (agent '${name}' not found — run S1/S2/S3 after scripts/seed-50-fleet.sh)"
    record "${role}" "SKIP-NOT-READY" "agent '${name}' not found"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi
  agent_id="$(printf '%s' "${existing}" | cut -f1)"
  if [ -z "${agent_id}" ]; then
    bad "role '${role}': SKIP-NOT-READY (agent '${name}' resolved without an id)"
    record "${role}" "SKIP-NOT-READY" "agent '${name}' resolved without an id"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi

  # ---- Pass A1 (S1): bundle entry hash must match the local charter. ----
  if ! api GET "/api/agents/${agent_id}/instructions-bundle" > "${TMPDIR_WORK}/bundle-${role}.json"; then
    bad "role '${role}': SKIP-NOT-READY (bundle read failed for agent '${name}')"
    record "${role}" "SKIP-NOT-READY" "S1 bundle read failed"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi
  bundle_info=""
  if ! bundle_info="$(bundle_inspect "${TMPDIR_WORK}/bundle-${role}.json")"; then
    bad "role '${role}': SKIP-NOT-READY (bundle response for agent '${name}' is unparseable)"
    record "${role}" "SKIP-NOT-READY" "S1 bundle response unparseable"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi
  server_sha="$(printf '%s' "${bundle_info}" | cut -f3)"
  server_found="$(printf '%s' "${bundle_info}" | cut -f4)"
  if [ "${server_found}" != "true" ] || [ -z "${server_sha}" ] || [ "${server_sha}" != "${local_sha}" ]; then
    bad "role '${role}': SKIP-NOT-READY (S1 instructions not current for agent '${name}'; local sha256:${local_sha})"
    record "${role}" "SKIP-NOT-READY" "S1 instructions not current (local sha256:${local_sha})"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi

  # ---- Pass A2 (S2): every local slug's canonical key must be desired. ----
  if ! api GET "/api/agents/${agent_id}/skills" > "${TMPDIR_WORK}/desired-${role}.json"; then
    bad "role '${role}': SKIP-NOT-READY (desired-skills read failed for agent '${name}')"
    record "${role}" "SKIP-NOT-READY" "S2 desired-skills read failed"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi
  desired=""
  if ! desired="$(agent_desired_keys "${TMPDIR_WORK}/desired-${role}.json")"; then
    bad "role '${role}': SKIP-NOT-READY (desired-skills response for agent '${name}' is unparseable)"
    record "${role}" "SKIP-NOT-READY" "S2 desired-skills response unparseable"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi
  # Canonical managed_local keys (services/company-skills.ts:696-699).
  absent_slugs=""
  for slug in "${role_slugs[@]}"; do
    [ -n "${slug}" ] || continue
    want="company/${COMPANY_ID}/${slug}"
    present="false"
    while IFS= read -r have; do
      [ -n "${have}" ] || continue
      if [ "${have}" = "${want}" ]; then
        present="true"
        break
      fi
    done <<< "${desired}"
    if [ "${present}" = "false" ]; then
      absent_slugs="${absent_slugs:+${absent_slugs} }${slug}"
    fi
  done
  if [ -n "${absent_slugs}" ]; then
    bad "role '${role}': SKIP-NOT-READY (S2 desired keys absent for agent '${name}':${absent_slugs:+ }${absent_slugs})"
    record "${role}" "SKIP-NOT-READY" "S2 desired keys absent: ${absent_slugs}"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi

  # ---- Pass A3 (S3): effective tool summary must be non-empty. ----
  if ! api GET "/api/companies/${COMPANY_ID}/tools/profiles/effective/agents/${agent_id}" > "${TMPDIR_WORK}/effective-${role}.json"; then
    bad "role '${role}': SKIP-NOT-READY (effective summary read failed for agent '${name}')"
    record "${role}" "SKIP-NOT-READY" "S3 effective summary read failed"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi
  counts=""
  if ! counts="$(effective_counts "${TMPDIR_WORK}/effective-${role}.json")"; then
    bad "role '${role}': SKIP-NOT-READY (effective summary for agent '${name}' is unparseable)"
    record "${role}" "SKIP-NOT-READY" "S3 effective summary unparseable"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi
  tools_n="$(printf '%s' "${counts}" | cut -f1)"
  names_n="$(printf '%s' "${counts}" | cut -f2)"
  if ! [ "${tools_n}" -gt 0 ] && ! [ "${names_n}" -gt 0 ]; then
    bad "role '${role}': SKIP-NOT-READY (S3 effective allowed set empty for agent '${name}': allowedTools ${tools_n}, allowedToolNames ${names_n})"
    record "${role}" "SKIP-NOT-READY" "S3 effective allowed set empty (allowedTools ${tools_n}, allowedToolNames ${names_n})"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi
  log "role '${role}' ready (S1 hash match, S2 ${#role_slugs[@]} key(s) desired, S3 allowedTools ${tools_n}/allowedToolNames ${names_n})"

  # ---- Pass B: probe with the agent's CURRENT adapterConfig verbatim. ----
  if ! api GET "/api/agents/${agent_id}" > "${TMPDIR_WORK}/detail-${role}.json"; then
    bad "role '${role}': SKIP-NOT-READY (agent detail read failed for agent '${name}')"
    record "${role}" "SKIP-NOT-READY" "agent detail read failed"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi
  probe_src=""
  if ! probe_src="$(agent_probe_source "${TMPDIR_WORK}/detail-${role}.json" "${TMPDIR_WORK}/cfg-${role}.json")"; then
    bad "role '${role}': SKIP-NOT-READY (agent '${name}' detail lacks adapterType/adapterConfig — no stored-config fallback exists)"
    record "${role}" "SKIP-NOT-READY" "agent detail lacks adapterType/adapterConfig"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi
  adapter_type="$(printf '%s' "${probe_src}" | cut -f1)"
  if ! REQ_ENV="${ENV_ID}" build_probe_payload "${TMPDIR_WORK}/cfg-${role}.json" "${agent_id}" "${TMPDIR_WORK}/probe-${role}.json"; then
    bad "role '${role}': SKIP-NOT-READY (failed to build probe payload for agent '${name}')"
    record "${role}" "SKIP-NOT-READY" "probe payload build failed"
    nskipped=$((nskipped + 1))
    SKIPPED_LIST="${SKIPPED_LIST:+${SKIPPED_LIST} }${role}"
    continue
  fi

  log "probing agent '${name}' (POST /api/companies/${COMPANY_ID}/adapters/${adapter_type}/test-environment)"
  if ! api POST "/api/companies/${COMPANY_ID}/adapters/${adapter_type}/test-environment" "${TMPDIR_WORK}/probe-${role}.json" > "${TMPDIR_WORK}/result-${role}.json"; then
    bad "role '${role}': FAIL (probe request failed for agent '${name}'; server response above)"
    record "${role}" "FAIL" "probe request failed (HTTP error)"
    nfailed=$((nfailed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi

  # ---- Pass C: classify with the exact upstream gate. ----
  classified=""
  if ! classified="$(classify_result "${TMPDIR_WORK}/result-${role}.json")"; then
    bad "role '${role}': FAIL (probe result for agent '${name}' is unparseable)"
    record "${role}" "FAIL" "probe result unparseable"
    nfailed=$((nfailed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  status_out="$(printf '%s' "${classified}" | cut -f1)"
  detail_out="$(printf '%s' "${classified}" | cut -f2)"
  case "${status_out}" in
    PASS)
      ok "agent '${name}' PASS (${detail_out})"
      record "${role}" "PASS" "${detail_out}"
      npass=$((npass + 1))
      ;;
    BLOCKED-NO-CREDS)
      log "agent '${name}' BLOCKED-NO-CREDS (${detail_out}) — expected until provider credentials land"
      record "${role}" "BLOCKED-NO-CREDS" "${detail_out}"
      nblocked=$((nblocked + 1))
      BLOCKED_LIST="${BLOCKED_LIST:+${BLOCKED_LIST} }${role}"
      ;;
    FAIL)
      bad "role '${role}': FAIL (agent '${name}': ${detail_out})"
      record "${role}" "FAIL" "${detail_out}"
      nfailed=$((nfailed + 1))
      FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
      ;;
    *)
      bad "role '${role}': FAIL (classifier returned unknown status '${status_out}' for agent '${name}')"
      record "${role}" "FAIL" "classifier returned unknown status '${status_out}'"
      nfailed=$((nfailed + 1))
      FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
      ;;
  esac
done

log "per-role results:"
for i in "${!REC_ROLE[@]}"; do
  log "  role='${REC_ROLE[$i]}' status='${REC_STATUS[$i]}' detail='${REC_DETAIL[$i]}'"
done

log "verify summary: ${npass} pass, ${nblocked} blocked-no-creds, ${nfailed} failed, ${nskipped} skipped-not-ready across ${total} role(s)"
if [ -n "${BLOCKED_LIST}" ]; then
  log "blocked (auth-required, expected until provider credentials land):${BLOCKED_LIST:+ }${BLOCKED_LIST}"
fi
if [ "${nfailed}" -gt 0 ] || [ "${nskipped}" -gt 0 ]; then
  [ "${nfailed}" -gt 0 ] && bad "verify FAILED for ${nfailed} role(s):${FAILED_LIST:+ }${FAILED_LIST}"
  [ "${nskipped}" -gt 0 ] && bad "verify SKIPPED ${nskipped} role(s) not-ready:${SKIPPED_LIST:+ }${SKIPPED_LIST}"
  exit 1
fi
ok "enrich-verify complete"
