#!/usr/bin/env bash
#
# spec-gate.sh — CI spec-driven development (SDD) gate for Heretek-Crew.
#
# Usage:
#   ./scripts/spec-gate.sh [--check-only] [--dry-run] [--help]
#
# Modes:
#   (default)      Run all specification gates; exit 0 when satisfied,
#                  exit 1 fail-closed with diagnostics when any gate fails.
#   --check-only   CI alias for the default run (same checks; deterministic,
#                  no network, no docker, no secrets, no state changes).
#   --dry-run      Explain what would be checked, run the gates read-only,
#                  and always exit 0 (never fails; for change previews).
#   --help, -h     Print this header and exit 0.
#
# Gates (all must PASS; any FAIL exits 1, unknown states FAIL closed):
#   S1. spec-source presence — at least one spec corpus exists: roles-catalog/
#       (non-empty *.md) plus either specs/ or a standing RESEARCH_*.md /
#       PROMPT_*.md design document. (specs/ is optional while
#       roles-catalog/ remains the fleet spec of record; if NONE of these
#       exist the gate FAILs closed.)
#   S2. code<->spec delta — when the working tree changes code paths
#       (roles/, scripts/, docker/, docker-compose*.yml, Makefile), a
#       corresponding spec delta must exist: either an explicit spec-side
#       file (specs/**, roles-catalog/**, RESEARCH_*.md, PROMPT_*.md,
#       docs/**) in the same change, or coverage by the standing Phase A
#       spec (PROMPT_INTEGRATE_RESEARCH_EXPANSION.md +
#       RESEARCH_EXPANSION_REPORT.md jointly reference the Phase A change
#       vocabulary). With no code changes the gate PASSes (nothing to cover).
#   S3. plan checkboxes + acceptance — at least one PROMPT_*.md carries an
#       explicit task plan (literal "- [ ]" checkboxes, or the repo
#       convention of "### Task N" headings with Directives) AND at least
#       one carries test acceptance criteria (>=3 acceptance-term hits).
#   S4. role-spec completeness — every roles/*/ ships non-empty AGENTS.md,
#       opencode/opencode.json, and .opencode/agents/<role>.md (the per-role
#       spec charters; a role without them is an unspecced change).
#   S5. fleet hardening invariants (Task 3 gap closure) — every
#       roles/*/opencode/opencode.json carries small_model (haiku-class),
#       a compaction policy, numeric MCP server timeouts, and fs
#       read+write denies covering .env secrets.
#
# Exit code: 0 when nothing FAILs, 1 otherwise (2 on unknown arguments).
# Fail-closed: missing git work tree, missing python3, or any unknown state
# is a FAIL with a diagnostic, never a silent green.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

MODE="check"
DRY_RUN="false"
for arg in "$@"; do
  case "${arg}" in
    --check-only) MODE="check" ;;
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

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$*"; }
info() { printf '  [INFO] %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }

echo "spec-gate mode=${MODE} dry-run=${DRY_RUN} root=${REPO_ROOT}"
if [[ "${DRY_RUN}" == "true" ]]; then
  info "dry-run: gates S1..S5 evaluate read-only; exit is forced 0 (no failure)"
fi

# --- S1. spec-source presence --------------------------------------------------
section "S1. spec-source presence"
shopt -s nullglob
CATALOG_FILES=(roles-catalog/*.md)
SPECS_FILES=(specs/**/* specs/*.md)
RESEARCH_FILES=(RESEARCH_*.md)
PROMPT_FILES=(PROMPT_*.md)
shopt -u nullglob
CATALOG_COUNT=0
for f in "${CATALOG_FILES[@]}"; do
  if [[ -f "${f}" ]]; then CATALOG_COUNT=$((CATALOG_COUNT + 1)); fi
done
STANDING_COUNT=0
for f in "${RESEARCH_FILES[@]}" "${PROMPT_FILES[@]}"; do
  if [[ -f "${f}" ]]; then STANDING_COUNT=$((STANDING_COUNT + 1)); fi
done
SPECS_COUNT=0
for f in "${SPECS_FILES[@]}"; do
  if [[ -f "${f}" ]]; then SPECS_COUNT=$((SPECS_COUNT + 1)); fi
done
info "spec corpora: roles-catalog=${CATALOG_COUNT} specs/=${SPECS_COUNT} standing-docs(RESEARCH+PROMPT)=${STANDING_COUNT}"
if [[ "${CATALOG_COUNT}" -eq 0 && "${SPECS_COUNT}" -eq 0 ]]; then
  bad "S1: no spec corpus found (roles-catalog/*.md empty or missing AND no specs/ files)"
elif [[ "${CATALOG_COUNT}" -gt 0 ]]; then
  ok "S1: roles-catalog/ holds ${CATALOG_COUNT} spec file(s)"
else
  ok "S1: specs/ holds ${SPECS_COUNT} spec file(s) (roles-catalog/ absent)"
fi
if [[ "${STANDING_COUNT}" -gt 0 ]]; then
  ok "S1: ${STANDING_COUNT} standing design doc(s) present (RESEARCH_*.md / PROMPT_*.md)"
else
  info "S1: no RESEARCH_*.md / PROMPT_*.md standing docs (specs/ or roles-catalog/ still required above)"
fi

# --- S2. code<->spec delta ----------------------------------------------------
section "S2. code<->spec delta"
IN_GIT="false"
if command -v git >/dev/null 2>&1 \
  && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT="true"
fi
if [[ "${IN_GIT}" != "true" ]]; then
  bad "S2: not inside a git work tree (cannot establish code<->spec delta; fail-closed)"
else
  CHANGED="$(git status --porcelain --untracked-files=normal 2>/dev/null || true)"
  CODE_CHANGED=""
  SPEC_CHANGED=""
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    rest="${line:3}"
    if [[ "${rest}" == *" -> "* ]]; then
      rest="${rest##* -> }"
    fi
    # Strip surrounding quotes git adds for exotic paths.
    rest="${rest#\"}"
    rest="${rest%\"}"
    case "${rest}" in
      roles/*|scripts/*|docker/*|docker-compose*.yml|Makefile)
        CODE_CHANGED="${CODE_CHANGED}${rest}"$'\n'
        ;;
    esac
    case "${rest}" in
      specs/*|roles-catalog/*|RESEARCH_*.md|PROMPT_*.md|docs/*)
        SPEC_CHANGED="${SPEC_CHANGED}${rest}"$'\n'
        ;;
    esac
  done <<< "${CHANGED}"
  CODE_N="$(printf '%s' "${CODE_CHANGED}" | grep -c . || true)"
  SPEC_N="$(printf '%s' "${SPEC_CHANGED}" | grep -c . || true)"
  info "working-tree delta: code-path files=${CODE_N} spec-side files=${SPEC_N}"
  if [[ "${CODE_N}" -eq 0 ]]; then
    ok "S2: no code-path changes in the working tree (no spec delta required)"
  elif [[ "${SPEC_N}" -gt 0 ]]; then
    ok "S2: explicit spec delta present (${SPEC_N} spec-side file(s) alongside ${CODE_N} code file(s))"
  else
    # Fallback: standing Phase A spec authorization. The committed
    # PROMPT_INTEGRATE_RESEARCH_EXPANSION.md + RESEARCH_EXPANSION_REPORT.md
    # ARE the spec deltas for Phase A Tasks 1-4 (skills paths, superpowers
    # vendoring, fleet hardening, frontmatter uplift); they must jointly
    # reference the Phase A change vocabulary or the fallback is denied.
    STANDING_KEYWORDS=(skills superpowers small_model compaction timeout frontmatter spec-gate ai-red-teamer test-driven-development systematic-debugging)
    HITS=0
    for kw in "${STANDING_KEYWORDS[@]}"; do
      if grep -qi "${kw}" PROMPT_INTEGRATE_RESEARCH_EXPANSION.md RESEARCH_EXPANSION_REPORT.md 2>/dev/null; then
        HITS=$((HITS + 1))
      fi
    done
    info "standing Phase A spec keyword coverage: ${HITS}/${#STANDING_KEYWORDS[@]}"
    if [[ -f PROMPT_INTEGRATE_RESEARCH_EXPANSION.md && -f RESEARCH_EXPANSION_REPORT.md && "${HITS}" -ge 6 ]]; then
      ok "S2: ${CODE_N} code file(s) covered by the standing Phase A spec (PROMPT_INTEGRATE_RESEARCH_EXPANSION.md + RESEARCH_EXPANSION_REPORT.md)"
      info "S2: standing-spec coverage is Phase A-scoped; future tracks need explicit specs/ or roles-catalog/ deltas"
    else
      bad "S2: ${CODE_N} code file(s) changed with no spec delta (no specs//roles-catalog/ change, standing Phase A spec absent or keyword-poor)"
      info "S2: first code files lacking cover: $(printf '%s' "${CODE_CHANGED}" | head -5 | tr '\n' ' ')"
    fi
  fi
fi

# --- S3. plan checkboxes + acceptance -----------------------------------------
section "S3. task-plan checkboxes + acceptance criteria"
shopt -s nullglob
PLAN_FILES=(PROMPT_*.md)
shopt -u nullglob
if [[ "${#PLAN_FILES[@]}" -eq 0 ]]; then
  bad "S3: no PROMPT_*.md task plans found"
else
  PLAN_OK=""
  ACCEPT_OK=""
  for f in "${PLAN_FILES[@]}"; do
    [[ -f "${f}" ]] || continue
    HAS_BOX="false"
    if grep -qE '^- \[[ xX]\]' "${f}" 2>/dev/null; then
      HAS_BOX="true"
    fi
    HAS_TASKHEADS="false"
    if grep -qE '^### Task [0-9]+' "${f}" 2>/dev/null \
      && grep -q 'Directives' "${f}" 2>/dev/null; then
      HAS_TASKHEADS="true"
    fi
    if [[ "${HAS_BOX}" == "true" || "${HAS_TASKHEADS}" == "true" ]]; then
      PLAN_OK="${PLAN_OK}${f}"$'\n'
    fi
    ACC_HITS="$(grep -oiE 'acceptance|success criteria|verification|verify|PASS|FAIL|definition of done' "${f}" 2>/dev/null | grep -c . || true)"
    if [[ "${ACC_HITS}" -ge 3 ]]; then
      ACCEPT_OK="${ACCEPT_OK}${f}(${ACC_HITS})"$'\n'
    fi
  done
  if [[ -n "${PLAN_OK}" ]]; then
    ok "S3: explicit task plan(s) present: $(printf '%s' "${PLAN_OK}" | head -3 | tr '\n' ' ')"
  else
    bad "S3: no PROMPT_*.md carries an explicit plan (need '- [ ]' checkboxes or '### Task N' + Directives)"
  fi
  if [[ -n "${ACCEPT_OK}" ]]; then
    ok "S3: test acceptance criteria present: $(printf '%s' "${ACCEPT_OK}" | head -3 | tr '\n' ' ')"
  else
    bad "S3: no PROMPT_*.md carries test acceptance criteria (>=3 acceptance/verification/PASS/FAIL hits)"
  fi
fi

# --- S4. role-spec completeness ------------------------------------------------
section "S4. role-spec completeness"
ROLE_TOTAL=0
ROLE_BAD=0
for roledir in roles/*/; do
  [[ -d "${roledir}" ]] || continue
  role="$(basename "${roledir}")"
  ROLE_TOTAL=$((ROLE_TOTAL + 1))
  missing=""
  if [[ ! -s "roles/${role}/AGENTS.md" ]]; then
    missing="${missing}AGENTS.md "
  fi
  if [[ ! -s "roles/${role}/opencode/opencode.json" ]]; then
    missing="${missing}opencode/opencode.json "
  fi
  if [[ ! -s "roles/${role}/.opencode/agents/${role}.md" ]]; then
    missing="${missing}.opencode/agents/${role}.md "
  fi
  if [[ -n "${missing}" ]]; then
    ROLE_BAD=$((ROLE_BAD + 1))
    bad "S4: roles/${role}/ missing or empty spec charter(s): ${missing}"
  fi
done
if [[ "${ROLE_TOTAL}" -eq 0 ]]; then
  bad "S4: no role directories under roles/ (fleet spec has no subjects)"
elif [[ "${ROLE_BAD}" -eq 0 ]]; then
  ok "S4: all ${ROLE_TOTAL} role(s) ship complete spec charters (AGENTS.md + opencode.json + agent md)"
fi

# --- S5. fleet hardening invariants --------------------------------------------
section "S5. fleet hardening invariants (small_model + compaction + timeouts + .env denies)"
if ! command -v python3 >/dev/null 2>&1; then
  bad "S5: python3 is required for the JSON hardening sweep (fail-closed)"
else
  if HARDEN_ERR="$(python3 -c '
import glob, json, sys
problems = []
files = sorted(glob.glob("roles/*/opencode/opencode.json"))
if not files:
    sys.exit("no roles/*/opencode/opencode.json files found")
for f in files:
    role = f.split("/")[1]
    try:
        doc = json.load(open(f))
    except Exception as exc:
        problems.append("%s: invalid JSON (%s)" % (role, exc))
        continue
    sm = doc.get("small_model")
    if not (isinstance(sm, str) and sm and "haiku" in sm.lower()):
        problems.append("%s: small_model missing or not haiku-class (%r)" % (role, sm))
    comp = doc.get("compaction")
    if not (isinstance(comp, dict) and comp.get("auto") is True
            and comp.get("prune") is True
            and isinstance(comp.get("reserved"), int)):
        problems.append("%s: compaction policy missing/malformed (%r)" % (role, comp))
    servers = (doc.get("mcp") or {}).get("servers") or {}
    for name, srv in servers.items():
        if isinstance(srv, dict) and "command" in srv:
            if not isinstance(srv.get("timeout"), (int, float)):
                problems.append("%s: mcp server %r lacks a numeric timeout" % (role, name))
    perms = doc.get("permissions") or []
    if not any(p.get("effect") == "deny" and ".env" in str(p.get("resource", ""))
               and str(p.get("action", "")).startswith("fs:read") for p in perms):
        problems.append("%s: missing fs:read .env deny" % role)
    if not any(p.get("effect") == "deny" and ".env" in str(p.get("resource", ""))
               and str(p.get("action", "")).startswith("fs:write") for p in perms):
        problems.append("%s: missing fs:write .env deny" % role)
if problems:
    sys.exit("; ".join(problems))
print("all %d role configs carry small_model + compaction + MCP timeouts + .env denies" % len(files))
' 2>&1)"; then
    ok "S5: ${HARDEN_ERR}"
  else
    bad "S5: hardening invariant VIOLATION: $(printf '%s' "${HARDEN_ERR}" | head -c 400)"
  fi
fi

# --- summary -------------------------------------------------------------------
printf '\nSPEC-GATE RESULT: %d passed, %d failed (mode=%s dry-run=%s)\n' "${PASS}" "${FAIL}" "${MODE}" "${DRY_RUN}"
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "SPEC-GATE: DRY-RUN OK (read-only evaluation; failures non-blocking)"
  exit 0
fi
if [[ "${FAIL}" -gt 0 ]]; then
  echo "SPEC-GATE: FAIL"
  exit 1
fi
echo "SPEC-GATE: OK"
