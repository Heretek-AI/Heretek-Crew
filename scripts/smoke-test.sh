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
#                       seed-50-fleet.sh (1 company + 50 agents =
#                       51 payloads, fleet total == cap with no WARNING)
#                    5. shim translation: --dir stripped, --variant merged into
#                       --model#variant, exactly one --auto, --session and
#                       non-run subcommands pass through, `--` terminator kept
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
# statically. HARNESS_MANIFEST in §3b pins the 14 tools registered by
# @heretek-ai/opencode-harness@1.0.7 (enumerated empirically via
# `npm pack` + dist/index.js EXTENDED_HARNESS_TOOL_NAMES — the live
# setupOpenCodeV2Harness path registers all 14): every role that declares
# the harness plugin must allow exactly that set (per-tool allows, no
# `harness_*` allow) and carry a `harness_*` deny tail. A bump of the
# harness version requires re-enumeration + manifest update here.
# Live tool-registration (the runtime actually exposing those tools to an
# agent run) is still asserted only by a live agent run invoking a harness
# tool (tracked; needs `make up` + seeded fleet).
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
SMOKE_DUMMY_ENV=(POSTGRES_PASSWORD=__smoke_only__ BETTER_AUTH_SECRET=__smoke_only_0123456789abcdef__ POSTGRES_READER_PASSWORD=__smoke_only__ POSTGRES_READONLY_URL=postgres://paperclip_reader:__smoke_only__@postgres:5432/paperclip GITHUB_TOKEN=__smoke_only__ KUBECONFIG_READONLY_PATH=./secrets/.gitkeep REDIS_PASSWORD=__smoke_only__ QDRANT_API_KEY=__smoke_only__ SEARXNG_SECRET=__smoke_only__ FIRECRAWL_DB_PASSWORD=__smoke_only__ BROWSERLESS_TOKEN=__smoke_only__ NEO4J_PASSWORD=__smoke_only__ LITELLM_MASTER_KEY=__smoke_only__ MINIO_ROOT_USER=__smoke_only__ MINIO_ROOT_PASSWORD=__smoke_only__)
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
    docker compose config 2>/dev/null | grep -A 3 'target: /paperclip/secrets/kubeconfig-readonly' | grep -q 'read_only: true'; then
    ok "kubeconfig read-only volume renders (/paperclip/secrets/kubeconfig-readonly:ro)"
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
fi

# --- 3. role configs valid + pins -------------------------------------------
# Dynamically discovers every role directory under roles/ (the fleet —
# 51 roles incl. ai-red-teamer — never a hardcoded list), then per role
# asserts: valid v2
# opencode.json (provider/model, non-empty permissions with a fail-closed
# deny tail, non-empty rules where present), exact-pinned MCP commands
# (npx pkg@x.y.z / uvx pkg==x.y.z in the fleet `mcp.servers` shape; sole
# tracked exception @morluto/rea-mcp), and non-empty AGENTS.md +
# .opencode/agents/<role>.md charters.
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
# P1-7: every npx/uvx MCP command must carry an exact pin (npx pkg@x.y.z,
# uvx pkg==x.y.z). Sole tracked exception: npx -y @morluto/rea-mcp, which
# is not published on npm (registry 404) — any OTHER unpinned package, or
# any drift in the exception itself, FAILs closed.
if ROLE_PIN_TMP="${TMP}" python3 -c '
import glob, json, os, sys

EXCEPTIONS = {"npx -y @morluto/rea-mcp"}
violations = []
seen_exception = set()
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
                    if "npx -y %s" % pkg in EXCEPTIONS:
                        seen_exception.add(pkg)
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
if set(seen_exception) != {"@morluto/rea-mcp"}:
    violations.append("tracked rea-mcp exception drifted (seen=%r)" % sorted(seen_exception))
if violations:
    sys.exit("\n".join(violations))
print("all npx (pkg@ver) + uvx (pkg==ver) pinned; sole exception @morluto/rea-mcp tracked")
' >"${TMP}/pins.out" 2>"${TMP}/pins.err"; then
  ok "MCP supply chain pinned ($(cat "${TMP}/pins.out"))"
else
  bad "unpinned MCP package(s): $(head -c 400 "${TMP}/pins.err")"
fi
if grep -rnE ':(latest)([^a-zA-Z0-9._-]|$)|@(latest)([^a-zA-Z0-9._-]|$)|npm install[^@]*opencode[^@]*$' \
    docker-compose.yml docker-compose.prebuilt.yml docker-compose.override.yml.example docker/Dockerfile .env.example Makefile 2>/dev/null | grep -v '^.*#.*latest' | grep -q .; then
  bad "found ':latest' style pin in ops files (must pin exact versions)"
else
  ok "no :latest pins in docker-compose.yml / prebuilt overrides / Dockerfile / .env.example / Makefile"
fi
# Wave 3 P1-9: the prebuilt pin is the semver form :1.0.0 (NOT :v1.0.0 —
# the publish workflow's metadata-action semver on refs/tags/v* mints
# 1.0.0/1.0/latest/sha-* and NEVER :v1.0.0, so the old pin was
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
for pin in 'postgres:17-alpine' 'node:24-trixie-slim' '@opencode/cli@2.0.32' '127.0.0.1:3100'; do
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

# --- 3b. permission deny enforcement (static denied-tool simulation) -----------
# Simulates the denied-tool probe: asserts no role carries a bare
# allow-all, every role ends in an explicit shell deny, the seed payload
# requests permission enforcement (skip=False), and the socket proxy
# denies POST.
section "3b. permission deny enforcement (static)"
# Wave 3 P1-11: single fleet dialect — no bare allow-all may exist in ANY
# role (the old programmer-specific probe generalized after the 6 legacy
# roles were deleted as superseded). §3 already asserts each file's
# terminal deny tail; this gate additionally scans all 50 for allow-all.
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
# registry tarball @heretek-ai/opencode-harness@1.0.7 (dist/index.js
# EXTENDED_HARNESS_TOOL_NAMES — the live setupOpenCodeV2Harness path
# registers all 14): any role declaring the harness plugin must allow
# exactly this set (per-tool allows, NEVER a `harness_*` allow) and end
# the namespace with a `harness_*` deny tail (future manifest additions
# stay denied until explicitly allowed here). Roles without the plugin
# must carry no harness allows at all.
HARNESS_MANIFEST="file_hash_read file_hash_edit ast_structural_search ast_structural_rewrite ui_geometry_audit repo_map blast_radius file_outline symbol_references rename_symbol verify_scoped architecture_audit checkpoint_create checkpoint_rollback"
if HARNESS_MANIFEST="${HARNESS_MANIFEST}" python3 -c '
import glob, json, os, sys
manifest = os.environ["HARNESS_MANIFEST"].split()
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
        if allows != sorted(manifest):
            problems.append("%s: harness allows != manifest (got %s)" % (role, allows))
        if not deny_tail:
            problems.append("%s: missing harness_* deny tail" % role)
    elif allows:
        problems.append("%s: harness allows without the harness plugin" % role)
if problems:
    sys.exit("; ".join(problems))
print("fleet roles allow exactly the 14-tool manifest + deny tail")
' >"${TMP}/harness.out" 2>"${TMP}/harness.err"; then
  ok "harness manifest enforced ($(cat "${TMP}/harness.out"))"
else
  bad "harness manifest VIOLATION: $(head -c 400 "${TMP}/harness.err")"
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
    if [[ "${SEED50_NAMES}" -eq 51 ]] \
      && grep -q 'Heretek Autonomous Fleet' "${TMP}/seed50.out" \
      && grep -q 'opencode_local' "${TMP}/seed50.out" \
      && grep -q 'XDG_CONFIG_HOME' "${TMP}/seed50.out" \
      && grep -q 'OPENCODE_DISABLE_PROJECT_CONFIG' "${TMP}/seed50.out" \
      && grep -q 'dangerouslySkipPermissions' "${TMP}/seed50.out" \
      && grep -q 'total fleet budget' "${TMP}/seed50.out" \
      && [[ -n "${SEED50_TOTAL}" && "${SEED50_TOTAL}" == "${SEED50_CAP}" ]] \
      && ! grep -q 'WARNING' "${TMP}/seed50.err"; then
      ok "seed-50 dry-run emits 51 payloads (1 company + 50 agents: opencode_local, XDG_CONFIG_HOME, OPENCODE_DISABLE_PROJECT_CONFIG, skipPermissions, budget total ${SEED50_TOTAL} == cap, no WARNING)"
    else
      bad "seed-50 dry-run output unexpected (name keys=${SEED50_NAMES}, want 51 with fleet payload keys + total==cap and no WARNING)"
    fi
  else
    bad "seed-50 dry-run exited nonzero: $(head -c 300 "${TMP}/seed50.err")"
  fi
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
if shim_run run --format json --dir /tmp/ws --model opencode/gemini-3.8-flash --variant high "Create hello.txt"; then
  if diff -u <(printf 'run\n--format\njson\n--model\nopencode/gemini-3.8-flash#high\n--auto\nCreate hello.txt\n') "${TMP}/shim.args" >/dev/null; then
    ok "run: --dir stripped, --variant merged to model#variant, --auto injected in order"
  else
    bad "run translation mismatch; got: $(tr '\n' ' ' <"${TMP}/shim.args")"
  fi
else
  bad "shim run invocation failed"
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
if OPENCODE_REAL_BIN=/nonexistent ./scripts/opencode-shim.sh run "x" 2>/dev/null; then
  bad "shim with missing real binary should fail closed"
else
  ok "shim fail-closed when real binary is missing"
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
else
  section "8. PostgreSQL health"
  if docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"; then
    ok "postgres pg_isready accepting connections"
  else
    bad "postgres not healthy (run 'make up' and wait for healthcheck)"
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
fi

# --- summary -------------------------------------------------------------------
printf '\nSMOKE RESULT: %d passed, %d failed, %d skipped (mode=%s)\n' "${PASS}" "${FAIL}" "${SKIP}" "${MODE}"
if [[ "${FAIL}" -gt 0 ]]; then
  echo "SMOKE: FAIL"
  exit 1
fi
echo "SMOKE: OK"
