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
#            destroyed by this command). Evidence is staged in a temp dir and
#            renamed into place only after the worktree is removed; a failed
#            remove deletes the staged temp instead of littering a partial
#            archive. Same-second reruns get a -$RANDOM suffix (never clobber).
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
    # Wave B P2-4: never adopt a foreign/stale directory. A pre-existing
    # path is accepted ONLY when git reports it as a registered worktree on
    # THIS ticket's branch (porcelain check binds dir AND branch of the same
    # entry — either one elsewhere is not enough); anything else fails
    # closed, since dispatch-pipeline would otherwise write task_plan.md
    # into an unrelated directory.
    abs_target="${REPO_ROOT}/${target_dir}"
    if git worktree list --porcelain 2>/dev/null | awk -v dir="${abs_target}" -v want="refs/heads/${branch_name}" '
      /^worktree / { cur = substr($0, 10) }
      /^branch / { if (cur == dir && substr($0, 8) == want) found = 1 }
      END { exit !found }
    '; then
      echo "[worktree] Worktree already exists at ${target_dir} (verified registered on branch ${branch_name})"
      return 0
    fi
    echo "error: ${target_dir} exists but is not a registered worktree on branch ${branch_name} (fail-closed: refusing to adopt)" >&2
    exit 1
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
  # Wave E Stage 3 P1-10 same-second guard (mirrors backup-db.sh): a retry
  # within the same second must not reuse/clobber the prior archive dir.
  # First collision gets a -$RANDOM suffix; a second collision aborts
  # fail-closed instead of clobbering an existing archive.
  local archive_dir="${ARCHIVE_ROOT}/${ticket_id}-${timestamp}"
  if [[ -e "${archive_dir}" ]]; then
    archive_dir="${ARCHIVE_ROOT}/${ticket_id}-${timestamp}-${RANDOM}"
  fi
  if [[ -e "${archive_dir}" ]]; then
    echo "error: refusing to overwrite existing archive ${archive_dir} (fail-closed)" >&2
    exit 1
  fi
  # Wave E Stage 3 P1-10 temp-staging: evidence lands in a sibling temp dir
  # (name carries $RANDOM so concurrent archivers cannot share it) and is
  # renamed into place ONLY after `git worktree remove` succeeds. A failed
  # remove deletes the staged temp instead of littering a partial archive
  # that could be mistaken for a complete one.
  local archive_tmp="${ARCHIVE_ROOT}/.tmp-${ticket_id}-${timestamp}-${RANDOM}"
  if [[ -e "${archive_tmp}" ]]; then
    echo "error: refusing to overwrite existing staging dir ${archive_tmp} (fail-closed)" >&2
    exit 1
  fi

  if [ ! -d "${target_dir}" ]; then
    echo "error: worktree directory ${target_dir} does not exist" >&2
    exit 1
  fi

  # Resolve HEAD BEFORE creating the archive dir: a rev-parse failure must
  # refuse the archive without littering a partial archive dir (Wave B P2-4,
  # no trap needed — nothing is created before this point).
  local head_commit
  if ! head_commit="$(git -C "${target_dir}" rev-parse HEAD)"; then
    echo "error: cannot resolve HEAD of ${target_dir}; refusing to archive (fail-closed)" >&2
    exit 1
  fi

  mkdir -p "${ARCHIVE_ROOT}" "${archive_tmp}"
  echo "[worktree] Archiving ${target_dir} to ${archive_dir}..."

  # Stage the evidence files as one guarded unit (Wave B P2-4 / Alpha P3-5):
  # ANY failure removes the just-created staging dir instead of littering a
  # partial archive that could be mistaken for a complete one.
  if ! {
    git -C "${target_dir}" diff "${base_branch}" > "${archive_tmp}/patch.diff" &&
    git -C "${target_dir}" status --short > "${archive_tmp}/status.log" &&
    git -C "${target_dir}" log -n 20 --oneline > "${archive_tmp}/commits.log" &&
    cat > "${archive_tmp}/manifest.json" <<EOF
{
  "ticketId": "${ticket_id}",
  "branch": "${branch_name}",
  "baseBranch": "${base_branch}",
  "archivedAt": "${timestamp}",
  "headCommit": "${head_commit}"
}
EOF
  }; then
    rm -rf "${archive_tmp}"
    echo "error: archive evidence staging failed; removed partial ${archive_tmp} (fail-closed)" >&2
    exit 1
  fi

  echo "[worktree] Detaching and removing worktree ${target_dir}..."
  # Fail-closed removal: never --force here. A dirty or locked worktree
  # aborts instead of destroying uncommitted work — and the staged temp is
  # removed with it, so no orphan archive dir is left behind.
  if ! git worktree remove "${target_dir}"; then
    rm -rf "${archive_tmp}"
    echo "error: worktree remove failed; removed staged ${archive_tmp} instead of littering ${archive_dir} (fail-closed)" >&2
    exit 1
  fi

  mv "${archive_tmp}" "${archive_dir}"

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
