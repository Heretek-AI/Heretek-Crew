#!/usr/bin/env bash
#
# backup-db.sh — timestamped PostgreSQL backup for the Heretek-Crew stack.
#
# Usage:
#   ./scripts/backup-db.sh [--help]
#
# What it does:
#   1. Loads repo .env (if present) for POSTGRES_USER / POSTGRES_DB.
#   2. Fail-closed gate: requires `docker compose` and a healthy `postgres`
#      service (pg_isready inside the container). Refuses to write an empty
#      dump instead of silently succeeding.
#   3. Streams `pg_dump` out of the container through gzip into
#      backups/backup-YYYYMMDD-HHMMSS.sql.gz (never `latest`, never unversioned
#      overwrite — every backup is timestamped; a same-second rerun gets a
#      -$RANDOM suffix instead of overwriting, and a second collision aborts
#      fail-closed rather than clobbering).
#   4. Verifies the dump file is non-empty, then enforces retention: keeps the
#      newest $BACKUP_RETENTION_COUNT dumps, deletes older ones (NUL-delimited
#      mtime sort — safe against whitespace/newlines in filenames).
#
# Environment (all optional):
#   POSTGRES_USER ............ default: paperclip (matches docker-compose.yml)
#   POSTGRES_DB .............. default: paperclip
#   BACKUP_DIR ............... default: backups
#   BACKUP_RETENTION_COUNT ... default: 14 (0 disables pruning)
#
# No secrets are baked or echoed: credentials stay inside the container's
# environment; only the dump bytes cross the pipe.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

for arg in "$@"; do
  case "${arg}" in
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

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source ./.env
  set +a
fi

POSTGRES_USER="${POSTGRES_USER:-paperclip}"
POSTGRES_DB="${POSTGRES_DB:-paperclip}"
BACKUP_DIR="${BACKUP_DIR:-backups}"
BACKUP_RETENTION_COUNT="${BACKUP_RETENTION_COUNT:-14}"

command -v docker >/dev/null 2>&1 || { echo "error: docker is required" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "error: 'docker compose' plugin is required" >&2; exit 1; }

mkdir -p "${BACKUP_DIR}"

echo "[backup] gating on postgres health (pg_isready inside container)..."
if ! docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null; then
  echo "error: postgres is not healthy/ready; refusing to back up (fail-closed)" >&2
  echo "hint: start the stack with 'make up' and wait for the healthcheck" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
OUTFILE="${BACKUP_DIR}/backup-${STAMP}.sql.gz"
# Same-second rerun guard (P2-2): never silently overwrite. First collision
# gets a -$RANDOM suffix (still timestamped, still sortable); a second
# collision aborts fail-closed instead of clobbering an existing dump.
if [[ -e "${OUTFILE}" ]]; then
  OUTFILE="${BACKUP_DIR}/backup-${STAMP}-${RANDOM}.sql.gz"
fi
if [[ -e "${OUTFILE}" ]]; then
  echo "error: refusing to overwrite existing dump ${OUTFILE} (fail-closed)" >&2
  exit 1
fi
echo "[backup] dumping ${POSTGRES_USER}/${POSTGRES_DB} -> ${OUTFILE} ..."

docker compose exec -T postgres pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
  --no-owner --clean --if-exists \
  | gzip -c > "${OUTFILE}"

if [[ ! -s "${OUTFILE}" ]]; then
  echo "error: backup produced an empty file; removing it and aborting" >&2
  rm -f "${OUTFILE}"
  exit 1
fi
echo "[backup] wrote $(du -h "${OUTFILE}" | cut -f1) to ${OUTFILE}"

if [[ "${BACKUP_RETENTION_COUNT}" =~ ^[0-9]+$ ]] && [[ "${BACKUP_RETENTION_COUNT}" -gt 0 ]]; then
  # NUL-delimited mtime sort (P2-2): `ls -1t | tail` breaks on whitespace or
  # newlines in filenames. `find -printf '%T@ %p\0' | sort -z -n` yields
  # oldest-first, NUL-separated; the timestamp prefix contains no spaces, so
  # the first space always delimits it from the path.
  mapfile -d '' SORTED < <(find "${BACKUP_DIR}" -maxdepth 1 -name 'backup-*.sql.gz' -printf '%T@ %p\0' | sort -z -n)
  if [[ "${#SORTED[@]}" -gt "${BACKUP_RETENTION_COUNT}" ]]; then
    PRUNE_COUNT=$(("${#SORTED[@]}" - BACKUP_RETENTION_COUNT))
    echo "[backup] pruning ${PRUNE_COUNT} dump(s) beyond retention=${BACKUP_RETENTION_COUNT}..."
    for (( k = 0; k < PRUNE_COUNT; k++ )); do
      entry="${SORTED[k]}"
      rm -f -- "${entry#* }"
    done
  fi
else
  echo "[backup] retention disabled (BACKUP_RETENTION_COUNT=${BACKUP_RETENTION_COUNT}); keeping all dumps"
fi

echo "[backup] done: ${OUTFILE}"
