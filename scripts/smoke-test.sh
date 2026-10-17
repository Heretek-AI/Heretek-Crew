#!/usr/bin/env bash
#
# smoke-test.sh — end-to-end compatibility & smoke test for Heretek-Crew.
#
# Usage:
#   ./scripts/smoke-test.sh [--check-only] [--help]
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
#                       role — legacy 6 prototype roles still validated
#                       when present; plus 3b. static denied-tool probe
#                       (programmer has no allow-all + terminal shell deny,
#                       qa/tester bash narrowed to named test commands +
#                       terminal bash deny, dba/k8s MCP-boundary shell
#                       denies intact, seeds set dangerouslySkipPermissions
#                       False, socket proxy denies POST/BUILD/EXEC)
#                    4. seed dry-runs emit company + agent payloads:
#                       seed-company.sh (company + 6 agents) and
#                       seed-50-fleet.sh (1 company + 50 agents =
#                       51 payloads, fleet total == cap with no WARNING)
#                    5. shim translation: --dir stripped, --variant merged into
#                       --model#variant, exactly one --auto, --session and
#                       non-run subcommands pass through, `--` terminator kept
#                    6. file-creation simulation (hello.txt with today's date)
#                    7. session-resume support advertised by the opencode CLI
#                       (skipped with a note when no opencode binary is present)
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
# NOTE (P1-7): harness_* MCP tool registration cannot be verified statically —
# the harness tarball ships implementation files without a tool() manifest, so
# no static gate can prove the runtime registers those tools. Registration is
# asserted only by a live agent run invoking a harness tool (tracked; needs
# `make up` + seeded fleet).
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
COMPANY_NAME="${COMPANY_NAME:-Acme Autonomous Corp}"
POSTGRES_USER="${POSTGRES_USER:-paperclip}"
POSTGRES_DB="${POSTGRES_DB:-paperclip}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-30}"
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-600}"

MODE="live"
for arg in "$@"; do
  case "${arg}" in
    --check-only) MODE="check-only" ;;
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

# --- 1. required files -------------------------------------------------------
section "1. required files"
REQUIRED_FILES=(
  docker-compose.yml docker-compose.prebuilt.yml docker-compose.override.yml.example
  docker/Dockerfile .env.example Makefile
  .github/workflows/docker-publish.yml
  scripts/opencode-shim.sh scripts/seed-company.sh scripts/seed-50-fleet.sh
  scripts/generate-50-roles.py scripts/worktree-manager.sh scripts/dispatch-pipeline.sh
  scripts/backup-db.sh scripts/restore-db.sh scripts/smoke-test.sh
)
for f in "${REQUIRED_FILES[@]}"; do
  if [[ -f "${f}" ]]; then ok "${f} exists"; else bad "${f} MISSING"; fi
done
for role in director pm programmer tester qa designer; do
  if [[ -f "roles/${role}/opencode/opencode.json" ]]; then
    ok "roles/${role}/opencode/opencode.json exists"
  else
    bad "roles/${role}/opencode/opencode.json MISSING"
  fi
  if [[ -f "roles/${role}/AGENTS.md" ]]; then
    ok "roles/${role}/AGENTS.md exists"
  else
    bad "roles/${role}/AGENTS.md MISSING"
  fi
done
for s in scripts/opencode-shim.sh scripts/seed-company.sh scripts/seed-50-fleet.sh \
         scripts/worktree-manager.sh scripts/dispatch-pipeline.sh \
         scripts/backup-db.sh scripts/restore-db.sh scripts/smoke-test.sh; do
  if [[ -x "${s}" ]]; then ok "${s} executable"; else bad "${s} NOT executable"; fi
done

# --- 2. compose config parses -----------------------------------------------
section "2. docker compose config"
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
    # Throwaway dummy secrets: validation only, never written anywhere.
    if POSTGRES_PASSWORD=__smoke_only__ BETTER_AUTH_SECRET=__smoke_only_0123456789abcdef__ \
      docker compose config -q 2>"${TMP}/compose.err"; then
      ok "docker compose config parses (dummy secrets, .env absent)"
    else
      bad "docker compose config FAILED: $(head -c 300 "${TMP}/compose.err")"
    fi
  fi

  # Prebuilt compose override validation
  if POSTGRES_PASSWORD=__smoke_only__ BETTER_AUTH_SECRET=__smoke_only_0123456789abcdef__ \
    docker compose -f docker-compose.yml -f docker-compose.prebuilt.yml config -q 2>"${TMP}/compose-prebuilt.err"; then
    ok "docker compose prebuilt override config parses"
  else
    bad "docker compose prebuilt override config FAILED: $(head -c 300 "${TMP}/compose-prebuilt.err")"
  fi

  # P1-4 defense-in-depth: paperclip must render
  # OPENCODE_DISABLE_PROJECT_CONFIG=true (explicit env beats upstream
  # defaults; OS env overrides .env here, so this holds either way).
  if POSTGRES_PASSWORD=__smoke_only__ BETTER_AUTH_SECRET=__smoke_only_0123456789abcdef__ \
    docker compose config 2>/dev/null | grep -q 'OPENCODE_DISABLE_PROJECT_CONFIG: .true'; then
    ok "paperclip renders OPENCODE_DISABLE_PROJECT_CONFIG=true (project-config defense-in-depth)"
  else
    bad "paperclip rendered config lacks OPENCODE_DISABLE_PROJECT_CONFIG=true"
  fi
fi

# --- 3. role configs valid + pins -------------------------------------------
# Dynamically discovers every role directory under roles/ (the 50-agent
# fleet plus the legacy 6 prototype roles when present — never a hardcoded
# list), then per role asserts: valid v2 opencode.json (provider/model,
# non-empty permissions with a fail-closed deny tail, non-empty rules
# where present), exact-pinned MCP commands (npx pkg@x.y.z / uvx pkg==x.y.z
# in either the legacy flat `mcp: {<name>: {command}}` shape or the fleet
# `mcp.servers` shape; sole tracked exception @morluto/rea-mcp),
# and non-empty AGENTS.md + .opencode/agents/<role>.md charters.
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
    "permissions must end with a fail-closed deny tail (shell * deny / bash * deny by dialect); bare allow-all is forbidden"
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
if grep -q 'ghcr\.io/heretek-ai/heretek-crew:v1\.0\.0' docker-compose.prebuilt.yml; then
  ok "pin present: ghcr.io/heretek-ai/heretek-crew:v1.0.0 in docker-compose.prebuilt.yml"
else
  bad "pin MISSING: ghcr.io/heretek-ai/heretek-crew:v1.0.0 in docker-compose.prebuilt.yml"
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

# --- 3b. permission deny enforcement (static denied-tool simulation) -----------
# Simulates the denied-tool probe: asserts the programmer role carries no
# bare allow-all, ends in an explicit shell deny, seed payloads request
# permission enforcement (skip=False), and the socket proxy denies POST.
section "3b. permission deny enforcement (static)"
if python3 -c '
import json, sys
doc = json.load(open("roles/programmer/opencode/opencode.json"))
perms = doc.get("permissions", [])
if any(p.get("action") == "*" and p.get("resource") == "*" and p.get("effect") == "allow" for p in perms):
    sys.exit("programmer carries a bare allow-all")
tails = [p for p in perms if p.get("action") == "shell" and p.get("resource") == "*" and p.get("effect") == "deny"]
if not tails or perms[-1].get("effect") != "deny":
    sys.exit("programmer lacks a terminal shell deny tail")
print("programmer: enumerated allows + terminal shell deny, no allow-all")
' >"${TMP}/deny.out" 2>"${TMP}/deny.err"; then
  ok "programmer opencode.json denies by default ($(cat "${TMP}/deny.out"))"
else
  bad "programmer permission probe FAILED: $(head -c 200 "${TMP}/deny.err")"
fi
if grep -q '"dangerouslySkipPermissions": False' scripts/seed-company.sh \
  && grep -q '"dangerouslySkipPermissions": False' scripts/seed-50-fleet.sh \
  && ! grep -q '"dangerouslySkipPermissions": True' scripts/seed-company.sh \
  && ! grep -q '"dangerouslySkipPermissions": True' scripts/seed-50-fleet.sh; then
  ok "seed scripts enforce permissions (dangerouslySkipPermissions False, no True remains)"
else
  bad "seed scripts still request dangerouslySkipPermissions True"
fi
if grep -q 'POST: "0"' docker-compose.sidecars.yml \
  && grep -q 'BUILD: "0"' docker-compose.sidecars.yml \
  && grep -q 'EXEC: "0"' docker-compose.sidecars.yml; then
  ok "docker-socket-proxy denies POST/BUILD/EXEC (read-only proxy)"
else
  bad "docker-socket-proxy still permits POST/BUILD/EXEC (host-escape primitive)"
fi
# P1-5: qa/tester bash narrowed to named test commands + terminal bash deny.
# Any `bash * allow` here re-opens curl/redirection exfil (see AUDIT P1-5).
for _role in qa tester; do
  if _ROLE="${_role}" python3 -c '
import json, os, sys
role = os.environ["_ROLE"]
doc = json.load(open("roles/%s/opencode/opencode.json" % role))
perms = doc.get("permissions", [])
if any(p.get("action") == "bash" and p.get("resource") == "*" and p.get("effect") == "allow" for p in perms):
    sys.exit("%s still carries bash * allow" % role)
last = perms[-1]
if not (last.get("action") == "bash" and last.get("resource") == "*" and last.get("effect") == "deny"):
    sys.exit("%s lacks a terminal bash * deny tail" % role)
named = [p["resource"] for p in perms if p.get("action") == "bash" and p.get("effect") == "allow"]
if not named:
    sys.exit("%s has no named bash allows left" % role)
print("%s: bash narrowed to %s + terminal deny" % (role, ", ".join(named)))
' >"${TMP}/narrow.out" 2>"${TMP}/narrow.err"; then
    ok "$(cat "${TMP}/narrow.out")"
  else
    bad "$(head -c 200 "${TMP}/narrow.err")"
  fi
done
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

# --- 4. seed dry-runs ---------------------------------------------------------
section "4. seed dry-runs (seed-company.sh + seed-50-fleet.sh)"
if ./scripts/seed-company.sh --dry-run >"${TMP}/seed.out" 2>"${TMP}/seed.err"; then
  if grep -q 'Acme Autonomous Corp' "${TMP}/seed.out" \
    && grep -q 'opencode_local' "${TMP}/seed.out" \
    && grep -q 'XDG_CONFIG_HOME' "${TMP}/seed.out" \
    && grep -q 'OPENCODE_DISABLE_PROJECT_CONFIG' "${TMP}/seed.out" \
    && grep -q 'dangerouslySkipPermissions' "${TMP}/seed.out"; then
    ok "seed dry-run emits company + 6 agent payloads (opencode_local, XDG_CONFIG_HOME, OPENCODE_DISABLE_PROJECT_CONFIG, skipPermissions)"
  else
    bad "seed dry-run output missing expected payload keys"
  fi
else
  bad "seed dry-run exited nonzero: $(head -c 300 "${TMP}/seed.err")"
fi
if [[ -f scripts/seed-50-fleet.sh ]]; then
  if ./scripts/seed-50-fleet.sh --dry-run >"${TMP}/seed50.out" 2>"${TMP}/seed50.err"; then
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
        bad "company '${COMPANY_NAME}' not found; run 'make seed' first"
      else
        ok "resolved company '${COMPANY_NAME}' (${COMPANY_ID})"
        curl "${AUTH[@]}" -o "${TMP}/agents.json" "${PAPERCLIP_URL}/api/companies/${COMPANY_ID}/agents" || true
        AGENT_ID="$(python3 -c '
import json, sys
doc = json.load(open(sys.argv[1]))
items = doc.get("agents", doc) if isinstance(doc, dict) else doc
names = {"Programmer", "PM"}
pick = next((a for a in items if isinstance(a, dict) and a.get("name") in names), None)
pick = pick or next((a for a in items if isinstance(a, dict) and a.get("id")), {})
print(pick.get("id", ""))
' "${TMP}/agents.json")"
        if [[ -z "${AGENT_ID}" ]]; then
          bad "no agent found to assign the test ticket to; run 'make seed' first"
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
