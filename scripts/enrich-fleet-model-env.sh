#!/usr/bin/env bash
#
# enrich-fleet-model-env.sh — stamp the fleet-wide Go model cutover onto every
# seeded fleet agent: adapterConfig.model := opencode-go/muse-spark-1.3-contributor
# plus the two managed env keys OPENCODE_GO_API_KEY and
# PAPERCLIP_OPENCODE_SMALL_MODEL, preserving every other env key verbatim.
#
# WHY (a): the fleet is cut over from anthropic/claude-sonnet-4-5 to the
# gateway-served Go model opencode-go/muse-spark-1.3-contributor (verified
# GO-OK live 2026-10-18: the model works via `opencode run` with
# OPENCODE_GO_API_KEY in env). Each agent's adapterConfig.model selects the
# provider/model OpenCode resolves at run time, and
# PAPERCLIP_OPENCODE_SMALL_MODEL pins OpenCode's auxiliary small_model (title
# generation, helper tasks) to a gateway-served model so those calls never
# fall back to a built-in default the gateway does not serve.
#
# Usage:
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... OPENCODE_GO_API_KEY=... \
#     bash scripts/enrich-fleet-model-env.sh [--dry-run] [--help] [--only <role>[,<role>...]]
#
#   --dry-run   Print the per-role would-check plan (target model, managed key
#               names, merge rule) without performing ANY network calls. No
#               PAPERCLIP_TOKEN or OPENCODE_GO_API_KEY is required. Safe
#               against a dead PAPERCLIP_URL: not a single byte is sent.
#   --only      Restrict the run to a comma-separated subset of role dirs,
#               e.g. --only dba-specialist or --only dba-specialist,k8s-orchestrator
#               (also accepts --only=<list>). Unknown role dirs fail closed.
#   --help, -h  Print this usage guide and exit.
#
# Environment (all optional unless noted):
#   PAPERCLIP_URL             Base URL of the Paperclip server.
#                             Default: http://127.0.0.1:3100
#   PAPERCLIP_TOKEN           Board API key for Authorization: Bearer auth.
#                             Falls back to ADMIN_API_KEY. Required unless
#                             --dry-run is passed.
#   ADMIN_API_KEY             Fallback for PAPERCLIP_TOKEN.
#   OPENCODE_GO_API_KEY       The Go subscription key stamped into every
#                             agent's adapterConfig.env. REQUIRED unless
#                             --dry-run is passed. Never echoed: only the key
#                             NAME and match/mismatch are logged.
#   GO_SMALL_MODEL            Value stamped as PAPERCLIP_OPENCODE_SMALL_MODEL.
#                             Default: opencode-go/glm-5.3-flash
#   COMPANY_NAME              Fleet company used to resolve agent ids.
#                             Default: "Heretek Autonomous Fleet"
#   HEALTH_TIMEOUT_SEC        How long to wait for Paperclip health.
#                             Default: 120
#
# Upstream API contracts (verified against /tmp/paperclip — re-verify here
# before any live run if the checkout moved):
#   1. Update route (b): PATCH /api/agents/:id
#      (server/src/routes/agents.ts:5199:
#      `router.patch("/agents/:id", validate(updateAgentSchema), ...)`) with
#      the updateAgentSchema
#      (packages/shared/src/validators/agent.ts:152-163: the create schema,
#      partial, plus optional replaceAdapterConfig/status; `permissions` is
#      rejected with 422 — this script never sends it).
#   2. Read route: GET /api/agents/:id (server/src/routes/agents.ts:4002)
#      returns buildAgentDetail (server/src/routes/agents.ts:1297), whose
#      adapterConfig passes through redactAgentRowForResponse ->
#      redactAgentAdapterConfig (server/src/redaction.ts:991): EVERY
#      plaintext env value reads back as the display-only placeholder
#      `{type:"plain", value:"***REDACTED***"}` (server/src/redaction.ts
#      redactAgentEnvBinding). Plaintext env values NEVER leave the API, for
#      any actor scope. Consequence: live secret VALUES are unobservable
#      through reads — verification compares the model string plus managed
#      KEY presence/shape (see below), never values.
#   3. Env merge semantics (c): the PATCH handler merges adapterConfig
#      TOP-LEVEL ONLY — `{...existingAdapterConfig, ...requested}`
#      (server/src/routes/agents.ts:5294, when replaceAdapterConfig is not
#      true and the adapter type is unchanged). A PATCH body whose
#      adapterConfig carries `env` REPLACES the whole env map: keys omitted
#      from the request env are DROPPED server-side. This script therefore
#      merges env CLIENT-SIDE: it re-uses every existing env entry verbatim
#      (redacted placeholders included) and overwrites only the two managed
#      keys. Echoing `{type:"plain", value:"***REDACTED***"}` entries back
#      is the supported round-trip: restoreRedactedAgentEnv
#      (server/src/routes/agents.ts:2894-2914) restores those placeholders
#      from the saved config before persistence, so untouched keys keep
#      their live values. The two managed keys carry REAL values in the
#      PATCH, so they are stored, not restored-over. Non-plain-binding
#      entries (bare "***REDACTED***" strings, secret-ref bindings) are
#      echoed back byte-identical and never interpreted here.
#   4. Runtime effect: prepareOpenCodeRuntimeConfig
#      (packages/adapters/opencode-local/src/server/runtime-config.ts)
#      resolves adapterConfig.model (provider/model) against the merged
#      provider map (PAPERCLIP_OPENCODE_PROVIDERS custom providers +
#      auto-registration of the configured model id) and pins
#      `small_model` from input.env.PAPERCLIP_OPENCODE_SMALL_MODEL ??
#      process.env.PAPERCLIP_OPENCODE_SMALL_MODEL (runtime-config.ts:214-222).
#      XDG_CONFIG_HOME + OPENCODE_DISABLE_PROJECT_CONFIG ride along inside
#      the preserved env — dropping them would break per-role isolation,
#      which is why the merge (not replace) rule above is load-bearing.
# If any assumption breaks against your Paperclip build, --dry-run output
# shows the intended per-role targets to adapt.
#
# DURABILITY NOTE (d): this stamp is NOT self-preserving across re-seeds.
# scripts/seed-50-fleet.sh builds adapterConfig.model from MODEL_DEFAULT
# (default anthropic/claude-sonnet-4-5) with MODEL_COORDINATOR for the three
# coordination roles, and carries no Go env keys. Any future
# seed-50-fleet.sh run MUST export
#   MODEL_DEFAULT=opencode-go/muse-spark-1.3-contributor
# (and MODEL_COORDINATOR likewise, unless coordinators should diverge), or
# the re-seed will revert models to anthropic/claude-sonnet-4-5 and this
# script must be re-run to restore the cutover.
#
# Idempotency: per role the script GETs the agent, compares adapterConfig
# model plus the two managed env KEY names, and skips ("already stamped")
# when the model matches and both keys are present. Otherwise it PATCHes
# the merged config, re-GETs, and verifies: model equality, both managed
# keys present with a held (non-empty) value shape, and every pre-existing
# env key still present (merge-not-replace proof). A role that fails at any
# step is reported and the run continues; the exit code is nonzero with a
# failure count when any role failed.
#
# Secret hygiene: secret VALUES are never echoed, never hashed-to-log, never
# appear in error text. Logs carry only key NAMES (OPENCODE_GO_API_KEY,
# PAPERCLIP_OPENCODE_SMALL_MODEL), model strings (not secrets), key-presence
# match/mismatch, and counts. The token travels only as an Authorization
# header; the Go key travels only inside the PATCH JSON body.
#
# Exit codes: 0 all roles stamped-or-already-stamped (verified); 1 one or
# more roles failed (count printed) or a fail-closed preflight tripped;
# 2 CLI misuse (unknown argument, bad --only value).
#
# Examples:
#   bash scripts/enrich-fleet-model-env.sh --dry-run
#   PAPERCLIP_URL=http://127.0.0.1:3100 PAPERCLIP_TOKEN=xxx OPENCODE_GO_API_KEY=yyy bash scripts/enrich-fleet-model-env.sh
#   PAPERCLIP_URL=... PAPERCLIP_TOKEN=... OPENCODE_GO_API_KEY=... bash scripts/enrich-fleet-model-env.sh --only dba-specialist
#
set -euo pipefail

PAPERCLIP_URL="${PAPERCLIP_URL:-http://127.0.0.1:3100}"
PAPERCLIP_TOKEN="${PAPERCLIP_TOKEN:-${ADMIN_API_KEY:-}}"
OPENCODE_GO_API_KEY="${OPENCODE_GO_API_KEY:-}"
GO_SMALL_MODEL="${GO_SMALL_MODEL:-opencode-go/glm-5.3-flash}"
COMPANY_NAME="${COMPANY_NAME:-Heretek Autonomous Fleet}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-120}"

# Fleet-wide Go cutover target (pinned; see WHY above). Not overridable via
# env: an accidental override would stamp a divergent model fleet-wide.
TARGET_MODEL="opencode-go/muse-spark-1.3-contributor"
MANAGED_KEY_GO="OPENCODE_GO_API_KEY"
MANAGED_KEY_SMALL="PAPERCLIP_OPENCODE_SMALL_MODEL"

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

if [ "${DRY_RUN}" != "true" ] && [ -z "${OPENCODE_GO_API_KEY}" ]; then
  echo "error: OPENCODE_GO_API_KEY must be set (the Go subscription key stamped into every agent)" >&2
  exit 1
fi

if [ -z "${PAPERCLIP_URL}" ]; then
  echo "error: PAPERCLIP_URL must be set (default http://127.0.0.1:3100)" >&2
  exit 1
fi

if [ -z "${GO_SMALL_MODEL}" ]; then
  echo "error: GO_SMALL_MODEL must be non-empty (default opencode-go/glm-5.3-flash)" >&2
  exit 1
fi
case "${GO_SMALL_MODEL}" in
  */*) ;;
  *)
    echo "error: GO_SMALL_MODEL must be a provider/model reference (got '${GO_SMALL_MODEL}')" >&2
    exit 1
    ;;
esac

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

log() { printf '[enrich-model-env] %s\n' "$*"; }
ok() { printf '[enrich-model-env] OK: %s\n' "$*"; }
bad() { printf '[enrich-model-env] ERROR: %s\n' "$*" >&2; }

# --dry-run exits here, BEFORE curl/python3 are required and before any
# network call could occur: every statement above and below this block is
# pure local computation (arg parsing, constant targets). Any curl
# invocation while DRY_RUN=true is a bug — gate all api() calls live-only.
if [ "${DRY_RUN}" = "true" ]; then
  log "--dry-run: per-role model+env stamp plan (no network calls)"
  log "target model: '${TARGET_MODEL}' (pinned fleet-wide; not overridable — see WHY)"
  log "managed env keys: '${MANAGED_KEY_GO}' (from OPENCODE_GO_API_KEY: $([ -n "${OPENCODE_GO_API_KEY}" ] && echo 'set' || echo 'UNSET — required live')) + '${MANAGED_KEY_SMALL}' (from GO_SMALL_MODEL='${GO_SMALL_MODEL}')"
  log "merge rule: PATCH adapterConfig {model, env} where env = every existing key echoed verbatim + the two managed keys overwritten; server top-level-merges, nested env replaces (routes/agents.ts:5294) — hence client-side merge"
  log "verify rule: re-GET must show model equality + both managed keys present with a held value + every pre-existing env key still present"
  for role in "${TARGET_ROLES[@]}"; do
    name="$(role_display_name "${role}")"
    log "role '${role}' (agent '${name}'): would GET /api/agents/<id> -> skip when model matches and both managed keys present ('already stamped'); else PATCH merged adapterConfig then re-GET and verify"
  done
  log "dry-run summary: ${#TARGET_ROLES[@]} role(s) would be checked (GET -> compare -> PATCH-if-drift -> re-GET verify); zero network calls attempted"
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

agent_model_keys() {
  # $1 = GET /api/agents/:id detail JSON. Prints the adapterConfig model on
  # line 1, then one "KEY:<name>" line per env key (sorted). Accepts
  # {agent,...}/{data,...} wrappers defensively. Exits NONZERO on
  # unparseable bodies or when adapterConfig/adapterConfig.env has an
  # unexpected shape (fail-closed: never treat a 500 page as "unstamped").
  # NOTE: env VALUES are redacted display placeholders — only key names are
  # extracted; values are never printed, hashed, or compared here.
  python3 -c '
import json, sys
raw = open(sys.argv[1], "r", encoding="utf-8").read()
try:
    doc = json.loads(raw)
except Exception as exc:
    sys.stderr.write("error: agent detail response is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
if not isinstance(doc, dict):
    sys.stderr.write("error: agent detail response has unexpected shape (expected object)\n")
    sys.exit(1)
body = doc
for key in ("agent", "data"):
    inner = doc.get(key)
    if isinstance(inner, dict) and ("adapterConfig" in inner or "adapterType" in inner):
        body = inner
        break
cfg = body.get("adapterConfig")
if not isinstance(cfg, dict):
    sys.stderr.write("error: agent detail adapterConfig is not an object\n")
    sys.exit(1)
model = cfg.get("model")
if not isinstance(model, str):
    model = ""
env = cfg.get("env")
if env is None:
    env = {}
if not isinstance(env, dict):
    sys.stderr.write("error: agent detail adapterConfig.env is not an object\n")
    sys.exit(1)
print(model)
for name in sorted(env.keys()):
    print("KEY:%s" % (name,))
' "$1"
}

build_stamp_payload() {
  # $1 = GET /api/agents/:id detail JSON, $2 = output PATCH payload path.
  # Writes {"adapterConfig": {<existing keys...>, model: TARGET, env: merged}}
  # where merged env = every existing entry echoed VERBATIM (redacted
  # placeholders ride along for server-side restore) plus the two managed
  # keys overwritten with live values. Live values arrive via environment
  # (never argv) and are never printed. Exits NONZERO when the detail is
  # unparseable, adapterConfig/env has an unexpected shape, or a managed
  # value is empty (fail-closed: never stamp an empty secret).
  DETAIL_PATH="$1" OUT_PATH="$2" python3 -c '
import json, os, sys
detail_path = os.environ["DETAIL_PATH"]
out_path = os.environ["OUT_PATH"]
target_model = os.environ["TARGET_MODEL"]
go_key = os.environ.get("OPENCODE_GO_API_KEY", "")
small_model = os.environ.get("GO_SMALL_MODEL", "")
if not go_key:
    sys.stderr.write("error: OPENCODE_GO_API_KEY is empty; refusing to stamp an empty secret\n")
    sys.exit(1)
if not small_model:
    sys.stderr.write("error: GO_SMALL_MODEL is empty; refusing to stamp an empty small-model reference\n")
    sys.exit(1)
try:
    with open(detail_path, "r", encoding="utf-8") as fh:
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
    if isinstance(inner, dict) and ("adapterConfig" in inner or "adapterType" in inner):
        body = inner
        break
cfg = body.get("adapterConfig")
if not isinstance(cfg, dict):
    sys.stderr.write("error: agent detail adapterConfig is not an object\n")
    sys.exit(1)
env = cfg.get("env")
if env is None:
    env = {}
if not isinstance(env, dict):
    sys.stderr.write("error: agent detail adapterConfig.env is not an object; refusing to merge blindly\n")
    sys.exit(1)
merged = dict(env)
merged[os.environ["MANAGED_KEY_GO"]] = go_key
merged[os.environ["MANAGED_KEY_SMALL"]] = small_model
new_cfg = dict(cfg)
new_cfg["model"] = target_model
new_cfg["env"] = merged
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump({"adapterConfig": new_cfg}, fh)
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

log "target model '${TARGET_MODEL}'; managed keys '${MANAGED_KEY_GO}' + '${MANAGED_KEY_SMALL}' (names only; values never logged)"

total=0
nstamped=0
nskipped=0
nfailed=0
FAILED_LIST=""
for role in "${TARGET_ROLES[@]}"; do
  total=$((total + 1))
  name="$(role_display_name "${role}")"

  existing=""
  if ! existing="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"; then
    bad "role '${role}': agent list is unparseable; skipping role"
    nfailed=$((nfailed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  if [ -z "${existing}" ]; then
    # Miss against a possibly stale cache: refresh once before concluding
    # the agent is absent.
    if ! api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"; then
      bad "role '${role}': agent list refresh failed; skipping role"
      nfailed=$((nfailed + 1))
      FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
      continue
    fi
    if ! existing="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"; then
      bad "role '${role}': agent list is unparseable after refresh; skipping role"
      nfailed=$((nfailed + 1))
      FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
      continue
    fi
  fi
  if [ -z "${existing}" ]; then
    bad "role '${role}': agent '${name}' not found — seed the fleet first with scripts/seed-50-fleet.sh; skipping role"
    nfailed=$((nfailed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  agent_id="$(printf '%s' "${existing}" | cut -f1)"
  if [ -z "${agent_id}" ]; then
    bad "role '${role}': agent '${name}' resolved without an id; skipping role"
    nfailed=$((nfailed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi

  # ---- Compare: GET the agent and check model + managed key presence. ----
  if ! api GET "/api/agents/${agent_id}" > "${TMPDIR_WORK}/detail-${role}.json"; then
    bad "role '${role}': agent detail read failed for agent '${name}'; skipping role"
    nfailed=$((nfailed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  snapshot=""
  if ! snapshot="$(agent_model_keys "${TMPDIR_WORK}/detail-${role}.json")"; then
    bad "role '${role}': agent detail for '${name}' is unparseable; skipping role"
    nfailed=$((nfailed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  current_model="$(printf '%s\n' "${snapshot}" | sed -n '1p')"
  current_keys="$(printf '%s\n' "${snapshot}" | sed -n '2,$p' | sed 's/^KEY://')"
  # Key-name match/mismatch only — values are redacted server-side and are
  # never compared or printed (see header contract 2).
  model_match="mismatch"
  [ "${current_model}" = "${TARGET_MODEL}" ] && model_match="match"
  go_match="mismatch"
  small_match="mismatch"
  while IFS= read -r have; do
    [ -n "${have}" ] || continue
    [ "${have}" = "${MANAGED_KEY_GO}" ] && go_match="match"
    [ "${have}" = "${MANAGED_KEY_SMALL}" ] && small_match="match"
  done <<< "${current_keys}"
  # Snapshot the pre-stamp key set for the merge-not-replace proof below.
  printf '%s\n' "${current_keys}" > "${TMPDIR_WORK}/prekeys-${role}.txt"

  if [ "${model_match}" = "match" ] && [ "${go_match}" = "match" ] && [ "${small_match}" = "match" ]; then
    log "role '${role}' already stamped (model ${model_match}, ${MANAGED_KEY_GO} ${go_match}, ${MANAGED_KEY_SMALL} ${small_match}); skipping"
    nskipped=$((nskipped + 1))
    continue
  fi
  log "role '${role}': drift detected (model ${model_match}, ${MANAGED_KEY_GO} ${go_match}, ${MANAGED_KEY_SMALL} ${small_match}); stamping"

  # ---- Stamp: PATCH the client-side-merged adapterConfig. ----
  if ! build_stamp_payload "${TMPDIR_WORK}/detail-${role}.json" "${TMPDIR_WORK}/patch-${role}.json"; then
    bad "role '${role}': failed to build stamp payload for agent '${name}'; skipping role"
    nfailed=$((nfailed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  if ! api PATCH "/api/agents/${agent_id}" "${TMPDIR_WORK}/patch-${role}.json" > "${TMPDIR_WORK}/patch-${role}.resp.json"; then
    bad "role '${role}': PATCH failed for agent '${name}' (server response above); skipping role"
    nfailed=$((nfailed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi

  # ---- Verify: re-GET and prove model + keys + no key dropped. ----
  if ! api GET "/api/agents/${agent_id}" > "${TMPDIR_WORK}/verify-${role}.json"; then
    bad "role '${role}': post-stamp re-read failed for agent '${name}'; skipping role"
    nfailed=$((nfailed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  verified=""
  if ! verified="$(agent_model_keys "${TMPDIR_WORK}/verify-${role}.json")"; then
    bad "role '${role}': post-stamp detail for '${name}' is unparseable; skipping role"
    nfailed=$((nfailed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  post_model="$(printf '%s\n' "${verified}" | sed -n '1p')"
  post_keys="$(printf '%s\n' "${verified}" | sed -n '2,$p' | sed 's/^KEY://')"
  post_go="mismatch"
  post_small="mismatch"
  while IFS= read -r have; do
    [ -n "${have}" ] || continue
    [ "${have}" = "${MANAGED_KEY_GO}" ] && post_go="match"
    [ "${have}" = "${MANAGED_KEY_SMALL}" ] && post_small="match"
  done <<< "${post_keys}"
  # Merge-not-replace proof: every pre-stamp env key must still be present.
  # (Managed keys are in both sets by construction; this guards the rest,
  # e.g. XDG_CONFIG_HOME + OPENCODE_DISABLE_PROJECT_CONFIG.)
  dropped=""
  while IFS= read -r want; do
    [ -n "${want}" ] || continue
    found="false"
    while IFS= read -r have; do
      [ -n "${have}" ] || continue
      if [ "${have}" = "${want}" ]; then
        found="true"
        break
      fi
    done <<< "${post_keys}"
    if [ "${found}" = "false" ]; then
      dropped="${dropped:+${dropped} }${want}"
    fi
  done < "${TMPDIR_WORK}/prekeys-${role}.txt"
  if [ "${post_model}" != "${TARGET_MODEL}" ] || [ "${post_go}" != "match" ] || [ "${post_small}" != "match" ] || [ -n "${dropped}" ]; then
    bad "role '${role}': post-stamp verification failed for agent '${name}' (model '${post_model}', ${MANAGED_KEY_GO} ${post_go}, ${MANAGED_KEY_SMALL} ${post_small}, dropped keys:${dropped:+ }${dropped:-none}); skipping role"
    nfailed=$((nfailed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  ok "agent '${name}' stamped+verified (model '${TARGET_MODEL}', ${MANAGED_KEY_GO} ${post_go}, ${MANAGED_KEY_SMALL} ${post_small}, 0 keys dropped)"
  nstamped=$((nstamped + 1))
done

log "enrich-model-env summary: ${nstamped} stamped, ${nskipped} already stamped, ${nfailed} failed across ${total} role(s)"
if [ "${nfailed}" -gt 0 ]; then
  bad "enrich-model-env FAILED for ${nfailed} role(s):${FAILED_LIST:+ }${FAILED_LIST}"
  exit 1
fi
ok "enrich-model-env complete"
