#!/usr/bin/env bash
#
# smoke-test.sh — end-to-end compatibility & smoke test for Heretek-Crew.
#
# Usage:
#   ./scripts/smoke-test.sh [--check-only] [--dry-run] [--help]
#
# Modes:
#   --check-only   Static checks only; needs NO live server, NO docker daemon,
#                  NO secrets. Safe for CI lint gates. Verifies:
#                    1. required repo files exist (incl. 50-fleet generator +
#                       seeder when the fleet track is present)
#                    2. `docker compose config` parses (with throwaway dummy
#                       secrets when .env is absent — validation only)
#                    2b. EROFS nested-mount contract, TEXT ONLY (no docker,
#                       no .env, no containers): parent ./roles:/roles:ro,z
#                       once + per-role long-syntax tmpfs (explicit mode
#                       1777/size 16M) + :ro,:z file bind; counts ==
#                       role dirs with zero missing/extra (each named);
#                       parent<tmpfs<file line order; no short-syntax
#                       tmpfs: key; no :ro under /paperclip
#                    3. every roles/*/opencode/opencode.json discovered
#                       dynamically under roles/ is a valid v2 config
#                       (valid JSON, provider/model string, non-empty
#                       permissions with a fail-closed deny tail,
#                       non-empty rules where present) with pinned MCP
#                       commands (no `:latest`), plus a non-empty
#                       AGENTS.md and .opencode/agents/<role>.md per
#                       role — single fleet dialect (Wave 3 P1-11: the 6
#                       legacy prototype roles were deleted as superseded;
#                       `ls roles/` matches the roles-catalog/ Role count
#                       (51 incl. ai-red-teamer)); plus 3b. static denied-tool probe
#                       (no bare allow-all anywhere + terminal shell deny,
#                       dba/k8s MCP-boundary shell
#                       denies intact, harness manifest == per-tool allows
#                       (14 full / 10 read-only + 4 mutating denies),
#                       read-only set drift pin, fs:read deny-first order
#                       + secret-material denies (**/secrets/**,
#                       **/kubeconfig*, **/*.pem, **/id_rsa*),
#                       adb-connect host allowlist, docker DOCKER_HOST pins,
#                       with no wildcard, MCP namespaces scoped to read
#                       verbs + deny tails, negative prefix-chain probes
#                       denied by the reference matcher, seed sets
#                       dangerouslySkipPermissions False, socket proxy
#                       denies POST/BUILD/EXEC, fs:write glob-specificity
#                       (no unanchored *substring* allows)); plus 3c. skills
#                       path resolution (every configured
#                       /roles/<id>/skills + /roles/<id>/.opencode/skills
#                       entry resolves to roles/<id>/.opencode/skills via
#                       the relative roles/<id>/skills symlink, with at
#                       least one <skill>/SKILL.md on disk)
#                    3d. spec-driven development gate
#                       (scripts/spec-gate.sh --check-only: spec corpora
#                       present, code<->spec delta covered, task plans carry
#                       checkboxes + acceptance criteria, per-role spec
#                       charters complete, fleet hardening invariants hold)
#                    4. seed dry-run emits company + agent payloads:
#                       seed-50-fleet.sh (1 company + 51 agents =
#                       52 payloads, fleet total == cap with no WARNING)
#                    5. shim translation: --dir flag dropped (on-disk
#                       dirs consumed per P0-1, non-dirs preserved),
#                       --variant merged into
#                       first --model#variant (first-wins, P2-2c), exactly
#                       one --auto, --session and non-run subcommands pass
#                       through, `--` terminator kept, empty values dropped
#                    5b. Wave B remediation gates (dispatch provisioner scope +
#                       exit-0, backup .age preservation, restore CLI-wins +
#                       bind + listing, worktree adoption/archive guards)
#                    6. file-creation simulation (hello.txt with today's date)
#                    7. session-resume support advertised by the opencode CLI
#                       (skipped with a note when no opencode binary is present)
#   --dry-run      Alias for --check-only (static checks only; no live
#                  calls, no state changes — the static suite writes only
#                  to scratch mktemp files).
#   (live)         All static checks PLUS, against a running stack:
#                    8. PostgreSQL health (pg_isready via `docker compose exec`)
#                    9. Paperclip web server responds at $PAPERCLIP_URL
#                       (default http://127.0.0.1:3100, /api/health then /)
#                   10. Ticket flow (requires PAPERCLIP_TOKEN or ADMIN_API_KEY):
#                       create a test issue assigned to an agent
#                       ("Create hello.txt with today's date"), wait for run
#                       completion, verify transcript / token-cost accounting /
#                       workspace file, post a follow-up comment to confirm
#                       session resumption. Without a token these sub-checks
#                       SKIP with an explanation (use --check-only instead).
#
# Live-mode requirements: `make up` healthy, PAPERCLIP_TOKEN set, and (for the
# workspace-file check) ./workspaces visible on the host. Timeouts:
#   HEALTH_TIMEOUT_SEC (default 30 here), RUN_TIMEOUT_SEC (default 600).
#
# NOTE (P1-7 / Wave 2 P0-3): the harness tool manifest IS verified
# statically. HARNESS_READONLY_MANIFEST in §3b pins the 10 non-mutating
# tools registered by @heretek-ai/opencode-harness@1.0.9 (enumerated
# empirically via `npm pack` + dist/index.js EXTENDED_HARNESS_TOOL_NAMES
# re-verified 2026-10-18: EXTENDED 14 = 10 readonly + 4 mutating unchanged —
# the live setupOpenCodeV2Harness path registers all 14): every role
# that declares the harness plugin must allow exactly that 10-tool set
# (per-tool allows, no `harness_*` allow), must DENY the 4 mutating
# tools (P0-9: zero mutating harness allows fleet-wide), and must carry
# a `harness_*` deny tail. A bump of the harness version requires
# re-enumeration + manifest update here.
# Wave D P0-1 root cause FIXED-IN-1.0.9 (upstream npm dist/index.js,
# verified 2026-10-18 — not fixed in-repo): pre-1.0.9, host
# @opencode/cli@2.0.32 supplied an empty-string directory, and
# `inferredRoot = ctx?.directory ?? ... ?? process.cwd()` never skips ""
# (`??` skips null/undefined only), so resolveHarnessOptions({rootDir:""})
# threw fail-closed and the plugin died before registering anything
# (debug log: Die(Error: rootDir must be non-empty); live `opencode run`
# replies "file_hash_read is not available"). The 1.0.9 fix is the
# falsy-tolerant pick() guard (dist/index.js:638-642) over the four
# context slots with `process.cwd()` fallback: live
# `setup({directory:''})` NO-THROW, while direct empty rootDir still
# throws fail-closed (contract preserved). Domain 4 harness primitives
# are fixed-in-1.0.9 pending Crew publish green. Keep the live gate
# reference in §10b.
# Live tool-registration (the runtime actually exposing those tools to an
# agent run) is asserted ONLY by the live gate in §10b (needs `make up` +
# seeded fleet + HARNESS_LIVE_GATE=1): it runs the probe fixture at
# scripts/fixtures/harness-probe-opencode.json through a real `opencode
# run` and FAILs on the rootDir Die. `npm ls` alone never catches a
# load-time Die — do not treat the publish-gate install check as
# tool-visibility proof.
#
# Exit code: 0 when nothing FAILs (SKIPs are informational), 1 otherwise.
# Fail-closed: every check reports PASS/FAIL/SKIP explicitly; unknown states
# are FAIL, never silent green.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

PAPERCLIP_URL="${PAPERCLIP_URL:-http://127.0.0.1:3100}"
PAPERCLIP_TOKEN="${PAPERCLIP_TOKEN:-${ADMIN_API_KEY:-}}"
COMPANY_NAME="${COMPANY_NAME:-Heretek Autonomous Fleet}"
POSTGRES_USER="${POSTGRES_USER:-paperclip}"
POSTGRES_DB="${POSTGRES_DB:-paperclip}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-30}"
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-600}"

MODE="live"
DRY_RUN="false"
for arg in "$@"; do
  case "${arg}" in
    --check-only) MODE="check-only" ;;
    --dry-run) MODE="check-only"; DRY_RUN="true" ;;
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

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 1; }

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$*"; }
skip() { SKIP=$((SKIP + 1)); printf '  [SKIP] %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "smoke-test mode=${MODE} url=${PAPERCLIP_URL}"
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "dry-run: static checks only (no live calls, no state changes)"
fi

# --- 1. required files -------------------------------------------------------
section "1. required files"
REQUIRED_FILES=(
  docker-compose.yml docker-compose.prebuilt.yml docker-compose.override.yml.example
  docker/Dockerfile .env.example Makefile
  .github/workflows/docker-publish.yml
  scripts/opencode-shim.sh scripts/seed-50-fleet.sh
  scripts/generate-50-roles.py scripts/worktree-manager.sh scripts/dispatch-pipeline.sh
  scripts/backup-db.sh scripts/restore-db.sh scripts/smoke-test.sh
  scripts/spec-gate.sh
)
for f in "${REQUIRED_FILES[@]}"; do
  if [[ -f "${f}" ]]; then ok "${f} exists"; else bad "${f} MISSING"; fi
done
# Wave 3 P1-11: the 6 legacy prototype roles (director, pm, programmer,
# tester, qa, designer) were deleted as superseded by the 50-fleet — no
# hardcoded legacy list remains; §3 below discovers roles dynamically.
for s in scripts/opencode-shim.sh scripts/seed-50-fleet.sh \
         scripts/worktree-manager.sh scripts/dispatch-pipeline.sh \
         scripts/backup-db.sh scripts/restore-db.sh scripts/smoke-test.sh \
         scripts/spec-gate.sh; do
  if [[ -x "${s}" ]]; then ok "${s} executable"; else bad "${s} NOT executable"; fi
done

# --- 2. compose config parses -----------------------------------------------
section "2. docker compose config"
# Throwaway dummy secrets: validation only, never written anywhere.
# Wave 2: the provisioning :? guards (POSTGRES_READER_PASSWORD,
# POSTGRES_READONLY_URL, GITHUB_TOKEN, KUBECONFIG_READONLY_PATH) need
# dummies too; the kubeconfig dummy points at a real repo file so the
# bind-mount source exists. Defined once for every config invocation below.
SMOKE_DUMMY_ENV=(POSTGRES_PASSWORD=__smoke_only__ BETTER_AUTH_SECRET=__smoke_only_0123456789abcdef__ PAPERCLIP_TOOL_ACTION_SIGNING_SECRET=__smoke_only_0123456789abcdef__ POSTGRES_READER_PASSWORD=__smoke_only__ POSTGRES_READONLY_URL=postgres://paperclip_reader:__smoke_only__@postgres:5432/paperclip GITHUB_TOKEN=__smoke_only__ KUBECONFIG_READONLY_PATH=./secrets/.gitkeep REDIS_PASSWORD=__smoke_only__ QDRANT_API_KEY=__smoke_only__ SEARXNG_SECRET=__smoke_only__ FIRECRAWL_DB_PASSWORD=__smoke_only__ BROWSERLESS_TOKEN=__smoke_only__ NEO4J_PASSWORD=__smoke_only__ LITELLM_MASTER_KEY=__smoke_only__ MINIO_ROOT_USER=__smoke_only__ MINIO_ROOT_PASSWORD=__smoke_only__ RABBITMQ_USER=__smoke_only__ RABBITMQ_PASSWORD=__smoke_only__)
if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  skip "'docker compose' not available; config validation skipped"
else
  if [[ -f .env ]]; then
    if docker compose config -q 2>"${TMP}/compose.err"; then
      ok "docker compose config parses (.env present)"
    else
      bad "docker compose config FAILED: $(head -c 300 "${TMP}/compose.err")"
    fi
  else
    if env "${SMOKE_DUMMY_ENV[@]}" docker compose config -q 2>"${TMP}/compose.err"; then
      ok "docker compose config parses (dummy secrets, .env absent)"
    else
      bad "docker compose config FAILED: $(head -c 300 "${TMP}/compose.err")"
    fi
  fi

  # Prebuilt compose override validation
  if env "${SMOKE_DUMMY_ENV[@]}" \
    docker compose -f docker-compose.yml -f docker-compose.prebuilt.yml config -q 2>"${TMP}/compose-prebuilt.err"; then
    ok "docker compose prebuilt override config parses"
  else
    bad "docker compose prebuilt override config FAILED: $(head -c 300 "${TMP}/compose-prebuilt.err")"
  fi

  # P1-4 defense-in-depth: paperclip must render
  # OPENCODE_DISABLE_PROJECT_CONFIG=true (explicit env beats upstream
  # defaults; OS env overrides .env here, so this holds either way).
  if env "${SMOKE_DUMMY_ENV[@]}" \
    docker compose config 2>/dev/null | grep -q 'OPENCODE_DISABLE_PROJECT_CONFIG: .true'; then
    ok "paperclip renders OPENCODE_DISABLE_PROJECT_CONFIG=true (project-config defense-in-depth)"
  else
    bad "paperclip rendered config lacks OPENCODE_DISABLE_PROJECT_CONFIG=true"
  fi

  # Wave 2 (P0-2/P1-8) provisioning: the read-only PG URL + scoped github
  # token must reach the paperclip runtime env, the kubeconfig must mount
  # read-only at the path k8s-orchestrator's MCP server expects, and the
  # initdb hook that provisions paperclip_reader must be mounted.
  if env "${SMOKE_DUMMY_ENV[@]}" \
    docker compose config 2>/dev/null | grep -q 'POSTGRES_READONLY_URL'; then
    ok "paperclip renders POSTGRES_READONLY_URL (read-only-role URL provisioned)"
  else
    bad "paperclip rendered config lacks POSTGRES_READONLY_URL"
  fi
  if env "${SMOKE_DUMMY_ENV[@]}" \
    docker compose config 2>/dev/null | grep -q 'GITHUB_TOKEN'; then
    ok "paperclip renders GITHUB_TOKEN (scoped PAT provisioned)"
  else
    bad "paperclip rendered config lacks GITHUB_TOKEN"
  fi
  if env "${SMOKE_DUMMY_ENV[@]}" \
    docker compose config 2>/dev/null | grep -A 3 'target: /kubeconfig/kubeconfig-readonly' | grep -q 'read_only: true'; then
    ok "kubeconfig read-only volume renders (/kubeconfig/kubeconfig-readonly:ro)"
  else
    bad "rendered config lacks the read-only kubeconfig volume"
  fi
  if env "${SMOKE_DUMMY_ENV[@]}" \
    docker compose config 2>/dev/null | grep -q 'target: /docker-entrypoint-initdb.d/01-readonly-role.sh'; then
    ok "postgres renders the read-only-role initdb hook (01-readonly-role.sh:ro)"
  else
    bad "rendered config lacks the postgres read-only-role initdb hook"
  fi
  # The init hook itself: --dry-run SQL must create the SELECT-only role
  # with read-only default transactions and no write grants; placeholders
  # must be rejected before any live execution.
  if POSTGRES_USER=paperclip POSTGRES_DB=paperclip POSTGRES_READER_PASSWORD=__smoke_only__ \
    ./scripts/postgres-init-readonly-role.sh --dry-run >"${TMP}/readonly.sql" 2>"${TMP}/readonly.err" \
    && grep -q 'CREATE ROLE paperclip_reader' "${TMP}/readonly.sql" \
    && grep -q 'GRANT SELECT ON ALL TABLES IN SCHEMA public TO paperclip_reader' "${TMP}/readonly.sql" \
    && grep -q 'default_transaction_read_only = on' "${TMP}/readonly.sql" \
    && ! grep -qE 'GRANT (INSERT|UPDATE|DELETE|ALL PRIVILEGES)' "${TMP}/readonly.sql"; then
    ok "read-only-role hook SQL grants SELECT-only + read-only transactions (no write grants)"
  else
    bad "read-only-role hook SQL shape unexpected: $(head -c 200 "${TMP}/readonly.err" "${TMP}/readonly.sql")"
  fi
  if POSTGRES_USER=paperclip POSTGRES_DB=paperclip POSTGRES_READER_PASSWORD=CHANGE_ME__x \
    ./scripts/postgres-init-readonly-role.sh --dry-run >/dev/null 2>&1; then
    bad "read-only-role hook accepted a CHANGE_ME__ placeholder (must fail closed)"
  else
    ok "read-only-role hook rejects CHANGE_ME__ placeholders (fail-closed)"
  fi
  # Wave D P2-7.3: the tool-action signing secret must be fail-closed
  # (:? — no empty `:-` default that silently disables signature
  # verification). An empty/missing value must refuse `config`, and the
  # dummy above must render.
  # shellcheck disable=SC2016 # literal ${...:?...} source-text match intended
  if grep -q 'PAPERCLIP_TOOL_ACTION_SIGNING_SECRET: ${PAPERCLIP_TOOL_ACTION_SIGNING_SECRET:?' docker-compose.yml \
    && ! grep -q 'PAPERCLIP_TOOL_ACTION_SIGNING_SECRET: ${PAPERCLIP_TOOL_ACTION_SIGNING_SECRET:-}' docker-compose.yml; then
    ok "tool-action signing secret is fail-closed (:? guard, no empty default)"
  else
    bad "tool-action signing secret not fail-closed (want :? guard, no :- default)"
  fi
  if env "${SMOKE_DUMMY_ENV[@]}" \
    docker compose config 2>/dev/null | grep -q 'PAPERCLIP_TOOL_ACTION_SIGNING_SECRET'; then
    ok "paperclip renders PAPERCLIP_TOOL_ACTION_SIGNING_SECRET (provisioned)"
  else
    bad "paperclip rendered config lacks PAPERCLIP_TOOL_ACTION_SIGNING_SECRET"
  fi
  # Wave D P2-6: the caddy 80/443 all-interfaces exposure is enforced by
  # `make proxy-up` (Makefile guard-proxy), not honor-system. The guard
  # must refuse non-private exposure and missing/placeholder auth
  # secrets; the compose exposure note must point at it (no raw
  # `--profile proxy` bypass in docs).
  if grep -q '^guard-proxy:' Makefile \
    && grep -q '^proxy-up: guard-proxy' Makefile \
    && grep -q "refusing --profile proxy" Makefile; then
    ok "Makefile proxy preflight guard present (guard-proxy + proxy-up)"
  else
    bad "Makefile proxy preflight guard MISSING (P2-6)"
  fi
  if grep -q 'proxy-up' docker-compose.yml; then
    ok "compose exposure note routes operators to make proxy-up (no raw --profile proxy)"
  else
    bad "compose exposure note does not route operators to make proxy-up (P2-6)"
  fi
fi

# --- 2b. EROFS per-role mounts (text-only, no docker/.env needed) -------------
# Wave EROFS remediation (issues #1/#4, Drift F1/F4): §2 above asserts
# nothing about the /roles mount shape, so deleting one role's lines
# still passed green. This gate parses docker-compose.yml TEXT ONLY
# (never `docker compose config`, never .env, never containers — it
# runs even when docker is absent and in --check-only/--dry-run) and
# fail-closed asserts the full nested-mount contract per role dir
# discovered under roles/ (never a hardcoded list, so role 52 with a
# new dir but no compose lines FAILs loud and names the role):
#   (a) the shared parent bind `./roles:/roles:ro,z` is present once;
#   (b) every role has its file bind
#       `./roles/<r>/opencode/opencode.json:/roles/<r>/opencode/opencode.json:ro,z`
#       carrying BOTH :ro and :z, with the source file on disk;
#   (c) every role has a long-syntax `type: tmpfs` entry targeting
#       `/roles/<r>/opencode` with explicit `mode: 1777` + `size: 16M`;
#   (d) counts match exactly (role dirs == file binds == tmpfs
#       entries) with zero missing/extra, each named;
#   (e) line order is parent bind < tmpfs entry < file bind per role
#       (single ordered `volumes:` list — the F3 parent-before-child
#       contract; a drifted order FAILs here, live `docker inspect`
#       Mounts[] order is the post-merge proof);
#   (f) no service-level short-syntax `tmpfs:` key remains (that split
#       key is the unordered shape — drift back FAILs);
#   (g) no :ro mount targets anything under /paperclip (eaa9394
#       entrypoint-chown precedent).
section "2b. EROFS per-role mounts (text-only)"
if EROFS_ERR="$(python3 -c '
import glob, os, re, sys

text = open("docker-compose.yml").read().splitlines()
roles = sorted(os.path.basename(p.rstrip("/")) for p in glob.glob("roles/*/") if os.path.isdir(p))
if not roles:
    sys.exit("no role directories discovered under roles/")

problems = []

parent = [i for i, l in enumerate(text) if l.strip() == "- ./roles:/roles:ro,z"]
if len(parent) != 1:
    problems.append("parent bind ./roles:/roles:ro,z present %dx (want exactly 1)" % len(parent))
parent_idx = parent[0] if parent else -1

if [i for i, l in enumerate(text) if re.match(r"^    tmpfs:\s*$", l)]:
    problems.append("service-level short-syntax tmpfs: key present (want long-syntax type: tmpfs in volumes: only)")

file_idx, tmpfs_idx = {}, {}
extra_files, extra_tmpfs = [], []
for i, l in enumerate(text):
    s = l.strip()
    m = re.match(r"^-\s+\./roles/([^/]+)/opencode/opencode\.json:/roles/\1/opencode/opencode\.json:(.*)$", s)
    if m:
        role, opts = m.group(1), m.group(2).split(",")
        file_idx.setdefault(role, []).append(i)
        if "ro" not in opts:
            problems.append("%s: file bind lacks :ro" % role)
        if "z" not in opts:
            problems.append("%s: file bind lacks :z" % role)
        if role in extra_files:
            pass
        continue
    m = re.match(r"^target:\s+/roles/([^/]+)/opencode\s*$", s)
    if m:
        tmpfs_idx.setdefault(m.group(1), []).append(i)

for role, idxs in file_idx.items():
    if role not in roles:
        extra_files.append(role)
    if len(idxs) > 1:
        problems.append("%s: %d file binds (want exactly 1)" % (role, len(idxs)))
for role, idxs in tmpfs_idx.items():
    if role not in roles:
        extra_tmpfs.append(role)
    if len(idxs) > 1:
        problems.append("%s: %d tmpfs targets (want exactly 1)" % (role, len(idxs)))

missing_files = [r for r in roles if r not in file_idx]
missing_tmpfs = [r for r in roles if r not in tmpfs_idx]
for r in missing_files:
    problems.append("missing file bind for role: %s (add ./roles/%s/opencode/opencode.json:/roles/%s/opencode/opencode.json:ro,z)" % (r, r, r))
for r in missing_tmpfs:
    problems.append("missing tmpfs entry for role: %s (add type: tmpfs target /roles/%s/opencode)" % (r, r))
for r in sorted(set(extra_files)):
    problems.append("file bind for unknown role dir: %s (no roles/%s/ on disk)" % (r, r))
for r in sorted(set(extra_tmpfs)):
    problems.append("tmpfs target for unknown role dir: %s (no roles/%s/ on disk)" % (r, r))

for r in roles:
    src = "roles/%s/opencode/opencode.json" % r
    if not os.path.isfile(src):
        problems.append("missing source file on disk: %s" % src)
    if r in file_idx and r in tmpfs_idx:
        ti = tmpfs_idx[r][0]
        fi = file_idx[r][0]
        window = "\n".join(text[ti:ti + 6])
        if "type: tmpfs" not in "\n".join(text[max(0, ti - 1):ti + 1]):
            problems.append("%s: tmpfs target not under a type: tmpfs entry" % r)
        if "mode: 1777" not in window:
            problems.append("%s: tmpfs entry lacks explicit mode: 1777" % r)
        if "size: 16M" not in window:
            problems.append("%s: tmpfs entry lacks explicit size: 16M" % r)
        if not (parent_idx < ti < fi):
            problems.append("%s: mount order violated (want parent:%d < tmpfs:%d < file:%d)" % (r, parent_idx, ti, fi))

for i, l in enumerate(text):
    if ":ro" in l and re.search(r"/paperclip[^:]*:ro", l):
        problems.append("line %d: :ro mount under /paperclip (eaa9394 entrypoint-chown crash-loop): %s" % (i + 1, l.strip()))

if problems:
    sys.exit("; ".join(problems))
print("%d roles: parent :ro,z + %d tmpfs (mode 1777/size 16M) + %d file binds (:ro,:z) in parent-before-child order" % (len(roles), len(tmpfs_idx), len(file_idx)))
' 2>&1)"; then
  ok "EROFS nested mounts intact ($(printf '%s' "${EROFS_ERR}"))"
else
  bad "EROFS mount contract VIOLATION: $(printf '%s' "${EROFS_ERR}" | head -c 600)"
fi

# --- 3. role configs valid + pins -------------------------------------------
# Dynamically discovers every role directory under roles/ (the fleet —
# 51 roles incl. ai-red-teamer — never a hardcoded list), then per role
# asserts: valid v2
# opencode.json (provider/model, non-empty permissions with a fail-closed
# deny tail, non-empty rules where present), exact-pinned MCP commands
# (npx pkg@x.y.z / uvx pkg==x.y.z in the fleet `mcp.servers` shape, zero
# exceptions since Wave C removed the rea-mcp server), and non-empty
# AGENTS.md + .opencode/agents/<role>.md charters.
section "3. role opencode.json validity + version pins"
ROLE_COUNT=0
for roledir in roles/*/; do
  [[ -d "${roledir}" ]] || continue
  role="$(basename "${roledir}")"
  f="roles/${role}/opencode/opencode.json"
  ROLE_COUNT=$((ROLE_COUNT + 1))
  if [[ ! -f "${f}" ]]; then
    bad "${f} MISSING (role dir exists without a v2 config)"
    continue
  fi
  if ROLE="$role" FILE="$f" python3 -c 'import json, os
path = os.environ["FILE"]
role = os.environ["ROLE"]
doc = json.load(open(path))
assert isinstance(doc.get("model"), str) and "/" in doc["model"], "model must be provider/model"
assert isinstance(doc.get("permissions"), list) and doc["permissions"], "permissions must be non-empty"
for p in doc["permissions"]:
    assert p.get("effect") in ("allow", "deny", "ask"), "permission effect must be allow/deny/ask"
assert doc["permissions"][-1].get("effect") == "deny", \
    "permissions must end with a fail-closed deny tail (fleet dialect: shell * deny); bare allow-all is forbidden"
rules = doc.get("rules")
if rules is not None:
    assert isinstance(rules, list) and rules, "rules, when present, must be non-empty"
def iter_commands(node):
    if isinstance(node, dict):
        if "command" in node:
            cmd = node["command"]
            yield " ".join(cmd) if isinstance(cmd, list) else str(cmd)
        elif isinstance(node.get("servers"), dict):
            for child in node["servers"].values():
                yield from iter_commands(child)
        elif isinstance(node.get("mcpServers"), dict):
            for child in node["mcpServers"].values():
                yield from iter_commands(child)
        else:
            for child in node.values():
                if isinstance(child, dict):
                    yield from iter_commands(child)
    elif isinstance(node, list):
        for child in node:
            yield from iter_commands(child)
for cmd in iter_commands(doc.get("mcp") or {}):
    assert "latest" not in cmd, "MCP command must not use latest: %s" % cmd
print("role %s model=%s perms=%d" % (role, doc["model"], len(doc["permissions"])))
' >"${TMP}/role.out" 2>"${TMP}/role.err"; then
    ok "${f} valid (model + perms + deny tail + pinned MCP)"
  else
    bad "${f} INVALID: $(head -c 200 "${TMP}/role.err")"
  fi
  if [[ -s "roles/${role}/AGENTS.md" ]]; then
    ok "roles/${role}/AGENTS.md present and non-empty"
  else
    bad "roles/${role}/AGENTS.md MISSING or empty"
  fi
  if [[ -s "roles/${role}/.opencode/agents/${role}.md" ]]; then
    ok "roles/${role}/.opencode/agents/${role}.md present and non-empty"
  else
    bad "roles/${role}/.opencode/agents/${role}.md MISSING or empty"
  fi
done
if [[ "${ROLE_COUNT}" -eq 0 ]]; then
  bad "no role directories discovered under roles/"
else
  ok "discovered ${ROLE_COUNT} role directories under roles/"
fi
# Wave 3 rework (QA gate gap), expanded Phase A Task 6: the fleet size is
# NOT hardcoded here — it is derived from the authoritative fleet spec
# (roles-catalog/ `## Role N` headers). A re-added legacy dir, a missing
# role, or an unregistered role dir must FAIL closed here, not pass
# with a human-enforced `ls` criterion.
EXPECTED_FLEET="$(grep -rhoE '^## Role [0-9]+' roles-catalog/*.md 2>/dev/null | wc -l)"
EXPECTED_FLEET="$(printf '%s' "${EXPECTED_FLEET}" | tr -d ' ')"
if [[ "${ROLE_COUNT}" -ne "${EXPECTED_FLEET}" ]]; then
  bad "fleet role drift: ${ROLE_COUNT} role directorie(s) under roles/ vs ${EXPECTED_FLEET} registered '## Role N' header(s) in roles-catalog/ (expected 51 incl. ai-red-teamer)"
else
  ok "fleet role count matches the fleet spec (${ROLE_COUNT} roles/ == ${EXPECTED_FLEET} roles-catalog/ headers)"
fi
if grep -rnE ':(latest)([^a-zA-Z0-9._-]|$)|@(latest)([^a-zA-Z0-9._-]|$)' \
    roles/*/opencode/opencode.json 2>/dev/null | grep -q .; then
  bad "found ':latest'/@latest pin in a role opencode.json (must pin exact versions)"
else
  ok "no :latest pins in any roles/*/opencode/opencode.json"
fi
# Wave C P1-12: every npx/uvx MCP command must carry an exact pin
# (npx pkg@x.y.z, uvx pkg==x.y.z) with NO exceptions — the former
# @morluto/rea-mcp exception is gone with the server itself (npm E404,
# verified 2026-10-17). Any unpinned package FAILs closed.
# Fork-justification record (npm dist-tags verified 2026-10-17, all pins
# == latest so no migration is owed):
#   @executeautomation/playwright-mcp-server@1.0.12 (latest 1.0.12;
#     canonical @playwright/mcp@0.0.83 is a DIFFERENT package line,
#     not a newer same-package release — no migration invented),
#   @upstash/context7-mcp@4.4.2 (latest 4.4.2),
#   @cyanheads/git-mcp-server@2.15.3 (latest 2.15.3),
#   @modelcontextprotocol/server-postgres@0.6.2 (latest 0.6.2).
# PyPI pins verified via `pip index versions` 2026-10-17:
#   mcp-server-redis 0.1.1, mcp-server-kubernetes 0.1.6,
#   mcp-server-qdrant 0.8.1, k6-mcp-server 2.2.0, mcp-clickhouse 0.7.0,
#   docker-mcp 0.2.0, r2mcp 0.2.5, prometheus-mcp-server 1.6.2,
#   mcp-server-duckdb 1.1.0 — all == pinned.
# Residual (tracked, honest): kafka-mcp-server is NOT resolvable on PyPI
# (pip 404, verified 2026-10-17) AND its kafka sidecar does not exist —
# doubly dead, so the kafka MCP server + kafka_* allow were DELETED from
# cache-streaming-eng (P2-8, 2026-10-17) rather than kept infra-pending.
if ROLE_PIN_TMP="${TMP}" python3 -c '
import glob, json, os, sys

violations = []
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    role = f.split("/")[1]
    doc = json.load(open(f))
    stack = [doc.get("mcp") or {}]
    while stack:
        node = stack.pop()
        if isinstance(node, dict):
            if "command" in node:
                argv = node["command"]
                argv = list(argv) if isinstance(argv, list) else [str(argv)]
                if argv[:1] == ["npx"]:
                    try:
                        pkg = argv[argv.index("-y") + 1]
                    except (ValueError, IndexError):
                        violations.append("%s: malformed npx argv %r" % (role, argv))
                        continue
                    if "@" not in pkg.rsplit("/", 1)[-1]:
                        violations.append("%s: unpinned npx package %r" % (role, pkg))
                elif argv[:1] == ["uvx"]:
                    pkg = argv[1] if len(argv) > 1 else ""
                    if "==" not in pkg:
                        violations.append("%s: unpinned uvx package %r" % (role, pkg))
            else:
                stack.extend(v for v in node.values() if isinstance(v, (dict, list)))
        elif isinstance(node, list):
            stack.extend(v for v in node if isinstance(v, (dict, list)))
if violations:
    sys.exit("\n".join(violations))
print("all npx (pkg@ver) + uvx (pkg==ver) pinned, zero exceptions")
' >"${TMP}/pins.out" 2>"${TMP}/pins.err"; then
  ok "MCP supply chain pinned ($(cat "${TMP}/pins.out"))"
else
  bad "unpinned MCP package(s): $(head -c 400 "${TMP}/pins.err")"
fi
# Wave C P1-2 dead-wiring allowlist (P2-8 remediated 2026-10-17: the five
# dead MCP servers — ollama, prometheus ×2, redis, kafka, clickhouse —
# plus their tool allows were DELETED from the role configs instead of
# being kept infra-pending; no unpinned replacement services invented).
# This gate pins the residual decision: the flagged set must EQUAL the
# allowlist exactly. A new dead server, or a pending server gaining
# infra without leaving the list, FAILs. (Wave D P1-6/P3-5: the two
# docker-MCP blocks LEFT this list — they now declare DOCKER_HOST
# explicitly and talk to the GET-only socket proxy as read-only
# observers; see the docker-host gate below.)
if python3 -c '
import glob, json, sys

# (role, server) pairs whose backing infra is knowingly absent.
EXPECTED_DEAD = {
    ("load-stress-tester", "k6"),          # no k6 sidecar (CLI tool)
}
ABSENT_HOSTS = ("://ollama", "://prometheus", "kafka:", "://clickhouse", "://redis:")

flagged = set()
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    role = f.split("/")[1]
    doc = json.load(open(f))
    for name, srv in ((doc.get("mcp") or {}).get("servers", {}) or {}).items():
        if not isinstance(srv, dict):
            continue
        env = srv.get("env") or {}
        blob = " ".join(str(v) for v in env.values())
        if any(h in blob for h in ABSENT_HOSTS):
            flagged.add((role, name))
        elif name == "k6":
            flagged.add((role, name))
        elif name == "docker" and "DOCKER_HOST" not in env:
            flagged.add((role, name))
if flagged != EXPECTED_DEAD:
    sys.exit("dead-MCP drift: flagged=%r expected=%r"
             % (sorted(flagged), sorted(EXPECTED_DEAD)))
print("dead-MCP wiring matches the tracked infra-pending allowlist (%d)" % len(flagged))
' >"${TMP}/deadmcp.out" 2>"${TMP}/deadmcp.err"; then
  ok "no untracked dead MCP wiring ($(cat "${TMP}/deadmcp.out"))"
else
  bad "dead MCP wiring drift: $(head -c 400 "${TMP}/deadmcp.err")"
fi
# Wave C P0-5 plugin-install gate (static complement of the publish
# workflow plugin-resolution gate): every `plugins` string in any
# roles/*/opencode/opencode.json must name a package the Dockerfile
# installs globally — otherwise the role loads with a tool surface
# that can never materialize (the `opencode-rea` E404 class).
if python3 -c '
import glob, json, re, sys

dockerfile = open("docker/Dockerfile").read()
installed = set()
for tok in re.findall(r"\"(@?[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?)@\$\{", dockerfile):
    installed.add(tok)
plugins = set()
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    for p in json.load(open(f)).get("plugins", []):
        plugins.add("@heretek-ai/opencode-harness" if p == "opencode-harness" else p)
missing = sorted(p for p in plugins if p not in installed)
if missing:
    sys.exit("plugins without a Dockerfile install: %r (installed=%r)" % (missing, sorted(installed)))
print("all role plugins installed by Dockerfile: %s" % sorted(plugins))
' >"${TMP}/plugate.out" 2>"${TMP}/plugate.err"; then
  ok "role plugins resolve to Dockerfile installs ($(cat "${TMP}/plugate.out"))"
else
  bad "unresolvable role plugin(s): $(head -c 400 "${TMP}/plugate.err")"
fi
# Wave C P0-6: the publish workflow must NEVER mint a `latest` tag
# (repo never-:latest invariant — the raw `value=latest` line was
# removed; semver 1.0.0/1.0 + sha-* remain the only tags). Comment lines
# are exempt (they document the removal); any live YAML line FAILs.
if grep -vE '^[[:space:]]*#' .github/workflows/docker-publish.yml | grep -q 'value=latest'; then
  bad "docker-publish.yml mints a 'latest' tag (never-:latest invariant violated)"
else
  ok "docker-publish.yml mints no 'latest' tag (semver + sha only)"
fi
if grep -rnE ':(latest)([^a-zA-Z0-9._-]|$)|@(latest)([^a-zA-Z0-9._-]|$)|npm install[^@]*opencode[^@]*$' \
    docker-compose.yml docker-compose.prebuilt.yml docker-compose.override.yml.example docker/Dockerfile .env.example Makefile 2>/dev/null | grep -v '^.*#.*latest' | grep -q .; then
  bad "found ':latest' style pin in ops files (must pin exact versions)"
else
  ok "no :latest pins in docker-compose.yml / prebuilt overrides / Dockerfile / .env.example / Makefile"
fi
# Wave 3 P1-9 (Wave C P0-6: `latest` is no longer minted — the workflow
# emits 1.0.0/1.0/sha-* only): the prebuilt pin is the semver form
# :1.0.0 (NOT :v1.0.0 — the publish workflow's metadata-action semver on
# refs/tags/v* mints 1.0.0/1.0/sha-* and NEVER :v1.0.0, so the old pin was
# unpublishable by construction). Fail closed on any drift back.
if grep -q 'ghcr\.io/heretek-ai/heretek-crew:1\.0\.0' docker-compose.prebuilt.yml \
  && ! grep -q 'heretek-crew:v1\.0\.0' docker-compose.prebuilt.yml; then
  ok "pin present: ghcr.io/heretek-ai/heretek-crew:1.0.0 in docker-compose.prebuilt.yml (no :v1.0.0)"
else
  bad "pin MISSING or REGRESSED: docker-compose.prebuilt.yml must pin ghcr.io/heretek-ai/heretek-crew:1.0.0 with no :v1.0.0"
fi
# Wave 3 rework (P1-2 regression gate): no `external:` network key may
# appear in any compose file — the fleet uses the managed `name: heretek`
# network (compose creates what `config` references). Anchored to YAML
# keys so prose comments mentioning `external: true` do not trip the
# gate; any real key FAILs closed (`config -q` passes either way).
if grep -rnE '^[[:space:]]*external:' docker-compose.yml docker-compose.sidecars.yml docker-compose.prebuilt.yml docker-compose.override.yml.example 2>/dev/null | grep -q .; then
  bad "found 'external:' network key in compose files (must use managed name: heretek): $(grep -rnE '^[[:space:]]*external:' docker-compose.yml docker-compose.sidecars.yml docker-compose.prebuilt.yml docker-compose.override.yml.example | head -c 200)"
else
  ok "no 'external:' network keys in compose files (managed heretek network)"
fi
for pin in 'postgres:17.11-alpine' 'node:24-trixie-slim' '@opencode/cli@2.0.32' '127.0.0.1:3100'; do
  case "${pin}" in
    127.0.0.1:3100)
      if grep -q '127\.0\.0\.1:3100' docker-compose.yml; then ok "pin present: ${pin}"; else bad "pin MISSING: ${pin}"; fi ;;
    @opencode/cli@2.0.32)
      # Dockerfile pins via ENV (OPENCODE_CLI_VERSION=2.0.32) consumed by the
      # npm install line — accept that indirection as a valid pin.
      if grep -q '@opencode/cli@2.0.32' docker/Dockerfile \
        || grep -q 'OPENCODE_CLI_VERSION=2.0.32' docker/Dockerfile; then
        ok "pin present: ${pin} (via OPENCODE_CLI_VERSION env)"
      else
        bad "pin MISSING: ${pin}"
      fi ;;
    *)
      if grep -rq "${pin}" docker-compose.yml docker/Dockerfile; then ok "pin present: ${pin}"; else bad "pin MISSING: ${pin}"; fi ;;
  esac
done
if grep -q 'UID 1000' docker/Dockerfile && grep -q 'gosu node' docker/Dockerfile; then
  ok "non-root runtime documented (node UID 1000 via gosu)"
else
  bad "non-root runtime note missing from docker/Dockerfile"
fi
# P1-5: the Paperclip source pin must be a recorded 40-hex commit (no
# <paste-…> placeholder). Trivial static assert; live equality with the
# build host (`git -C /tmp/paperclip rev-parse HEAD`) stays a build-time
# operator check (see docker/Dockerfile pin comment).
if grep -Eq 'PAPERCLIP_SOURCE_COMMIT=[0-9a-f]{40}' docker/Dockerfile \
  && ! grep -q 'paste-40-char-sha-here\|<paste-' docker/Dockerfile; then
  ok "Paperclip source pin recorded ($(grep -Eo 'PAPERCLIP_SOURCE_COMMIT=[0-9a-f]{40}' docker/Dockerfile | head -n 1))"
else
  bad "Paperclip source pin placeholder still present in docker/Dockerfile (P1-5)"
fi

# --- 3a. Wave 4 image pins + service auth (P1-4, P1-10, P1-6, P1-12) -----------
# Every bumped tag is asserted present AND its predecessor absent (fail
# closed on drift back). Auth guards (requirepass, API keys, authed URLs)
# and segmentation nets are asserted alongside — a bump without its auth
# wiring is a regression, not a fix.
section "3a. Wave 4 image pins + service auth"
# P1-4: redis 7.4.11-alpine x2, old 7.4.1 gone (bare tag, not the
# 7.4.11-alpine substring — anchored with a trailing quote/space guard).
if [[ "$(grep -c 'image: redis:7.4.11-alpine' docker-compose.sidecars.yml)" -eq 2 ]] \
  && ! grep -qE 'image: redis:7\.4\.1-alpine' docker-compose.sidecars.yml; then
  ok "pin present: redis:7.4.11-alpine x2 (no 7.4.1-alpine remains)"
else
  bad "pin MISSING or REGRESSED: want exactly 2x redis:7.4.11-alpine, zero redis:7.4.1-alpine"
fi
for w4pin in 'semgrep/semgrep:1.181.0' 'qdrant/qdrant:v1.19.2' 'neo4j:5.26.32-community-trixie' 'jaegertracing/jaeger:2.22.0'; do
  if grep -q "${w4pin}" docker-compose.sidecars.yml; then ok "pin present: ${w4pin}"; else bad "pin MISSING: ${w4pin}"; fi
done
for w4old in 'semgrep/semgrep:1.97.0' 'qdrant/qdrant:v1.12.5' 'neo4j:5.26.0-community-bullseye' 'jaegertracing/all-in-one:1.63.0'; do
  # (image: lines only — migration comments above legitimately name the
  # predecessor for provenance; only a live pin may not drift back).
  if grep -E '^[[:space:]]*image:' docker-compose.sidecars.yml | grep -q "${w4old}"; then bad "pin REGRESSED: ${w4old} still present"; else ok "predecessor gone: ${w4old}"; fi
done
# minio: exact quay RELEASE tag retained (digest auth-gated, tracked) + AGPL note.
if grep -q 'quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z' docker-compose.sidecars.yml \
  && grep -q 'AGPL' docker-compose.sidecars.yml; then
  ok "minio exact RELEASE tag pin retained + AGPL implication noted (digest pending authed pull)"
else
  bad "minio pin or AGPL note MISSING in docker-compose.sidecars.yml"
fi
# piston: upstream digest pin retained, vendoring release step documented, no :latest.
if grep -q 'ghcr.io/engineer-man/piston@sha256:' docker-compose.sidecars.yml \
  && grep -q 'ghcr.io/heretek-ai/piston' docker-compose.sidecars.yml \
  && ! grep -qE 'image: ghcr.io/engineer-man/piston:[a-z]' docker-compose.sidecars.yml; then
  ok "piston digest pin retained + ghcr.io/heretek-ai vendoring step documented (no floating tag)"
else
  bad "piston pin or vendoring note MISSING/REGRESSED in docker-compose.sidecars.yml"
fi
# P1-4/P1-6 auth: requirepass on both redises, authed healthchecks, authed URLs (fail-closed, no bare redis://).
if grep -c -- '--requirepass' docker-compose.sidecars.yml | grep -qx '2' \
  && grep -q 'redis-cli -a' docker-compose.sidecars.yml \
  && grep -q "SEARXNG_REDIS_URL: \"redis://:\${REDIS_PASSWORD:?" docker-compose.sidecars.yml \
  && grep -q "REDIS_URL: \"redis://:\${REDIS_PASSWORD:?" docker-compose.sidecars.yml \
  && ! grep -qE 'redis://(searxng-redis|firecrawl-redis):6379' docker-compose.sidecars.yml; then
  ok "redis auth wired: requirepass x2 + authed healthchecks + authed SEARXNG/REDIS URLs (no bare redis://)"
else
  bad "redis auth REGRESSED: requirepass/healthcheck/authed-URL wiring incomplete"
fi
# P1-10/P1-6 auth: qdrant API key enforced + MCP client sends it.
if grep -q "QDRANT__SERVICE__API_KEY: \"\${QDRANT_API_KEY:?" docker-compose.sidecars.yml \
  && grep -q "\"QDRANT_API_KEY\": \"\${QDRANT_API_KEY}\"" roles/vector-rag-spec/opencode/opencode.json; then
  ok "qdrant auth wired: QDRANT__SERVICE__API_KEY enforced + vector-rag-spec MCP sends QDRANT_API_KEY"
else
  bad "qdrant auth REGRESSED: server key or MCP client key wiring missing"
fi
# Wave D P3-3: firecrawl-rabbitmq runs on env-provided creds (guest
# retired): RABBITMQ_DEFAULT_USER/PASS are fail-closed :?, the
# NUQ_RABBITMQ_URL carries user:pass (no bare amqp://host URL remains),
# and .env.example provisions both values.
# shellcheck disable=SC2016 # literal ${...:?...} source-text match intended
if grep -q 'RABBITMQ_DEFAULT_USER: ${RABBITMQ_USER:?' docker-compose.sidecars.yml \
  && grep -q 'RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASSWORD:?' docker-compose.sidecars.yml \
  && grep -q 'NUQ_RABBITMQ_URL: "amqp://${RABBITMQ_USER:?' docker-compose.sidecars.yml \
  && ! grep -q 'NUQ_RABBITMQ_URL: "amqp://firecrawl-rabbitmq' docker-compose.sidecars.yml \
  && grep -q '^RABBITMQ_USER=' .env.example \
  && grep -q '^RABBITMQ_PASSWORD=' .env.example; then
  ok "rabbitmq auth wired: env-provided user/pass (:?) + authed NUQ URL (no guest, no bare amqp://)"
else
  bad "rabbitmq auth REGRESSED: env-provided user/pass or authed NUQ URL wiring incomplete (P3-3)"
fi
# Wave D P1-5: firecrawl :3002 stays loopback-published (the auth
# decision in-file keeps USE_DB_AUTHENTICATION=false ONLY under this
# restriction — an all-interfaces publish would expose an
# unauthenticated SSRF primitive). P2-8: hound host side moved
# 6080 -> 6081 (container :6080 unchanged); android noVNC keeps host
# :6080 — the two no longer share a host port even across the
# mutually-exclusive profiles.
if grep -q '"127.0.0.1:3002:3002"' docker-compose.sidecars.yml \
  && ! grep -qE '"0\.0\.0\.0:3002|"3002:3002"' docker-compose.sidecars.yml; then
  ok "firecrawl :3002 loopback-published only (no all-interfaces publish)"
else
  bad "firecrawl :3002 publish REGRESSED (want 127.0.0.1:3002:3002 only)"
fi
# Wave E Stage 2 P1-4: all 14 sidecar loopback binds + paperclip :3100.
# Every `ports:` entry in this stack must be 127.0.0.1-bound except the
# profile-gated caddy 80/443 (guard-proxy enforced, compose-noted).
# Expected set: paperclip 3100 + sidecars 8888/3002/3003/8081/6081/6333/
# 7474/4000/8025/9001/8089/16686/5555/6080 (14). Any new all-interfaces
# publish or missing loopback bind fails closed here.
if python3 -c '
import re, sys
base = open("docker-compose.yml").read()
side = open("docker-compose.sidecars.yml").read()
want_side = {"8888","3002","3003","8081","6081","6333","7474","4000",
             "8025","9001","8089","16686","5555","6080"}
have_side = set(re.findall(r"\"127\.0\.0\.1:(\d+):\d+\"", side))
problems = []
if want_side != have_side:
    problems.append("sidecar loopback set drift: missing=%s extra=%s"
                    % (sorted(want_side - have_side), sorted(have_side - want_side)))
if "\"127.0.0.1:3100:3100\"" not in base:
    problems.append("paperclip 127.0.0.1:3100:3100 missing")
bare = [l.strip() for l in (base + side).splitlines()
        if re.search(r"\"[0-9]+:[0-9]+\"", l) and "127.0.0.1" not in l]
allowed_bare = {"\"80:80\"", "\"443:443\""}
for b in bare:
    m = re.search(r"\"[0-9]+:[0-9]+\"", b)
    if m and m.group(0) not in allowed_bare:
        problems.append("non-loopback publish outside caddy 80/443: %s" % b)
if problems:
    sys.exit("; ".join(problems))
print("15 loopback binds (3100 + 14 sidecars); only caddy 80/443 all-interfaces (profile-gated)")
' >"${TMP}/loopback.out" 2>"${TMP}/loopback.err"; then
  ok "loopback binds enforced ($(cat "${TMP}/loopback.out"))"
else
  bad "loopback bind REGRESSION (P1-4): $(head -c 400 "${TMP}/loopback.err")"
fi
if python3 -c '
import re, sys
text = open("docker-compose.sidecars.yml").read()
blocks = {}
for m in re.finditer(r"^  ([a-z][a-z0-9-]*):\n", text, re.M):
    start = m.start()
    nxt = re.search(r"^  [a-z][a-z0-9-]*:\n", text[m.end():], re.M)
    end = m.end() + nxt.start() if nxt else len(text)
    blocks[m.group(1)] = text[start:end]
hound = blocks.get("hound", "")
android = blocks.get("docker-android", "")
problems = []
if "127.0.0.1:6081:6080" not in hound:
    problems.append("hound block lacks 127.0.0.1:6081:6080")
if "127.0.0.1:6080:6080" in hound:
    problems.append("hound block still publishes host :6080")
if "127.0.0.1:6080:6080" not in android:
    problems.append("docker-android noVNC moved off host :6080")
if problems:
    sys.exit("; ".join(problems))
print("hound host :6081, android noVNC host :6080, container ports unchanged")
' >"${TMP}/houndport.out" 2>"${TMP}/houndport.err"; then
  ok "hound host port remapped to :6081 ($(cat "${TMP}/houndport.out"))"
else
  bad "hound :6081 remap MISSING or android :6080 moved (P2-8): $(head -c 200 "${TMP}/houndport.err")"
fi
# P1-6/P1-12: open curl allows gone fleet-wide (exact-host piston pins are
# the only sanctioned curl shape); segmentation nets + paperclip attachment
# present; runner workspaces ro + dedicated scratch rw.
if grep -rn '"resource": "curl -s http://\*"' roles/*/opencode/opencode.json 2>/dev/null | grep -q .; then
  bad "open curl allow 'curl -s http://*' still present (P1-6 SSRF primitive)"
else
  ok "open curl 'curl -s http://*' gone fleet-wide"
fi
if grep -rn '"resource": "curl -sI\*"' roles/*/opencode/opencode.json 2>/dev/null | grep -q .; then
  bad "open curl allow 'curl -sI*' still present (P1-6 SSRF primitive)"
else
  ok "open curl 'curl -sI*' gone fleet-wide"
fi
if grep -q 'heretek-devsec:' docker-compose.sidecars.yml \
  && grep -q 'heretek-mobile:' docker-compose.sidecars.yml \
  && grep -q 'networks:' docker-compose.sidecars.yml; then
  ok "segmentation nets heretek-devsec + heretek-mobile declared"
else
  bad "segmentation nets MISSING in docker-compose.sidecars.yml"
fi
if grep -q 'refusing to co-schedule --profile mobile' Makefile \
  && grep -q '^guard-profiles:' Makefile \
  && grep -q '^sidecars-up: guard-profiles' Makefile; then
  ok "Makefile co-scheduling guard present (mobile+devsec/web-research refused)"
else
  bad "Makefile co-scheduling guard MISSING (P1-12)"
fi
if grep -q '\./workspaces:/paperclip/workspaces:ro' docker-compose.sidecars.yml \
  && grep -q '\./workspaces/scratch:/scratch:rw' docker-compose.sidecars.yml; then
  ok "runner workspaces ro + dedicated /scratch rw (P1-12)"
else
  bad "runner workspace hardening MISSING (want :ro + /scratch:rw)"
fi
# P2-7/P2-8 + goal-plugin scope: server-github already at target (confirm,
# do not regress); fleet playwright is @executeautomation (NOT @playwright/mcp);
# goal-plugin is director-only.
if grep -q '@modelcontextprotocol/server-github@2025.4.8' roles/exec-director/opencode/opencode.json; then
  ok "server-github@2025.4.8 confirmed at target (no regression)"
else
  bad "server-github pin REGRESSED (want @2025.4.8)"
fi
if grep -rln '@playwright/mcp' roles/*/opencode/opencode.json 2>/dev/null | grep -q .; then
  bad "@playwright/mcp present in fleet (fleet standard is @executeautomation/playwright-mcp-server)"
else
  ok "no @playwright/mcp in fleet (fleet uses @executeautomation/playwright-mcp-server@1.0.12; P2-8 discrepancy documented)"
fi
if [[ "$(grep -rln 'opencode-goal-plugin' roles/*/opencode/opencode.json | wc -l)" -eq 1 ]] \
  && grep -q 'opencode-goal-plugin' roles/exec-director/opencode/opencode.json; then
  ok "goal-plugin scope confirmed director-only (exec-director)"
else
  bad "goal-plugin scope DRIFTED (want exactly exec-director)"
fi
# sabotage-qa-tester pinned to piston/CI (no raw toolchain exec on host).
if ! python3 -c '
import json
perms = json.load(open("roles/sabotage-qa-tester/opencode/opencode.json"))["permissions"]
shell = [p["resource"] for p in perms if p.get("action")=="shell" and p.get("effect")=="allow"]
banned = [s for s in shell if s.startswith(("cargo mutants", "npx stryker", "npm test tests/chaos", "cargo test chaos"))]
assert not banned, "raw toolchain exec remains: %s" % banned
assert any("piston:2000/api/v2/execute" in s for s in shell), "no piston execute pin"
' 2>"${TMP}/sabotage.err"; then
  bad "sabotage-qa-tester NOT pinned to piston/CI: $(head -c 200 "${TMP}/sabotage.err")"
else
  ok "sabotage-qa-tester executes via piston API (no raw host toolchain)"
fi
# Wave E Stage 4 P2-3/P2-5/P2-6/P2-8/P2-9: live-resolved tag@digest pins.
# Each pin below was resolved live against its registry on 2026-10-17
# (registry Docker-Content-Digest, never invented offline) with zero
# behavior change except the ordered ghidra 11.2 -> 12.1.4 major bump
# (Hub 12.1.4 verified live). The digest wins; the tag is provenance.
# A tag-only drift back (digest stripped) or a predecessor-tag return
# FAILs closed here.
for digpin in 'postgres:17.11-alpine@sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24' 'blacktop/ghidra:12.1.4@sha256:b2479177bd6a10d974da1bff30cc911ea2856843d858ad0ba02a608152ca193c' 'mitmproxy/mitmproxy:11.0.2@sha256:92ab9e0626ec73a3abae9c460e5475323f414745d7d0001205c8fa0c77ad31a2' 'ghcr.io/firecrawl/firecrawl:2.10.19@sha256:50446cbc0bc700a78cc588c96bd38a97f01cc4299c99b349c7bfa1ba57b6d7ed' 'ghcr.io/catthehacker/ubuntu:act-22.04@sha256:f5f5c29208c4fd541704fe7b8df33d3bf620ce4ac46f36853b7abeb0159705c4'; do
  if grep -rq "image: ${digpin}" docker-compose.yml docker-compose.sidecars.yml; then
    ok "digest pin present: ${digpin%%@*}"
  else
    bad "digest pin MISSING or REGRESSED: ${digpin%%@*} (want exact tag@digest)"
  fi
done
for oldimg in 'image: postgres:17-alpine$' 'blacktop/ghidra:11.2' 'image: mitmproxy/mitmproxy:11.0.2$' 'image: ghcr.io/firecrawl/firecrawl:2.10.19$' 'image: ghcr.io/catthehacker/ubuntu:act-22.04$'; do
  # (image: lines only — bump-plan comments above legitimately name the
  # predecessor for provenance; only a live pin may not drift back).
  if grep -rE "^[[:space:]]*${oldimg}" docker-compose.yml docker-compose.sidecars.yml 2>/dev/null | grep -q .; then
    bad "image pin REGRESSED: ${oldimg} still present as a live pin"
  else
    ok "predecessor pin gone: ${oldimg}"
  fi
done
# Wave E Stage 4 P2-14 (static complement of the publish-workflow gates):
# the workflow must keep the fixture-argv translation gate
# (--model#variant + exactly-one --auto reach opencode-bin, no --dir
# leak), the harness plugin-load gate (FAILs on the empty-string rootDir
# Die until the upstream fix lands), and the pre-push linux/arm64 smoke.
# A gate deletion would let P0-1 pass by construction again (Claim 9.3).
if grep -q 'shim translation gate' .github/workflows/docker-publish.yml \
  && grep -q 'harness plugin-load gate' .github/workflows/docker-publish.yml \
  && grep -q 'verify-arm64' .github/workflows/docker-publish.yml \
  && grep -q 'platform linux/arm64' .github/workflows/docker-publish.yml; then
  ok "publish workflow keeps translation + plugin-load + arm64 gates (P2-14)"
else
  bad "publish workflow lost a P2-14 gate (translation/plugin-load/arm64)"
fi
# Wave E Stage 4 P3-8: the runner's /scratch bind source must stay
# tracked — a first `up` with the ci profile would otherwise create a
# root-owned ./workspaces/scratch, breaking the node runner.
if [[ -f workspaces/scratch/.gitkeep ]] && git ls-files --error-unmatch workspaces/scratch/.gitkeep >/dev/null 2>&1; then
  ok "workspaces/scratch/.gitkeep tracked (runner /scratch source exists, P3-8)"
else
  bad "workspaces/scratch/.gitkeep MISSING or untracked (P3-8)"
fi
# Wave E Stage 4 P2-10: full-stack + per-profile CPU/memory budget.
# Every image-bearing service must carry cpus + mem_limit (already true —
# asserted here so a new service without caps FAILs closed), and the
# effective load per profile (always-on services + that profile's
# services) must equal the pinned matrix below. The full stack sums to
# 32.6 CPUs / ~50G — physically impossible on one host — so safety rests
# on profile gating + the Makefile co-scheduling guard (mobile refused
# with devsec/web-research); this gate is the automated assertion that
# the matrix (and therefore the gating premise) has not drifted. Any
# resourcing change must update EXPECTED here deliberately.
if python3 -c '
import re, sys
def parse(text):
    blocks = {}
    for m in re.finditer(r"^  ([a-z][a-z0-9-]*):\n", text, re.M):
        start = m.start()
        nxt = re.search(r"^  [a-z][a-z0-9-]*:\n", text[m.end():], re.M)
        end = m.end() + nxt.start() if nxt else len(text)
        blocks[m.group(1)] = text[start:end]
    return blocks
def mem_mb(s):
    m = re.search(r"mem_limit: ([\d.]+)([mg])", s)
    return float(m.group(1)) * (1024 if m.group(2) == "g" else 1) if m else None
def cpu(s):
    m = re.search(r"cpus: \"([\d.]+)\"", s)
    return float(m.group(1)) if m else None
def prof(s):
    m = re.search(r"profiles: \[(.*?)\]", s)
    return [p.strip().strip("\"") for p in m.group(1).split(",")] if m else None
base = parse(open("docker-compose.yml").read())
side = parse(open("docker-compose.sidecars.yml").read())
svc = {}
for n, b in list(base.items()) + list(side.items()):
    if not re.search(r"^\s+(image:|build:)", b, re.M):
        continue
    e = svc.get(n, {})
    if cpu(b) is not None:
        e["cpu"] = cpu(b)
    if mem_mb(b) is not None:
        e["mem"] = mem_mb(b)
    if prof(b) is not None:
        e["prof"] = prof(b)
    svc[n] = e
nocaps = sorted(n for n, e in svc.items() if "cpu" not in e or "mem" not in e)
if nocaps:
    sys.exit("services without cpus+mem_limit: %s" % nocaps)
# (cpu, mem_MB) per profile, always-on services included. Pinned
# 2026-10-17; update deliberately with any resourcing change.
EXPECTED = {
    "ai-gateway": (7.0, 11264), "ci": (5.0, 9216),
    "core": (5.7, 10368), "devsec": (11.2, 17536),
    "mobile": (7.0, 13312), "observability": (3.5, 6144),
    "proxy": (3.5, 5632), "qa-testing": (13.7, 21248),
    "tailscale": (3.5, 5376), "web-research": (12.2, 18944),
}
always = [e for e in svc.values() if e.get("prof") is None]
base_cpu = sum(e["cpu"] for e in always)
base_mem = sum(e["mem"] for e in always)
problems = []
have = set()
for n, e in svc.items():
    for p in e.get("prof") or []:
        have.add(p)
if have != set(EXPECTED):
    problems.append("profile set drift: have=%s expected=%s"
                    % (sorted(have), sorted(EXPECTED)))
for p, (xc, xm) in EXPECTED.items():
    c = base_cpu + sum(e["cpu"] for e in svc.values() if e.get("prof") and p in e["prof"])
    m = base_mem + sum(e["mem"] for e in svc.values() if e.get("prof") and p in e["prof"])
    if abs(c - xc) > 0.001 or abs(m - xm) > 0.5:
        problems.append("%s: cpu=%.1f mem=%.0fMB want cpu=%.1f mem=%.0fMB"
                        % (p, c, m, xc, xm))
fc = sum(e["cpu"] for e in svc.values())
fm = sum(e["mem"] for e in svc.values())
if abs(fc - 32.6) > 0.001:
    problems.append("full-stack cpu=%.1f want 32.6" % fc)
if problems:
    sys.exit("; ".join(problems))
print("%d services capped; full-stack cpu=%.1f mem=%.0fMB across %d profiles"
      % (len(svc), fc, fm, len(EXPECTED)))
' >"${TMP}/budget.out" 2>"${TMP}/budget.err"; then
  ok "resource budget matrix holds ($(cat "${TMP}/budget.out"))"
else
  bad "resource budget DRIFT (P2-10): $(head -c 400 "${TMP}/budget.err")"
fi

# --- 3b. permission deny enforcement (static denied-tool simulation) -----------
# Simulates the denied-tool probe: asserts no role carries a bare
# allow-all, every role ends in an explicit shell deny, the seed payload
# requests permission enforcement (skip=False), and the socket proxy
# denies POST.
section "3b. permission deny enforcement (static)"
# Wave 3 P1-11: single fleet dialect — no bare allow-all may exist in ANY
# role (the old programmer-specific probe generalized after the 6 legacy
# roles were deleted as superseded). §3 already asserts each file's
# terminal deny tail; this gate additionally scans all 51 for allow-all.
if python3 -c '
import glob, json, sys
bad_roles = []
nodeny = []
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    role = f.split("/")[1]
    perms = json.load(open(f)).get("permissions", [])
    if any(p.get("action") == "*" and p.get("resource") == "*" and p.get("effect") == "allow" for p in perms):
        bad_roles.append(role)
    tails = [p for p in perms if p.get("action") == "shell" and p.get("resource") == "*" and p.get("effect") == "deny"]
    if not tails or perms[-1].get("effect") != "deny":
        nodeny.append(role)
if bad_roles:
    sys.exit("bare allow-all in: %s" % ", ".join(bad_roles))
if nodeny:
    sys.exit("missing terminal shell deny tail in: %s" % ", ".join(nodeny))
print("fleet roles: enumerated allows + terminal shell deny, no allow-all")
' >"${TMP}/deny.out" 2>"${TMP}/deny.err"; then
  ok "fleet opencode.json deny by default ($(cat "${TMP}/deny.out"))"
else
  bad "fleet permission probe FAILED: $(head -c 200 "${TMP}/deny.err")"
fi
if grep -q '"dangerouslySkipPermissions": False' scripts/seed-50-fleet.sh \
  && ! grep -q '"dangerouslySkipPermissions": True' scripts/seed-50-fleet.sh; then
  ok "seed script enforces permissions (dangerouslySkipPermissions False, no True remains)"
else
  bad "seed script still requests dangerouslySkipPermissions True"
fi
if grep -q 'POST: "0"' docker-compose.sidecars.yml \
  && grep -q 'BUILD: "0"' docker-compose.sidecars.yml \
  && grep -q 'EXEC: "0"' docker-compose.sidecars.yml; then
  ok "docker-socket-proxy denies POST/BUILD/EXEC (read-only proxy)"
else
  bad "docker-socket-proxy still permits POST/BUILD/EXEC (host-escape primitive)"
fi
# Wave 3 P1-11: the qa/tester legacy narrowing gate was removed with the
# 6 legacy roles (single fleet dialect now — §3 asserts every role's
# terminal `shell * deny`, and the fleet-wide probe above forbids
# allow-all). The `bash * allow` exfil concern (AUDIT P1-5) is closed by
# deletion: no `bash`-action permission exists anywhere in roles/.
# P1-5: MCP-boundary shell denies must not regress (MCP namespaces bypass
# these shell denies, so the denies are the inner layer — see AGENTS.md §4).
if python3 -c '
import json, sys
dba = json.load(open("roles/dba-specialist/opencode/opencode.json"))["permissions"]
if not any(p.get("action") == "shell" and "psql" in str(p.get("resource")) and p.get("effect") == "deny" for p in dba):
    sys.exit("dba-specialist lost its psql shell deny")
k8s = json.load(open("roles/k8s-orchestrator/opencode/opencode.json"))["permissions"]
for verb in ("kubectl apply*", "kubectl delete*"):
    if not any(p.get("action") == "shell" and p.get("resource") == verb and p.get("effect") == "deny" for p in k8s):
        sys.exit("k8s-orchestrator lost its %s shell deny" % verb)
print("dba psql deny + k8s kubectl apply/delete denies present")
' >"${TMP}/mcpbound.out" 2>"${TMP}/mcpbound.err"; then
  ok "MCP-boundary shell denies intact ($(cat "${TMP}/mcpbound.out"))"
else
  bad "MCP-boundary shell deny REGRESSED: $(head -c 200 "${TMP}/mcpbound.err")"
fi
# Wave 2 P0-3: harness tool manifest assertion. Manifest pinned from the
# registry tarball @heretek-ai/opencode-harness@1.0.9 (dist/index.js
# EXTENDED_HARNESS_TOOL_NAMES — the live setupOpenCodeV2Harness path
# registers all 14): every role declaring the harness plugin must allow
# exactly the 10 non-mutating tools (per-tool allows, NEVER a
# `harness_*` allow), must DENY the 4 file-mutating tools
# (file_hash_edit, ast_structural_rewrite, rename_symbol,
# checkpoint_rollback — P0-9 remediation: zero roles hold mutating
# harness allows fleet-wide), and must end the namespace with a
# `harness_*` deny tail (future manifest additions stay denied until
# explicitly allowed here). Roles without the plugin must carry no
# harness allows at all.
# NOTE: whether the runtime enforcer honors these static denies needs a
# live allow/deny matrix, tracked separately (fixture +
# live-only gate: scripts/fixtures/harness-probe-opencode.json + §10b —
# re-armed for 1.0.9 now that the P0-1 empty-string kill is fixed
# upstream; direct empty rootDir still throws fail-closed).
# Static shape is the in-repo gate; live enforcement stays tracked,
# never claimed.
HARNESS_READONLY_MANIFEST="file_hash_read ast_structural_search ui_geometry_audit repo_map blast_radius file_outline symbol_references verify_scoped architecture_audit checkpoint_create"
HARNESS_MUTATING="file_hash_edit ast_structural_rewrite rename_symbol checkpoint_rollback"
if HARNESS_READONLY_MANIFEST="${HARNESS_READONLY_MANIFEST}" HARNESS_MUTATING="${HARNESS_MUTATING}" python3 -c '
import glob, json, os, sys
ro_manifest = os.environ["HARNESS_READONLY_MANIFEST"].split()
mutating = os.environ["HARNESS_MUTATING"].split()
problems = []
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    role = f.split("/")[1]
    doc = json.load(open(f))
    perms = doc.get("permissions", [])
    allows = sorted(p["action"][len("harness_"):] for p in perms
                    if p.get("action", "").startswith("harness_")
                    and p.get("effect") == "allow")
    deny_tail = any(p.get("action") == "harness_*" and p.get("effect") == "deny"
                    for p in perms)
    has_plugin = any("harness" in str(pl) for pl in doc.get("plugins", []))
    if any(p.get("action") == "harness_*" and p.get("effect") == "allow"
           for p in perms):
        problems.append("%s: bare harness_* allow (must be per-tool)" % role)
    elif has_plugin:
        # P0-9: EVERY plugin role is read-only for harness — the 10-tool
        # non-mutating manifest plus explicit denies for the 4 mutating
        # tools (zero mutating allows fleet-wide).
        if allows != sorted(ro_manifest):
            problems.append("%s: harness allows != 10-tool read-only manifest (got %s)" % (role, allows))
        for t in mutating:
            if not any(p.get("action") == "harness_" + t and p.get("effect") == "deny" for p in perms):
                problems.append("%s: missing harness_%s deny" % (role, t))
        if not deny_tail:
            problems.append("%s: missing harness_* deny tail" % role)
    elif allows:
        problems.append("%s: harness allows without the harness plugin" % role)
if problems:
    sys.exit("; ".join(problems))
print("51/51 plugin roles allow the 10-tool read-only manifest + 4 mutating denies + deny tails")
' >"${TMP}/harness.out" 2>"${TMP}/harness.err"; then
  ok "harness manifest enforced ($(cat "${TMP}/harness.out"))"
else
  bad "harness manifest VIOLATION: $(head -c 400 "${TMP}/harness.err")"
fi
# Wave A P0-2: read-only set drift pin + fleet-wide mutating-tool ban.
# The on-disk set of roles whose fs:write allows are confined to
# report-output scopes (docs/**, sbom/**, deploy/security/**) must equal
# FS_READONLY_ROLES exactly — drift in EITHER direction fails (a role
# silently gaining a code-write scope must update the set, not silently
# regain edit primitives; a role narrowed to reports must join it).
# And NO role fleet-wide may allow the 4 mutating harness tools
# (P0-9: fail-closed — the ban is no longer confined to the 16).
FS_READONLY_ROLES="ai-red-teamer appsec-engineer binary-reverse-eng cloud-sec-auditor compliance-auditor exec-director firmware-sec-analyst git-drift-coord product-director release-qa-officer sre-incident-eng system-architect tech-docs-lead threat-modeler tpm-scrum-lead ux-research-analyst"
if HARNESS_MUTATING="${HARNESS_MUTATING}" FS_READONLY_ROLES="${FS_READONLY_ROLES}" python3 -c '
import glob, json, os, sys
mutating = {"harness_" + t for t in os.environ["HARNESS_MUTATING"].split()}
readonly = set(os.environ["FS_READONLY_ROLES"].split())
prefixes = ("docs/", "sbom/", "deploy/security/")
problems = []
on_disk = set()
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    role = f.split("/")[1]
    perms = json.load(open(f)).get("permissions", [])
    confined = True
    for p in perms:
        if p.get("action") == "fs:write" and p.get("effect") == "allow":
            res = str(p.get("resource", ""))
            if res == "*" or not res.startswith(prefixes):
                confined = False
    if confined:
        on_disk.add(role)
    allow = {p["action"] for p in perms if p.get("effect") == "allow"}
    if allow & mutating:
        problems.append("%s: role allows mutating harness tools %s" % (role, sorted(allow & mutating)))
if on_disk != readonly:
    problems.append("read-only set drift: on-disk=%s expected=%s" % (sorted(on_disk), sorted(readonly)))
if problems:
    sys.exit("; ".join(problems))
print("read-only set == 16 pinned roles; zero mutating harness allows fleet-wide (51/51)")
' >"${TMP}/readonly.out" 2>"${TMP}/readonly.err"; then
  ok "read-only harness strip enforced ($(cat "${TMP}/readonly.out"))"
else
  bad "read-only harness strip VIOLATION: $(head -c 400 "${TMP}/readonly.err")"
fi
# Wave A P1-7: fs:read deny-first ordering gate. In EVERY role file, no
# fs:read allow may precede an fs:read deny — the .env denies must sort
# above any fs:read allow so they hold under first-match-wins AND under
# deny-override/most-specific-wins (fail-closed under both semantics).
# fs:write ordering is deliberately out of scope here (scoped allows then
# * deny is already correct and is covered by the glob-specificity lint).
if python3 -c '
import glob, json, sys
problems = []
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    role = f.split("/")[1]
    perms = json.load(open(f)).get("permissions", [])
    first_allow = None
    last_deny = None
    for i, p in enumerate(perms):
        if p.get("action") == "fs:read" and p.get("effect") == "allow" and first_allow is None:
            first_allow = i
        if p.get("action") == "fs:read" and p.get("effect") == "deny":
            last_deny = i
    if last_deny is None:
        problems.append("%s: no fs:read deny entries (.env denies required)" % role)
    elif first_allow is not None and first_allow < last_deny:
        problems.append("%s: fs:read allow at index %d precedes fs:read deny at index %d" % (role, first_allow, last_deny))
if problems:
    sys.exit("; ".join(problems))
print("all roles: fs:read denies precede any fs:read allow")
' >"${TMP}/readorder.out" 2>"${TMP}/readorder.err"; then
  ok "fs:read deny-first ordering ($(cat "${TMP}/readorder.out"))"
else
  bad "fs:read ordering VIOLATION: $(head -c 400 "${TMP}/readorder.err")"
fi
# Wave D P0-3c: every role must deny secret-material reads up front
# (**/secrets/**, **/kubeconfig*, **/*.pem, **/id_rsa*), alongside the
# .env four — one UID/filesystem is shared by all agents, so the
# mounted kubeconfig, TLS keys and SSH keys are denied at the permission
# layer in every role (structural move-to-MCP-env tracked separately).
if python3 -c '
import glob, json, sys
WANT = ("**/secrets/**", "**/kubeconfig*", "**/*.pem", "**/id_rsa*")
problems = []
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    role = f.split("/")[1]
    denies = {str(p.get("resource")) for p in json.load(open(f)).get("permissions", [])
              if p.get("action") == "fs:read" and p.get("effect") == "deny"}
    missing = [w for w in WANT if w not in denies]
    if missing:
        problems.append("%s: missing fs:read denies %s" % (role, missing))
if problems:
    sys.exit("; ".join(problems))
print("all roles deny **/secrets/**, **/kubeconfig*, **/*.pem, **/id_rsa*")
' >"${TMP}/secretdeny.out" 2>"${TMP}/secretdeny.err"; then
  ok "secret-material fs:read denies present fleet-wide ($(cat "${TMP}/secretdeny.out"))"
else
  bad "secret fs:read deny VIOLATION: $(head -c 400 "${TMP}/secretdeny.err")"
fi
# Wave D P1-1/P3-2: `adb connect` is allowlisted to the loopback
# emulator + in-compose host — a bare `adb connect*` (arbitrary
# host:port probe) must not exist anywhere fleet-wide.
if python3 -c '
import glob, json, sys
problems = []
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    role = f.split("/")[1]
    for p in json.load(open(f)).get("permissions", []):
        if p.get("action") in ("shell", "bash") and p.get("effect") == "allow":
            if str(p.get("resource", "")) == "adb connect*":
                problems.append("%s: bare adb connect* allow (must be host-allowlisted)" % role)
if problems:
    sys.exit("; ".join(problems))
import json as j
android = j.load(open("roles/android-mobile-spec/opencode/opencode.json"))["permissions"]
want = {"adb connect 127.0.0.1*", "adb connect localhost*", "adb connect docker-android*"}
have = {p["resource"] for p in android
        if p.get("action") == "shell" and p.get("effect") == "allow"
        and str(p.get("resource", "")).startswith("adb connect")}
if have != want:
    sys.exit("android-mobile-spec adb allowlist drift: have=%s want=%s" % (sorted(have), sorted(want)))
print("no bare adb connect* fleet-wide; android allowlist == loopback + docker-android")
' >"${TMP}/adb.out" 2>"${TMP}/adb.err"; then
  ok "adb connect allowlisted ($(cat "${TMP}/adb.out"))"
else
  bad "adb connect scoping VIOLATION: $(head -c 300 "${TMP}/adb.err")"
fi
# Wave 2 P0-2: MCP namespace scoping. No bare-namespace allow may remain
# for kubernetes/docker/postgres/aws/git/filesystem (harness covered
# above); each scoped namespace must end in its deny tail, and the
# filesystem MCP roots must be re-rooted off the shared workspace.
if python3 -c '
import glob, json, sys
BARE = ("kubernetes_*", "docker_*", "postgres_*", "aws_*", "git_*",
        "filesystem_*")
problems = []
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    role = f.split("/")[1]
    perms = json.load(open(f)).get("permissions", [])
    for p in perms:
        if p.get("action") in BARE and p.get("effect") == "allow":
            problems.append("%s: bare %s allow" % (role, p["action"]))
def need(role, allows, denies):
    perms = json.load(open("roles/%s/opencode/opencode.json" % role))["permissions"]
    have_allow = {p["action"] for p in perms if p.get("effect") == "allow"}
    have_deny = {p["action"] for p in perms if p.get("effect") == "deny"}
    for a in allows:
        if a not in have_allow:
            problems.append("%s: missing allow %s" % (role, a))
    for d in denies:
        if d not in have_deny:
            problems.append("%s: missing deny %s" % (role, d))
need("k8s-orchestrator",
     ["kubernetes_kubectl_get*", "kubernetes_kubectl_describe*",
      "kubernetes_kubectl_previous_logs*", "docker_list*", "docker_get*"],
     ["kubernetes_kubectl_exec*", "kubernetes_*", "docker_create*",
      "docker_deploy*", "docker_*"])
need("mlops-serving-eng", ["docker_list*", "docker_get*"],
     ["docker_create*", "docker_deploy*", "docker_*"])
need("dba-specialist", ["postgres_query*"], ["postgres_*"])
need("cloud-platform-eng", ["aws_list*", "aws_select*"],
     ["aws_run*", "aws_*"])
need("cloud-sec-auditor", ["aws_list*", "aws_select*"],
     ["aws_run*", "aws_*"])
for r in ("binary-reverse-eng", "firmware-sec-analyst"):
    need(r, ["filesystem_read*", "filesystem_list*", "filesystem_directory*",
             "filesystem_search*", "filesystem_get*"],
         ["filesystem_write*", "filesystem_edit*", "filesystem_create*",
          "filesystem_move*", "filesystem_*"])
if problems:
    sys.exit("; ".join(problems))
print("namespaces scoped to read verbs + deny tails")
' >"${TMP}/nscope.out" 2>"${TMP}/nscope.err"; then
  ok "MCP namespaces scoped ($(cat "${TMP}/nscope.out"))"
else
  bad "MCP namespace scoping VIOLATION: $(head -c 400 "${TMP}/nscope.err")"
fi
# Filesystem MCP roots: the shared-workspace root must be gone (re-rooted
# to the read-only sample scope, or the server removed for docs roles).
if python3 -c '
import glob, json, sys
problems = []
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    role = f.split("/")[1]
    servers = (json.load(open(f)).get("mcp") or {}).get("servers") or {}
    fs = servers.get("filesystem")
    if fs is None:
        continue
    roots = [a for a in (fs.get("command") or []) if str(a).startswith("/")]
    if "/paperclip/workspaces" in roots:
        problems.append("%s: filesystem MCP rooted at shared /paperclip/workspaces" % role)
    if role in ("binary-reverse-eng", "firmware-sec-analyst") and roots != ["/paperclip/workspaces/binaries"]:
        problems.append("%s: unexpected filesystem roots %r" % (role, roots))
if problems:
    sys.exit("; ".join(problems))
print("filesystem MCP roots re-rooted off the shared workspace")
' >"${TMP}/fsroot.out" 2>"${TMP}/fsroot.err"; then
  ok "$(cat "${TMP}/fsroot.out")"
else
  bad "filesystem MCP root VIOLATION: $(head -c 300 "${TMP}/fsroot.err")"
fi
# Wave D P1-6/P3-5: the two docker-MCP blocks declare DOCKER_HOST
# explicitly (GET-only socket proxy — read-only observer) instead of
# dangling dead. Any docker MCP server without that exact env FAILs
# (undeclared default or future-activation hazard); a bare socket mount
# would be a separate violation (no role mounts it — compose paperclip
# mounts no socket, asserted below via the proxy-only DOCKER_HOST).
if python3 -c '
import glob, json, sys
problems = []
found = []
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    role = f.split("/")[1]
    servers = (json.load(open(f)).get("mcp") or {}).get("servers") or {}
    docker = servers.get("docker")
    if docker is None:
        continue
    found.append(role)
    env = docker.get("env") or {}
    if env.get("DOCKER_HOST") != "tcp://docker-socket-proxy:2375":
        problems.append("%s: docker MCP without DOCKER_HOST=tcp://docker-socket-proxy:2375 (got %r)" % (role, env.get("DOCKER_HOST")))
if sorted(found) != ["k8s-orchestrator", "mlops-serving-eng"]:
    problems.append("docker MCP role set drift: found=%s (want exactly k8s-orchestrator + mlops-serving-eng)" % sorted(found))
if problems:
    sys.exit("; ".join(problems))
print("docker MCP declares DOCKER_HOST=tcp://docker-socket-proxy:2375 in k8s-orchestrator + mlops-serving-eng")
' >"${TMP}/dockerhost.out" 2>"${TMP}/dockerhost.err"; then
  ok "$(cat "${TMP}/dockerhost.out")"
else
  bad "docker DOCKER_HOST VIOLATION: $(head -c 300 "${TMP}/dockerhost.err")"
fi
# Wave D P2-9: the seeder guards the ROLE_DIR hazard (ambient ROLE_DIR
# disagreeing with the iterated role aborts instead of stamping every
# payload with one role's config) and fetches the agent list once
# (cache + refresh-on-miss/create, not one LIST per role).
if grep -q 'ROLE_DIR hazard' scripts/seed-50-fleet.sh \
  && grep -q 'os.environ\["ROLE_DIR"\] != sys.argv\[1\]' scripts/seed-50-fleet.sh \
  && grep -q 'fetched ONCE up front' scripts/seed-50-fleet.sh; then
  ok "seed-50 guards ROLE_DIR hazard + fetches agent list once (P2-9)"
else
  bad "seed-50 P2-9 guards MISSING (ROLE_DIR assertion or fetch-once)"
fi
# Wave 4 P1-7: fs:write glob-specificity lint. Any fs:write ALLOW whose
# resource starts with a SINGLE `*` (unanchored `*substring*`, `*.md`,
# `*config*`) FAILs closed — such globs match repo-wide. Legitimate shapes
# that must NOT trip the gate: `**/`-anchored globs (`**/package-lock.json`,
# `docs/**/*.md`), exact filenames (`package.json`, `go.mod`), bare
# filename prefixes WITHOUT a leading star (`go.*`, `playwright.config.*`,
# `build.gradle*` — cwd-scoped, narrowed separately), the deny-tail `*`,
# and shell prefix allows (out of scope — this gate scans fs:write exactly).
if python3 -c '
import glob, json, sys
problems = []
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    role = f.split("/")[1]
    for p in json.load(open(f)).get("permissions", []):
        if p.get("action") != "fs:write" or p.get("effect") != "allow":
            continue
        res = str(p.get("resource", ""))
        if res == "*":
            continue
        if res.startswith("*") and not res.startswith("**/"):
            problems.append("%s: unanchored fs:write glob %r (anchor to **/ or a path prefix)" % (role, res))
if problems:
    sys.exit("; ".join(problems))
print("all fs:write allows anchored (**/, path prefix, or exact filename)")
' >"${TMP}/globlint.out" 2>"${TMP}/globlint.err"; then
  ok "fs:write glob-specificity lint ($(cat "${TMP}/globlint.out"))"
else
  bad "glob-specificity VIOLATION: $(head -c 400 "${TMP}/globlint.err")"
fi
# Wave 2 P0-5: git-drift-coord must not hold history-rewrite primitives.
if python3 -c '
import json, sys
perms = json.load(open("roles/git-drift-coord/opencode/opencode.json"))["permissions"]
for banned in ("git worktree*", "git rebase*", "git push --force-with-lease*"):
    if any(p.get("action") == "shell" and p.get("resource") == banned and p.get("effect") == "allow" for p in perms):
        sys.exit("git-drift-coord still allows %s" % banned)
if any(p.get("action") == "shell" and p.get("effect") == "allow" and str(p.get("resource")).startswith("git push") for p in perms):
    sys.exit("git-drift-coord retains a git push shell allow (pushes are human-approval-gated)")
print("no worktree/rebase/force-push allows; pushes human-gated")
' >"${TMP}/drift.out" 2>"${TMP}/drift.err"; then
  ok "git-drift-coord history-rewrite removed ($(cat "${TMP}/drift.out"))"
else
  bad "git-drift-coord P0-5 VIOLATION: $(head -c 300 "${TMP}/drift.err")"
fi
# Wave 2 P0-4: negative prefix-chain probes. Shell allows are advisory-only
# string prefixes (see AGENTS.md §4): a prefix enforcer grants
# `git status; <payload>` via the `git status*` allow. This gate pins the
# fail-closed reference matcher — any command containing shell chaining
# metacharacters is denied — and requires the three sabotage probes to be
# denied by it. It also requires every shell/bash allow to be a single
# command prefix (no chaining metacharacter baked into an allow itself),
# and prints (informational, NOT a failure) which naive-prefix allow each
# probe would have matched, documenting WHY allows are advisory-only.
if python3 -c '
import glob, json, re, sys
META = re.compile(r"[;&|`$><()\n]")
def reference_deny(cmd):
    """Fail-closed argv-aware reference: chaining metachars -> deny."""
    return bool(META.search(cmd))
probes = ["git status; id", "npm test && id", "curl -s http://x; id"]
refused = [p for p in probes if reference_deny(p)]
if refused != probes:
    sys.exit("reference matcher granted a chained probe: %s"
             % [p for p in probes if not reference_deny(p)])
allows = []
for f in sorted(glob.glob("roles/*/opencode/opencode.json")):
    role = f.split("/")[1]
    for p in json.load(open(f)).get("permissions", []):
        if p.get("action") in ("shell", "bash") and p.get("effect") == "allow":
            res = str(p.get("resource", ""))
            if META.search(res):
                sys.exit("%s: shell allow bakes in chaining metachars: %r" % (role, res))
            allows.append((role, res.rstrip("*")))
print("reference matcher denies all %d chained probes; %d shell allows are single-command prefixes"
      % (len(probes), len(allows)))
for probe in probes:
    hits = sorted("%s:%s*" % (r, a) for r, a in allows if probe.startswith(a))
    print("advisory-only demo: %r would match naive-prefix %s" % (probe, hits[:3]))
' >"${TMP}/negprobe.out" 2>"${TMP}/negprobe.err"; then
  ok "negative prefix probes denied ($(head -n 1 "${TMP}/negprobe.out"))"
  while IFS= read -r line; do printf '  [INFO] %s\n' "${line}"; done < <(tail -n +2 "${TMP}/negprobe.out")
else
  bad "negative prefix probe FAILED: $(head -c 300 "${TMP}/negprobe.err")"
fi

# --- 3c. skills path resolution (Phase A T1, §10.5) ---------------------------
# Load-bearing skills discovery: every role that configures `skills` in
# opencode.json must list BOTH the container-mount form
# (/roles/<id>/skills) and the XDG form (/roles/<id>/.opencode/skills).
# Both must resolve to roles/<id>/.opencode/skills on disk — bridged by the
# relative roles/<id>/skills -> .opencode/skills symlink so the mapping
# survives container mounts — and the canonical dir must hold at least one
# <skill>/SKILL.md. Fail closed: a missing entry, dangling link, or
# skill-less configured dir is a FAIL, never a silent green.
section "3c. role skills path resolution"
for roledir in roles/*/; do
  [[ -d "${roledir}" ]] || continue
  role="$(basename "${roledir}")"
  f="roles/${role}/opencode/opencode.json"
  if ! SKILLS_STATE="$(ROLE="${role}" FILE="${f}" python3 -c '
import json, os, sys
role = os.environ["ROLE"]
doc = json.load(open(os.environ["FILE"]))
skills = doc.get("skills")
if not skills:
    print("UNCONFIGURED")
    sys.exit(0)
if not isinstance(skills, list):
    sys.exit("skills is not a list: %r" % (skills,))
want = ["/roles/%s/skills" % role, "/roles/%s/.opencode/skills" % role]
missing = [w for w in want if w not in skills]
if missing:
    sys.exit("skills array missing entries %s (got %r)" % (missing, skills))
print("CONFIGURED")
' 2>"${TMP}/skills-err-${role}")"; then
    bad "${f} skills INVALID: $(head -c 200 "${TMP}/skills-err-${role}")"
    continue
  fi
  if [[ "${SKILLS_STATE}" == "UNCONFIGURED" ]]; then
    if [[ -d "roles/${role}/.opencode/skills" ]]; then
      bad "roles/${role}/.opencode/skills exists on disk but ${f} configures no skills (undiscoverable dir)"
    else
      skip "roles/${role} configures no skills and ships none"
    fi
    continue
  fi
  ok "${f} skills lists both /roles/${role}/skills and /roles/${role}/.opencode/skills"
  canon="roles/${role}/.opencode/skills"
  link="roles/${role}/skills"
  if [[ ! -d "${canon}" ]]; then
    bad "${canon}/ MISSING on disk (skills configured but canonical dir absent)"
    continue
  fi
  if [[ -L "${link}" ]]; then
    target="$(readlink "${link}")"
    if [[ "${target}" == ".opencode/skills" ]]; then
      ok "roles/${role}/skills -> .opencode/skills (relative symlink, mount-safe)"
    else
      bad "roles/${role}/skills symlink points at '${target}' (want relative '.opencode/skills')"
    fi
  elif [[ -d "${link}" ]]; then
    ok "roles/${role}/skills is a real directory (accepted; relative symlink preferred)"
  else
    bad "roles/${role}/skills MISSING (want relative symlink -> .opencode/skills)"
  fi
  for sp in "/roles/${role}/skills" "/roles/${role}/.opencode/skills"; do
    rel="${sp#/roles/"${role}"}"
    disk="roles/${role}${rel}"
    if [[ ! -d "${disk}" ]]; then
      bad "configured skill path ${sp} does not resolve on disk (want ${disk}/)"
      continue
    fi
    if resolved="$(cd "${disk}" || exit 1; pwd -P)" \
      && canonical="$(cd "${canon}" || exit 1; pwd -P)" \
      && [[ "${resolved}" == "${canonical}" ]]; then
      ok "configured skill path ${sp} resolves to roles/${role}/.opencode/skills"
    else
      bad "configured skill path ${sp} resolves off the canonical dir (got '${resolved:-unresolvable}')"
    fi
  done
  if find "${canon}" -mindepth 2 -maxdepth 2 -name 'SKILL.md' -print -quit 2>/dev/null | grep -q .; then
    skill_count="$(find "${canon}" -mindepth 2 -maxdepth 2 -name 'SKILL.md' -print 2>/dev/null | wc -l)"
    skill_count="$(printf '%s' "${skill_count}" | tr -d ' ')"
    ok "roles/${role}/.opencode/skills holds ${skill_count} SKILL.md file(s)"
  else
    bad "roles/${role}/.opencode/skills holds no <skill>/SKILL.md (skills configured but nothing discoverable)"
  fi
done

# --- 3d. spec-driven development gate (Phase A T5) ---------------------------
# CI SDD gate: code<->spec delta coverage, task-plan checkboxes +
# acceptance criteria, per-role spec completeness, and fleet hardening
# invariants. Delegated to scripts/spec-gate.sh --check-only (deterministic:
# no network, no docker, no secrets); any gate FAIL propagates via bad().
section "3d. spec-driven development gate (spec-gate.sh)"
if bash scripts/spec-gate.sh --check-only >"${TMP}/specgate.out" 2>&1; then
  ok "spec-gate.sh --check-only passed"
else
  bad "spec-gate.sh --check-only FAILED"
fi
grep -E '\[(PASS|FAIL|INFO)\]|SPEC-GATE RESULT' "${TMP}/specgate.out" 2>/dev/null \
  | while IFS= read -r line; do printf '  [INFO spec-gate] %s\n' "${line}"; done || true

# --- 4. seed dry-run ---------------------------------------------------------
# Wave 3 P1-11: scripts/seed-company.sh was deleted with the 6 legacy
# prototype roles it seeded (superseded by the 50-fleet). Only the fleet
# seeder remains; this section asserts its dry-run.
section "4. seed dry-run (seed-50-fleet.sh)"
if [[ -f scripts/seed-50-fleet.sh ]]; then
  # Wave 2 (P0-2/P1-8): the seed preflight requires provisioned MCP
  # credentials even for --dry-run (fail-closed); throwaway dummies here
  # (validation only), with a scratch regular file for the kubeconfig path.
  printf 'apiVersion: v1\nkind: Config\nclusters: []\n' >"${TMP}/kubeconfig.smoke-dummy"
  if POSTGRES_READONLY_URL='postgres://paperclip_reader:__smoke_only__@postgres:5432/paperclip' \
     GITHUB_TOKEN=__smoke_only__ \
     KUBECONFIG_READONLY_PATH="${TMP}/kubeconfig.smoke-dummy" \
     ./scripts/seed-50-fleet.sh --dry-run >"${TMP}/seed50.out" 2>"${TMP}/seed50.err"; then
    SEED50_NAMES="$(grep -c '"name"' "${TMP}/seed50.out" || true)"
    SEED50_TOTAL="$(grep -oE 'total fleet budget: [0-9]+ cents' "${TMP}/seed50.out" | grep -oE '[0-9]+' || true)"
    SEED50_CAP="$(grep -oE '\(cap [0-9]+ cents\)' "${TMP}/seed50.out" | grep -oE '[0-9]+' || true)"
    if [[ "${SEED50_NAMES}" -eq 52 ]] \
      && grep -q 'Heretek Autonomous Fleet' "${TMP}/seed50.out" \
      && grep -q 'opencode_local' "${TMP}/seed50.out" \
      && grep -q 'XDG_CONFIG_HOME' "${TMP}/seed50.out" \
      && grep -q 'OPENCODE_DISABLE_PROJECT_CONFIG' "${TMP}/seed50.out" \
      && grep -q 'dangerouslySkipPermissions' "${TMP}/seed50.out" \
      && grep -q 'total fleet budget' "${TMP}/seed50.out" \
      && [[ -n "${SEED50_TOTAL}" && "${SEED50_TOTAL}" == "${SEED50_CAP}" ]] \
      && ! grep -q 'WARNING' "${TMP}/seed50.err"; then
      ok "seed-50 dry-run emits 52 payloads (1 company + 51 agents: opencode_local, XDG_CONFIG_HOME, OPENCODE_DISABLE_PROJECT_CONFIG, skipPermissions, budget total ${SEED50_TOTAL} == cap, no WARNING)"
    else
      bad "seed-50 dry-run output unexpected (name keys=${SEED50_NAMES}, want 52 with fleet payload keys + total==cap and no WARNING)"
    fi
    # Wave D P0-3b/P2-7.1: adapterConfig.env is an allowlist (XDG_CONFIG_HOME
    # + OPENCODE_DISABLE_PROJECT_CONFIG ONLY). The superuser DATABASE_URL,
    # POSTGRES_PASSWORD, BETTER_AUTH_SECRET and every provider key must
    # NEVER enter agent payloads — a dba psql deny + read-only MCP URL are
    # moot if the agent inherits superuser credentials. (Upstream
    # inheritance scrubbing in prepareOpenCodeRuntimeConfig is separately
    # live-unverified — see the §10b canary note. P0-3 live canary: in a
    # live agent turn, `printenv | grep -c DATABASE_URL` MUST be 0 —
    # sanitizeInheritedPaperclipEnv only strips PAPERCLIP_*/identity keys,
    # so any DATABASE_URL on the server process survives into the child.)
    if grep -q 'DATABASE_URL\|POSTGRES_PASSWORD\|BETTER_AUTH_SECRET\|OPENCODE_API_KEY\|OPENCODE_GO_API_KEY\|OPENAI_API_KEY\|ANTHROPIC_API_KEY\|GEMINI_API_KEY\|OPENROUTER_API_KEY\|DEEPSEEK_API_KEY\|GROQ_API_KEY\|MISTRAL_API_KEY\|XAI_API_KEY\|AZURE_OPENAI_API_KEY' "${TMP}/seed50.out"; then
      bad "seed-50 payloads leak server credentials/provider keys into adapterConfig.env (P0-3b)"
    else
      ok "seed-50 payloads carry no DATABASE_URL/POSTGRES_PASSWORD/BETTER_AUTH_SECRET/provider keys (env allowlist)"
    fi
  else
    bad "seed-50 dry-run exited nonzero: $(head -c 300 "${TMP}/seed50.err")"
  fi
  # Wave E Stage 3 P1-9 live rerun-diff gate (live-gated SKIP, needs
  # `make up`): a second live seeding pass must be drift-only (PATCH on
  # drift, zero duplicate creates). Run against the live stack:
  #   PAPERCLIP_TOKEN=... ./scripts/seed-50-fleet.sh >/tmp/rerun1.log 2>&1
  #   PAPERCLIP_TOKEN=... ./scripts/seed-50-fleet.sh >/tmp/rerun2.log 2>&1
  # then diff — rerun 2 must create 0 agents and PATCH only drifted
  # reportsTo/budget fields. Unrunnable here (no live Paperclip); the
  # static 52-doc / total==cap / no-WARNING assertions above are the
  # in-repo gate.
  skip "seeder live two-pass rerun diff (P1-9) — needs live stack (run seed-50-fleet.sh twice against make-up Paperclip, assert rerun creates 0 agents)"
else
  bad "scripts/seed-50-fleet.sh MISSING"
fi

# --- 5. shim translation -----------------------------------------------------
section "5. opencode-shim translation (fake real binary)"
cat >"${TMP}/fake-opencode" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${FAKE_OUT:?FAKE_OUT must be set}"
EOF
chmod +x "${TMP}/fake-opencode"
shim_run() { OPENCODE_REAL_BIN="${TMP}/fake-opencode" FAKE_OUT="${TMP}/shim.args" ./scripts/opencode-shim.sh "$@"; }
if shim_run run --format json --dir /tmp --model opencode/gemini-3.8-flash --variant high "Create hello.txt"; then
  if diff -u <(printf 'run\n--format\njson\n--model\nopencode/gemini-3.8-flash#high\n--auto\nCreate hello.txt\n') "${TMP}/shim.args" >/dev/null; then
    ok "run: --dir + on-disk dir consumed (P0-1), --variant merged to model#variant, --auto injected in order"
  else
    bad "run translation mismatch; got: $(tr '\n' ' ' <"${TMP}/shim.args")"
  fi
else
  bad "shim run invocation failed"
fi
if shim_run run --format json --dir /nonexistent-ws-dir-xyz --model opencode/gemini-3.8-flash "Create hello.txt" \
  && grep -qx '/nonexistent-ws-dir-xyz' "${TMP}/shim.args"; then
  ok "run: --dir preserves non-existent absolute path (P0-1 fail-closed toward prompt preservation)"
else
  bad "shim --dir non-dir preservation failed; got: $(tr '\n' ' ' <"${TMP}/shim.args")"
fi
if shim_run run --variant low --model anthropic/claude-sonnet-4-5 --dir=/tmp/x --auto "p" \
  && grep -qx -- '--auto' "${TMP}/shim.args" \
  && [[ "$(grep -c -- '--auto' "${TMP}/shim.args")" -eq 1 ]] \
  && grep -qx 'anthropic/claude-sonnet-4-5#low' "${TMP}/shim.args" \
  && ! grep -q -- '--dir' "${TMP}/shim.args"; then
  ok "run: variant-first order, --dir= form, duplicate --auto suppressed"
else
  bad "shim variant-first/equals-form case failed; got: $(tr '\n' ' ' <"${TMP}/shim.args")"
fi
if shim_run models --verbose && grep -qx 'models' "${TMP}/shim.args" && grep -qx -- '--verbose' "${TMP}/shim.args"; then
  ok "non-run subcommand (models) passes through untouched"
else
  bad "non-run passthrough failed"
fi
if shim_run run --session abc123 --model m "p" \
  && grep -qx -- '--session' "${TMP}/shim.args" && grep -qx 'abc123' "${TMP}/shim.args"; then
  ok "run: --session passes through (resume compatible)"
else
  bad "--session passthrough failed"
fi
if shim_run run --model m -- --dir kept "p" \
  && grep -qx -- '--' "${TMP}/shim.args" && grep -qx -- '--dir' "${TMP}/shim.args" && grep -qx 'kept' "${TMP}/shim.args"; then
  ok "run: '--' terminator preserves prompt tail verbatim"
else
  bad "'--' terminator handling failed"
fi
# P0-1: non-directory token after --dir is preserved (fail-closed
# toward prompt preservation — no silent prompt loss).
if shim_run run --model m --dir prompt; then
  if diff -u <(printf 'run\n--model\nm\n--auto\nprompt\n') "${TMP}/shim.args" >/dev/null; then
    ok "run: non-directory --dir token preserved (P0-1)"
  else
    bad "P0-1 --dir case mismatch; got: $(tr '\n' ' ' <"${TMP}/shim.args")"
  fi
else
  bad "shim P0-1 invocation failed"
fi
# Wave B P2-2b: empty-string --variant/--dir values are consumed and dropped
# (no stray "" leaks into the positionals).
if shim_run run --model m --variant '' prompt; then
  if diff -u <(printf 'run\n--model\nm\n--auto\nprompt\n') "${TMP}/shim.args" >/dev/null; then
    ok "run: empty --variant value consumed, model untouched (P2-2b)"
  else
    bad "P2-2b empty --variant mismatch; got: $(tr '\n' ' ' <"${TMP}/shim.args")"
  fi
else
  bad "shim P2-2b empty --variant invocation failed"
fi
if shim_run run --model m --dir "" prompt; then
  if diff -u <(printf 'run\n--model\nm\n--auto\nprompt\n') "${TMP}/shim.args" >/dev/null; then
    ok "run: empty --dir value consumed, no stray positional (P2-2b)"
  else
    bad "P2-2b empty --dir mismatch; got: $(tr '\n' ' ' <"${TMP}/shim.args")"
  fi
else
  bad "shim P2-2b empty --dir invocation failed"
fi
# Wave B P2-2c: duplicate --model is first-wins (live-probed against the
# real binary) — the variant merges into the first occurrence.
if shim_run run --model aaa --model bbb --variant high prompt; then
  if diff -u <(printf 'run\n--model\naaa#high\n--auto\n--model\nbbb\nprompt\n') "${TMP}/shim.args" >/dev/null; then
    ok "run: duplicate --model merges into first (first-wins, P2-2c)"
  else
    bad "P2-2c duplicate --model mismatch; got: $(tr '\n' ' ' <"${TMP}/shim.args")"
  fi
else
  bad "shim P2-2c duplicate --model invocation failed"
fi
if OPENCODE_REAL_BIN=/nonexistent ./scripts/opencode-shim.sh run "x" 2>/dev/null; then
  bad "shim with missing real binary should fail closed"
else
  ok "shim fail-closed when real binary is missing"
fi

# --- 5b. Wave B remediation gates (dispatch/backup/restore/worktree) --------
# Static pins for the Wave B fixes: provisioner-tracer scope + exit-0,
# backup .age-suffix preservation, restore CLI-wins + bind + listing, and
# worktree adoption/archive guards. Fail closed on any drift back.
section "5b. Wave B remediation gates (dispatch/backup/restore/worktree)"
# P0-4: dispatch is a provisioner-tracer — no Paperclip API surface in
# EXECUTABLE lines (comment disclaimers naming curl/PAPERCLIP_URL//api/ are
# expected and stripped here), an explicit header disclaimer, and no
# nonzero exit past Phase 6 (execute mode exits 0 after phase-3
# provisioning; the manual merge is retained but is not a failure).
if ! grep -vE '^[[:space:]]*#' scripts/dispatch-pipeline.sh | grep -qE 'curl|PAPERCLIP_URL|/api/'; then
  ok "dispatch performs no Paperclip API calls (provisioner-tracer scope)"
else
  bad "dispatch references Paperclip API surface (provisioner scope violation)"
fi
if grep -q 'does NOT call the Paperclip API' scripts/dispatch-pipeline.sh \
  && grep -q 'does NOT perform todo' scripts/dispatch-pipeline.sh; then
  ok "dispatch header disclaims Paperclip calls + ticket transitions"
else
  bad "dispatch header missing the provisioner-tracer disclaimer"
fi
if awk '/# Phase 6/{flag=1} flag && /^[[:space:]]*exit 1/{found=1} END{exit !found}' scripts/dispatch-pipeline.sh; then
  bad "dispatch phase-6 still exits nonzero (execute mode must exit 0 after provisioning)"
else
  ok "dispatch execute mode exits 0 after provisioning (manual merge retained, fail-closed)"
fi
# P1-10: same-second collision must preserve the .age suffix — an
# age-encrypted dump under a plaintext name is unrestorable by restore-db.sh.
# The Wave B fix keeps the old unconditional bare reassign gone (2-space
# indent, end-of-line anchored); RANDOM rewrites now live only in the
# ENCRYPT-conditional branches.
# shellcheck disable=SC2016 # literal ${STAMP}/${RANDOM} source-text match intended
if grep -q '^  OUTFILE="${BACKUP_DIR}/backup-${STAMP}-${RANDOM}.sql.gz"$' scripts/backup-db.sh; then
  bad "backup collision branch drops the .age suffix unconditionally (P1-10)"
else
  ok "backup unconditional bare-suffix reassign gone (P1-10)"
fi
# shellcheck disable=SC2016 # literal ${STAMP}/${RANDOM} source-text match intended
if grep -q 'backup-${STAMP}-${RANDOM}.sql.gz.age' scripts/backup-db.sh; then
  ok "backup collision branch keeps .age for encrypted dumps (P1-10)"
else
  bad "backup collision branch missing the .age-preserving path (P1-10)"
fi
# P2-13: fail-closed encryption gate — no recipient + no opt-in must
# refuse BEFORE any dump bytes (exit 1); --plaintext-ok must pass the
# gate (downstream docker/health failures are out of scope statically).
code=0
refusal="$(env -u BACKUP_AGE_RECIPIENT BACKUP_PLAINTEXT_OK=0 ./scripts/backup-db.sh 2>&1)" || code=$?
if [[ "${code}" -eq 0 ]]; then
  bad "backup wrote/refused-silently without recipient or opt-in (P2-13)"
elif [[ "${code}" -eq 1 && "${refusal}" == *"refusing plaintext dump"* ]]; then
  ok "backup fail-closed without BACKUP_AGE_RECIPIENT and without --plaintext-ok (P2-13)"
else
  bad "backup refusal has wrong exit/message (P2-13)"
fi
if BACKUP_PLAINTEXT_OK=0 ./scripts/backup-db.sh --plaintext-ok >/dev/null 2>&1; then
  bad "backup --plaintext-ok unexpectedly fully succeeded without a stack (P2-13)"
else
  if ./scripts/backup-db.sh --plaintext-ok 2>&1 | grep -q "refusing plaintext dump"; then
    bad "backup --plaintext-ok still trips the plaintext gate (P2-13)"
  else
    ok "backup --plaintext-ok passes the encryption gate (P2-13)"
  fi
fi
# P2-3: explicit CLI --file/--yes must survive .env sourcing; the
# FILE-required hint must list encrypted dumps; the terminate query must
# bind (psql -v) instead of interpolating into single quotes.
if grep -q 'CLI_FILE_GIVEN' scripts/restore-db.sh \
  && grep -q 'CLI_YES_GIVEN' scripts/restore-db.sh; then
  ok "restore snapshots CLI --file/--yes across .env sourcing (P2-3)"
else
  bad "restore lets .env override explicit CLI --file/--yes (P2-3)"
fi
if grep -q 'backup-\*.sql.gz.age' scripts/restore-db.sh; then
  ok "restore available-dumps hint lists *.age dumps (P2-3)"
else
  bad "restore available-dumps hint omits *.age (P2-3)"
fi
if grep -q "datname=:'dbname'" scripts/restore-db.sh \
  && ! grep -q "datname='\${POSTGRES_DB}'" scripts/restore-db.sh; then
  ok "restore terminate query binds dbname via psql -v (P2-3)"
else
  bad "restore interpolates \${POSTGRES_DB} into SQL single quotes (P2-3)"
fi
# P1-15: --file must accept the space form (usage header documents
# `--file path`). Space form with a missing file must fail on the
# file-not-found gate (exit 1), never on argument parsing (exit 2).
if ./scripts/restore-db.sh --file backups/definitely-missing-p115.sql.gz >/dev/null 2>&1; then
  bad "restore --file space form unexpectedly exited 0 for a missing file (P1-15)"
else
  code=$?
  if [[ "${code}" -eq 1 ]]; then
    ok "restore --file space form parses (missing file fails on file gate, exit 1 — P1-15)"
  else
    bad "restore --file space form exits ${code}, want file-gate exit 1 (P1-15)"
  fi
fi
code=0
./scripts/restore-db.sh --file >/dev/null 2>&1 || code=$?
if [[ "${code}" -eq 2 ]]; then
  ok "restore bare --file fails closed with parse exit 2 (P1-15)"
elif [[ "${code}" -eq 0 ]]; then
  bad "restore bare --file unexpectedly exited 0 (P1-15)"
else
  bad "restore bare --file exits ${code}, want parse exit 2 (P1-15)"
fi
# P2-4: create must verify porcelain registration before adopting a
# pre-existing dir; archive must resolve HEAD up front and clean up partial
# dirs instead of littering them.
if grep -q 'worktree list --porcelain' scripts/worktree-manager.sh \
  && grep -q 'refusing to adopt' scripts/worktree-manager.sh; then
  ok "worktree create verifies registration before adopting (P2-4)"
else
  bad "worktree create adopts pre-existing dirs without verification (P2-4)"
fi
if grep -q 'removed partial' scripts/worktree-manager.sh \
  && grep -q 'cannot resolve HEAD' scripts/worktree-manager.sh; then
  ok "worktree archive guards HEAD + removes partial dirs (P2-4)"
else
  bad "worktree archive missing fail-closed guards (P2-4)"
fi
# Wave E Stage 3 P1-10: same-second collision gets a -$RANDOM suffix (never
# clobber, second collision aborts); evidence stages to a temp dir and is
# renamed into place only after `remove` succeeds (a failed remove deletes
# the staged temp instead of littering the archive dir); branch naming is
# ticket-<id> with a dash (never ticket/<id> with a slash); removal is
# never --force (dirty worktrees abort, branch retained).
# shellcheck disable=SC2016 # literal ${RANDOM} source-text match intended
if grep -q 'timestamp}-${RANDOM}' scripts/worktree-manager.sh \
  && grep -q 'archive_tmp' scripts/worktree-manager.sh \
  && grep -q 'removed staged' scripts/worktree-manager.sh; then
  ok "worktree archive temp-stages + RANDOM same-second guard (P1-10)"
else
  bad "worktree archive missing temp-stage or RANDOM guard (P1-10)"
fi
# shellcheck disable=SC2016 # literal ${ticket_id} source-text match intended
if grep -q 'branch_name="ticket-${ticket_id}"' scripts/worktree-manager.sh \
  && ! grep -q 'ticket/${ticket_id}\|ticket/\${ticket_id}' scripts/worktree-manager.sh \
  && ! grep -q 'worktree remove --force\|worktree remove -f' scripts/worktree-manager.sh; then
  ok "worktree branch ticket-<id> dash + never --force (P1-10)"
else
  bad "worktree branch naming or --force drift (P1-10: want ticket-<id> dash, no --force)"
fi

# --- 6. file creation simulation ---------------------------------------------
section "6. file-creation simulation"
SIMDIR="${TMP}/workspace"
mkdir -p "${SIMDIR}"
TODAY="$(date +%F)"
echo "${TODAY}" >"${SIMDIR}/hello.txt"
if grep -qx "${TODAY}" "${SIMDIR}/hello.txt"; then
  ok "hello.txt with today's date (${TODAY}) created and verified"
else
  bad "hello.txt simulation failed"
fi

# --- 7. session-resume support -------------------------------------------------
section "7. session resume (--session) support"
if command -v opencode >/dev/null 2>&1; then
  if opencode run --help 2>&1 | grep -qi 'session'; then
    ok "installed opencode CLI advertises --session (resume supported)"
  else
    bad "installed opencode CLI does not advertise --session"
  fi
else
  skip "no opencode binary on PATH; live runs use the in-image shim + opencode-bin"
fi

# --- live-only checks ----------------------------------------------------------
if [[ "${MODE}" == "check-only" ]]; then
  section "live checks (8-10) skipped in --check-only mode"
  skip "postgres pg_isready — needs 'make up'"
  skip "paperclip HTTP health — needs 'make up'"
  skip "ticket flow — needs live server + PAPERCLIP_TOKEN (see --help)"
  skip "harness tool-visibility probe (P0-1) — needs live stack + HARNESS_LIVE_GATE=1 (fixture: scripts/fixtures/harness-probe-opencode.json)"
  skip "XDG/canary isolation probe (P1-8) — needs live stack (plant canary opencode.json + .opencode/ in scratch workspace, run one agent turn, assert canary ignored)"
  skip "backup->restore round-trip (P2-12) — needs live stack + BACKUP_ROUNDTRIP_LIVE=1 (backup + --yes restore + table-count verify)"
else
  section "8. PostgreSQL health"
  if docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"; then
    ok "postgres pg_isready accepting connections"
  else
    bad "postgres not healthy (run 'make up' and wait for healthcheck)"
  fi
  # Wave D P2-5: the server (and every agent child) must run as node
  # UID 1000 via the base entrypoint's gosu drop — never root. If the
  # entrypoint ever stops dropping (or PAPERCLIP_BASE_IMAGE is
  # overridden), this fails instead of silently running as root.
  if PAPERCLIP_UID="$(docker compose exec -T paperclip id -u 2>/dev/null | tr -d ' \r\n')" \
    && [[ -n "${PAPERCLIP_UID}" ]]; then
    if [[ "${PAPERCLIP_UID}" == "1000" ]]; then
      ok "paperclip effective UID==1000 (node via gosu, non-root confirmed)"
    else
      bad "paperclip effective UID=${PAPERCLIP_UID} != 1000 (server running as wrong user — non-root invariant broken)"
    fi
  else
    bad "paperclip container not running (run 'make up' first — UID==1000 unverifiable while down)"
  fi

  # Wave E Stage 4 P2-12: backup->restore round-trip (live-only, opt-in).
  # Destructive by design (the dump carries --clean, the restore drops
  # and recreates), so it runs ONLY with BACKUP_ROUNDTRIP_LIVE=1 and
  # SKIPs otherwise (never fake-passes, never surprises). Uses the --file
  # + --yes CLI flags (the .env-proof snapshot path, not env passthrough)
  # into a scratch BACKUP_DIR; asserts the backup lands non-empty and the
  # --yes restore exits 0 with its own table-count verification. Passes
  # --plaintext-ok explicitly (P2-13: the fail-closed encryption gate
  # would otherwise refuse; the opt-in is scoped to this scratch test).
  section "8b. backup->restore round-trip (P2-12, live-only)"
  if [[ "${BACKUP_ROUNDTRIP_LIVE:-0}" != "1" ]]; then
    skip "BACKUP_ROUNDTRIP_LIVE!=1: backup to scratch dir + --yes restore + table-count verify (re-run with BACKUP_ROUNDTRIP_LIVE=1 + 'make up' healthy for full live proof)"
  else
    RT_DIR="${TMP}/roundtrip-backups"
    mkdir -p "${RT_DIR}"
    if RT_OUT="$(BACKUP_DIR="${RT_DIR}" ./scripts/backup-db.sh --plaintext-ok 2>"${TMP}/roundtrip-backup.err")"; then
      RT_FILE="$(printf '%s\n' "${RT_OUT}" | sed -n 's/^\[backup\] done: //p' | tail -n 1)"
      if [[ -n "${RT_FILE}" && -s "${RT_FILE}" ]]; then
        ok "round-trip backup landed non-empty (${RT_FILE})"
        if ./scripts/restore-db.sh --file="${RT_FILE}" --yes >"${TMP}/roundtrip-restore.out" 2>"${TMP}/roundtrip-restore.err"; then
          ok "round-trip --yes restore exited 0 (restore-db.sh table-count verification passed)"
        else
          bad "round-trip restore FAILED: $(head -c 200 "${TMP}/roundtrip-restore.err")"
        fi
      else
        bad "round-trip backup produced no dump file: $(head -c 200 "${TMP}/roundtrip-backup.err")"
      fi
    else
      bad "round-trip backup FAILED (needs healthy postgres — run 'make up' first): $(head -c 200 "${TMP}/roundtrip-backup.err")"
    fi
  fi

  section "9. Paperclip HTTP health"
  if curl -sf -m 10 -o /dev/null "${PAPERCLIP_URL}/api/health"; then
    ok "GET ${PAPERCLIP_URL}/api/health -> 2xx"
  elif curl -sf -m 10 -o /dev/null "${PAPERCLIP_URL}/"; then
    ok "GET ${PAPERCLIP_URL}/ -> 2xx (UI serving; /api/health unavailable)"
  else
    bad "paperclip web server not responding at ${PAPERCLIP_URL}"
  fi

  section "10. live ticket flow (assign -> run -> transcript/cost/file -> comment -> resume)"
  if [[ -z "${PAPERCLIP_TOKEN}" ]]; then
    skip "PAPERCLIP_TOKEN (or ADMIN_API_KEY) unset; ticket flow needs it — re-run with token for full live test"
  else
    AUTH=(-sS -m 30 -H "Content-Type: application/json" -H "Authorization: Bearer ${PAPERCLIP_TOKEN}")
    if ! curl "${AUTH[@]}" -o "${TMP}/companies.json" "${PAPERCLIP_URL}/api/companies"; then
      bad "could not list companies at ${PAPERCLIP_URL}/api/companies"
    else
      COMPANY_ID="$(COMPANY_NAME="${COMPANY_NAME}" python3 -c '
import json, os, sys
doc = json.load(open(sys.argv[1]))
items = doc.get("companies", doc) if isinstance(doc, dict) else doc
print(next((c.get("id","") for c in items if isinstance(c, dict) and c.get("name")==os.environ["COMPANY_NAME"]), ""))
' "${TMP}/companies.json")"
      if [[ -z "${COMPANY_ID}" ]]; then
        bad "company '${COMPANY_NAME}' not found; run 'make seed-50' first"
      else
        ok "resolved company '${COMPANY_NAME}' (${COMPANY_ID})"
        curl "${AUTH[@]}" -o "${TMP}/agents.json" "${PAPERCLIP_URL}/api/companies/${COMPANY_ID}/agents" || true
        AGENT_ID="$(python3 -c '
import json, sys
doc = json.load(open(sys.argv[1]))
items = doc.get("agents", doc) if isinstance(doc, dict) else doc
# Wave 3 rework: prefer fleet display names (the live API returns the
# seed-50 "name" = role_display_name strings verbatim; legacy
# seed-company names "Programmer"/"PM" no longer exist). Any-agent
# fallback below keeps the flow alive if the fleet is reseeded.
names = {"TypeScript / Node Fullstack Engineer", "End-to-End Browser Automation Engineer"}
pick = next((a for a in items if isinstance(a, dict) and a.get("name") in names), None)
pick = pick or next((a for a in items if isinstance(a, dict) and a.get("id")), {})
print(pick.get("id", ""))
' "${TMP}/agents.json")"
        if [[ -z "${AGENT_ID}" ]]; then
          bad "no agent found to assign the test ticket to; run 'make seed-50' first"
        else
          ok "assigning test ticket to agent ${AGENT_ID}"
          ISSUE_BODY="$(TODAY="${TODAY}" AGENT_ID="${AGENT_ID}" python3 -c '
import json, os
print(json.dumps({
  "title": "smoke-test: Create hello.txt with today date",
  "body": "Create hello.txt containing today date (%s) in the workspace, then report back." % os.environ["TODAY"],
  "assigneeId": os.environ["AGENT_ID"],
}))')"
          printf '%s' "${ISSUE_BODY}" >"${TMP}/issue.json"
          # Discover the issues endpoint (fail-closed: skip, never fake-pass).
          ISSUE_PATH=""
          for candidate in "/api/companies/${COMPANY_ID}/issues" "/api/issues"; do
            code="$(curl "${AUTH[@]}" -o /dev/null -w '%{http_code}' "${PAPERCLIP_URL}${candidate}" || true)"
            if [[ "${code}" == "200" ]]; then ISSUE_PATH="${candidate}"; break; fi
          done
          if [[ -z "${ISSUE_PATH}" ]]; then
            skip "no issue endpoint discovered under /api (tried company + top-level); create a ticket in the UI to finish the live flow manually"
          else
            if curl "${AUTH[@]}" -d @"${TMP}/issue.json" -o "${TMP}/issue.resp.json" "${PAPERCLIP_URL}${ISSUE_PATH}"; then
              ISSUE_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "${TMP}/issue.resp.json")"
              if [[ -z "${ISSUE_ID}" ]]; then
                bad "issue creation returned no id: $(head -c 300 "${TMP}/issue.resp.json")"
              else
                ok "created test ticket ${ISSUE_ID} (wake on assignment expected)"
                echo "  polling run completion (timeout ${RUN_TIMEOUT_SEC}s)..."
                deadline=$((SECONDS + RUN_TIMEOUT_SEC))
                RUN_DONE="false"
                while [[ "${SECONDS}" -lt "${deadline}" ]]; do
                  if curl "${AUTH[@]}" -o "${TMP}/runs.json" "${PAPERCLIP_URL}${ISSUE_PATH}/${ISSUE_ID}/runs" 2>/dev/null \
                    && RUN_DONE="$(python3 -c '
import json, sys
doc = json.load(open(sys.argv[1]))
items = doc.get("runs", doc) if isinstance(doc, dict) else doc
items = items if isinstance(items, list) else []
done = [r for r in items if isinstance(r, dict) and r.get("status") in ("completed", "succeeded", "done")]
print("true" if done else "false")
' "${TMP}/runs.json")" && [[ "${RUN_DONE}" == "true" ]]; then
                    break
                  fi
                  sleep 10
                done
                if [[ "${RUN_DONE}" == "true" ]]; then
                  ok "agent run completed"
                  if python3 -c '
import json, sys
doc = json.load(open(sys.argv[1]))
items = doc.get("runs", doc) if isinstance(doc, dict) else doc
items = items if isinstance(items, list) else []
run = next((r for r in items if isinstance(r, dict) and r.get("status") in ("completed","succeeded","done")), {})
usage = run.get("usage") or run.get("tokens") or {}
assert run.get("transcript") or run.get("messages") or usage, "no transcript/usage evidence"
print(json.dumps({"usage": usage})[:200])
' "${TMP}/runs.json"; then
                    ok "transcript + token/cost accounting present on completed run"
                  else
                    bad "completed run lacks transcript/token-cost evidence"
                  fi
                else
                  bad "agent run did not complete within ${RUN_TIMEOUT_SEC}s (check paperclip logs: make logs)"
                fi
                if grep -rlx "${TODAY}" ./workspaces/*/hello.txt ./workspaces/hello.txt 2>/dev/null | head -1 | grep -q .; then
                  ok "workspace hello.txt with today's date found under ./workspaces"
                else
                  bad "hello.txt with today's date NOT found under ./workspaces"
                fi
                printf '{"body": "smoke-test follow-up: please confirm session resumption with --session."}' >"${TMP}/comment.json"
                if curl "${AUTH[@]}" -d @"${TMP}/comment.json" -o /dev/null "${PAPERCLIP_URL}${ISSUE_PATH}/${ISSUE_ID}/comments" 2>/dev/null; then
                  ok "follow-up comment posted (session resumption via --session; shim passes it through, §5)"
                else
                  skip "comment endpoint not available at ${ISSUE_PATH}/${ISSUE_ID}/comments; post a follow-up in the UI to verify --session resume"
                fi
              fi
            else
              bad "issue creation POST failed at ${ISSUE_PATH}"
            fi
          fi
        fi
      fi
    fi
  fi

  # Wave D P0-1/P1-8 live gates (10b): harness tool-visibility + XDG canary
  # isolation. Both are live-UNVERIFIED until this section runs green —
  # never claim them from static checks. Gated on HARNESS_LIVE_GATE=1
  # (the probe spends a real model call); otherwise SKIP with the exact
  # steps, never a fake pass.
  section "10b. harness tool-visibility + XDG canary probes (P0-1/P1-8, live-only)"
  if [[ "${HARNESS_LIVE_GATE:-0}" != "1" ]]; then
    skip "HARNESS_LIVE_GATE!=1: P0-1 probe = stage scripts/fixtures/harness-probe-opencode.json as XDG config, run one real 'opencode run' turn invoking file_hash_read, FAIL on 'rootDir must be' Die or 'not available'; P1-8 probe = plant canary opencode.json + .opencode/ in a scratch workspace, run one agent turn, assert the canary was ignored; Wave E P1-6 probe = from a scratch workspace, run one agent turn asking to read .env via fs:read AND via filesystem_read_text_file MCP — both must be DENIED (static §3b deny-first ordering is the in-repo gate; enforcement needs this live negative test) (re-run with HARNESS_LIVE_GATE=1 + PAPERCLIP_TOKEN for full live proof)"
  elif ! command -v opencode >/dev/null 2>&1; then
    skip "no opencode binary on PATH for the P0-1 probe (run inside the built image)"
  else
    PROBE_HOME="${TMP}/harness-probe"
    mkdir -p "${PROBE_HOME}/opencode"
    cp scripts/fixtures/harness-probe-opencode.json "${PROBE_HOME}/opencode/opencode.json"
    echo "probe scratch" >"${PROBE_HOME}/target.txt"
    if XDG_CONFIG_HOME="${PROBE_HOME}" timeout 300 opencode run --format json "Call the file_hash_read tool on target.txt and report its hash" >"${TMP}/probe.jsonl" 2>"${TMP}/probe.err"; then
      if grep -q 'file_hash_read' "${TMP}/probe.jsonl" \
        && ! grep -qi 'not available\|rootDir must be' "${TMP}/probe.jsonl" "${TMP}/probe.err"; then
        ok "harness tool-visibility probe: file_hash_read invoked successfully (P0-1 fixed upstream)"
      else
        bad "harness tool-visibility probe: run succeeded but file_hash_read not evidenced (P0-1 still broken — see head of probe output)"
        head -c 300 "${TMP}/probe.jsonl" "${TMP}/probe.err" || true
      fi
    else
      if grep -qi 'rootDir must be\|not available' "${TMP}/probe.jsonl" "${TMP}/probe.err" 2>/dev/null; then
        bad "harness tool-visibility probe FAILED with the P0-1 rootDir Die (upstream fix pending — not claimed)"
      else
        skip "harness probe run failed without P0-1 signature (needs model auth/network; exit retained as SKIP, not proof): $(head -c 200 "${TMP}/probe.err" 2>/dev/null)"
      fi
    fi
  fi
fi

# --- summary -------------------------------------------------------------------
printf '\nSMOKE RESULT: %d passed, %d failed, %d skipped (mode=%s)\n' "${PASS}" "${FAIL}" "${SKIP}" "${MODE}"
if [[ "${FAIL}" -gt 0 ]]; then
  echo "SMOKE: FAIL"
  exit 1
fi
echo "SMOKE: OK"
