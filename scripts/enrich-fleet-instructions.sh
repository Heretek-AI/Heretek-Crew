#!/usr/bin/env bash
#
# enrich-fleet-instructions.sh — idempotently sync roles/<id>/AGENTS.md
# charters into the Paperclip instructions bundle of each seeded fleet agent.
#
# STAGE S1 (instructions only): this script syncs the AGENTS.md entry file
# only. Skills (S2), MCP/tools wiring (S3) and end-to-end verification (S4)
# are later stages and are explicitly out of scope here.
#
# Usage:
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... bash scripts/enrich-fleet-instructions.sh [--dry-run] [--help] [--only <role-dir>[,<role-dir>...]]
#
#   --dry-run   Print the per-role would-write/skip decisions (local entry
#               byte counts + sha256) without performing ANY network calls.
#               No PAPERCLIP_TOKEN is required. Safe against a dead
#               PAPERCLIP_URL: not a single byte is sent.
#   --only      Restrict the run to a comma-separated subset of role dirs,
#               e.g. --only dba-specialist or --only dba-specialist,k8s-orchestrator
#               (also accepts --only=<list>). Unknown role dirs fail closed.
#   --help, -h  Print this usage guide and exit.
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
#   ROLES_DIR                 Directory holding the per-role charters.
#                             Default: <repo>/roles (resolved from this script's path).
#
# Upstream API contracts (verified against /tmp/paperclip @73659c6):
#   1. Read bundle first: GET /api/agents/:id/instructions-bundle
#      (routes/agents.ts) -> entryFile + head revision.
#   2. Write entry: PUT /api/agents/:id/instructions-bundle/file
#      {path: "AGENTS.md", content, baseRevisionId}
#      (validators/agent.ts: path 1-512 chars, content <= 1MiB,
#      baseRevisionId required for the entry path, null for new).
#   3. Non-entry managed files take baseHash instead of baseRevisionId —
#      not used here (S1 syncs the AGENTS.md entry only).
#   4. Instruction paths must stay in the bundle root (no symlinks);
#      the entry file is AGENTS.md.
#   5. New agents could take instructionsBundle at create — IRRELEVANT
#      here (all 51 agents already exist); this script uses the PUT file
#      API only and never creates agents. If the fleet company or an
#      agent is missing, the run fails that scope fail-closed with a
#      pointer to scripts/seed-50-fleet.sh — it never invents agents.
# If any assumption breaks against your Paperclip build, --dry-run output
# shows the intended local payloads (bytes + hashes) to adapt.
#
# Idempotency: per role, the server entry content hash is compared with
# the local roles/<id>/AGENTS.md sha256; identical hashes skip with
# "already current". Stale/missing entries are PUT with the bundle's
# baseRevisionId (null only when the bundle reports none), then re-read
# to confirm the hashes match. A role that fails at any step is reported
# and the run continues with the rest; the exit code is nonzero with a
# failure count when any role failed.
#
# Secret hygiene: file contents are never echoed (only byte counts and
# sha256 digests appear in logs; at most nothing beyond that); the token
# is only ever sent as an Authorization header and is never printed.
#
# Exit codes: 0 all roles current/updated and verified; 1 one or more
# roles failed (count printed) or a fail-closed preflight tripped;
# 2 CLI misuse (unknown argument, bad --only value).
#
# Examples:
#   bash scripts/enrich-fleet-instructions.sh --dry-run
#   PAPERCLIP_URL=http://127.0.0.1:3100 PAPERCLIP_TOKEN=xxx bash scripts/enrich-fleet-instructions.sh
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... bash scripts/enrich-fleet-instructions.sh --only dba-specialist
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

log() { printf '[enrich] %s\n' "$*"; }
ok() { printf '[enrich] OK: %s\n' "$*"; }
bad() { printf '[enrich] ERROR: %s\n' "$*" >&2; }

# --dry-run exits here, BEFORE curl/python3 are required and before any
# network call could occur: every statement above and below this block is
# pure local computation (arg parsing, file reads, hashes). Any curl
# invocation while DRY_RUN=true is a bug — gate all api() calls live-only.
if [ "${DRY_RUN}" = "true" ]; then
  log "--dry-run: per-role sync decisions (no network calls)"
  dry_write=0
  dry_skip=0
  for role in "${TARGET_ROLES[@]}"; do
    name="$(role_display_name "${role}")"
    local_file="${ROLES_DIR}/${role}/AGENTS.md"
    if [ -f "${local_file}" ]; then
      local_bytes="$(wc -c < "${local_file}" | tr -d '[:space:]')"
      local_sha="$(sha256sum "${local_file}" | cut -d' ' -f1)"
      log "role '${role}' (agent '${name}'): would-write entry 'AGENTS.md' (${local_bytes} bytes, sha256:${local_sha})"
      dry_write=$((dry_write + 1))
    else
      log "role '${role}' (agent '${name}'): skip (no local charter at roles/${role}/AGENTS.md)"
      dry_skip=$((dry_skip + 1))
    fi
  done
  log "dry-run summary: ${dry_write} would-write, ${dry_skip} skip across ${#TARGET_ROLES[@]} role(s); zero network calls attempted"
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

bundle_inspect() {
  # $1 = instructions-bundle JSON file. Prints
  # "<entryFile>\t<baseRevisionId or empty>\t<serverSha or empty>\t<true|false>".
  # found=true only when the entry carries content (hashed here) or an
  # explicit hash field. Unparseable bodies exit NONZERO (fail-closed:
  # never "empty bundle, write with null revision" on a 500 page).
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

build_put_payload() {
  # $1 = local AGENTS.md path, $2 = base revision ("" -> JSON null),
  # $3 = output JSON path. Content is JSON-encoded via python so arbitrary
  # charter text (quotes, newlines, unicode) can never break the payload.
  # Validators: path 1-512 chars, content <= 1MiB, baseRevisionId required
  # for the entry path except null for a brand-new bundle.
  LOCAL_PATH="$1" BASE_REV="$2" OUT_PATH="$3" python3 -c '
import json, os
with open(os.environ["LOCAL_PATH"], "r", encoding="utf-8") as fh:
    content = fh.read()
rev = os.environ.get("BASE_REV", "")
payload = {"path": "AGENTS.md", "content": content, "baseRevisionId": rev if rev else None}
with open(os.environ["OUT_PATH"], "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
'
}

# Upstream validator cap (validators/agent.ts): entry content <= 1MiB.
MAX_ENTRY_BYTES=1048576

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

total=0
wrote=0
skipped=0
failed=0
FAILED_LIST=""
for role in "${TARGET_ROLES[@]}"; do
  total=$((total + 1))
  name="$(role_display_name "${role}")"
  local_file="${ROLES_DIR}/${role}/AGENTS.md"
  if [ ! -f "${local_file}" ]; then
    bad "role '${role}': local charter missing at roles/${role}/AGENTS.md; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  local_bytes="$(wc -c < "${local_file}" | tr -d '[:space:]')"
  local_sha="$(sha256sum "${local_file}" | cut -d' ' -f1)"
  if [ "${local_bytes}" -gt "${MAX_ENTRY_BYTES}" ]; then
    bad "role '${role}': local charter is ${local_bytes} bytes, exceeding the 1MiB upstream entry limit; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi

  existing=""
  if ! existing="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"; then
    bad "role '${role}': agent list is unparseable; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  if [ -z "${existing}" ]; then
    # Miss against a possibly stale cache: refresh once before concluding
    # the agent is absent.
    if ! api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"; then
      bad "role '${role}': agent list refresh failed; skipping role"
      failed=$((failed + 1))
      FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
      continue
    fi
    if ! existing="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"; then
      bad "role '${role}': agent list is unparseable after refresh; skipping role"
      failed=$((failed + 1))
      FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
      continue
    fi
  fi
  if [ -z "${existing}" ]; then
    bad "role '${role}': agent '${name}' not found — seed the fleet first with scripts/seed-50-fleet.sh; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  agent_id="$(printf '%s' "${existing}" | cut -f1)"
  if [ -z "${agent_id}" ]; then
    bad "role '${role}': agent '${name}' resolved without an id; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi

  # Pass 1: read the bundle, learn entryFile + baseRevisionId, compare hashes.
  if ! api GET "/api/agents/${agent_id}/instructions-bundle" > "${TMPDIR_WORK}/bundle-${role}.json"; then
    bad "role '${role}': bundle read failed for agent '${name}'; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  bundle_info=""
  if ! bundle_info="$(bundle_inspect "${TMPDIR_WORK}/bundle-${role}.json")"; then
    bad "role '${role}': bundle response for agent '${name}' is unparseable; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  entry_file="$(printf '%s' "${bundle_info}" | cut -f1)"
  base_rev="$(printf '%s' "${bundle_info}" | cut -f2)"
  server_sha="$(printf '%s' "${bundle_info}" | cut -f3)"
  server_found="$(printf '%s' "${bundle_info}" | cut -f4)"
  if [ "${entry_file}" != "AGENTS.md" ]; then
    log "role '${role}': server reports entryFile '${entry_file}' (expected 'AGENTS.md'); writing the S1 entry path 'AGENTS.md' per contract"
  fi
  if [ "${server_found}" = "true" ] && [ -n "${server_sha}" ] && [ "${server_sha}" = "${local_sha}" ]; then
    log "agent '${name}' instructions already current (AGENTS.md ${local_bytes} bytes, sha256:${local_sha}); skipping"
    skipped=$((skipped + 1))
    continue
  fi

  # Pass 2: PUT stale/missing entries only, then re-GET to verify.
  if [ "${server_found}" = "true" ]; then
    reason="stale"
  else
    reason="missing"
  fi
  if [ -n "${base_rev}" ]; then
    log "updating agent '${name}' entry 'AGENTS.md' (${reason}, ${local_bytes} bytes, baseRevisionId:${base_rev})"
  else
    log "updating agent '${name}' entry 'AGENTS.md' (${reason}, ${local_bytes} bytes, baseRevisionId:null for new bundle)"
  fi
  if ! build_put_payload "${local_file}" "${base_rev}" "${TMPDIR_WORK}/put-${role}.json"; then
    bad "role '${role}': failed to build PUT payload for agent '${name}'; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  if ! api PUT "/api/agents/${agent_id}/instructions-bundle/file" "${TMPDIR_WORK}/put-${role}.json" > "${TMPDIR_WORK}/put-${role}.resp.json"; then
    bad "role '${role}': PUT failed for agent '${name}' (server response above); skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  if ! api GET "/api/agents/${agent_id}/instructions-bundle" > "${TMPDIR_WORK}/verify-${role}.json"; then
    bad "role '${role}': post-write bundle re-read failed for agent '${name}'; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  verify_info=""
  if ! verify_info="$(bundle_inspect "${TMPDIR_WORK}/verify-${role}.json")"; then
    bad "role '${role}': post-write bundle response for agent '${name}' is unparseable; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  verify_sha="$(printf '%s' "${verify_info}" | cut -f3)"
  verify_found="$(printf '%s' "${verify_info}" | cut -f4)"
  if [ "${verify_found}" = "true" ] && [ "${verify_sha}" = "${local_sha}" ]; then
    ok "agent '${name}' entry verified (AGENTS.md ${local_bytes} bytes, sha256:${local_sha})"
    wrote=$((wrote + 1))
  else
    bad "role '${role}': post-write hash mismatch for agent '${name}' (local sha256:${local_sha}); skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
  fi
done

log "enrich summary: ${wrote} updated+verified, ${skipped} already current, ${failed} failed across ${total} role(s)"
if [ "${failed}" -gt 0 ]; then
  bad "enrich FAILED for ${failed} role(s):${FAILED_LIST:+ }${FAILED_LIST}"
  exit 1
fi
ok "enrich complete"
