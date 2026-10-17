#!/usr/bin/env bash
#
# restore-db.sh — restore a PostgreSQL dump created by scripts/backup-db.sh.
#
# Usage:
#   FILE=backups/backup-YYYYMMDD-HHMMSS.sql.gz ./scripts/restore-db.sh [--yes]
#   ./scripts/restore-db.sh --file backups/backup-....sql.gz [--yes] [--help]
#
# What it does:
#   1. Requires FILE (fail-closed: refuses to guess which dump to restore).
#   2. Requires the file to exist and end in .sql.gz or .sql.
#   3. Asks for explicit typed confirmation unless --yes / RESTORE_YES=1
#      (restores are DESTRUCTIVE: the dump was taken with --clean, so existing
#      objects are dropped and recreated). Without a TTY and without --yes,
#      it refuses immediately instead of aborting mid-read.
#   4. Waits for postgres to become healthy (pg_isready, up to timeout).
#   5. Terminates remaining backends on the target database (the restore
#      needs an AccessExclusiveLock; idle sessions would block it).
#   6. Streams gunzip -> psql with ON_ERROR_STOP=1 (fail-closed: aborts the
#      restore on the first SQL error instead of partially applying it).
#   7. Verifies post-restore (pg_isready + asserted non-zero table count).
#
# Environment (all optional):
#   FILE ..................... path to the dump (or pass --file)
#   RESTORE_YES .............. set to 1 to skip the confirmation prompt
#   POSTGRES_USER ............ default: paperclip (matches docker-compose.yml)
#   POSTGRES_DB .............. default: paperclip
#   HEALTH_TIMEOUT_SEC ....... default: 120
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

FILE="${FILE:-}"
ASSUME_YES="${RESTORE_YES:-0}"
for arg in "$@"; do
  case "${arg}" in
    --file=*) FILE="${arg#--file=}" ;;
    --file) echo "error: --file requires '=path' form" >&2; exit 2 ;;
    --yes|-y) ASSUME_YES="1" ;;
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

if [[ -z "${FILE}" ]]; then
  echo "error: FILE= is required (fail-closed: will not guess which dump to restore)" >&2
  echo "usage: FILE=backups/backup-YYYYMMDD-HHMMSS.sql.gz ./scripts/restore-db.sh" >&2
  # shellcheck disable=SC2012
  echo "available dumps:" >&2
  ls -1t backups/backup-*.sql.gz 2>/dev/null >&2 || echo "  (none in backups/)" >&2
  exit 1
fi
if [[ ! -f "${FILE}" ]]; then
  echo "error: dump file not found: ${FILE}" >&2
  exit 1
fi
case "${FILE}" in
  *.sql.gz|*.sql) ;;
  *) echo "error: unsupported dump extension (want .sql.gz or .sql): ${FILE}" >&2; exit 1 ;;
esac

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source ./.env
  set +a
fi

POSTGRES_USER="${POSTGRES_USER:-paperclip}"
POSTGRES_DB="${POSTGRES_DB:-paperclip}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-120}"

command -v docker >/dev/null 2>&1 || { echo "error: docker is required" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "error: 'docker compose' plugin is required" >&2; exit 1; }
case "${FILE}" in
  *.gz) command -v gunzip >/dev/null 2>&1 || { echo "error: gunzip is required" >&2; exit 1; } ;;
esac

if [[ "${ASSUME_YES}" != "1" ]]; then
  if [[ ! -t 0 ]]; then
    echo "error: no TTY for confirmation (closed stdin cannot answer the typed prompt; re-run with --yes/RESTORE_YES=1)" >&2
    exit 1
  fi
  echo "WARNING: this will DROP and recreate database objects in ${POSTGRES_DB} from:"
  echo "  ${FILE}"
  echo "Type the database name ('${POSTGRES_DB}') to confirm, or Ctrl-C to abort."
  read -r CONFIRM
  if [[ "${CONFIRM}" != "${POSTGRES_DB}" ]]; then
    echo "aborted: confirmation did not match (fail-closed)" >&2
    exit 1
  fi
fi

echo "[restore] waiting for postgres health (timeout ${HEALTH_TIMEOUT_SEC}s)..."
deadline=$((SECONDS + HEALTH_TIMEOUT_SEC))
while true; do
  if docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; then
    break
  fi
  if [[ "${SECONDS}" -ge "${deadline}" ]]; then
    echo "error: postgres did not become healthy in ${HEALTH_TIMEOUT_SEC}s" >&2
    exit 1
  fi
  sleep 3
done

echo "[restore] restoring ${FILE} into ${POSTGRES_DB} (ON_ERROR_STOP=1)..."
echo "[restore] terminating remaining backend connections to ${POSTGRES_DB}..."
docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d postgres \
  -v ON_ERROR_STOP=1 -q \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${POSTGRES_DB}' AND pid <> pg_backend_pid();"
case "${FILE}" in
  *.gz) gunzip -c -- "${FILE}" ;;
  *) cat -- "${FILE}" ;;
esac | docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
  -v ON_ERROR_STOP=1 -q

echo "[restore] verifying (pg_isready + table count)..."
docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null
TABLES="$(docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d '[:space:]')"
echo "[restore] done: public schema holds ${TABLES} table(s)"
if [[ ! "${TABLES}" =~ ^[0-9]+$ ]] || [[ "${TABLES}" -eq 0 ]]; then
  echo "error: restore verification failed (expected a non-zero table count, got '${TABLES}')" >&2
  exit 1
fi
