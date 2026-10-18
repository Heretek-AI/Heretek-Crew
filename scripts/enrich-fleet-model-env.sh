#!/usr/bin/env bash
#
# enrich-fleet-model-env.sh — stamp the fleet-wide Go model cutover onto every
# seeded fleet agent: adapterConfig.model := opencode-go/muse-spark-1.3-contributor
# plus the two managed env keys OPENCODE_GO_API_KEY (as a secret_ref binding
# to a company secret — NEVER a plaintext value, see STRICT SECRET MODE
# below) and PAPERCLIP_OPENCODE_SMALL_MODEL (as a plain binding), preserving
# every other env key verbatim.
#
# STRICT SECRET MODE (b): the server rejects a `type:"plain"` (or bare-string)
# binding for a sensitive key — any key matching `*_KEY`, which includes
# OPENCODE_GO_API_KEY — with HTTP 422
# "Strict secret mode requires secret references for sensitive key: ..."
# (server/src/services/secrets.ts:1905-1913, isSensitiveEnvKey gate inside
# normalizeEnvConfig; binding schema at
# packages/shared/src/validators/secret.ts:15-44). A PATCH carrying the Go
# key as a bare string therefore fails closed server-side. This script
# instead ENSURES a company secret named "OpenCode Go API Key" (POST
# /api/companies/:companyId/secrets, routes/secrets.ts:887, idempotent via a
# prior GET /api/companies/:companyId/secrets, routes/secrets.ts:594) holding
# the live key, then stamps each agent with the reference shape (verified
# live end-to-end, HTTP 200):
#   {"type":"secret_ref","secretId":"<company secret uuid>","version":"latest"}
# Reads return env values as BINDING OBJECTS, not bare strings — e.g.
# {"type":"plain","value":"***REDACTED***"} for live plaintext (redaction.ts)
# — so the merge echoes every existing entry VERBATIM (redacted placeholders
# ride along for server-side restore via restoreRedactedAgentEnv,
# routes/agents.ts:2894-2914) and "already stamped" means: model matches AND
# OPENCODE_GO_API_KEY is a secret_ref (any secretId — ids legitimately change
# after a re-create) AND PAPERCLIP_OPENCODE_SMALL_MODEL is present.
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
#   OPENCODE_GO_API_KEY       The Go subscription key stored in the managed
#                             company secret and referenced (by id) from every
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
# model plus the two managed env KEY names/shapes, and skips ("already
# stamped") when the model matches AND OPENCODE_GO_API_KEY is a secret_ref
# binding (type == secret_ref; a plaintext/bare entry counts as DRIFT and is
# re-stamped) AND PAPERCLIP_OPENCODE_SMALL_MODEL is present. Otherwise it
# PATCHes the merged config, re-GETs, and verifies: model equality,
# OPENCODE_GO_API_KEY present as a secret_ref,
# PAPERCLIP_OPENCODE_SMALL_MODEL present, and every pre-existing env key
# still present (merge-not-replace proof). A role that fails at any step is
# reported and the run continues; the exit code is nonzero with a failure
# count when any role failed. The company-secret ensure step is itself
# idempotent (GET-then-create).
#
# Secret hygiene: secret VALUES are never echoed, never hashed-to-log, never
# appear in error text — including the company-secret create response, from
# which only the secret `id` is extracted and logged. Logs carry only key
# NAMES (OPENCODE_GO_API_KEY, PAPERCLIP_OPENCODE_SMALL_MODEL), model strings
# (not secrets), key-presence match/mismatch, the company secret id, and
# counts. The token travels only as an Authorization header; the Go key
# travels only inside the company-secret POST body; per-agent PATCH bodies
# carry only the secret_ref (secretId), never the key value.
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

# Company secret holding the live Go key (ensured idempotently before the
# per-role loop; agents reference it by id — see STRICT SECRET MODE above).
GO_SECRET_NAME="OpenCode Go API Key"
GO_SECRET_CREATE_KEY="OPENCODE_GO_API_KEY"
GO_SECRET_DESC="Fleet-wide Go subscription key for opencode-go models (managed by enrich-fleet-model-env.sh)"

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
  echo "error: OPENCODE_GO_API_KEY must be set (the Go subscription key stored in the managed company secret)" >&2
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
  log "managed env keys: '${MANAGED_KEY_GO}' (as secret_ref to company secret '${GO_SECRET_NAME}'; strict secret mode rejects plaintext — services/secrets.ts:1905) + '${MANAGED_KEY_SMALL}' (as plain binding from GO_SMALL_MODEL='${GO_SMALL_MODEL}')"
  log "company secret: GET /api/companies/:companyId/secrets, reuse id when key/name matches, else POST create (name/key/description only logged; value never logged)"
  log "live inputs: OPENCODE_GO_API_KEY $([ -n "${OPENCODE_GO_API_KEY}" ] && echo 'set' || echo 'UNSET — required live') (goes ONLY into the company-secret POST body, never into a PATCH)"
  log "merge rule: PATCH adapterConfig {model, env} where env = every existing binding echoed verbatim (incl. ***REDACTED*** plain objects for server-side restore) + the two managed keys overwritten with binding objects; server top-level-merges, nested env replaces (routes/agents.ts:5294) — hence client-side merge"
  log "verify rule: re-GET must show model equality + ${MANAGED_KEY_GO} as secret_ref + ${MANAGED_KEY_SMALL} present + every pre-existing env key still present"
  for role in "${TARGET_ROLES[@]}"; do
    name="$(role_display_name "${role}")"
    log "role '${role}' (agent '${name}'): would GET /api/agents/<id> -> skip when model matches AND ${MANAGED_KEY_GO} is a secret_ref AND ${MANAGED_KEY_SMALL} present ('already stamped'); else ensure company secret then PATCH merged adapterConfig then re-GET and verify"
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
  # line 1, then one "KEY:<name>\t<kind>" line per env key (sorted by name).
  # <kind> is the binding shape as read back from the API: the `type` of a
  # binding object (plain, secret_ref, user_secret_ref), "bare" for a legacy
  # bare-string value, or "object" for a dict without a string `type`.
  # Accepts {agent,...}/{data,...} wrappers defensively. Exits NONZERO on
  # unparseable bodies or when adapterConfig/adapterConfig.env has an
  # unexpected shape (fail-closed: never treat a 500 page as "unstamped").
  # NOTE: env VALUES are redacted display placeholders — only key names and
  # binding kinds are extracted; values are never printed, hashed, or
  # compared here.
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
    binding = env[name]
    if isinstance(binding, dict):
        btype = binding.get("type")
        kind = btype if isinstance(btype, str) and btype else "object"
    elif isinstance(binding, str):
        kind = "bare"
    else:
        kind = "object"
    print("KEY:%s\t%s" % (name, kind))
' "$1"
}

find_go_secret_id() {
  # Reads a GET /api/companies/:companyId/secrets list body on stdin and
  # prints the id of the existing Go company secret, else prints nothing.
  # Match: secret `key` equal to OPENCODE_GO_API_KEY modulo case (the server
  # normalizes keys, e.g. "opencode_go_api_key"), or `name` equal to the
  # managed GO_SECRET_NAME. Accepts a bare list or {secrets:[...]}/{data:...}
  # wrappers. Exits NONZERO on unparseable/unexpected bodies (fail-closed:
  # never silently conclude "absent" from a 500 page and double-create).
  GO_SECRET_NAME="${GO_SECRET_NAME}" python3 -c '
import json, os, sys
raw = sys.stdin.read()
try:
    doc = json.loads(raw)
except Exception:
    sys.exit(1)
items = doc
if isinstance(doc, dict):
    for wrapper in ("secrets", "data", "items"):
        inner = doc.get(wrapper)
        if isinstance(inner, list):
            items = inner
            break
if not isinstance(items, list):
    sys.exit(1)
want_name = os.environ["GO_SECRET_NAME"]
for s in items:
    if not isinstance(s, dict):
        continue
    skey = s.get("key")
    sname = s.get("name")
    sid = s.get("id")
    if not isinstance(sid, str) or not sid:
        continue
    if (isinstance(skey, str) and skey.lower() == "opencode_go_api_key") or \
       (isinstance(sname, str) and sname == want_name):
        print(sid)
        break
'
}

build_secret_create_payload() {
  # $1 = output POST-body path for POST /api/companies/:companyId/secrets.
  # Writes {"name","key","value","description"}; the value arrives via
  # environment (never argv) and is never printed. Exits NONZERO when the
  # value is empty (fail-closed: never create an empty secret).
  OUT_PATH="$1" OPENCODE_GO_API_KEY="${OPENCODE_GO_API_KEY}" GO_SECRET_NAME="${GO_SECRET_NAME}" GO_SECRET_CREATE_KEY="${GO_SECRET_CREATE_KEY}" GO_SECRET_DESC="${GO_SECRET_DESC}" python3 -c '
import json, os, sys
out_path = os.environ["OUT_PATH"]
go_key = os.environ.get("OPENCODE_GO_API_KEY", "")
if not go_key:
    sys.stderr.write("error: OPENCODE_GO_API_KEY is empty; refusing to create an empty company secret\n")
    sys.exit(1)
body = {
    "name": os.environ["GO_SECRET_NAME"],
    "key": os.environ["GO_SECRET_CREATE_KEY"],
    "value": go_key,
    "description": os.environ["GO_SECRET_DESC"],
}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(body, fh)
'
}

secret_id_from_create() {
  # $1 = POST /api/companies/:companyId/secrets 201 response body path.
  # Prints the created secret `id` (uuid). Fail-closed: a missing/empty id
  # exits NONZERO instead of stamping agents against a phantom secret.
  # Only the id is printed — the response value (if echoed) is never shown.
  python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        doc = json.load(fh)
except Exception as exc:
    sys.stderr.write("error: secret create response is not valid JSON: %s\n" % (exc,))
    sys.exit(1)
body = doc
if isinstance(doc, dict):
    for wrapper in ("secret", "data"):
        inner = doc.get(wrapper)
        if isinstance(inner, dict) and isinstance(inner.get("id"), str):
            body = inner
            break
sid = body.get("id") if isinstance(body, dict) else None
if not isinstance(sid, str) or not sid:
    sys.stderr.write("error: secret create response carries no secret id; refusing to continue\n")
    sys.exit(1)
print(sid)
' "$1"
}

build_stamp_payload() {
  # $1 = GET /api/agents/:id detail JSON, $2 = output PATCH payload path.
  # Writes {"adapterConfig": {<existing keys...>, model: TARGET, env: merged}}
  # where merged env = every existing entry echoed VERBATIM (binding objects
  # ride along untouched — redacted plain placeholders are restored
  # server-side; pre-existing secret_refs are never reinterpreted) plus the
  # two managed keys overwritten with binding OBJECTS:
  #   OPENCODE_GO_API_KEY -> {"type":"secret_ref","secretId":<id>,"version":"latest"}
  #   PAPERCLIP_OPENCODE_SMALL_MODEL -> {"type":"plain","value":<small model>}
  # Plaintext for the Go key is REJECTED server-side with 422 under strict
  # secret mode (services/secrets.ts:1905-1913), so no plaintext Go value is
  # emitted here — only the company-secret reference. XDG_CONFIG_HOME and
  # OPENCODE_DISABLE_PROJECT_CONFIG are never touched: they are preserved
  # from the read because they are role-specific.
  # All inputs arrive via per-invocation environment (never argv, never
  # globals — see BUG-1 fix: TARGET_MODEL/MANAGED_KEY_* are plain shell
  # variables, so they are passed explicitly on the invocation line, in the
  # same VAR=... python3 style as DETAIL_PATH/OUT_PATH). The live Go key
  # value is NOT needed here at all: it travels only in the company-secret
  # POST body, never in a per-agent PATCH. Exits NONZERO when the detail is
  # unparseable, adapterConfig/env has an unexpected shape, the secret id is
  # empty, or the small-model reference is empty (fail-closed: never stamp
  # a dangling reference or an empty small-model value).
  DETAIL_PATH="$1" OUT_PATH="$2" TARGET_MODEL="${TARGET_MODEL}" MANAGED_KEY_GO="${MANAGED_KEY_GO}" MANAGED_KEY_SMALL="${MANAGED_KEY_SMALL}" GO_SECRET_ID="${GO_SECRET_ID}" GO_SMALL_MODEL="${GO_SMALL_MODEL}" python3 -c '
import json, os, sys
detail_path = os.environ["DETAIL_PATH"]
out_path = os.environ["OUT_PATH"]
target_model = os.environ["TARGET_MODEL"]
managed_go = os.environ["MANAGED_KEY_GO"]
managed_small = os.environ["MANAGED_KEY_SMALL"]
secret_id = os.environ.get("GO_SECRET_ID", "")
small_model = os.environ.get("GO_SMALL_MODEL", "")
if not secret_id:
    sys.stderr.write("error: GO_SECRET_ID is empty; refusing to stamp a dangling secret reference\n")
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
merged[managed_go] = {"type": "secret_ref", "secretId": secret_id, "version": "latest"}
merged[managed_small] = {"type": "plain", "value": small_model}
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

# ---- Ensure the company secret holding the Go key (idempotent). ----
# Strict secret mode forbids plaintext for OPENCODE_GO_API_KEY, so agents
# reference this secret by id; the key VALUE travels only in the POST body
# below (when creation is needed), never in per-agent PATCHes.
log "ensuring company secret '${GO_SECRET_NAME}'"
if ! api GET "/api/companies/${COMPANY_ID}/secrets" > "${TMPDIR_WORK}/secrets.json"; then
  echo "error: company secret list read failed; aborting (no agent will be touched)" >&2
  exit 1
fi
GO_SECRET_ID=""
if ! GO_SECRET_ID="$(find_go_secret_id < "${TMPDIR_WORK}/secrets.json")"; then
  echo "error: company secret list response is unparseable; aborting (refusing to double-create blindly)" >&2
  exit 1
fi
if [ -z "${GO_SECRET_ID}" ]; then
  log "company secret '${GO_SECRET_NAME}' absent; creating (value never logged)"
  if ! build_secret_create_payload "${TMPDIR_WORK}/secret-create.json"; then
    echo "error: failed to build company secret create payload; aborting" >&2
    exit 1
  fi
  if ! api POST "/api/companies/${COMPANY_ID}/secrets" "${TMPDIR_WORK}/secret-create.json" > "${TMPDIR_WORK}/secret-create.resp.json"; then
    echo "error: company secret create failed (server response above); aborting" >&2
    exit 1
  fi
  if ! GO_SECRET_ID="$(secret_id_from_create "${TMPDIR_WORK}/secret-create.resp.json")"; then
    echo "error: company secret create returned no usable id; aborting" >&2
    exit 1
  fi
  ok "company secret created: ${GO_SECRET_ID}"
else
  log "company secret exists: ${GO_SECRET_ID} (reused; no new secret created)"
fi

# The agent list is fetched ONCE up front and reused from the cache
# (mirrors seed-50-fleet.sh): refreshed only when a lookup misses, so
# steady-state runs cost exactly one LIST and correctness never depends
# on cache freshness.
api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"

log "target model '${TARGET_MODEL}'; managed keys '${MANAGED_KEY_GO}' (secret_ref ${GO_SECRET_ID}) + '${MANAGED_KEY_SMALL}' (plain); names/ids only, values never logged"

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

  # ---- Compare: GET the agent and check model + managed key name/kind. ----
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
  # Name+kind match/mismatch only — values are redacted server-side and are
  # never compared or printed (see header contract 2). The Go key counts as
  # stamped ONLY when its binding kind is secret_ref: a plaintext/bare
  # entry is drift (the server would 422 it) and must be re-stamped. Any
  # secret_ref id counts — ids legitimately change after a re-create.
  model_match="mismatch"
  [ "${current_model}" = "${TARGET_MODEL}" ] && model_match="match"
  go_match="mismatch"
  go_kind="absent"
  small_match="mismatch"
  small_kind="absent"
  while IFS= read -r have; do
    [ -n "${have}" ] || continue
    have_name="${have%%$'\t'*}"
    have_kind="${have#*$'\t'}"
    [ "${have_name}" = "${have}" ] && have_kind="bare"
    if [ "${have_name}" = "${MANAGED_KEY_GO}" ]; then
      go_kind="${have_kind}"
      [ "${have_kind}" = "secret_ref" ] && go_match="match"
    fi
    if [ "${have_name}" = "${MANAGED_KEY_SMALL}" ]; then
      small_kind="${have_kind}"
      small_match="match"
    fi
  done <<< "${current_keys}"
  # Snapshot the pre-stamp key NAMES for the merge-not-replace proof below.
  printf '%s\n' "${current_keys}" | sed 's/\t.*//' > "${TMPDIR_WORK}/prekeys-${role}.txt"

  if [ "${model_match}" = "match" ] && [ "${go_match}" = "match" ] && [ "${small_match}" = "match" ]; then
    log "role '${role}' already stamped (model ${model_match}, ${MANAGED_KEY_GO} ${go_match} [${go_kind}], ${MANAGED_KEY_SMALL} ${small_match} [${small_kind}]); skipping"
    nskipped=$((nskipped + 1))
    continue
  fi
  log "role '${role}': drift detected (model ${model_match}, ${MANAGED_KEY_GO} ${go_match} [${go_kind}], ${MANAGED_KEY_SMALL} ${small_match} [${small_kind}]); stamping"

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
  # Re-verify asserts: (a) OPENCODE_GO_API_KEY is a secret_ref in the
  # re-read (not merely present — plaintext would 422 on the next write and
  # means the stamp did not take), (b) the model matches, (c) every
  # pre-existing env key is still present (merge-not-replace).
  post_go="mismatch"
  post_go_kind="absent"
  post_small="mismatch"
  while IFS= read -r have; do
    [ -n "${have}" ] || continue
    have_name="${have%%$'\t'*}"
    have_kind="${have#*$'\t'}"
    [ "${have_name}" = "${have}" ] && have_kind="bare"
    if [ "${have_name}" = "${MANAGED_KEY_GO}" ]; then
      post_go_kind="${have_kind}"
      [ "${have_kind}" = "secret_ref" ] && post_go="match"
    fi
    [ "${have_name}" = "${MANAGED_KEY_SMALL}" ] && post_small="match"
  done <<< "${post_keys}"
  # Names-only view for the merge-not-replace proof below.
  post_names="$(printf '%s\n' "${post_keys}" | sed 's/\t.*//')"
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
    done <<< "${post_names}"
    if [ "${found}" = "false" ]; then
      dropped="${dropped:+${dropped} }${want}"
    fi
  done < "${TMPDIR_WORK}/prekeys-${role}.txt"
  if [ "${post_model}" != "${TARGET_MODEL}" ] || [ "${post_go}" != "match" ] || [ "${post_small}" != "match" ] || [ -n "${dropped}" ]; then
    bad "role '${role}': post-stamp verification failed for agent '${name}' (model '${post_model}', ${MANAGED_KEY_GO} ${post_go} [${post_go_kind}], ${MANAGED_KEY_SMALL} ${post_small}, dropped keys:${dropped:+ }${dropped:-none}); skipping role"
    nfailed=$((nfailed + 1))
    FAILED_LIST="${FAILED_LIST:+${FAILED_LIST} }${role}"
    continue
  fi
  ok "agent '${name}' stamped+verified (model '${TARGET_MODEL}', ${MANAGED_KEY_GO} ${post_go} [${post_go_kind}], ${MANAGED_KEY_SMALL} ${post_small}, 0 keys dropped)"
  nstamped=$((nstamped + 1))
done

log "enrich-model-env summary: ${nstamped} stamped, ${nskipped} already stamped, ${nfailed} failed across ${total} role(s)"
if [ "${nfailed}" -gt 0 ]; then
  bad "enrich-model-env FAILED for ${nfailed} role(s):${FAILED_LIST:+ }${FAILED_LIST}"
  exit 1
fi
ok "enrich-model-env complete"
