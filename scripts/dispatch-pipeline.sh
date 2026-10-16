#!/usr/bin/env bash
#
# scripts/dispatch-pipeline.sh — Multi-Agent Relay Pipeline Orchestrator for Heretek-Crew.
#
# Automates the end-to-end autonomous factory relay:
#   1. PRD: Product Director generates product requirements and user stories.
#   2. ARCH: System Architect generates ADR and interface contracts.
#   3. DECOMPOSE: TPM / Scrum Lead creates ticket, provisions isolated worktree.
#   4. DEV: Specialist engineer implements changes using opencode-harness.
#   5. QA: Tester & Release QA Officer verify via local CI and browser tests.
#   6. MERGE: Git Drift Coordinator fast-forwards to main and archives worktree.
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

log_stage() {
  printf '\n======================================================================\n'
  printf ' [PIPELINE STAGE: %s] %s\n' "$1" "$2"
  printf '======================================================================\n'
}

log_step() {
  printf '  -> %s\n' "$*"
}

WORKTREE_DIR="workspaces/tickets/${TICKET_ID}"

# Phase 1: PRD Generation
log_stage "1/6 PRD" "Product Director generates feature specification"
log_step "Role: product-director (Department: Executive & Product Management)"
log_step "Input Prompt: ${FEATURE_PROMPT}"
if [ "${DRY_RUN}" = "true" ]; then
  log_step "[DRY-RUN] Emitted PRD task to Paperclip agent 'product-director'"
  log_step "[DRY-RUN] Output artifact expected: docs/prd/PRD-${TICKET_ID}.md"
fi

# Phase 2: Architecture & ADR
log_stage "2/6 ARCH" "System Architect defines technical architecture & contracts"
log_step "Role: system-architect (Department: Executive & Product Management)"
log_step "Input Spec: docs/prd/PRD-${TICKET_ID}.md"
if [ "${DRY_RUN}" = "true" ]; then
  log_step "[DRY-RUN] Emitted ADR task to Paperclip agent 'system-architect'"
  log_step "[DRY-RUN] Output artifact expected: docs/adr/ADR-${TICKET_ID}.md"
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
  bash scripts/worktree-manager.sh create "${TICKET_ID}" "${BASE_BRANCH}"
  mkdir -p "${WORKTREE_DIR}"
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

# Phase 4: Implementation
log_stage "4/6 DEV" "Specialist engineer implements feature in worktree"
log_step "Role: ${PRIMARY_ROLE} (Target Workspace: ${WORKTREE_DIR})"
log_step "Runtime: OpenCode v2 + opencode-harness (FNV-1a hash edits, AST transforms)"
if [ "${DRY_RUN}" = "true" ]; then
  log_step "[DRY-RUN] Emitted implementation task to Paperclip agent '${PRIMARY_ROLE}'"
  log_step "[DRY-RUN] Working directory: ${WORKTREE_DIR}"
fi

# Phase 5: Local CI & QA Acceptance
log_stage "5/6 QA" "Automated testing and QA sign-off gate"
log_step "Roles: tester (Automation) + release-qa-officer (Acceptance Gate)"
log_step "Local CI Runner: docker compose --profile ci (act runner) / scripts/smoke-test.sh"
if [ "${DRY_RUN}" = "true" ]; then
  log_step "[DRY-RUN] Triggered local-ci-runner container on 'heretek' network"
  log_step "[DRY-RUN] Executed: bash scripts/smoke-test.sh --check-only"
  log_step "[DRY-RUN] Acceptance verification: release-qa-officer signed off"
fi

# Phase 6: Merge & Non-Destructive Archiving
log_stage "6/6 RELEASE" "Fast-forward merge and worktree archival"
log_step "Role: git-drift-coord (Department: Operations & Maintenance)"
log_step "Action: Archive worktree to .worktrees/archive/${TICKET_ID}-<timestamp>/"
if [ "${DRY_RUN}" = "true" ]; then
  log_step "[DRY-RUN] Executing: git -C ${WORKTREE_DIR} rebase ${BASE_BRANCH}"
  log_step "[DRY-RUN] Executing: bash scripts/worktree-manager.sh archive ${TICKET_ID} ${BASE_BRANCH}"
  log_step "[DRY-RUN] Saved patch diff, status log, and commit manifest to .worktrees/archive/"
else
  bash scripts/worktree-manager.sh archive "${TICKET_ID}" "${BASE_BRANCH}"
fi

log_stage "COMPLETE" "Autonomous relay pipeline finished successfully for ticket ${TICKET_ID}"
