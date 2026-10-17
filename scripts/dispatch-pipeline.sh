#!/usr/bin/env bash
#
# scripts/dispatch-pipeline.sh — Worktree Provisioner + Pipeline Tracer for Heretek-Crew.
#
# SCOPE (Wave 4 P2-2 header correction): despite the historical
# "Orchestrator" name, this script does NOT dispatch agent work to Paperclip
# (phases 1/2/4/5 only log what a human should assign; there are no
# Paperclip/harness API calls here). What it REALLY does:
#   - in --dry-run: trace all 6 phases and print the payloads (a planning aid);
#   - in execute mode: provision ONE isolated git worktree + task_plan.md
#     (phase 3), then stop fail-closed at phase 6 (no auto-merge).
# Call it a provisioner/tracer, not an end-to-end factory relay.
#
# Automates the end-to-end autonomous factory relay:
#   1. PRD: Product Director generates product requirements and user stories.
#   2. ARCH: System Architect generates ADR and interface contracts.
#   3. DECOMPOSE: TPM / Scrum Lead creates ticket, provisions isolated worktree.
#   4. DEV: Specialist engineer implements changes using opencode-harness.
#   5. QA: e2e-browser-qa & Release QA Officer verify via local CI and browser tests.
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
log_step "Roles: e2e-browser-qa (Automation) + release-qa-officer (Acceptance Gate)"
if [ "${DRY_RUN}" = "true" ]; then
  log_step "[DRY-RUN] Local CI Runner: docker compose --profile core --profile ci (act runner; core schedules the socket proxy) / scripts/smoke-test.sh"
  log_step "[DRY-RUN] Triggered local-ci-runner container on 'heretek' network"
  log_step "[DRY-RUN] Executed: bash scripts/smoke-test.sh --check-only"
  log_step "[DRY-RUN] Acceptance verification: release-qa-officer signed off"
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
  echo "error: auto-merge disabled (fail-closed): review ${WORKTREE_DIR} then run git merge explicitly" >&2
  echo "worktree retained at ${WORKTREE_DIR}; archive only after merge: bash scripts/worktree-manager.sh archive \"${TICKET_ID}\" \"${BASE_BRANCH}\"" >&2
  exit 1
fi

log_stage "COMPLETE" "Pipeline trace finished for ticket ${TICKET_ID} (execute mode stops fail-closed at Phase 6: manual merge still required)"
