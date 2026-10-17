#!/usr/bin/env bash
#
# restore-db.sh — restore a PostgreSQL dump created by scripts/backup-db.sh.
#
# Usage:
#   FILE=backups/backup-YYYYMMDD-HHMMSS.sql.gz ./scripts/restore-db.sh [--yes]
#   ./scripts/restore-db.sh --file backups/backup-....sql.gz [--yes] [--help]
#   FILE=backups/backup-YYYYMMDD-HHMMSS.sql.gz.age ./scripts/restore-db.sh [--yes]
#     (age-encrypted dumps from BACKUP_AGE_RECIPIENT backups; needs
#     BACKUP_AGE_IDENTITY=<identity-file> and the `age` binary)
#
# What it does:
#   1. Requires FILE (fail-closed: refuses to guess which dump to restore).
#   2. Requires the file to exist and end in .sql.gz, .sql, .sql.gz.age or .sql.age.
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
#   BACKUP_AGE_IDENTITY ...... path to the age identity file that decrypts
#      *.age dumps (required only for age-encrypted dumps; fail-closed if
#      absent/unreadable or if `age` is missing).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

FILE="${FILE:-}"
ASSUME_YES="${RESTORE_YES:-0}"
# Wave B P2-3: whether FILE/ASSUME_YES came from explicit CLI flags (vs the
# environment). Explicit CLI flags must survive the .env sourcing below —
# without the snapshot, `set -a; source .env` would silently overwrite an
# operator's --file/--yes with stale .env values.
CLI_FILE_GIVEN="false"
CLI_YES_GIVEN="false"
for arg in "$@"; do
  case "${arg}" in
    --file=*) FILE="${arg#--file=}"; CLI_FILE_GIVEN="true" ;;
    --file) echo "error: --file requires '=path' form" >&2; exit 2 ;;
    --yes|-y) ASSUME_YES="1"; CLI_YES_GIVEN="true" ;;
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
CLI_FILE="${FILE}"
CLI_YES="${ASSUME_YES}"

if [[ -z "${FILE}" ]]; then
  echo "error: FILE= is required (fail-closed: will not guess which dump to restore)" >&2
  echo "usage: FILE=backups/backup-YYYYMMDD-HHMMSS.sql.gz ./scripts/restore-db.sh" >&2
  # shellcheck disable=SC2012
  DUMP_LIST="$(ls -1t backups/backup-*.sql.gz backups/backup-*.sql backups/backup-*.sql.gz.age backups/backup-*.sql.age 2>/dev/null || true)"
  if [[ -n "${DUMP_LIST}" ]]; then
    echo "available dumps:" >&2
    printf '%s\n' "${DUMP_LIST}" >&2
  else
    echo "available dumps: (none in backups/)" >&2
  fi
  exit 1
fi
if [[ ! -f "${FILE}" ]]; then
  echo "error: dump file not found: ${FILE}" >&2
  exit 1
fi
case "${FILE}" in
  *.sql.gz|*.sql|*.sql.gz.age|*.sql.age) ;;
  *) echo "error: unsupported dump extension (want .sql.gz, .sql, .sql.gz.age or .sql.age): ${FILE}" >&2; exit 1 ;;
esac

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  # NOTE (Wave B P2-3): `source` executes .env as shell. Only POSTGRES_* /
  # HEALTH_TIMEOUT_SEC / BACKUP_AGE_IDENTITY are consumed below; a restricted
  # dotenv parser for just those keys would shrink this surface (tracked —
  # behavior-preserving minimal path keeps `source` here). Explicit CLI
  # --file / --yes are restored immediately after (they must win over .env).
  source ./.env
  set +a
fi
# Wave B P2-3: explicit CLI flags win over .env (fail-closed toward the
# operator's typed invocation, never toward a stale file).
if [[ "${CLI_FILE_GIVEN}" == "true" ]]; then
  FILE="${CLI_FILE}"
fi
if [[ "${CLI_YES_GIVEN}" == "true" ]]; then
  ASSUME_YES="${CLI_YES}"
fi

POSTGRES_USER="${POSTGRES_USER:-paperclip}"
POSTGRES_DB="${POSTGRES_DB:-paperclip}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-120}"

command -v docker >/dev/null 2>&1 || { echo "error: docker is required" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "error: 'docker compose' plugin is required" >&2; exit 1; }
case "${FILE}" in
  *.gz|*.gz.age) command -v gunzip >/dev/null 2>&1 || { echo "error: gunzip is required" >&2; exit 1; } ;;
esac
# Wave 4 P2-12: age-encrypted dumps need the identity up front (fail-closed
# before the destructive confirmation prompt, not after it).
BACKUP_AGE_IDENTITY="${BACKUP_AGE_IDENTITY:-}"
case "${FILE}" in
  *.age)
    command -v age >/dev/null 2>&1 || { echo "error: dump is age-encrypted but 'age' is not installed" >&2; exit 1; }
    if [[ -z "${BACKUP_AGE_IDENTITY}" ]]; then
      echo "error: dump is age-encrypted but BACKUP_AGE_IDENTITY is unset (path to the age identity file)" >&2
      exit 1
    fi
    if [[ ! -r "${BACKUP_AGE_IDENTITY}" ]]; then
      echo "error: BACKUP_AGE_IDENTITY is not readable: ${BACKUP_AGE_IDENTITY}" >&2
      exit 1
    fi
    ;;
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
# Wave B P2-3: the database name is BOUND via psql -v (:'dbname' quotes it
# as a literal server-side) — never interpolated into SQL single quotes,
# where a quote-containing name would break out.
docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d postgres \
  -v ON_ERROR_STOP=1 -q -v "dbname=${POSTGRES_DB}" \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname=:'dbname' AND pid <> pg_backend_pid();"
case "${FILE}" in
  *.sql.gz.age) age --decrypt -i "${BACKUP_AGE_IDENTITY}" -- "${FILE}" | gunzip -c - ;;
  *.sql.age) age --decrypt -i "${BACKUP_AGE_IDENTITY}" -- "${FILE}" ;;
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
