#!/usr/bin/env bash
#
# seed-50-fleet.sh — idempotently seed "Heretek Autonomous Fleet" and its
# 51-agent specialist fleet into Paperclip.
#
# Scope note (Wave 3 P1-11, Wave C P1-4): this seeds the 51 fleet roles -
# the ONLY roles on disk (`ls roles/` = 51, single fleet dialect;
# ai-red-teamer promoted from pending to seeded Wave C P1-4). The 6 legacy
# prototype roles (director, pm, programmer, tester, qa, designer) and
# their seeder (scripts/seed-company.sh) were deleted as superseded:
# director -> exec-director; pm -> product-director + tpm-scrum-lead;
# programmer -> the 8 language engineers (19-26); tester/qa ->
# e2e-browser-qa + api-contract-tester + release-qa-officer; designer ->
# ui-ux-designer + design-system-eng + brand-copy-spec.
# scripts/smoke-test.sh discovers roles dynamically and asserts this
# seed's own payload count (52 documents: 1 company + 51 agents).
#
# Usage:
#   ./scripts/seed-50-fleet.sh [--dry-run] [--help]
#
#   --dry-run   Print the exact JSON payloads that would be POSTed (1 company +
#               51 agents) without performing any network calls. Also prints the
#               computed total fleet budget and a WARNING when it differs from
#               the documented fleet cap.
#   --help, -h  Print this usage guide and exit.
#
# Environment (all optional unless noted):
#   PAPERCLIP_URL             Base URL of the Paperclip server.
#                             Default: http://127.0.0.1:3100
#   PAPERCLIP_TOKEN           Board API token for Authorization: Bearer auth.
#                             Falls back to ADMIN_API_KEY. Required unless
#                             --dry-run is passed.
#   ADMIN_API_KEY             Fallback for PAPERCLIP_TOKEN.
#   COMPANY_NAME              Default: "Heretek Autonomous Fleet"
#   MODEL_DEFAULT             Default model for all 51 agents.
#                             Default: anthropic/claude-sonnet-4-5
#   MODEL_COORDINATOR         Model override for the three coordination roles
#                             (exec-director, tpm-scrum-lead, system-architect).
#                             Default: ${MODEL_DEFAULT}
#   TIMER_EXEC_SEC            Scheduler heartbeat interval for exec-director.
#                             0 disables. Default: 1800 (30m)
#   TIMER_TPM_SEC             Scheduler heartbeat interval for tpm-scrum-lead.
#                             0 disables. Default: 3600 (1h)
#   FLEET_BUDGET_CAP_CENTS    Documented total fleet budget cap, in cents.
#                             Default: 1300000 ($13,000.00 USD) — exactly the
#                             sum of the verbatim per-role catalog values
#                             (51 roles incl. ai-red-teamer @ $300, promoted
#                             Wave C P1-4). A WARNING is emitted when the
#                             computed sum differs (e.g. via env override).
#   HEALTH_TIMEOUT_SEC        How long to wait for Paperclip health.
#                             Default: 120
#   POSTGRES_READONLY_URL       REQUIRED (dry-run and live): paperclip_reader
#                             role URL for dba-specialist's postgres MCP.
#                             Must match postgres://paperclip_reader:*@*:*/*;
#                             placeholders and superuser URLs are rejected.
#   GITHUB_TOKEN                REQUIRED (dry-run and live): scoped read-only
#                             PAT for the 7 github-backed roles. CHANGE_ME__
#                             placeholders are rejected. Never echoed.
#   KUBECONFIG_READONLY_PATH    Host path of the read-only kubeconfig bound
#                             to /paperclip/secrets/kubeconfig-readonly.
#                             Default: ./secrets/kubeconfig-readonly. Must be
#                             a regular file; absence fails the run.
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
#     dangerouslySkipPermissions (bool, default true)}. env carries
#     XDG_CONFIG_HOME=/roles/<role> plus OPENCODE_DISABLE_PROJECT_CONFIG=true
#     (defense-in-depth with docker-compose.yml paperclip environment).
#   * Per-role isolation: adapterConfig.env.XDG_CONFIG_HOME=/roles/<role-id> is
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
# Org hierarchy wired via reportsTo (two-pass, idempotent):
#   exec-director -> null (Human Board)
#   product-director, system-architect -> exec-director
#   tpm-scrum-lead, tech-docs-lead, ux-research-analyst -> product-director
#   Dept2 Game Dev (07-12), Dept3 Web/Design (13-18), Dept4 Language (19-26),
#     Dept6 QA (33-38), Dept9 Ops (49-50) -> tpm-scrum-lead
#   Dept5 Cloud/SRE (27-32), Dept7 Security (39-44), Dept8 Data/AI (45-48)
#     -> system-architect
#
# Budgets: exact integer cents from roles-catalog/ROLE_CATALOG_50.md
# (authoritative per-role values), summing to 1300000 cents ($13,000.00 USD),
# which equals FLEET_BUDGET_CAP_CENTS. Per-role values are used verbatim and
# never invented to force a total; print_budget_summary still warns if an
# env override makes the cap disagree with the computed sum.
#
set -euo pipefail

PAPERCLIP_URL="${PAPERCLIP_URL:-http://127.0.0.1:3100}"
PAPERCLIP_TOKEN="${PAPERCLIP_TOKEN:-${ADMIN_API_KEY:-}}"
COMPANY_NAME="${COMPANY_NAME:-Heretek Autonomous Fleet}"
MODEL_DEFAULT="${MODEL_DEFAULT:-anthropic/claude-sonnet-4-5}"
MODEL_COORDINATOR="${MODEL_COORDINATOR:-${MODEL_DEFAULT}}"
TIMER_EXEC_SEC="${TIMER_EXEC_SEC:-1800}"
TIMER_TPM_SEC="${TIMER_TPM_SEC:-3600}"
FLEET_BUDGET_CAP_CENTS="${FLEET_BUDGET_CAP_CENTS:-1300000}"
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

# Wave 2 (P0-2/P1-8) provisioning preflight (fail-closed, dry-run AND live):
# the fleet's MCP configs reference ${POSTGRES_READONLY_URL}
# (dba-specialist), ${GITHUB_TOKEN} (7 github-backed roles) and
# /paperclip/secrets/kubeconfig-readonly (k8s-orchestrator). Seeding with
# any of them absent or still a CHANGE_ME__ placeholder leaves agents with
# unresolvable credentials — refuse instead. Secret VALUES are never echoed;
# only the variable name and the remediation are printed.
require_provisioned_secrets() {
  local missing=0
  local readonly_url="${POSTGRES_READONLY_URL:-}"
  case "${readonly_url}" in
    postgres://paperclip_reader:*@*:*/*)
      ;;
    CHANGE_ME__*|"")
      echo "error: POSTGRES_READONLY_URL must be set to the paperclip_reader role URL (see .env.example; provision the role with scripts/postgres-init-readonly-role.sh)" >&2
      missing=1
      ;;
    *)
      echo "error: POSTGRES_READONLY_URL must use the paperclip_reader user (read-only role) — superuser URLs are rejected" >&2
      missing=1
      ;;
  esac
  case "${GITHUB_TOKEN:-}" in
    ""|CHANGE_ME__*)
      echo "error: GITHUB_TOKEN must be set to a scoped read-only PAT (see .env.example)" >&2
      missing=1
      ;;
  esac
  local kube_path="${KUBECONFIG_READONLY_PATH:-./secrets/kubeconfig-readonly}"
  if [ ! -f "${kube_path}" ]; then
    echo "error: KUBECONFIG_READONLY_PATH '${kube_path}' is not a regular file — place the read-only kubeconfig there (see .env.example)" >&2
    missing=1
  fi
  if [ "${missing}" -ne 0 ]; then
    exit 1
  fi
}
require_provisioned_secrets

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 1; }

TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

log() { printf '[seed] %s\n' "$*"; }

# api METHOD PATH [BODY_FILE] -> prints response body to stdout.
# Wave C P1-3: --fail-with-body (curl >= 7.76) makes every HTTP error
# (4xx/5xx, including a 500 page on GET) exit nonzero WITH the body on
# stderr — a 500 can no longer parse as "missing" and trigger a
# duplicate-create POST, and a rejected Pass-2 PATCH can no longer
# report success. No `|| true`, no status swallowing: callers run under
# `set -e`, so any failed call aborts the run fail-closed.
api() {
  local method="$1" path="$2" body_file="${3:-}"
  local args=(-sS -m 30 --fail-with-body -H "Content-Type: application/json" -H "Authorization: Bearer ${PAPERCLIP_TOKEN}")
  if [ -n "${body_file}" ]; then
    args+=(-d "@${body_file}")
  fi
  curl "${args[@]}" -X "${method}" "${PAPERCLIP_URL}${path}"
}

# Canonical 51 role IDs in catalog order (Roles 01-51; Role 51
# ai-red-teamer promoted Wave C P1-4 — see ROLE_CATALOG_50.md Total line).
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

# Static per-role metadata: Paperclip role enum values come from AGENT_ROLES
# (packages/shared/src/constants.ts): ceo|cto|cmo|cfo|security|engineer|
# designer|pm|qa|devops|researcher|general.
role_paperclip_role() {
  case "$1" in
    exec-director) echo "ceo" ;;
    product-director|tpm-scrum-lead) echo "pm" ;;
    system-architect) echo "cto" ;;
    tech-docs-lead) echo "general" ;;
    ux-research-analyst) echo "researcher" ;;
    game-systems-dev|graphics-shader-eng|engine-systems-eng|game-ai-dev|physics-sim-eng|tech-artist-pipeline) echo "engineer" ;;
    ui-ux-designer|design-system-eng|mobile-web-eng|brand-copy-spec) echo "designer" ;;
    a11y-specialist) echo "qa" ;;
    fe-perf-eng) echo "engineer" ;;
    rust-systems-spec|go-backend-eng|python-backend-spec|ts-node-fullstack|cpp-lowlevel-eng|java-kotlin-eng|ios-mobile-spec|android-mobile-spec) echo "engineer" ;;
    cloud-platform-eng|k8s-orchestrator|sre-incident-eng|observability-eng|dba-specialist|cache-streaming-eng) echo "devops" ;;
    e2e-browser-qa|api-contract-tester|load-stress-tester|sabotage-qa-tester|static-analysis-lead|release-qa-officer) echo "qa" ;;
    appsec-engineer|cloud-sec-auditor|binary-reverse-eng|firmware-sec-analyst|threat-modeler|compliance-auditor) echo "security" ;;
    ai-red-teamer) echo "security" ;;
    data-pipeline-eng|mlops-serving-eng) echo "engineer" ;;
    vector-rag-spec|analytics-metrics-eng) echo "researcher" ;;
    dependency-patcher|git-drift-coord) echo "engineer" ;;
    *) echo "general" ;;
  esac
}

# Display names are the catalog Role headers (roles-catalog/0*.md) and double
# as the Paperclip agent `name` used for idempotent lookup.
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

# Paperclip agent `title`: display name qualified by department.
role_title() {
  case "$1" in
    exec-director|product-director|tpm-scrum-lead|system-architect|tech-docs-lead|ux-research-analyst)
      printf '%s (Executive & Product Management)\n' "$(role_display_name "$1")" ;;
    game-systems-dev|graphics-shader-eng|engine-systems-eng|game-ai-dev|physics-sim-eng|tech-artist-pipeline)
      printf '%s (Game Development)\n' "$(role_display_name "$1")" ;;
    ui-ux-designer|design-system-eng|a11y-specialist|fe-perf-eng|mobile-web-eng|brand-copy-spec)
      printf '%s (Web & UI/UX Design)\n' "$(role_display_name "$1")" ;;
    rust-systems-spec|go-backend-eng|python-backend-spec|ts-node-fullstack|cpp-lowlevel-eng|java-kotlin-eng|ios-mobile-spec|android-mobile-spec)
      printf '%s (Specialized Language Engineering)\n' "$(role_display_name "$1")" ;;
    cloud-platform-eng|k8s-orchestrator|sre-incident-eng|observability-eng|dba-specialist|cache-streaming-eng)
      printf '%s (Cloud, Platform & Site Reliability)\n' "$(role_display_name "$1")" ;;
    e2e-browser-qa|api-contract-tester|load-stress-tester|sabotage-qa-tester|static-analysis-lead|release-qa-officer)
      printf '%s (Quality Assurance & Verification)\n' "$(role_display_name "$1")" ;;
    appsec-engineer|cloud-sec-auditor|binary-reverse-eng|firmware-sec-analyst|threat-modeler|compliance-auditor)
      printf '%s (Defensive Security & Forensics)\n' "$(role_display_name "$1")" ;;
    ai-red-teamer)
      printf '%s (Defensive Security & Forensics)\n' "$(role_display_name "$1")" ;;
    data-pipeline-eng|vector-rag-spec|mlops-serving-eng|analytics-metrics-eng)
      printf '%s (Data & AI Systems)\n' "$(role_display_name "$1")" ;;
    dependency-patcher|git-drift-coord)
      printf '%s (Operations & Maintenance)\n' "$(role_display_name "$1")" ;;
    *) printf '%s\n' "$(role_display_name "$1")" ;;
  esac
}

role_model() {
  case "$1" in
    exec-director|tpm-scrum-lead|system-architect) printf '%s' "${MODEL_COORDINATOR}" ;;
    *) printf '%s' "${MODEL_DEFAULT}" ;;
  esac
}

# Exact integer cents from roles-catalog/ROLE_CATALOG_50.md (authoritative).
# Comments show the USD face value. Sum = 1300000 cents ($13,000.00 USD).
role_budget_cents() {
  case "$1" in
    exec-director) printf '25000' ;; # $250.00 USD
    product-director) printf '20000' ;; # $200.00 USD
    tpm-scrum-lead) printf '20000' ;; # $200.00 USD
    system-architect) printf '25000' ;; # $250.00 USD
    tech-docs-lead) printf '15000' ;; # $150.00 USD
    ux-research-analyst) printf '12000' ;; # $120.00 USD
    game-systems-dev) printf '30000' ;; # $300.00 USD
    graphics-shader-eng) printf '30000' ;; # $300.00 USD
    engine-systems-eng) printf '30000' ;; # $300.00 USD
    game-ai-dev) printf '25000' ;; # $250.00 USD
    physics-sim-eng) printf '25000' ;; # $250.00 USD
    tech-artist-pipeline) printf '20000' ;; # $200.00 USD
    ui-ux-designer) printf '20000' ;; # $200.00 USD
    design-system-eng) printf '25000' ;; # $250.00 USD
    a11y-specialist) printf '18000' ;; # $180.00 USD
    fe-perf-eng) printf '22000' ;; # $220.00 USD
    mobile-web-eng) printf '20000' ;; # $200.00 USD
    brand-copy-spec) printf '15000' ;; # $150.00 USD
    rust-systems-spec) printf '35000' ;; # $350.00 USD
    go-backend-eng) printf '30000' ;; # $300.00 USD
    python-backend-spec) printf '28000' ;; # $280.00 USD
    ts-node-fullstack) printf '30000' ;; # $300.00 USD
    cpp-lowlevel-eng) printf '35000' ;; # $350.00 USD
    java-kotlin-eng) printf '30000' ;; # $300.00 USD
    ios-mobile-spec) printf '30000' ;; # $300.00 USD
    android-mobile-spec) printf '30000' ;; # $300.00 USD
    cloud-platform-eng) printf '30000' ;; # $300.00 USD
    k8s-orchestrator) printf '28000' ;; # $280.00 USD
    sre-incident-eng) printf '30000' ;; # $300.00 USD
    observability-eng) printf '25000' ;; # $250.00 USD
    dba-specialist) printf '30000' ;; # $300.00 USD
    cache-streaming-eng) printf '25000' ;; # $250.00 USD
    e2e-browser-qa) printf '28000' ;; # $280.00 USD
    api-contract-tester) printf '22000' ;; # $220.00 USD
    load-stress-tester) printf '26000' ;; # $260.00 USD
    sabotage-qa-tester) printf '25000' ;; # $250.00 USD
    static-analysis-lead) printf '20000' ;; # $200.00 USD
    release-qa-officer) printf '18000' ;; # $180.00 USD
    appsec-engineer) printf '30000' ;; # $300.00 USD
    cloud-sec-auditor) printf '25000' ;; # $250.00 USD
    binary-reverse-eng) printf '35000' ;; # $350.00 USD
    firmware-sec-analyst) printf '30000' ;; # $300.00 USD
    threat-modeler) printf '22000' ;; # $220.00 USD
    compliance-auditor) printf '16000' ;; # $160.00 USD
    data-pipeline-eng) printf '28000' ;; # $280.00 USD
    vector-rag-spec) printf '30000' ;; # $300.00 USD
    mlops-serving-eng) printf '35000' ;; # $350.00 USD
    analytics-metrics-eng) printf '25000' ;; # $250.00 USD
    dependency-patcher) printf '22000' ;; # $220.00 USD
    git-drift-coord) printf '20000' ;; # $200.00 USD
    ai-red-teamer) printf '30000' ;; # $300.00 USD (Role 51, promoted Wave C P1-4)
    *) echo "error: unknown role '$1' has no catalog budget (fail-closed)" >&2; exit 1 ;;
  esac
}

role_timer_sec() {
  case "$1" in
    exec-director) printf '%s' "${TIMER_EXEC_SEC}" ;;
    tpm-scrum-lead) printf '%s' "${TIMER_TPM_SEC}" ;;
    *) printf '0' ;;
  esac
}

# Prints the parent role-id for reportsTo wiring, or "" for exec-director
# (reports to the Human Board; no reportsTo key).
role_reports_to_parent() {
  case "$1" in
    exec-director) printf '' ;;
    product-director|system-architect) printf 'exec-director' ;;
    tpm-scrum-lead|tech-docs-lead|ux-research-analyst) printf 'product-director' ;;
    cloud-platform-eng|k8s-orchestrator|sre-incident-eng|observability-eng|dba-specialist|cache-streaming-eng) printf 'system-architect' ;;
    appsec-engineer|cloud-sec-auditor|binary-reverse-eng|firmware-sec-analyst|threat-modeler|compliance-auditor) printf 'system-architect' ;;
    ai-red-teamer) printf 'system-architect' ;;
    data-pipeline-eng|vector-rag-spec|mlops-serving-eng|analytics-metrics-eng) printf 'system-architect' ;;
    *) printf 'tpm-scrum-lead' ;;
  esac
}

# build_agent_payload ROLE REPORTS_TO_UUID_OR_EMPTY -> writes JSON to stdout.
build_agent_payload() {
  local role="$1" reports_to="$2"
  # Wave D P2-9 ROLE_DIR hazard guard: ROLE_DIR selects the staged
  # opencode.json via adapterConfig.env.XDG_CONFIG_HOME=/roles/<ROLE_DIR>;
  # a wrong value silently stamps every payload with one role's config.
  # The env chain below sets ROLE_DIR="$1" explicitly (overriding any
  # ambient export), and the python body asserts the chain delivered the
  # iterated role — either mismatch aborts fail-closed, never silently.
  if [ -n "${ROLE_DIR:-}" ] && [ "${ROLE_DIR}" != "$1" ]; then
    echo "error: ROLE_DIR hazard: ambient ROLE_DIR='${ROLE_DIR}' != iterated role '$1' (refusing to stamp payloads with the wrong role config)" >&2
    return 1
  fi
  local timer_sec
  timer_sec="$(role_timer_sec "${role}")"
  local heartbeat_enabled="false"
  if [ "${timer_sec}" != "0" ]; then
    heartbeat_enabled="true"
  fi
  # Fail-closed permissions: dangerouslySkipPermissions MUST stay False.
  # NOTE: even the per-role opencode.json allow-lists are only hints once the
  # CLI runs with --auto (see scripts/opencode-shim.sh) — treat them as
  # defense-in-depth, not as a sandbox boundary. Never set this to True.
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
import json, os, sys
# Wave D P2-9: prove the env chain delivered the iterated role, not a
# stale/wrong ROLE_DIR (fail-closed on mismatch).
if os.environ["ROLE_DIR"] != sys.argv[1]:
    sys.exit(
        "ROLE_DIR hazard: env ROLE_DIR=%r != iterated role %r"
        % (os.environ["ROLE_DIR"], sys.argv[1])
    )
timer = int(os.environ["ROLE_TIMER_SEC"])
payload = {
    "name": os.environ["ROLE_NAME"],
    "role": os.environ["ROLE_ENUM"],
    "title": os.environ["ROLE_TITLE"],
    "adapterType": "opencode_local",
    "adapterConfig": {
        "model": os.environ["ROLE_MODEL"],
        "env": {
            "XDG_CONFIG_HOME": "/roles/" + os.environ["ROLE_DIR"],
            "OPENCODE_DISABLE_PROJECT_CONFIG": "true",
        },
        "dangerouslySkipPermissions": False,
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
' "${role}"
}

find_company_id() {
  # Prints the company id matching $COMPANY_NAME in a list response, else "".
  # Wave C P1-3: an unparseable body or an unexpected shape exits NONZERO
  # (fail-closed) instead of masquerading as "" = "not found" — only a
  # successfully parsed list without a match prints "".
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
  # Wave C P1-3: same fail-closed contract as find_company_id — parse
  # failure or unexpected shape exits nonzero, never "" = "not found".
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

print_budget_summary() {
  # $1 = total cents. Prints the total and a WARNING when it differs from the
  # documented fleet cap (per-role catalog values stay authoritative).
  local total_cents="$1"
  local dollars=$((total_cents / 100))
  local cents=$((total_cents % 100))
  printf '[seed] total fleet budget: %s cents ($%s.%02d USD) across 51 agents (cap %s cents)\n' "${total_cents}" "${dollars}" "${cents}" "${FLEET_BUDGET_CAP_CENTS}"
  if [ "${total_cents}" != "${FLEET_BUDGET_CAP_CENTS}" ]; then
    printf '[seed] WARNING: catalog per-role budgets sum to %s cents, which differs from the documented fleet cap of %s cents; per-role catalog values are authoritative and are used verbatim.\n' "${total_cents}" "${FLEET_BUDGET_CAP_CENTS}" >&2
  fi
}

if [ "${DRY_RUN}" = "true" ]; then
  log "--dry-run: payloads that would be POSTed (no network calls)"
  printf '{"name": "%s"}\n' "${COMPANY_NAME}"
  total=0
  for role in "${ROLE_LIST[@]}"; do
    # reportsTo UUIDs are unknown until creation; dry-run uses placeholders
    # showing the intended org-chart wiring.
    parent="$(role_reports_to_parent "${role}")"
    reports_to=""
    if [ -n "${parent}" ]; then
      reports_to="<${parent}-id>"
    fi
    build_agent_payload "${role}" "${reports_to}"
    budget="$(role_budget_cents "${role}")"
    total=$((total + budget))
  done
  print_budget_summary "${total}"
  exit 0
fi

log "waiting for Paperclip health at ${PAPERCLIP_URL} (timeout ${HEALTH_TIMEOUT_SEC}s)"
deadline=$((SECONDS + HEALTH_TIMEOUT_SEC))
while true; do
  # Wave C P1-3: -f so ANY HTTP error (incl. 500) counts as unhealthy —
  # a 500 page used to count as "healthy" and poison every later lookup.
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

# Pass 1: ensure all 51 agents exist (reportsTo wired in pass 2, when every id
# is known — keeps the script idempotent and order-independent).
# Wave D P2-9: the agent list is fetched ONCE up front and reused from the
# cache (previously one LIST per role, O(n²) at n=51). The cache is
# refreshed only when a lookup misses (stale cache or genuine absence)
# and after every create (server state mutated) — steady-state runs cost
# exactly one LIST, and correctness never depends on cache freshness.
api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"
for role in "${ROLE_LIST[@]}"; do
  name="$(role_display_name "${role}")"
  existing="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"
  if [ -z "${existing}" ]; then
    # Miss against a possibly stale cache: refresh once before concluding
    # the agent is absent (a 500-body can no longer masquerade as missing —
    # find_agent exits nonzero on unparseable bodies via api --fail-with-body).
    api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"
    existing="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"
  fi
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
    # Server state mutated: refresh the cache so later lookups see it.
    api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"
  fi
done

# Resolve ids for org-chart wiring (fail-closed: every parent must resolve).
api GET "/api/companies/${COMPANY_ID}/agents" > "${TMPDIR_WORK}/agents.json"
for role in "${ROLE_LIST[@]}"; do
  name="$(role_display_name "${role}")"
  find_agent "${name}" < "${TMPDIR_WORK}/agents.json" | cut -f1 > "${TMPDIR_WORK}/id-${role}.txt"
done
for parent in exec-director product-director tpm-scrum-lead system-architect; do
  if [ -z "$(cat "${TMPDIR_WORK}/id-${parent}.txt")" ]; then
    echo "error: could not resolve id for org-chart parent '${parent}'" >&2
    exit 1
  fi
done

# Pass 2: enforce reportsTo + budget (idempotent: PATCH only on drift).
for role in "${ROLE_LIST[@]}"; do
  name="$(role_display_name "${role}")"
  current="$(find_agent "${name}" < "${TMPDIR_WORK}/agents.json")"
  agent_id="$(printf '%s' "${current}" | cut -f1)"
  current_reports="$(printf '%s' "${current}" | cut -f2)"
  current_budget="$(printf '%s' "${current}" | cut -f3)"
  parent="$(role_reports_to_parent "${role}")"
  want_reports=""
  if [ -n "${parent}" ]; then
    want_reports="$(cat "${TMPDIR_WORK}/id-${parent}.txt")"
  fi
  want_budget="$(role_budget_cents "${role}")"
  if [ "${current_reports}" != "${want_reports}" ] || [ "${current_budget}" != "${want_budget}" ]; then
    log "updating '${name}': reportsTo=${want_reports:-none} budgetMonthlyCents=${want_budget}"
    # Explicit reportsTo in every PATCH (null clears a stray reportsTo, e.g.
    # on exec-director which must report to none / the Human Board).
    PATCH_REPORTS_TO="${want_reports}" PATCH_BUDGET="${want_budget}" python3 -c '
import json, os
payload = {
    "budgetMonthlyCents": int(os.environ["PATCH_BUDGET"]),
    "reportsTo": os.environ["PATCH_REPORTS_TO"] or None,
}
print(json.dumps(payload))
' > "${TMPDIR_WORK}/patch-${role}.json"
    # Wave C P1-3: the PATCH result is checked — a rejected PATCH (bad
    # reportsTo/budget) aborts with the server body on stderr instead of
    # exiting 0 while "PATCH only upon drift" silently never happened.
    # (api() already exits nonzero on HTTP error via --fail-with-body;
    # the explicit `|| exit 1` pins the contract at this call site too.)
    api PATCH "/api/agents/${agent_id}" "${TMPDIR_WORK}/patch-${role}.json" > "${TMPDIR_WORK}/patch-${role}.resp.json" || {
      echo "error: PATCH for agent '${name}' failed; server response:" >&2
      cat "${TMPDIR_WORK}/patch-${role}.resp.json" >&2
      exit 1
    }
  else
    log "agent '${name}' already correctly wired; no update"
  fi
done

log "seed complete: company '${COMPANY_NAME}' (${COMPANY_ID}) with 51 agents"
log "org chart: exec-director -> {product-director, system-architect}; product-director -> {tpm-scrum-lead, tech-docs-lead, ux-research-analyst}; tpm-scrum-lead -> {game(6), web(6), language(8), qa(6), ops(2)}; system-architect -> {cloud(6), security(7), data(4)}"
