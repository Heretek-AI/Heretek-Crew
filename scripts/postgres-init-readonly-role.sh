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
# Incident (evileye 2026-10-18): a psql invocation lacking the secret
# binding sent an unsubstituted :'reader_pwd' reference to the server
# (syntax error at ":") → initdb hook exited 3 → entrypoint skipped
# hooks forever, leaving paperclip_reader missing on the fresh volume.
#
# Secret channel: the password travels via the existing container env,
# read inside psql with `\getenv _pw POSTGRES_READER_PASSWORD` (env var
# NAME only in this template text — safe to log/diff), never via argv
# (-v leaks into the process table). Requires psql >= 16
# for \getenv (pinned image is postgres 17.11). --dry-run output
# contains the env var NAME only, never the secret value.
#
# Channel shape (verified live against postgres 17.11 — do NOT simplify):
# psql performs NO variable substitution inside dollar-quoted DO bodies,
# so the password cannot be referenced as :'var' there (that is exactly
# the evileye exit-3 class). Instead \getenv feeds a top-level SET into
# the session GUC app.reader_pwd, and the DO block reads it back with
# current_setting(). Two fail-loud guards, same message: a psql \if on
# :{?_pw} aborts when the env var never reached psql (e.g. hand-applying
# --dry-run SQL without exporting POSTGRES_READER_PASSWORD first), and a
# NULL/empty guard inside the DO block fires if the GUC is ever unset.
# Either produces RAISE 'reader_pwd empty (...)' + nonzero exit, never a
# server syntax error.
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

# Static SQL body: the secret is pulled inside psql via \getenv from the
# existing container env (NAME only in this text) and staged through a
# session GUC — quoted safely as a literal with :'_pw' at the top level
# only, never interpolated into this text and never passed on argv, so
# --dry-run output is safe to log and diff. The \if guard plus the
# NULL/empty guard below turn a dropped channel into a loud RAISE
# (nonzero exit) instead of a cryptic server syntax error.
read -r -d '' READONLY_SQL <<'EOSQL' || true
\getenv _pw POSTGRES_READER_PASSWORD
\if :{?_pw}
SELECT set_config('app.reader_pwd', :'_pw', false);
\else
DO $loud$ BEGIN RAISE EXCEPTION 'reader_pwd empty (substitution failed: POSTGRES_READER_PASSWORD not visible to psql)'; END $loud$;
\endif
DO $readonly_role$
DECLARE
  pwd text := current_setting('app.reader_pwd', true);
BEGIN
  IF pwd IS NULL OR pwd = '' THEN RAISE EXCEPTION 'reader_pwd empty (substitution failed: POSTGRES_READER_PASSWORD not visible to psql)'; END IF;
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
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<<"${READONLY_SQL}"
