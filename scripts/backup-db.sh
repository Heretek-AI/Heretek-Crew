#!/usr/bin/env bash
#
# backup-db.sh — timestamped PostgreSQL backup for the Heretek-Crew stack.
#
# Usage:
#   ./scripts/backup-db.sh [--plaintext-ok] [--help]
#
# What it does:
#   1. Loads repo .env (if present) for POSTGRES_USER / POSTGRES_DB /
#      BACKUP_DIR / BACKUP_RETENTION_COUNT / BACKUP_AGE_RECIPIENT /
#      BACKUP_PLAINTEXT_OK (P3-1: header synced with the sourcing block
#      below — every consumed key is named here, no silent inputs).
#   2. Fail-closed gate: requires `docker compose` and a healthy `postgres`
#      service (pg_isready inside the container). Refuses to write an empty
#      dump instead of silently succeeding.
#   3. Fail-closed encryption gate (P2-13): refuses plaintext dumps unless
#      BACKUP_AGE_RECIPIENT names an age public key (age1...) or the
#      operator passes explicit --plaintext-ok (in-env override:
#      BACKUP_PLAINTEXT_OK=1). An unset recipient without the explicit
#      opt-in aborts BEFORE any dump bytes are written.
#   4. Streams `pg_dump` out of the container through gzip into
#      backups/backup-YYYYMMDD-HHMMSS.sql.gz (never `latest`, never unversioned
#      overwrite — every backup is timestamped; a same-second rerun gets a
#      -$RANDOM suffix instead of overwriting, and a second collision aborts
#      fail-closed rather than clobbering).
#   5. Verifies the dump file is non-empty, then enforces retention: keeps the
#      newest $BACKUP_RETENTION_COUNT dumps, deletes older ones (NUL-delimited
#      mtime sort — safe against whitespace/newlines in filenames).
#
# Environment (all optional):
#   POSTGRES_USER ............ default: paperclip (matches docker-compose.yml)
#   POSTGRES_DB .............. default: paperclip
#   BACKUP_DIR ............... default: backups
#   BACKUP_RETENTION_COUNT ... default: 14 (0 disables pruning)
#   BACKUP_AGE_RECIPIENT ..... REQUIRED unless --plaintext-ok (P2-13
#      fail-closed): an age public key (age1...) — the gzip stream is
#      encrypted with `age -r` and the dump lands as
#      backup-*.sql.gz.age. If the variable is set but the `age` binary
#      is missing, the backup aborts instead of writing plaintext.
#      Restore with FILE=backups/<name>.sql.gz.age ./scripts/restore-db.sh
#      (needs BACKUP_AGE_IDENTITY pointing at the matching identity file).
#      gpg is NOT shelled out to (one tool, one format); age is the
#      documented at-rest mechanism (see P2-12).
#   BACKUP_PLAINTEXT_OK ...... set to 1 (or pass --plaintext-ok) to
#      explicitly allow an unencrypted dump (operator opt-in only).
#
# No secrets are baked or echoed: credentials stay inside the container's
# environment; only the dump bytes cross the pipe.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

for arg in "$@"; do
  case "${arg}" in
    # P2-13: explicit plaintext opt-in (operator acknowledges an
    # unencrypted dump; equivalent to BACKUP_PLAINTEXT_OK=1).
    --plaintext-ok) BACKUP_PLAINTEXT_OK_CLI="1" ;;
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
  # NOTE (P3-1): `source` executes .env as shell. Only POSTGRES_USER /
  # POSTGRES_DB / BACKUP_DIR / BACKUP_RETENTION_COUNT /
  # BACKUP_AGE_RECIPIENT / BACKUP_PLAINTEXT_OK are consumed below (see
  # header step 1); a restricted dotenv parser for just those keys would
  # shrink this surface (tracked — behavior-preserving minimal path keeps
  # `source` here). CLI --plaintext-ok can only ever OPT IN (OR logic in
  # the P2-13 gate) — it can never weaken a .env-provided recipient.
  source ./.env
  set +a
fi

POSTGRES_USER="${POSTGRES_USER:-paperclip}"
POSTGRES_DB="${POSTGRES_DB:-paperclip}"
BACKUP_DIR="${BACKUP_DIR:-backups}"
BACKUP_RETENTION_COUNT="${BACKUP_RETENTION_COUNT:-14}"
BACKUP_AGE_RECIPIENT="${BACKUP_AGE_RECIPIENT:-}"
# P2-13 fail-closed encryption gate: plaintext dumps require explicit
# operator opt-in (--plaintext-ok or BACKUP_PLAINTEXT_OK=1). An unset
# recipient without opt-in aborts BEFORE any dump bytes are written —
# backups never silently land unencrypted.
if [[ -z "${BACKUP_AGE_RECIPIENT}" && "${BACKUP_PLAINTEXT_OK_CLI:-}" != "1" && "${BACKUP_PLAINTEXT_OK:-0}" != "1" ]]; then
  echo "error: BACKUP_AGE_RECIPIENT is unset and --plaintext-ok was not passed (fail-closed: refusing plaintext dump)" >&2
  echo "hint: set BACKUP_AGE_RECIPIENT=age1... for encrypted backups, or pass --plaintext-ok to explicitly allow plaintext" >&2
  exit 1
fi

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
# Wave 4 P2-12: opt-in age encryption. Fail-closed: a set recipient without
# the `age` binary aborts BEFORE any dump bytes are written (never silently
# plaintext). Recipient shape-checked (age1...) so a pasted secret key or
# typo fails here, not inside age.
if [[ -n "${BACKUP_AGE_RECIPIENT}" ]]; then
  command -v age >/dev/null 2>&1 || { echo "error: BACKUP_AGE_RECIPIENT is set but 'age' is not installed; refusing plaintext fallback (fail-closed)" >&2; exit 1; }
  if [[ ! "${BACKUP_AGE_RECIPIENT}" =~ ^age1[0-9a-z]+$ ]]; then
    echo "error: BACKUP_AGE_RECIPIENT does not look like an age public key (want age1...)" >&2
    exit 1
  fi
  OUTFILE="${BACKUP_DIR}/backup-${STAMP}.sql.gz.age"
  ENCRYPT="true"
else
  OUTFILE="${BACKUP_DIR}/backup-${STAMP}.sql.gz"
  ENCRYPT="false"
fi
# Same-second rerun guard (P2-2, Wave B P1-10): never silently overwrite.
# First collision gets a -$RANDOM suffix (still timestamped, still sortable)
# AND keeps the .age suffix when encrypted — an age-encrypted dump with a
# plaintext .sql.gz name would be routed by restore-db.sh to gunzip and fail
# ("not in gzip format"), i.e. unrestorable by the documented command. A
# second collision aborts fail-closed instead of clobbering an existing dump.
if [[ -e "${OUTFILE}" ]]; then
  if [[ "${ENCRYPT}" == "true" ]]; then
    OUTFILE="${BACKUP_DIR}/backup-${STAMP}-${RANDOM}.sql.gz.age"
  else
    OUTFILE="${BACKUP_DIR}/backup-${STAMP}-${RANDOM}.sql.gz"
  fi
fi
if [[ -e "${OUTFILE}" ]]; then
  echo "error: refusing to overwrite existing dump ${OUTFILE} (fail-closed)" >&2
  exit 1
fi
echo "[backup] dumping ${POSTGRES_USER}/${POSTGRES_DB} -> ${OUTFILE} ..."

if [[ "${ENCRYPT}" == "true" ]]; then
  docker compose exec -T postgres pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    --no-owner --clean --if-exists \
    | gzip -c | age -r "${BACKUP_AGE_RECIPIENT}" > "${OUTFILE}"
else
  echo "[backup] PLAINTEXT dump explicitly opted in (--plaintext-ok): ${OUTFILE} is UNENCRYPTED at rest"
  docker compose exec -T postgres pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
    --no-owner --clean --if-exists \
    | gzip -c > "${OUTFILE}"
fi

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
  mapfile -d '' SORTED < <(find "${BACKUP_DIR}" -maxdepth 1 \( -name 'backup-*.sql.gz' -o -name 'backup-*.sql.gz.age' \) -printf '%T@ %p\0' | sort -z -n)
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
