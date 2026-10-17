#!/usr/bin/env bash
#
# postgres-init-readonly-role.sh — provision the read-only `paperclip_reader`
# role consumed by dba-specialist's postgres MCP server (P0-2/P1-8).
#
# Runs inside the postgres container as an initdb hook (mounted at
# /docker-entrypoint-initdb.d/01-readonly-role.sh:ro by docker-compose.yml;
# executes once on first boot against a fresh pgdata volume, as POSTGRES_USER
# against POSTGRES_DB). Existing volumes do NOT re-run initdb hooks — for
# those, apply the SQL printed by --dry-run manually (see
# roles/dba-specialist/AGENTS.md §4 for the equivalent GRANT reference).
#
# The role carries SELECT-only grants plus
# `default_transaction_read_only = on`, so even a bypass of the MCP
# `query` tool's own READ ONLY transaction still cannot write. No
# INSERT/UPDATE/DELETE/DDL grant is ever issued here.
#
# Usage:
#   POSTGRES_USER=paperclip POSTGRES_DB=paperclip \
#     POSTGRES_READER_PASSWORD=<secret> ./scripts/postgres-init-readonly-role.sh [--dry-run] [--help]
#
#   --dry-run   Validate inputs and print the SQL without executing it
#               (used by scripts/smoke-test.sh §2; no live database needed).
#   --help, -h  Print this usage guide and exit.
#
# Fail-closed: exits 1 when any input is unset/empty or still carries a
# CHANGE_ME__ placeholder (compose :? guards + the seed gate enforce the
# same before this ever runs against a live database).
#
set -euo pipefail

DRY_RUN="false"
for arg in "$@"; do
  case "${arg}" in
    --dry-run) DRY_RUN="true" ;;
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

: "${POSTGRES_USER:?POSTGRES_USER must be set (database superuser/bootstrap owner)}"
: "${POSTGRES_DB:?POSTGRES_DB must be set (target database)}"
: "${POSTGRES_READER_PASSWORD:?POSTGRES_READER_PASSWORD must be set in .env (password for the paperclip_reader role)}"
case "${POSTGRES_READER_PASSWORD}" in
  CHANGE_ME__*)
    echo "error: POSTGRES_READER_PASSWORD still carries a CHANGE_ME__ placeholder — generate one with: openssl rand -base64 24" >&2
    exit 1
    ;;
esac

# Static SQL body: the secret travels via psql -v reader_pwd (quoted as a
# literal with :'reader_pwd'), never interpolated into this text, so
# --dry-run output is safe to log and diff.
read -r -d '' READONLY_SQL <<'EOSQL' || true
DO $readonly_role$
DECLARE
  pwd text := :'reader_pwd';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'paperclip_reader') THEN
    EXECUTE format('CREATE ROLE paperclip_reader WITH LOGIN PASSWORD %L', pwd);
  ELSE
    EXECUTE format('ALTER ROLE paperclip_reader WITH LOGIN PASSWORD %L', pwd);
  END IF;
END
$readonly_role$;
DO $readonly_grants$
BEGIN
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO paperclip_reader', current_database());
END
$readonly_grants$;
GRANT USAGE ON SCHEMA public TO paperclip_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO paperclip_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO paperclip_reader;
ALTER ROLE paperclip_reader WITH CONNECTION LIMIT 5;
ALTER ROLE paperclip_reader SET default_transaction_read_only = on;
EOSQL

if [ "${DRY_RUN}" = "true" ]; then
  printf '%s\n' "${READONLY_SQL}"
  exit 0
fi

command -v psql >/dev/null 2>&1 || { echo "error: psql is required" >&2; exit 1; }
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" \
  -v reader_pwd="${POSTGRES_READER_PASSWORD}" <<<"${READONLY_SQL}"
