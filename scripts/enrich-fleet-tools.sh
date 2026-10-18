#!/usr/bin/env bash
#
# enrich-fleet-tools.sh — ensure one company-default tool profile for the
# fleet and bind it so every seeded agent's effective tool summary is
# non-empty, then verify per agent.
#
# STAGE S3 (tool profiles only): Pass A ensures the fleet profile exists
# (lookup by profileKey in the profiles list, create when missing with
# tool_name entries covering the fleet-common MCP/tool surface); Pass B
# binds it once as the company default (or once per agent with
# --profile-per-agent), skipping targets that already carry an identical
# binding; Pass C re-reads each agent's effective summary and fails the
# role when the allowed set is empty. End-to-end verification (S4) is
# explicitly out of scope here.
#
# Usage:
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... bash scripts/enrich-fleet-tools.sh [--dry-run] [--help] [--only <role>[,<role>...]] [--profile-per-agent]
#
#   --dry-run           Print the profile/bind decisions (profileKey, entry
#                       tool names + counts, per-role would-bind targets, no
#                       network calls. No PAPERCLIP_TOKEN is required. Safe
#                       against a dead PAPERCLIP_URL: not a single byte is sent.
#   --only              Restrict the run to a comma-separated subset of role
#                       dirs, e.g. --only dba-specialist (also --only=<list>).
#                       Unknown role dirs fail closed.
#   --profile-per-agent Bind the fleet profile once per agent
#                       (targetType agent) instead of the default single
#                       company-default bind (targetType company). Same
#                       profile, same entries; only the binding targets differ.
#   --help, -h          Print this usage guide and exit.
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
#   ROLES_DIR                 Directory holding the per-role opencode.json
#                             files (read-only; used to derive the entry set).
#                             Default: <repo>/roles (resolved from this path).
#   FLEET_PROFILE_KEY         profileKey of the fleet tool profile.
#                             Default: "fleet-default-tools"
#   FLEET_PROFILE_NAME        Display name of the fleet tool profile.
#                             Default: "Fleet Default Tools"
#
# Upstream API contracts (verified against /tmp/paperclip @73659c6 — re-verify
# here before any live run if the checkout moved):
#   1. List: GET /api/companies/:companyId/tools/profiles
#      (server/src/routes/tool-access.ts:2296-2301) ->
#      {profiles: ToolProfileWithDetails[]} where each profile carries
#      .id, .profileKey, .entries[] and .bindings[] ({targetType, targetId,
#      ...}; shared/src/types/tool-access.ts:615-627,779-783). There is NO
#      standalone bindings-list endpoint: the embedded .bindings[] arrays
#      are the idempotency source for Pass B ("read bindings first").
#   2. Create: POST /api/companies/:companyId/tools/profiles
#      (routes/tool-access.ts:2310-2328) with createToolProfileWithEntriesSchema
#      (packages/shared/src/validators/tool-access.ts:599-603): profileKey
#      (required, /^[a-z0-9][a-z0-9._:-]*$/i), name (required, 1-160),
#      description?, status (default "active"), defaultAction deny|allow
#      (default "deny"), metadata?, entries[] (max 250) of
#      createToolProfileEntryForProfileSchema (:588: selectorType,
#      effect default "include", plus exactly one selector payload:
#      applicationId | connectionId | catalogEntryId | toolName | riskLevel
#      — enforced by assertProfileEntryShape in
#      server/src/services/tool-profile-entry-validation.ts:24-38, with
#      live-UUID existence checks in assertProfileEntryInputs :40+).
#   3. Bind: POST /api/companies/:companyId/tools/profiles/:profileId/bind
#      (routes/tool-access.ts:2479-2502) with
#      createToolProfileBindingForProfileSchema (validators/tool-access.ts:
#      647-649): {targetType, targetId, priority=100 (0-10000), metadata?};
#      targetType enum company|agent|project|routine|issue|gateway
#      (shared/src/constants.ts:1092). service bindProfile asserts the target
#      exists, so binds to unknown agent ids fail server-side (fail-closed).
#   4. Verify: GET /api/companies/:companyId/tools/profiles/effective/agents/:agentId
#      (routes/tool-access.ts:2330-2335) -> ToolProfileEffectiveSummary
#      (shared/src/types/tool-access.ts:818-826): {agentId, profiles[],
#      entries[], bindings[], allowedTools[], allowedToolNames[],
#      installedConnections[]}.
#   5. Precedence: agent(3) beats company(5)
#      (server/src/services/tool-profile-binding-precedence.ts:17-46): a
#      single company-default bind covers the fleet unless a narrower
#      agent/project/issue binding exists, which then wins for that scope.
#
# Profile entry design (what the schema actually accepts — no invented shapes):
#   Only the `tool_name` selector is creatable without live server-side UUIDs:
#   application/connection/catalog_entry selectors require UUIDs that exist in
#   this company's tables (entry-validation.ts:40+ rejects unknown ids), and
#   risk_level is catalog-derived. The entries below are `tool_name` includes
#   for the exact, fleet-common ALLOW tools observed in all 51 roles'
#   opencode.json permissions (harness_* read/map/audit set; git_* names are
#   intentionally excluded — only 25/51 roles allow them, so they do not
#   belong in a company-default profile). KNOWN MAPPING GAP (must be closed
#   on the live run): these names are the OpenCode-side MCP tool names from
#   our opencode.json allow-lists, NOT verified Paperclip catalog toolNames.
#   Paperclip profiles govern Paperclip tools/MCP gateway, not opencode.json
#   allow-lists directly. tool_name includes always surface in the effective
#   summary's allowedToolNames (services/tool-access.ts getEffectiveProfiles-
#   ForAgent adds them even with zero catalog rows), while allowedTools only
#   fills when a catalog row with the same toolName exists. If the live
#   catalog uses different toolNames, reconcile the entry list (or add
#   application/connection selectors once their UUIDs are known) and re-run.
#
# Pass C gate (deliberate, cited deviation from "allowedTools non-empty"):
#   a role passes when allowedTools OR allowedToolNames is non-empty (both
#   counts are logged). Rationale: allowedTools is built ONLY from company
#   catalog rows (services/tool-access.ts:20088-20135), so on a company with
#   an empty tool catalog a strict allowedTools gate can never pass no matter
#   how correct the profile is; allowedToolNames is the catalog-independent
#   signal our tool_name includes guarantee. A profile that truly grants
#   nothing still fails the role (both empty) — the gate stays fail-closed.
#
# Idempotency: Pass A looks the profile up by profileKey before any create
# (and re-GETs the list after creating — create responses are never trusted
# for the id); Pass B skips targets whose identical {targetType,targetId}
# binding already exists in the profile's embedded bindings; Pass C is
# read-only. A role that fails at any step is reported and the run continues
# with the rest; the exit code is nonzero with a failure count.
#
# Secret hygiene: only names/keys/ids/counts are logged (no entry internals
# beyond tool names, which are repo-visible opencode.json allow-list names);
# the token is only ever sent as an Authorization header, never printed.
#
# Exit codes: 0 all roles bound+verified; 1 one or more roles failed (count
# printed) or a fail-closed preflight tripped; 2 CLI misuse.
#
# Examples:
#   bash scripts/enrich-fleet-tools.sh --dry-run
#   PAPERCLIP_URL=http://127.0.0.1:3100 PAPERCLIP_TOKEN=xxx bash scripts/enrich-fleet-tools.sh
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... bash scripts/enrich-fleet-tools.sh --only dba-specialist
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... bash scripts/enrich-fleet-tools.sh --profile-per-agent --only dba-specialist,k8s-orchestrator
#
set -euo pipefail

PAPERCLIP_URL="${PAPERCLIP_URL:-http://127.0.0.1:3100}"
PAPERCLIP_TOKEN="${PAPERCLIP_TOKEN:-${ADMIN_API_KEY:-}}"
COMPANY_NAME="${COMPANY_NAME:-Heretek Autonomous Fleet}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-120}"
FLEET_PROFILE_KEY="${FLEET_PROFILE_KEY:-fleet-default-tools}"
FLEET_PROFILE_NAME="${FLEET_PROFILE_NAME:-Fleet Default Tools}"

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

# Fleet-common exact ALLOW tool names (present with effect allow in all 51
# roles' opencode.json permissions; verified by scanning roles/*/opencode/
# opencode.json). deny-effect names (harness_ast_structural_rewrite,
# harness_checkpoint_rollback, harness_file_hash_edit, harness_rename_symbol)
# and partial-fleet names (git_*, 25/51) are deliberately excluded from the
# company-default profile — see header "Profile entry design".
FLEET_TOOL_NAMES=(
  harness_architecture_audit
  harness_ast_structural_search
  harness_blast_radius
  harness_checkpoint_create
  harness_file_hash_read
  harness_file_outline
  harness_repo_map
  harness_symbol_references
  harness_ui_geometry_audit
  harness_verify_scoped
)

DRY_RUN="false"
ONLY_RAW=""
ONLY_SET="false"
PER_AGENT="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN="true"; shift ;;
    --profile-per-agent) PER_AGENT="true"; shift ;;
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

if [ -z "${FLEET_PROFILE_KEY}" ]; then
  echo "error: FLEET_PROFILE_KEY must be non-empty" >&2
  exit 1
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

log() { printf '[enrich-tools] %s\n' "$*"; }
ok() { printf '[enrich-tools] OK: %s\n' "$*"; }
bad() { printf '[enrich-tools] ERROR: %s\n' "$*" >&2; }

# --dry-run exits here, BEFORE curl/python3 are required and before any
# network call could occur: every statement above and below this block is
# pure local computation (arg parsing, list scans). Any curl invocation
# while DRY_RUN=true is a bug — gate all api() calls live-only.
if [ "${DRY_RUN}" = "true" ]; then
  log "--dry-run: profile + bind decisions (no network calls)"
  log "profile: would-ensure profileKey '${FLEET_PROFILE_KEY}' (name '${FLEET_PROFILE_NAME}', status active, defaultAction deny) with ${#FLEET_TOOL_NAMES[@]} tool_name include entries:"
  for tool in "${FLEET_TOOL_NAMES[@]}"; do
    log "  entry: selectorType tool_name, effect include, toolName '${tool}'"
  done
  if [ "${PER_AGENT}" = "true" ]; then
    mode_desc="per-agent binds (targetType agent, priority 100)"
  else
    mode_desc="single company-default bind (targetType company, priority 100)"
  fi
  log "bind mode: ${mode_desc}"
  for role in "${TARGET_ROLES[@]}"; do
    name="$(role_display_name "${role}")"
    if [ "${PER_AGENT}" = "true" ]; then
      log "role '${role}' (agent '${name}'): would-bind profile '${FLEET_PROFILE_KEY}' to agent target (skip when identical agent binding already exists); would-verify effective summary shows non-empty allowed set"
    else
      log "role '${role}' (agent '${name}'): covered by company-default bind of profile '${FLEET_PROFILE_KEY}' (skip when identical company binding already exists); would-verify effective summary shows non-empty allowed set"
    fi
  done
  if [ "${PER_AGENT}" = "true" ]; then
    log "dry-run summary: 1 profile would-ensured (${#FLEET_TOOL_NAMES[@]} entries), ${#TARGET_ROLES[@]} per-agent bind(s) would-checked across ${#TARGET_ROLES[@]} role(s); zero network calls attempted"
  else
    log "dry-run summary: 1 profile would-ensured (${#FLEET_TOOL_NAMES[@]} entries), 1 company-default bind would-checked covering ${#TARGET_ROLES[@]} role(s); zero network calls attempted"
  fi
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
# record a role failure, and preflights run under `set -e` fail-closed.
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

# Parse a profiles-list body ({profiles:[...]}) into
# "profileKey\tid\tname" lines. Accepts a bare array defensively, but exits
# NONZERO on anything unparseable (fail-closed: never let a 500 page
# masquerade as "no profiles yet").
profiles_index() {
  python3 -c '
import json, sys
raw = open(sys.argv[1], "r", encoding="utf-8").read()
try:
    doc = json.loads(raw)
except Exception as exc:
    sys.stderr.write("error: profiles list response is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
items = doc
if isinstance(doc, dict):
    for key in ("profiles", "items", "data", "results"):
        if isinstance(doc.get(key), list):
            items = doc[key]
            break
if not isinstance(items, list):
    sys.stderr.write("error: profiles list response has unexpected shape (expected {profiles: [...]})\n")
    sys.exit(1)
for entry in items:
    if not isinstance(entry, dict):
        sys.stderr.write("error: profiles list entry has unexpected shape (expected object)\n")
        sys.exit(1)
    pkey = entry.get("profileKey")
    pid = entry.get("id")
    pname = entry.get("name")
    if not isinstance(pkey, str) or not pkey or not isinstance(pid, str) or not pid:
        continue
    print("%s\t%s\t%s" % (pkey, pid, pname if isinstance(pname, str) else ""))
' "$1"
}

# Parse a profiles-list body into "profileId\ttargetType\ttargetId" binding
# lines across ALL profiles (bindings are embedded per profile — there is no
# standalone bindings-list endpoint). Exits NONZERO on unparseable bodies.
all_bindings() {
  python3 -c '
import json, sys
raw = open(sys.argv[1], "r", encoding="utf-8").read()
try:
    doc = json.loads(raw)
except Exception as exc:
    sys.stderr.write("error: profiles list response is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
items = doc
if isinstance(doc, dict):
    for key in ("profiles", "items", "data", "results"):
        if isinstance(doc.get(key), list):
            items = doc[key]
            break
if not isinstance(items, list):
    sys.stderr.write("error: profiles list response has unexpected shape (expected {profiles: [...]})\n")
    sys.exit(1)
for entry in items:
    if not isinstance(entry, dict):
        sys.stderr.write("error: profiles list entry has unexpected shape (expected object)\n")
        sys.exit(1)
    pid = entry.get("id")
    if not isinstance(pid, str) or not pid:
        continue
    bindings = entry.get("bindings")
    if not isinstance(bindings, list):
        continue
    for binding in bindings:
        if not isinstance(binding, dict):
            continue
        ttype = binding.get("targetType")
        tid = binding.get("targetId")
        if isinstance(ttype, str) and ttype and isinstance(tid, str) and tid:
            print("%s\t%s\t%s" % (pid, ttype, tid))
' "$1"
}

# Parse an effective-summary body into
# "allowedToolsCount\tallowedToolNamesCount\tprofileCount". Exits NONZERO
# on unparseable bodies (fail-closed: never treat a 500 page as "empty").
effective_counts() {
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

# Build the fleet profile create payload: $1 = output JSON path.
# Entries are tool_name includes only (the sole selector creatable without
# live UUIDs — see header). JSON-encoded via python so names/descriptions
# can never break the payload. status active + defaultAction deny pin the
# least-privilege posture explicitly even though both match server defaults.
build_create_payload() {
  OUT_PATH="$1" PROFILE_KEY="${FLEET_PROFILE_KEY}" PROFILE_NAME="${FLEET_PROFILE_NAME}" TOOL_NAMES="${FLEET_TOOL_NAMES[*]}" python3 -c '
import json, os
names = [n for n in os.environ.get("TOOL_NAMES", "").split() if n]
payload = {
    "profileKey": os.environ["PROFILE_KEY"],
    "name": os.environ["PROFILE_NAME"],
    "description": "Fleet default tool profile (S3): company-wide baseline granting the fleet-common MCP/tool surface. tool_name entries mirror the exact ALLOW tools present in all 51 roles opencode.json permissions; application/connection/catalog_entry selectors need live UUIDs and are a follow-up.",
    "status": "active",
    "defaultAction": "deny",
    "metadata": {"managedBy": "fleet-enrich-s3", "source": "scripts/enrich-fleet-tools.sh"},
    "entries": [{"selectorType": "tool_name", "effect": "include", "toolName": n} for n in names],
}
with open(os.environ["OUT_PATH"], "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
'
}

# Build a bind payload: $1 = output path, $2 = targetType, $3 = targetId.
# priority 100 pins the schema default explicitly.
build_bind_payload() {
  OUT_PATH="$1" TARGET_TYPE="$2" TARGET_ID="$3" python3 -c '
import json, os
payload = {
    "targetType": os.environ["TARGET_TYPE"],
    "targetId": os.environ["TARGET_ID"],
    "priority": 100,
}
with open(os.environ["OUT_PATH"], "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
'
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

# ---- Pass A: ensure the fleet profile exists (lookup by profileKey). ----
log "pass A: ensuring fleet profile '${FLEET_PROFILE_KEY}'"
api GET "/api/companies/${COMPANY_ID}/tools/profiles" > "${TMPDIR_WORK}/profiles.json"
if ! profiles_index "${TMPDIR_WORK}/profiles.json" > "${TMPDIR_WORK}/profiles-index.tsv"; then
  echo "error: profiles list response is unparseable; aborting (server body above)" >&2
  exit 1
fi
PROFILE_ID="$(awk -F'\t' -v key="${FLEET_PROFILE_KEY}" '$1 == key { print $2; exit }' "${TMPDIR_WORK}/profiles-index.tsv")"
if [ -n "${PROFILE_ID}" ]; then
  log "profile '${FLEET_PROFILE_KEY}' already exists: ${PROFILE_ID}; skipping create"
else
  log "creating profile '${FLEET_PROFILE_KEY}' (name '${FLEET_PROFILE_NAME}', defaultAction deny, ${#FLEET_TOOL_NAMES[@]} tool_name include entries)"
  if ! build_create_payload "${TMPDIR_WORK}/create-profile.json"; then
    echo "error: failed to build profile create payload; aborting" >&2
    exit 1
  fi
  if ! api POST "/api/companies/${COMPANY_ID}/tools/profiles" "${TMPDIR_WORK}/create-profile.json" > "${TMPDIR_WORK}/create-profile.resp.json"; then
    echo "error: profile create failed (server response above); aborting" >&2
    exit 1
  fi
  # Never trust the create response alone: re-GET the list and learn the id
  # from the server (mirrors enrich-fleet-skills.sh pass A).
  api GET "/api/companies/${COMPANY_ID}/tools/profiles" > "${TMPDIR_WORK}/profiles.json"
  if ! profiles_index "${TMPDIR_WORK}/profiles.json" > "${TMPDIR_WORK}/profiles-index.tsv"; then
    echo "error: post-create profiles list response is unparseable; aborting (server body above)" >&2
    exit 1
  fi
  PROFILE_ID="$(awk -F'\t' -v key="${FLEET_PROFILE_KEY}" '$1 == key { print $2; exit }' "${TMPDIR_WORK}/profiles-index.tsv")"
  if [ -z "${PROFILE_ID}" ]; then
    echo "error: profile '${FLEET_PROFILE_KEY}' absent from server list after create; aborting" >&2
    exit 1
  fi
  ok "profile '${FLEET_PROFILE_KEY}' created: ${PROFILE_ID}"
fi

# Load the binding map once: "profileId targetType targetId" lines. Refreshed
# after each successful bind below so later roles see earlier binds.
if ! all_bindings "${TMPDIR_WORK}/profiles.json" > "${TMPDIR_WORK}/bindings.tsv"; then
  echo "error: profiles list bindings are unparseable; aborting (server body above)" >&2
  exit 1
fi
binding_exists() {
  local pid="$1" ttype="$2" tid="$3"
  awk -F'\t' -v pid="${pid}" -v ttype="${ttype}" -v tid="${tid}" \
    '$1 == pid && $2 == ttype && $3 == tid { found=1; exit } END { exit found ? 0 : 1 }' \
    "${TMPDIR_WORK}/bindings.tsv"
}
refresh_bindings() {
  api GET "/api/companies/${COMPANY_ID}/tools/profiles" > "${TMPDIR_WORK}/profiles.json"
  if ! profiles_index "${TMPDIR_WORK}/profiles.json" > "${TMPDIR_WORK}/profiles-index.tsv"; then
    return 1
  fi
  if ! all_bindings "${TMPDIR_WORK}/profiles.json" > "${TMPDIR_WORK}/bindings.tsv"; then
    return 1
  fi
  return 0
}

resolve_agent_id() {
  # $1 = role, $2 = display name. Prints the agent id or returns nonzero.
  local role="$1" name="$2" existing agent_id
  if ! existing="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"; then
    bad "role '${role}': agent list is unparseable; skipping role"
    return 1
  fi
  if [ -z "${existing}" ]; then
    # Miss against a possibly stale cache: refresh once before concluding
    # the agent is absent.
    if ! api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"; then
      bad "role '${role}': agent list refresh failed; skipping role"
      return 1
    fi
    if ! existing="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"; then
      bad "role '${role}': agent list is unparseable after refresh; skipping role"
      return 1
    fi
  fi
  if [ -z "${existing}" ]; then
    bad "role '${role}': agent '${name}' not found — seed the fleet first with scripts/seed-50-fleet.sh; skipping role"
    return 1
  fi
  agent_id="$(printf '%s' "${existing}" | cut -f1)"
  if [ -z "${agent_id}" ]; then
    bad "role '${role}': agent '${name}' resolved without an id; skipping role"
    return 1
  fi
  printf '%s' "${agent_id}"
  return 0
}

# ---- Pass B: bind (company-default once, or per-agent with the flag). ----
total=0
bound=0
bskip=0
failed=0
FAILED_LIST=""
if [ "${PER_AGENT}" = "true" ]; then
  log "pass B: per-agent binds of profile '${FLEET_PROFILE_KEY}' (${PROFILE_ID})"
else
  log "pass B: company-default bind of profile '${FLEET_PROFILE_KEY}' (${PROFILE_ID})"
  if binding_exists "${PROFILE_ID}" "company" "${COMPANY_ID}"; then
    log "company-default binding (company/${COMPANY_ID}) already exists; skipping bind"
  else
    log "binding profile '${FLEET_PROFILE_KEY}' as company default (targetType company, targetId ${COMPANY_ID}, priority 100)"
    if build_bind_payload "${TMPDIR_WORK}/bind-company.json" "company" "${COMPANY_ID}" \
      && api POST "/api/companies/${COMPANY_ID}/tools/profiles/${PROFILE_ID}/bind" "${TMPDIR_WORK}/bind-company.json" > "${TMPDIR_WORK}/bind-company.resp.json"; then
      ok "company-default bind created"
      if ! refresh_bindings; then
        echo "error: profiles list re-read after company bind is unparseable; aborting" >&2
        exit 1
      fi
    else
      echo "error: company-default bind failed (server response above); aborting — no agent can verify without it" >&2
      exit 1
    fi
  fi
fi

for role in "${TARGET_ROLES[@]}"; do
  total=$((total + 1))
  name="$(role_display_name "${role}")"

  agent_id=""
  if ! agent_id="$(resolve_agent_id "${role}" "${name}")"; then
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi

  if [ "${PER_AGENT}" = "true" ]; then
    if binding_exists "${PROFILE_ID}" "agent" "${agent_id}"; then
      log "agent '${name}' already bound to profile '${FLEET_PROFILE_KEY}'; skipping bind"
      bskip=$((bskip + 1))
    else
      log "binding profile '${FLEET_PROFILE_KEY}' to agent '${name}' (targetType agent, priority 100)"
      if ! build_bind_payload "${TMPDIR_WORK}/bind-${role}.json" "agent" "${agent_id}"; then
        bad "role '${role}': failed to build bind payload for agent '${name}'; skipping role"
        failed=$((failed + 1))
        FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
        continue
      fi
      if ! api POST "/api/companies/${COMPANY_ID}/tools/profiles/${PROFILE_ID}/bind" "${TMPDIR_WORK}/bind-${role}.json" > "${TMPDIR_WORK}/bind-${role}.resp.json"; then
        bad "role '${role}': bind failed for agent '${name}' (server response above); skipping role"
        failed=$((failed + 1))
        FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
        continue
      fi
      if ! refresh_bindings; then
        bad "role '${role}': profiles list re-read after bind is unparseable; skipping role"
        failed=$((failed + 1))
        FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
        continue
      fi
      bound=$((bound + 1))
    fi
  fi

  # ---- Pass C: verify the effective summary shows a non-empty allowed set.
  if ! api GET "/api/companies/${COMPANY_ID}/tools/profiles/effective/agents/${agent_id}" > "${TMPDIR_WORK}/effective-${role}.json"; then
    bad "role '${role}': effective summary read failed for agent '${name}'; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  counts=""
  if ! counts="$(effective_counts "${TMPDIR_WORK}/effective-${role}.json")"; then
    bad "role '${role}': effective summary for agent '${name}' is unparseable; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  tools_n="$(printf '%s' "${counts}" | cut -f1)"
  names_n="$(printf '%s' "${counts}" | cut -f2)"
  prof_n="$(printf '%s' "${counts}" | cut -f3)"
  if [ "${tools_n}" -gt 0 ] || [ "${names_n}" -gt 0 ]; then
    ok "agent '${name}' tools verified (allowedTools ${tools_n}, allowedToolNames ${names_n}, profiles ${prof_n})"
    if [ "${PER_AGENT}" != "true" ]; then
      # Company-default mode binds once up front; count each verified role
      # as covered here. (Per-agent mode already counted bound/already-bound
      # above.)
      bskip=$((bskip + 1))
    fi
  else
    bad "role '${role}': effective summary for agent '${name}' shows an empty allowed set (allowedTools ${tools_n}, allowedToolNames ${names_n}, profiles ${prof_n}); skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
done

if [ "${PER_AGENT}" = "true" ]; then
  log "enrich-tools summary: ${bound} bound, ${bskip} already bound, ${failed} failed across ${total} role(s); profile '${FLEET_PROFILE_KEY}' (${PROFILE_ID})"
else
  log "enrich-tools summary: company-default bind ensured, ${bskip} verified, ${failed} failed across ${total} role(s); profile '${FLEET_PROFILE_KEY}' (${PROFILE_ID})"
fi
if [ "${failed}" -gt 0 ]; then
  bad "enrich-tools FAILED for ${failed} role(s):${FAILED_LIST:+ }${FAILED_LIST}"
  exit 1
fi
ok "enrich-tools complete"
