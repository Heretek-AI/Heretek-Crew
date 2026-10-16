#!/usr/bin/env bash
#
# scripts/worktree-manager.sh — Git worktree isolation and archival engine for Paperclip agents.
#
# Usage:
#   ./scripts/worktree-manager.sh create <ticket-id> [base-branch]
#   ./scripts/worktree-manager.sh rebase <ticket-id> [base-branch]
#   ./scripts/worktree-manager.sh archive <ticket-id> [base-branch]
#   ./scripts/worktree-manager.sh list
#   ./scripts/worktree-manager.sh --help
#
# Commands:
#   create   Create an isolated worktree at workspaces/tickets/<ticket-id> on branch ticket-<ticket-id>
#   rebase   Rebase active ticket branch against base-branch (default: main)
#   archive  Save diff and commit log to .worktrees/archive/<ticket-id>-<timestamp>, remove worktree, delete branch
#   list     List all active Git worktrees
#
set -euo pipefail

WORKTREE_ROOT="workspaces/tickets"
ARCHIVE_ROOT=".worktrees/archive"

show_help() {
  sed -n '3,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//'
}

cmd_create() {
  local ticket_id="$1"
  local base_branch="${2:-main}"
  local target_dir="${WORKTREE_ROOT}/${ticket_id}"
  local branch_name="ticket-${ticket_id}"

  if [ -d "${target_dir}" ]; then
    echo "[worktree] Worktree already exists at ${target_dir}"
    return 0
  fi

  mkdir -p "${WORKTREE_ROOT}"
  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    echo "[worktree] Checking out existing branch ${branch_name} into ${target_dir}..."
    git worktree add "${target_dir}" "${branch_name}"
  else
    echo "[worktree] Creating new worktree at ${target_dir} branched from ${base_branch}..."
    git worktree add -b "${branch_name}" "${target_dir}" "${base_branch}"
  fi

  echo "[worktree] Active worktree ready: ${target_dir}"
}

cmd_rebase() {
  local ticket_id="$1"
  local base_branch="${2:-main}"
  local target_dir="${WORKTREE_ROOT}/${ticket_id}"

  if [ ! -d "${target_dir}" ]; then
    echo "error: worktree directory ${target_dir} does not exist" >&2
    exit 1
  fi

  echo "[worktree] Rebasing ${target_dir} on ${base_branch}..."
  git -C "${target_dir}" rebase "${base_branch}"
  echo "[worktree] Rebase successful."
}

cmd_archive() {
  local ticket_id="$1"
  local base_branch="${2:-main}"
  local target_dir="${WORKTREE_ROOT}/${ticket_id}"
  local branch_name="ticket-${ticket_id}"
  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local archive_dir="${ARCHIVE_ROOT}/${ticket_id}-${timestamp}"

  if [ ! -d "${target_dir}" ]; then
    echo "error: worktree directory ${target_dir} does not exist" >&2
    exit 1
  fi

  mkdir -p "${archive_dir}"
  echo "[worktree] Archiving ${target_dir} to ${archive_dir}..."

  # Save diff against base branch, git status, and commit history
  git -C "${target_dir}" diff "${base_branch}" > "${archive_dir}/patch.diff" || true
  git -C "${target_dir}" status --short > "${archive_dir}/status.log" || true
  git -C "${target_dir}" log -n 20 --oneline > "${archive_dir}/commits.log" || true

  # Write manifest
  cat <<EOF > "${archive_dir}/manifest.json"
{
  "ticketId": "${ticket_id}",
  "branch": "${branch_name}",
  "baseBranch": "${base_branch}",
  "archivedAt": "${timestamp}",
  "headCommit": "$(git -C "${target_dir}" rev-parse HEAD)"
}
EOF

  echo "[worktree] Detaching and removing worktree ${target_dir}..."
  git worktree remove --force "${target_dir}"

  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    git branch -D "${branch_name}" || true
  fi

  echo "[worktree] Successfully archived ${ticket_id} to ${archive_dir}"
}

cmd_list() {
  git worktree list
}

# Entrypoint routing
ACTION="${1:-}"
case "${ACTION}" in
  create)
    [ $# -ge 2 ] || { echo "error: ticket-id required (see --help)" >&2; exit 2; }
    cmd_create "$2" "${3:-main}"
    ;;
  rebase)
    [ $# -ge 2 ] || { echo "error: ticket-id required (see --help)" >&2; exit 2; }
    cmd_rebase "$2" "${3:-main}"
    ;;
  archive)
    [ $# -ge 2 ] || { echo "error: ticket-id required (see --help)" >&2; exit 2; }
    cmd_archive "$2" "${3:-main}"
    ;;
  list)
    cmd_list
    ;;
  --help|-h|help|"")
    show_help
    exit 0
    ;;
  *)
    echo "error: unknown action '${ACTION}' (see --help)" >&2
    exit 2
    ;;
esac
