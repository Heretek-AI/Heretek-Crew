#!/usr/bin/env bash
#
# enrich-fleet-skills.sh — idempotently register role SKILL.md bodies as
# company skills and bind them to each seeded fleet agent's desired skill set.
#
# STAGE S2 (skills only): Pass A registers every roles/<id>/.opencode/skills/*
# SKILL.md as a company skill (lookup by slug, create when missing with
# sharingScope "company"); Pass B binds each role's skill keys to its agent
# via skill sync mode "add" (skipping keys already present); Pass C re-reads
# each agent's bindings and fails the role when any expected key is missing.
# Instructions (S1), MCP/tools wiring (S3) and end-to-end verification (S4)
# are explicitly out of scope here.
#
# Usage:
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... bash scripts/enrich-fleet-skills.sh [--dry-run] [--help] [--only <role>[,<role>...]]
#
#   --dry-run   Print the per-role would-create/would-bind decisions (skill
#               slugs, local SKILL.md byte counts + sha256, derived canonical
#               keys) without performing ANY network calls. No PAPERCLIP_TOKEN
#               is required. Safe against a dead PAPERCLIP_URL: not a single
#               byte is sent.
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
#   ROLES_DIR                 Directory holding the per-role skill trees.
#                             Default: <repo>/roles (resolved from this script's path).
#
# Upstream API contracts (verified against /tmp/paperclip @73659c6 — re-verify
# here before any live run if the checkout moved):
#   1. Register: POST /api/companies/:companyId/skills
#      (server/src/routes/company-skills.ts vec of router.post
#      "/companies/:companyId/skills" + validate(companySkillCreateSchema);
#      schema validators/company-skill.ts:364-379: name required, slug/
#      description/markdown optional, sharingScope "private"|"company"|
#      "public_link"). We send {name, slug, description, markdown,
#      sharingScope:"company", idempotencyKey:"fleet-enrich-s2-<slug>"} so
#      retried creates collapse server-side (409 only on fingerprint clash).
#   2. List: GET /api/companies/:companyId/skills -> JSON ARRAY of
#      CompanySkillListItem (services/company-skills.ts list(): id, key, slug,
#      name, ...). Managed-local keys look like company/<companyId>/<slug>;
#      bundled look like paperclipai/paperclip/<slug>.
#   3. Bind: POST /api/agents/:id/skills/sync {mode:"add"|"remove"|"replace",
#      desiredSkills:[{key, versionId:null}]} (routes/agents.ts + validate
#      agentSkillSyncSchema validators/adapter-skills.ts:67-70; the toggle path
#      passes tolerateUnknownDesiredSkills:true so stale keys never break us).
#   4. Verify: GET /api/agents/:id/skills (routes/agents.ts) ->
#      {desiredSkills[], desiredSkillEntries[{key,versionId}], entries[], ...}.
#   5. Canonical key derivation: services/company-skills.ts
#      deriveCanonicalSkillKey -> `company/<companyId>/<slug>` for
#      managed_local input. We NEVER guess: after Pass A we re-GET the list
#      and learn every key from the server (lookup by slug); a slug still
#      absent after create fails its roles fail-closed.
# If any assumption breaks against your Paperclip build, --dry-run output
# shows the intended local payloads (slugs, bytes, hashes, derived keys) to
# adapt.
#
# Idempotency: per slug, the server list is consulted before any create
# (identical slugs across roles share byte-identical SKILL.md bodies —
# verified — so one company skill serves all roles holding it); per agent,
# current desired keys are read before sync and already-present keys are
# never re-sent. Retried creates carry a deterministic idempotencyKey.
# A role that fails at any step is reported and the run continues with the
# rest; the exit code is nonzero with a failure count when any role failed.
#
# Supporting files: role skills are SKILL.md-only (no scripts/ or references/
# trees exist fleet-wide — verified). If a skill dir ever gains extra files,
# they are NOT silently dropped: the role logs "deferred: N supporting file(s)
# need manual attach" and the summary counts deferred files explicitly. The
# SKILL.md body (the executable contract) is still registered and bound, and
# the run exits 0 only when every SKILL.md body is attached and every binding
# verifies; the deferral is documented in the summary for manual follow-up.
#
# Secret hygiene: SKILL.md bodies are repo content, not secrets, but logs are
# still kept to names/keys/counts/hashes (no body text is ever printed); the
# token is only ever sent as an Authorization header and is never printed.
#
# Exit codes: 0 all roles registered+bound+verified (deferrals, if any, are
# logged); 1 one or more roles failed (count printed) or a fail-closed
# preflight tripped; 2 CLI misuse (unknown argument, bad --only value).
#
# Examples:
#   bash scripts/enrich-fleet-skills.sh --dry-run
#   PAPERCLIP_URL=http://127.0.0.1:3100 PAPERCLIP_TOKEN=xxx bash scripts/enrich-fleet-skills.sh
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... bash scripts/enrich-fleet-skills.sh --only dba-specialist
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

log() { printf '[enrich-skills] %s\n' "$*"; }
ok() { printf '[enrich-skills] OK: %s\n' "$*"; }
bad() { printf '[enrich-skills] ERROR: %s\n' "$*" >&2; }

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

# Count supporting files (anything besides SKILL.md) inside a role's skill
# dirs. Prints the count. These are never silently dropped: callers log the
# deferral explicitly (see header).
role_supporting_count() {
  local role="$1" skills_dir="${ROLES_DIR}/$1/.opencode/skills"
  local count=0
  if [ ! -d "${skills_dir}" ]; then
    printf '0\n'
    return 0
  fi
  while IFS= read -r _; do
    count=$((count + 1))
  done < <(find "${skills_dir}" -type f ! -name 'SKILL.md' 2>/dev/null)
  printf '%s\n' "${count}"
}

# --dry-run exits here, BEFORE curl/python3 are required and before any
# network call could occur: every statement above and below this block is
# pure local computation (arg parsing, dir scans, hashes). Any curl
# invocation while DRY_RUN=true is a bug — gate all api() calls live-only.
if [ "${DRY_RUN}" = "true" ]; then
  log "--dry-run: per-role sync decisions (no network calls)"
  dry_roles=0
  dry_refs=0
  dry_deferred=0
  dry_failed=0
  dry_unique_tmp="$(mktemp)"
  trap 'rm -f "${dry_unique_tmp}"' EXIT
  for role in "${TARGET_ROLES[@]}"; do
    name="$(role_display_name "${role}")"
    if ! slugs="$(role_skill_slugs "${role}")"; then
      log "role '${role}' (agent '${name}'): no skills found under roles/${role}/.opencode/skills/*/SKILL.md; would FAIL this role live (fail-closed)"
      dry_failed=$((dry_failed + 1))
      continue
    fi
    nslugs="$(printf '%s\n' "${slugs}" | wc -l | tr -d '[:space:]')"
    log "role '${role}' (agent '${name}'): ${nslugs} skill(s)"
    while IFS= read -r slug; do
      [ -n "${slug}" ] || continue
      skill_file="${ROLES_DIR}/${role}/.opencode/skills/${slug}/SKILL.md"
      skill_bytes="$(wc -c < "${skill_file}" | tr -d '[:space:]')"
      skill_sha="$(sha256sum "${skill_file}" | cut -d' ' -f1)"
      # Derived per upstream deriveCanonicalSkillKey (company/<id>/<slug>);
      # <companyId> is unknown offline so the id segment is a placeholder.
      log "  skill '${slug}': would-ensure company skill (sharingScope company, SKILL.md ${skill_bytes} bytes, sha256:${skill_sha}); would-bind key 'company/<companyId>/${slug}' via sync mode add"
      printf '%s\n' "${slug}" >> "${dry_unique_tmp}"
      dry_refs=$((dry_refs + 1))
    done <<< "${slugs}"
    extra="$(role_supporting_count "${role}")"
    if [ "${extra}" != "0" ]; then
      log "  deferred: ${extra} supporting file(s) need manual attach (SKILL.md-only upload; see --help)"
      dry_deferred=$((dry_deferred + extra))
    fi
    dry_roles=$((dry_roles + 1))
  done
  dry_unique="$(sort -u "${dry_unique_tmp}" | wc -l | tr -d '[:space:]')"
  rm -f "${dry_unique_tmp}"
  trap - EXIT
  log "dry-run summary: ${dry_roles} role(s) scannable, ${dry_refs} skill ref(s) across ${dry_unique} unique slug(s), ${dry_deferred} supporting file(s) deferred, ${dry_failed} role(s) with no skills; zero network calls attempted"
  if [ "${dry_failed}" -gt 0 ]; then
    exit 1
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

# Parse a company-skills list body (JSON ARRAY of {id,key,slug,...}) into
# "slug\tkey\tid" lines. Accepts {skills:[...]} / {items:[...]} wrappers
# defensively, but exits NONZERO on anything unparseable (fail-closed: never
# let a 500 page masquerade as "no skills yet").
skills_index() {
  python3 -c '
import json, sys
raw = open(sys.argv[1], "r", encoding="utf-8").read()
try:
    doc = json.loads(raw)
except Exception as exc:
    sys.stderr.write("error: skills list response is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
items = doc
if isinstance(doc, dict):
    for key in ("skills", "items", "data", "results"):
        if isinstance(doc.get(key), list):
            items = doc[key]
            break
if not isinstance(items, list):
    sys.stderr.write("error: skills list response has unexpected shape (expected array)\n")
    sys.exit(1)
for entry in items:
    if not isinstance(entry, dict):
        sys.stderr.write("error: skills list entry has unexpected shape (expected object)\n")
        sys.exit(1)
    slug = entry.get("slug")
    key = entry.get("key")
    sid = entry.get("id")
    if not isinstance(slug, str) or not slug or not isinstance(key, str) or not key:
        continue
    print("%s\t%s\t%s" % (slug, key, sid if isinstance(sid, str) else ""))
' "$1"
}

# Parse a create-skill response body into "id\tkey\tslug". Exits NONZERO
# when the shape is wrong or key/slug are missing (fail-closed).
skill_create_info() {
  python3 -c '
import json, sys
raw = open(sys.argv[1], "r", encoding="utf-8").read()
try:
    doc = json.loads(raw)
except Exception as exc:
    sys.stderr.write("error: skill create response is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
if isinstance(doc, dict):
    for key in ("skill", "data"):
        if isinstance(doc.get(key), dict):
            doc = doc[key]
            break
if not isinstance(doc, dict):
    sys.stderr.write("error: skill create response has unexpected shape (expected object)\n")
    sys.exit(1)
sid = doc.get("id")
skey = doc.get("key")
slug = doc.get("slug")
if not isinstance(skey, str) or not skey or not isinstance(slug, str) or not slug:
    sys.stderr.write("error: skill create response is missing key/slug\n")
    sys.exit(1)
print("%s\t%s\t%s" % (sid if isinstance(sid, str) else "", skey, slug))
' "$1"
}

# Parse an agent skills snapshot (GET /api/agents/:id/skills) into the set
# of desired skill keys, one per line. Collects desiredSkillEntries[].key
# plus desiredSkills[] (string form), deduplicated. Exits NONZERO on
# unparseable bodies (fail-closed).
agent_desired_keys() {
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

# Extract frontmatter name/description from a SKILL.md file into
# "name\t<description or empty>". Exits NONZERO when no usable name is
# found (create requires name; fail the role fail-closed, never invent one).
skill_frontmatter() {
  python3 -c '
import re, sys
raw = open(sys.argv[1], "r", encoding="utf-8").read()
name = ""
desc = ""
match = re.match(r"\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|$)", raw, re.S)
if match:
    for line in match.group(1).splitlines():
        field = re.match(r"\s*name\s*:\s*(.+?)\s*$", line)
        if field and not name:
            name = field.group(1).strip().strip("\"'"'"'")
            continue
        field = re.match(r"\s*description\s*:\s*(.+?)\s*$", line)
        if field and not desc:
            desc = field.group(1).strip().strip("\"'"'"'")
if not name:
    sys.stderr.write("error: SKILL.md has no frontmatter name: %s\n" % sys.argv[1])
    sys.exit(1)
print("%s\t%s" % (name, desc))
' "$1"
}

# Build a skill-create payload: $1 = SKILL.md path, $2 = skill name,
# $3 = slug, $4 = description (may be empty), $5 = output JSON path.
# JSON-encoded via python so arbitrary markdown (quotes, newlines, unicode)
# can never break the payload. sharingScope is always "company"; the
# idempotencyKey is deterministic per slug so retried runs collapse
# server-side instead of duplicating skills.
build_create_payload() {
  SKILL_PATH="$1" SKILL_NAME="$2" SKILL_SLUG="$3" SKILL_DESC="$4" OUT_PATH="$5" python3 -c '
import json, os
with open(os.environ["SKILL_PATH"], "r", encoding="utf-8") as fh:
    markdown = fh.read()
desc = os.environ.get("SKILL_DESC", "")
payload = {
    "name": os.environ["SKILL_NAME"],
    "slug": os.environ["SKILL_SLUG"],
    "description": desc if desc else None,
    "markdown": markdown,
    "sharingScope": "company",
    "idempotencyKey": "fleet-enrich-s2-%s" % os.environ["SKILL_SLUG"],
}
with open(os.environ["OUT_PATH"], "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
'
}

# Build a skill-sync payload: $1 = output path, $2.. = desired keys.
# desiredSkills entries are {key, versionId:null} per
# agentDesiredSkillSelectionSchema (string form would also validate, but the
# explicit object form pins versionId:null deliberately).
build_sync_payload() {
  local out_path="$1"
  shift
  SYNC_KEYS="$*" OUT_PATH="${out_path}" python3 -c '
import json, os
keys = [k for k in os.environ.get("SYNC_KEYS", "").split() if k]
payload = {"mode": "add", "desiredSkills": [{"key": k, "versionId": None} for k in keys]}
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

# ---- Pass A: register every needed slug as a company skill. ----
# Needed slugs are gathered across TARGET_ROLES first so each unique slug is
# created at most once (duplicate slugs across roles share byte-identical
# bodies — verified — so one company skill serves every holder).
log "pass A: collecting skill slugs across ${#TARGET_ROLES[@]} role(s)"
NEED_SLUGS=()
ROLE_SLUGS_TMP="$(mktemp -d)"
for role in "${TARGET_ROLES[@]}"; do
  if ! slugs="$(role_skill_slugs "${role}")"; then
    # Recorded as a role failure later (Pass B); keep collecting for the rest.
    printf '' > "${ROLE_SLUGS_TMP}/${role}.slugs"
    printf 'MISSING\n' > "${ROLE_SLUGS_TMP}/${role}.state"
    continue
  fi
  printf '%s\n' "${slugs}" > "${ROLE_SLUGS_TMP}/${role}.slugs"
  printf 'OK\n' > "${ROLE_SLUGS_TMP}/${role}.state"
  while IFS= read -r slug; do
    [ -n "${slug}" ] || continue
    already="false"
    for have in ${NEED_SLUGS[@]+"${NEED_SLUGS[@]}"}; do
      if [ "${have}" = "${slug}" ]; then
        already="true"
        break
      fi
    done
    if [ "${already}" = "false" ]; then
      NEED_SLUGS+=("${slug}")
    fi
  done <<< "${slugs}"
done
log "pass A: ${#NEED_SLUGS[@]} unique skill slug(s) needed"

api GET "/api/companies/${COMPANY_ID}/skills" > "${TMPDIR_WORK}/skills-list.json"
if ! skills_index "${TMPDIR_WORK}/skills-list.json" > "${TMPDIR_WORK}/skills-index.tsv"; then
  echo "error: skills list response is unparseable; aborting (server body above)" >&2
  exit 1
fi

# slug -> canonical key, learned from the server list only (never guessed).
slug_key() {
  local want="$1"
  awk -F'\t' -v slug="${want}" '$1 == slug { print $2; exit }' "${TMPDIR_WORK}/skills-index.tsv"
}

# Representative SKILL.md path for a slug: first TARGET_ROLES holder wins.
# Same-slug bodies are byte-identical fleet-wide (verified), so any holder's
# file is the canonical payload.
slug_source_file() {
  local want="$1" role slug
  for role in "${TARGET_ROLES[@]}"; do
    while IFS= read -r slug; do
      if [ "${slug}" = "${want}" ]; then
        printf '%s\n' "${ROLES_DIR}/${role}/.opencode/skills/${slug}/SKILL.md"
        return 0
      fi
    done < "${ROLE_SLUGS_TMP}/${role}.slugs"
  done
  return 1
}

PASSA_FAILED=""
for slug in ${NEED_SLUGS[@]+"${NEED_SLUGS[@]}"}; do
  existing_key="$(slug_key "${slug}")"
  if [ -n "${existing_key}" ]; then
    log "skill '${slug}' already registered as '${existing_key}'; skipping create"
    continue
  fi
  src_file=""
  if ! src_file="$(slug_source_file "${slug}")"; then
    bad "skill '${slug}': no local SKILL.md found among target roles; holders of this slug will fail in pass B"
    PASSA_FAILED="${PASSA_FAILED:+${PASSA_FAILED} }${slug}"
    continue
  fi
  fm=""
  if ! fm="$(skill_frontmatter "${src_file}")"; then
    bad "skill '${slug}': SKILL.md frontmatter is unusable (${src_file}); holders of this slug will fail in pass B"
    PASSA_FAILED="${PASSA_FAILED:+${PASSA_FAILED} }${slug}"
    continue
  fi
  skill_name="$(printf '%s' "${fm}" | cut -f1)"
  skill_desc="$(printf '%s' "${fm}" | cut -f2)"
  skill_bytes="$(wc -c < "${src_file}" | tr -d '[:space:]')"
  log "creating company skill '${slug}' (name '${skill_name}', SKILL.md ${skill_bytes} bytes, sharingScope company)"
  if ! build_create_payload "${src_file}" "${skill_name}" "${slug}" "${skill_desc}" "${TMPDIR_WORK}/create-${slug}.json"; then
    bad "skill '${slug}': failed to build create payload; holders of this slug will fail in pass B"
    PASSA_FAILED="${PASSA_FAILED:+${PASSA_FAILED} }${slug}"
    continue
  fi
  if ! api POST "/api/companies/${COMPANY_ID}/skills" "${TMPDIR_WORK}/create-${slug}.json" > "${TMPDIR_WORK}/create-${slug}.resp.json"; then
    bad "skill '${slug}': create failed (server response above); holders of this slug will fail in pass B"
    PASSA_FAILED="${PASSA_FAILED:+${PASSA_FAILED} }${slug}"
    continue
  fi
  created=""
  if ! created="$(skill_create_info "${TMPDIR_WORK}/create-${slug}.resp.json")"; then
    bad "skill '${slug}': create response is unparseable; holders of this slug will fail in pass B"
    PASSA_FAILED="${PASSA_FAILED:+${PASSA_FAILED} }${slug}"
    continue
  fi
  created_key="$(printf '%s' "${created}" | cut -f2)"
  created_slug="$(printf '%s' "${created}" | cut -f3)"
  if [ "${created_slug}" != "${slug}" ]; then
    bad "skill '${slug}': server returned slug '${created_slug}' (fingerprint clash on idempotency key?); holders of this slug will fail in pass B"
    PASSA_FAILED="${PASSA_FAILED:+${PASSA_FAILED} }${slug}"
    continue
  fi
  ok "skill '${slug}' registered as '${created_key}'"
done

# Never trust create responses alone: re-GET the list and learn every key
# from the server. A slug still absent here fails its holder roles.
api GET "/api/companies/${COMPANY_ID}/skills" > "${TMPDIR_WORK}/skills-list-final.json"
if ! skills_index "${TMPDIR_WORK}/skills-list-final.json" > "${TMPDIR_WORK}/skills-index.tsv"; then
  echo "error: post-create skills list response is unparseable; aborting (server body above)" >&2
  exit 1
fi
for slug in ${NEED_SLUGS[@]+"${NEED_SLUGS[@]}"}; do
  if [ -z "$(slug_key "${slug}")" ]; then
    bad "skill '${slug}': absent from server list after pass A; holders of this slug will fail"
    case " ${PASSA_FAILED} " in
      *" ${slug} "*) ;;
      *) PASSA_FAILED="${PASSA_FAILED:+${PASSA_FAILED} }${slug}" ;;
    esac
  fi
done
if [ -n "${PASSA_FAILED}" ]; then
  bad "pass A failed for slug(s):${PASSA_FAILED:+ }${PASSA_FAILED}"
fi

# ---- Pass B + C: bind each role's keys (mode add) and verify. ----
total=0
bound=0
skipped=0
failed=0
deferred_total=0
FAILED_LIST=""
for role in "${TARGET_ROLES[@]}"; do
  total=$((total + 1))
  name="$(role_display_name "${role}")"
  if [ "$(cat "${ROLE_SLUGS_TMP}/${role}.state")" != "OK" ]; then
    bad "role '${role}': no skills found under roles/${role}/.opencode/skills/*/SKILL.md; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  mapfile -t role_slugs < "${ROLE_SLUGS_TMP}/${role}.slugs"

  # Resolve this role's canonical keys from the verified server index.
  role_keys=()
  missing_slugs=""
  for slug in "${role_slugs[@]}"; do
    [ -n "${slug}" ] || continue
    key="$(slug_key "${slug}")"
    if [ -z "${key}" ]; then
      missing_slugs="${missing_slugs:+${missing_slugs} }${slug}"
    else
      role_keys+=("${key}")
    fi
  done
  if [ -n "${missing_slugs}" ]; then
    bad "role '${role}': slug(s) unregistered after pass A:${missing_slugs:+ }${missing_slugs}; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi

  # Supporting files are deferred LOUDLY, never silently: count them here so
  # the per-role log and the final summary both name the gap. The SKILL.md
  # bodies below still register/bind — the deferral blocks exit 0 only via
  # explicit documentation, and the summary carries the manual follow-up.
  extra="$(role_supporting_count "${role}")"
  if [ "${extra}" != "0" ]; then
    log "role '${role}': deferred: ${extra} supporting file(s) need manual attach (SKILL.md-only upload)"
    deferred_total=$((deferred_total + extra))
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

  # Pass B: read current desired keys first (idempotency), sync mode "add"
  # only the keys not already present.
  if ! api GET "/api/agents/${agent_id}/skills" > "${TMPDIR_WORK}/desired-${role}.json"; then
    bad "role '${role}': desired-skills read failed for agent '${name}'; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  current=""
  if ! current="$(agent_desired_keys "${TMPDIR_WORK}/desired-${role}.json")"; then
    bad "role '${role}': desired-skills response for agent '${name}' is unparseable; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  to_add=()
  for key in "${role_keys[@]}"; do
    present="false"
    while IFS= read -r have; do
      [ -n "${have}" ] || continue
      if [ "${have}" = "${key}" ]; then
        present="true"
        break
      fi
    done <<< "${current}"
    if [ "${present}" = "false" ]; then
      to_add+=("${key}")
    fi
  done
  if [ "${#to_add[@]}" -eq 0 ]; then
    log "agent '${name}' already bound to all ${#role_keys[@]} skill key(s); skipping sync"
    skipped=$((skipped + 1))
  else
    log "binding agent '${name}': syncing ${#to_add[@]} new key(s) via mode add (${#role_keys[@]} total)"
    # shellcheck disable=SC2086
    if ! build_sync_payload "${TMPDIR_WORK}/sync-${role}.json" ${to_add[@]+"${to_add[@]}"}; then
      bad "role '${role}': failed to build sync payload for agent '${name}'; skipping role"
      failed=$((failed + 1))
      FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
      continue
    fi
    if ! api POST "/api/agents/${agent_id}/skills/sync" "${TMPDIR_WORK}/sync-${role}.json" > "${TMPDIR_WORK}/sync-${role}.resp.json"; then
      bad "role '${role}': skill sync failed for agent '${name}' (server response above); skipping role"
      failed=$((failed + 1))
      FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
      continue
    fi
  fi

  # Pass C: re-read bindings; every expected key must be present.
  if ! api GET "/api/agents/${agent_id}/skills" > "${TMPDIR_WORK}/verify-${role}.json"; then
    bad "role '${role}': post-sync skills re-read failed for agent '${name}'; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  verified=""
  if ! verified="$(agent_desired_keys "${TMPDIR_WORK}/verify-${role}.json")"; then
    bad "role '${role}': post-sync skills response for agent '${name}' is unparseable; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  absent=""
  for key in "${role_keys[@]}"; do
    present="false"
    while IFS= read -r have; do
      [ -n "${have}" ] || continue
      if [ "${have}" = "${key}" ]; then
        present="true"
        break
      fi
    done <<< "${verified}"
    if [ "${present}" = "false" ]; then
      absent="${absent:+${absent} }${key}"
    fi
  done
  if [ -n "${absent}" ]; then
    bad "role '${role}': post-sync verification missing key(s) for agent '${name}':${absent:+ }${absent}; skipping role"
    failed=$((failed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  ok "agent '${name}' skills verified (${#role_keys[@]} key(s) bound)"
  bound=$((bound + 1))
done

log "enrich-skills summary: ${bound} bound+verified, ${skipped} already bound, ${failed} failed across ${total} role(s); ${#NEED_SLUGS[@]} unique slug(s) ensured; ${deferred_total} supporting file(s) deferred for manual attach"
if [ "${failed}" -gt 0 ]; then
  bad "enrich-skills FAILED for ${failed} role(s):${FAILED_LIST:+ }${FAILED_LIST}"
  exit 1
fi
ok "enrich-skills complete"
