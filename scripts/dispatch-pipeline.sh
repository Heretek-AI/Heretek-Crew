#!/usr/bin/env bash
#
# scripts/dispatch-pipeline.sh — Worktree Provisioner + Pipeline Tracer for Heretek-Crew.
#
# SCOPE (Wave B P0-4 re-scope): despite the historical "pipeline" name, this
# script is a provisioner/tracer, NOT an end-to-end dispatcher:
#   - it does NOT call the Paperclip API (no curl, no PAPERCLIP_URL, no
#     /api/ — there is deliberately no ticket-transition code here, so it
#     does NOT perform todo->in_progress->in_review->done transitions);
#   - in --dry-run: it traces all 6 phases and prints the payloads (a
#     planning aid for MANUAL assignment in Paperclip);
#   - in execute mode: it provisions ONE isolated git worktree + task_plan.md
#     (phase 3) and exits 0. Phases 1/2/4/5 describe MANUAL steps a human
#     performs in Paperclip; phase 6 requires an explicit MANUAL merge
#     (no auto-merge is ever performed — fail-closed).
# Do not cite this script as executing agent work, assigning tickets, or
# changing ticket state: it provisions the worktree and stops.
#
# Phases (agent work is MANUAL unless noted — only phase 3 executes):
#   1. PRD: Product Director generates product requirements and user stories (manual).
#   2. ARCH: System Architect generates ADR and interface contracts (manual).
#   3. DECOMPOSE: TPM / Scrum Lead creates ticket, provisions isolated worktree (EXECUTED).
#   4. DEV: Specialist engineer implements changes using opencode-harness (manual).
#   5. QA: e2e-browser-qa & Release QA Officer verify via local CI and browser tests (manual).
#   6. ARCHIVE-ONLY: no auto-merge is performed (fail-closed). The worktree is
#      retained for explicit manual review + git merge; archiving runs only
#      after a human merges (see Phase 6 body).
#
# Usage:
#   ./scripts/dispatch-pipeline.sh [options] "<feature-prompt>"
#
# Options:
#   --ticket-id <id>     Unique ticket identifier (default: tkt-<timestamp>)
#   --role <role-id>     Primary engineering specialist (default: ts-node-fullstack)
#   --base-branch <name> Git branch to fork and merge against (default: main)
#   --dry-run            Trace all phases and print payloads without execution
#   --help, -h           Show this help message
#
set -euo pipefail

# Wave 4 P2-3: anchor to the repo root so the script works from any cwd
# (and a hostile same-named script earlier in PATH/cwd can never shadow
# the worktree-manager call below — it is invoked via ${REPO_ROOT}).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# P2-2: fail-closed ticket-id allowlist (mirrors worktree-manager.sh
# require_ticket_id): blocks path traversal (../evil), absolute paths
# (/tmp/wt-abs), and ref-hostile names before any worktree path or
# branch name is derived from the id. The default timestamp id always
# matches; an explicit --ticket-id that violates the gate exits 2.
require_ticket_id() {
  local ticket_id="$1"
  if [[ ! "${ticket_id}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$ ]]; then
    echo "error: invalid ticket-id '${ticket_id}' (allowlist: ^[A-Za-z0-9][A-Za-z0-9._-]{1,63}\$)" >&2
    exit 2
  fi
}

DRY_RUN="false"
TICKET_ID="tkt-$(date +%Y%m%d%H%M%S)"
PRIMARY_ROLE="ts-node-fullstack"
BASE_BRANCH="main"
FEATURE_PROMPT=""

show_help() {
  sed -n '3,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ticket-id)
      shift
      TICKET_ID="${1:?--ticket-id requires a value}"
      ;;
    --role)
      shift
      PRIMARY_ROLE="${1:?--role requires a value}"
      ;;
    --base-branch)
      shift
      BASE_BRANCH="${1:?--base-branch requires a value}"
      ;;
    --dry-run)
      DRY_RUN="true"
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    -*)
      echo "error: unknown option '$1' (see --help)" >&2
      exit 2
      ;;
    *)
      if [ -z "${FEATURE_PROMPT}" ]; then
        FEATURE_PROMPT="$1"
      else
        FEATURE_PROMPT="${FEATURE_PROMPT} $1"
      fi
      ;;
  esac
  shift
done

if [ -z "${FEATURE_PROMPT}" ]; then
  echo "error: feature prompt is required (e.g. $0 'Build OAuth login flow')" >&2
  exit 1
fi
require_ticket_id "${TICKET_ID}"

log_stage() {
  printf '\n======================================================================\n'
  printf ' [PIPELINE STAGE: %s] %s\n' "$1" "$2"
  printf '======================================================================\n'
}

log_step() {
  printf '  -> %s\n' "$*"
}

WORKTREE_DIR="workspaces/tickets/${TICKET_ID}"

# Phase 1: PRD Generation (MANUAL — this script performs no Paperclip call)
log_stage "1/6 PRD" "Product Director generates feature specification (manual step)"
log_step "Role: product-director (Department: Executive & Product Management)"
log_step "Input Prompt: ${FEATURE_PROMPT}"
if [ "${DRY_RUN}" = "true" ]; then
  log_step "[DRY-RUN] MANUAL assignment (no API call, nothing emitted): assign the PRD task to 'product-director' in Paperclip"
  log_step "[DRY-RUN] Output artifact expected: docs/prd/PRD-${TICKET_ID}.md"
else
  log_step "MANUAL step: assign the PRD task to 'product-director' in Paperclip (no API call performed by this script)"
fi

# Phase 2: Architecture & ADR (MANUAL — this script performs no Paperclip call)
log_stage "2/6 ARCH" "System Architect defines technical architecture & contracts (manual step)"
log_step "Role: system-architect (Department: Executive & Product Management)"
log_step "Input Spec: docs/prd/PRD-${TICKET_ID}.md"
if [ "${DRY_RUN}" = "true" ]; then
  log_step "[DRY-RUN] MANUAL assignment (no API call, nothing emitted): assign the ADR task to 'system-architect' in Paperclip"
  log_step "[DRY-RUN] Output artifact expected: docs/adr/ADR-${TICKET_ID}.md"
else
  log_step "MANUAL step: assign the ADR task to 'system-architect' in Paperclip (no API call performed by this script)"
fi

# Phase 3: Worktree Isolation & Sprint Planning
log_stage "3/6 DECOMPOSE" "TPM / Scrum Lead provisions worktree and task ledger"
log_step "Role: tpm-scrum-lead (Department: Executive & Product Management)"
log_step "Action: Provision isolated Git worktree via scripts/worktree-manager.sh"
if [ "${DRY_RUN}" = "true" ]; then
  log_step "[DRY-RUN] Executing: bash scripts/worktree-manager.sh create ${TICKET_ID} ${BASE_BRANCH}"
  log_step "[DRY-RUN] Target directory: ${WORKTREE_DIR}"
  log_step "[DRY-RUN] Initialized planning-with-files ledger: ${WORKTREE_DIR}/task_plan.md"
else
  bash "${REPO_ROOT}/scripts/worktree-manager.sh" create "${TICKET_ID}" "${BASE_BRANCH}"
  # (Wave 4 P2-2: no mkdir -p here — worktree-manager already created the
  # directory; re-creating it would mask a failed provisioning. If the dir
  # is absent the redirect below fails closed via set -e.)
  cat <<EOF > "${WORKTREE_DIR}/task_plan.md"
# Sprint Task Plan: ${TICKET_ID}
## Goal
${FEATURE_PROMPT}

## Constraints & Invariants
- Zero-stub policy: full production implementation.
- Pinned dependencies only.
- Strict Least-Privilege permissions enforced.

## Definition of Done (DoD)
- [ ] Feature implemented in ${WORKTREE_DIR}
- [ ] Unit & integration tests passing
- [ ] Local CI verification pass (act / smoke-test)
- [ ] QA sign-off from release-qa-officer
EOF
fi

# Phase 4: Implementation (MANUAL — this script performs no Paperclip call)
log_stage "4/6 DEV" "Specialist engineer implements feature in worktree (manual step)"
log_step "Role: ${PRIMARY_ROLE} (Target Workspace: ${WORKTREE_DIR})"
log_step "Runtime: OpenCode v2 + opencode-harness (FNV-1a hash edits, AST transforms)"
if [ "${DRY_RUN}" = "true" ]; then
  log_step "[DRY-RUN] MANUAL assignment (no API call, nothing emitted): assign the implementation task to '${PRIMARY_ROLE}' in Paperclip"
  log_step "[DRY-RUN] Working directory: ${WORKTREE_DIR}"
else
  log_step "MANUAL step: assign the implementation task to '${PRIMARY_ROLE}' in Paperclip (no API call performed by this script)"
fi

# Phase 5: Local CI & QA Acceptance (MANUAL — this script performs no CI call)
log_stage "5/6 QA" "Automated testing and QA sign-off gate (manual step)"
log_step "Roles: e2e-browser-qa (Automation) + release-qa-officer (Acceptance Gate)"
if [ "${DRY_RUN}" = "true" ]; then
  log_step "[DRY-RUN] Local CI: run mutating jobs on the HOST via act (docker compose --profile core --profile ci); the local-ci-runner container is a read-only observer via the GET-only socket proxy"
  log_step "[DRY-RUN] Executed on host: bash scripts/smoke-test.sh --check-only"
  log_step "[DRY-RUN] Acceptance verification: release-qa-officer signed off"
else
  log_step "MANUAL step: run QA on the host and record release-qa-officer sign-off (no CI call performed by this script)"
fi

# Phase 6: Archive ONLY (no merge performed — see below)
log_stage "6/6 ARCHIVE-ONLY" "Worktree retained for explicit manual merge; no auto-merge"
log_step "Role: git-drift-coord (Department: Operations & Maintenance)"
log_step "Action: MANUAL merge required — auto-merge is disabled (fail-closed)"
if [ "${DRY_RUN}" = "true" ]; then
  log_step "[DRY-RUN] Would require: review ${WORKTREE_DIR}, then run git merge explicitly"
  log_step "[DRY-RUN] Only after merge: bash scripts/worktree-manager.sh archive ${TICKET_ID} ${BASE_BRANCH}"
  log_step "[DRY-RUN] Saved patch diff, status log, and commit manifest to .worktrees/archive/"
else
  # Execute mode success (Wave B P0-4): provisioning (phase 3) completed, so
  # exit 0. The retained worktree + required manual merge is NOT a failure —
  # only the merge itself stays manual (fail-closed: never auto-merged here).
  log_step "Worktree provisioned at ${WORKTREE_DIR}; review it, then run git merge explicitly"
  log_step "Only after merge: bash scripts/worktree-manager.sh archive \"${TICKET_ID}\" \"${BASE_BRANCH}\""
fi

log_stage "COMPLETE" "Provisioner-tracer finished for ticket ${TICKET_ID} (execute mode provisions the worktree; implementation + merge stay manual)"
