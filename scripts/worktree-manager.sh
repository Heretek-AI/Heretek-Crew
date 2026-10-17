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
#   archive  Save diff and commit log to .worktrees/archive/<ticket-id>-<timestamp>,
#            then remove a CLEAN worktree (never --force); the branch is RETAINED
#            for explicit post-merge delete (fail-closed: unmerged work is never
#            destroyed by this command)
#   list     List all active Git worktrees
#
set -euo pipefail

# Wave 4 P2-3: anchor to the repo root so worktree/archive paths resolve
# identically from any cwd (fail-closed against cwd-dependent path bugs).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

command -v git >/dev/null 2>&1 || { echo "error: git is required" >&2; exit 127; }

WORKTREE_ROOT="workspaces/tickets"
ARCHIVE_ROOT=".worktrees/archive"

# Fail-closed ticket-id allowlist: blocks path traversal (../evil),
# absolute paths (/tmp/wt-abs), and ref-hostile names before any
# worktree path or branch name is derived from the id.
require_ticket_id() {
  local ticket_id="$1"
  if [[ ! "${ticket_id}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$ ]]; then
    echo "error: invalid ticket-id '${ticket_id}' (allowlist: ^[A-Za-z0-9][A-Za-z0-9._-]{1,63}\$)" >&2
    exit 2
  fi
}

show_help() {
  sed -n '3,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//'
}

cmd_create() {
  local ticket_id="$1"
  require_ticket_id "${ticket_id}"
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
  require_ticket_id "${ticket_id}"
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
  require_ticket_id "${ticket_id}"
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

  # Save diff against base branch, git status, and commit history.
  # Fail-closed: failures here abort the archive (never masked) so a
  # partial archive is never mistaken for a complete one.
  git -C "${target_dir}" diff "${base_branch}" > "${archive_dir}/patch.diff"
  git -C "${target_dir}" status --short > "${archive_dir}/status.log"
  git -C "${target_dir}" log -n 20 --oneline > "${archive_dir}/commits.log"

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
  # Fail-closed removal: never --force here. A dirty or locked worktree
  # aborts instead of destroying uncommitted work.
  git worktree remove "${target_dir}"

  # The branch is deliberately RETAINED: only delete it explicitly after
  # the work is merged (git branch -d). Archive must never destroy the
  # only ref to unmerged commits.
  echo "note: retaining branch ${branch_name}; delete explicitly after merge (git branch -d)" >&2

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
