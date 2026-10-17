#!/usr/bin/env bash
#
# test-shim.sh — local verification for scripts/opencode-shim.sh.
#
# Builds a fake `opencode-bin` (mock) that records the exact argv it receives,
# optionally relays stdin to stdout, and exits with a controllable code, then
# asserts the shim's translation logic case by case.
#
# Usage: bash scripts/test-shim.sh   (exit 0 = all PASS, exit 1 = any FAIL)
set -euo pipefail

SHIM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/opencode-shim.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "${SANDBOX}"' EXIT

export MOCK_ARGS_FILE="${SANDBOX}/args"
export MOCK_EXIT_CODE="0"
export MOCK_ECHO=""

# Mock real binary: records argv line-by-line, relays stdin (when piped),
# prints a canned stdout line when asked, exits with $MOCK_EXIT_CODE.
cat > "${SANDBOX}/opencode-bin" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${MOCK_ARGS_FILE}"
if [[ ! -t 0 ]]; then
    cat
fi
if [[ -n "${MOCK_ECHO:-}" ]]; then
    printf '%s\n' "${MOCK_ECHO}"
fi
exit "${MOCK_EXIT_CODE:-0}"
MOCK
chmod +x "${SANDBOX}/opencode-bin"
export OPENCODE_REAL_BIN="${SANDBOX}/opencode-bin"

PASS=0
FAIL=0

report() {
    local status="$1"
    shift
    if [[ "${status}" == "PASS" ]]; then
        PASS=$((PASS + 1))
        printf 'PASS: %s\n' "$*"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s\n' "$*"
    fi
}

# assert_args <name> <expected argv...>: run shim with the argv stored in
# RUN_ARGS and compare against the mock's recording, line by line.
RUN_ARGS=()
assert_args() {
    local name="$1"
    shift
    rm -f "${MOCK_ARGS_FILE}"
    "${SHIM}" "${RUN_ARGS[@]}" > "${SANDBOX}/stdout" 2> "${SANDBOX}/stderr"
    local code=$?
    if [[ "${code}" -ne 0 ]]; then
        report FAIL "${name} (shim exited ${code}, stderr: $(cat "${SANDBOX}/stderr"))"
        return
    fi
    local expected
    expected="$(printf '%s\n' "$@")"
    local actual
    actual="$(cat "${MOCK_ARGS_FILE}")"
    if [[ "${actual}" == "${expected}" ]]; then
        report PASS "${name}"
    else
        report FAIL "${name}"
        printf '  expected:\n%s\n' "${expected}" | sed 's/^/    /'
        printf '  actual:\n%s\n' "${actual}" | sed 's/^/    /'
    fi
}

printf '== opencode-shim translation tests ==\n'

# 1. Transparent pass-through for non-run subcommands.
RUN_ARGS=(models)
assert_args "passthrough: models" "models"

RUN_ARGS=(models --json)
assert_args "passthrough: models --json" "models" "--json"

RUN_ARGS=(debug --logs)
assert_args "passthrough: debug subcommand" "debug" "--logs"

RUN_ARGS=(auth login)
assert_args "passthrough: auth subcommand" "auth" "login"

# 2. --dir/--variant must NOT be stripped outside `run`.
RUN_ARGS=(mcp --dir /tmp --variant high)
assert_args "passthrough: flags untouched outside run" "mcp" "--dir" "/tmp" "--variant" "high"

# 3. Space-form --dir with a following non-flag token (Wave B P1-9): the
# token is AMBIGUOUS (path vs prompt) and is PRESERVED — only the flag is
# dropped. A bogus path then errors loudly in the real binary instead of
# the prompt being silently swallowed (Claim 2.1).
RUN_ARGS=(run --format json --dir /tmp prompt)
assert_args "strip: --dir flag dropped, following token preserved (P1-9)" \
    "run" "--auto" "--format" "json" "/tmp" "prompt"

# 4. Strip --dir (equals form).
RUN_ARGS=(run --format json --dir=/tmp prompt)
assert_args "strip: --dir=<path>" "run" "--auto" "--format" "json" "prompt"

# 5. Acceptance example, exact translation (Wave B P1-9: the ambiguous
# --dir value /tmp is preserved in place, not swallowed):
#    run --format json --dir /tmp --model opencode/gemini-3.8-flash --variant high "prompt"
#    -> run --format json /tmp --model opencode/gemini-3.8-flash#high --auto "prompt"
RUN_ARGS=(run --format json --dir /tmp --model opencode/gemini-3.8-flash --variant high prompt)
assert_args "acceptance: variant merge + auto injection (exact order)" \
    "run" "--format" "json" "/tmp" "--model" "opencode/gemini-3.8-flash#high" "--auto" "prompt"

# 6. Order independence: --variant before --model.
RUN_ARGS=(run --variant high --model opencode/gemini-3.8-flash prompt)
assert_args "merge: --variant before --model" \
    "run" "--model" "opencode/gemini-3.8-flash#high" "--auto" "prompt"

# 7. Equals forms for both flags.
RUN_ARGS=(run --model=opencode/gemini-3.8-flash --variant=high prompt)
assert_args "merge: --model= and --variant= forms" \
    "run" "--model=opencode/gemini-3.8-flash#high" "--auto" "prompt"

# 8. Mixed: space --model with equals --variant.
RUN_ARGS=(run --dir=/work --model anthropic/claude-sonnet-4-5 --variant=low prompt)
assert_args "merge: mixed flag forms + dir strip" \
    "run" "--model" "anthropic/claude-sonnet-4-5#low" "--auto" "prompt"

# 8a. Short -m with --variant (variant after model).
RUN_ARGS=(run -m mymodel --variant high prompt)
assert_args "merge: -m <model> + --variant" \
    "run" "-m" "mymodel#high" "--auto" "prompt"

# 8b. Order independence with short -m: --variant before -m.
RUN_ARGS=(run --variant high -m mymodel prompt)
assert_args "merge: --variant before -m" \
    "run" "-m" "mymodel#high" "--auto" "prompt"

# 8c. Equals forms with short -m: -m=value keeps its own prefix.
RUN_ARGS=(run -m=mymodel --variant=high prompt)
assert_args "merge: -m=<model> + --variant= keeps -m= prefix" \
    "run" "-m=mymodel#high" "--auto" "prompt"

# 8d. Model already carrying a variant suffix is not doubled via -m.
RUN_ARGS=(run -m provider/model#custom --variant high prompt)
assert_args "merge: -m existing #variant not doubled" \
    "run" "-m" "provider/model#custom" "--auto" "prompt"

# 8e. Empty --variant= carries no value: dropped, model left untouched.
RUN_ARGS=(run --model mymodel --variant= prompt)
assert_args "merge: empty --variant= dropped, model untouched" \
    "run" "--model" "mymodel" "--auto" "prompt"

# 8f. Duplicate --model: the FIRST occurrence is the effective one (the real
# binary is first-wins — live-probed on v2.0.30 with two bogus providers,
# space and equals forms) and takes the merge; later occurrences pass
# through for the real binary to judge.
RUN_ARGS=(run --model aaa --model bbb --variant high prompt)
assert_args "merge: duplicate --model merges into first (first-wins)" \
    "run" "--model" "aaa#high" "--auto" "--model" "bbb" "prompt"

# 8f2. Duplicate --model in equals form: likewise first-wins.
RUN_ARGS=(run --model=aaa --model=bbb --variant=high prompt)
assert_args "merge: duplicate --model= merges into first (first-wins)" \
    "run" "--model=aaa#high" "--auto" "--model=bbb" "prompt"

# 8g. Mid-argv --dir with no value (next token is a flag): dropped on its
# own, the following flag must survive.
RUN_ARGS=(run --model mymodel --dir --format json prompt)
assert_args "strip: mid-argv valueless --dir does not swallow next flag" \
    "run" "--model" "mymodel" "--auto" "--format" "json" "prompt"

# 9. --auto already present: never duplicated.
RUN_ARGS=(run --format json --model m --auto prompt)
assert_args "auto: not duplicated when present" \
    "run" "--format" "json" "--model" "m" "--auto" "prompt"

RUN_ARGS=(run --auto --format json --model m prompt)
assert_args "auto: leading --auto kept in place" \
    "run" "--auto" "--format" "json" "--model" "m" "prompt"

RUN_ARGS=(run --format json --auto=false --model m prompt)
assert_args "auto: explicit --auto=false respected" \
    "run" "--format" "json" "--auto=false" "--model" "m" "prompt"

# 10. Model already carrying a variant suffix is not double-suffixed.
RUN_ARGS=(run --model provider/model#custom --variant high prompt)
assert_args "merge: existing #variant not doubled" \
    "run" "--model" "provider/model#custom" "--auto" "prompt"

# 11. --variant with no --model is dropped (v2 would reject the flag).
RUN_ARGS=(run --format json --variant high prompt)
assert_args "variant without model: dropped, run still valid" \
    "run" "--auto" "--format" "json" "prompt"

# 12. Session resume flags pass through untouched.
RUN_ARGS=(run --format json --session abc123 --model m prompt)
assert_args "passthrough: --session preserved" \
    "run" "--format" "json" "--session" "abc123" "--model" "m" "--auto" "prompt"

# 13. No model at all: --auto goes right after `run`.
RUN_ARGS=(run --format json)
assert_args "auto: prepended after run when modeless" \
    "run" "--auto" "--format" "json"

# 14. Lone trailing --dir with no value: dropped without swallowing anything.
RUN_ARGS=(run --format json --dir)
assert_args "strip: bare trailing --dir" \
    "run" "--auto" "--format" "json"

# 15. --dir followed by another flag: flag must survive.
RUN_ARGS=(run --dir --format json)
assert_args "strip: --dir does not swallow next flag" \
    "run" "--auto" "--format" "json"

# 15a0. Wave B P1-9: valueless --dir followed by a bare word is AMBIGUOUS
# (path vs prompt — indistinguishable here). Fail closed toward prompt
# preservation: drop ONLY the flag, keep the token. A bogus path then
# errors loudly in the real binary; swallowing it would run prompt-less
# with exit 0 (silent prompt loss).
RUN_ARGS=(run --model m --dir prompt)
assert_args "strip: ambiguous --dir preserves following token (P1-9)" \
    "run" "--model" "m" "--auto" "prompt"

# 15a1. Wave B P2-2b: empty-string --dir value is consumed and dropped —
# no stray "" may leak into the positionals.
RUN_ARGS=(run --model m --dir "" prompt)
assert_args "strip: empty --dir value consumed, no stray positional (P2-2b)" \
    "run" "--model" "m" "--auto" "prompt"

# 15a2. Wave B P2-2b: empty-string --variant value is consumed and dropped —
# the model is left untouched and no stray "" is forwarded.
RUN_ARGS=(run --model mymodel --variant '' prompt)
assert_args "merge: empty --variant value consumed, model untouched (P2-2b)" \
    "run" "--model" "mymodel" "--auto" "prompt"

# 15a3. Wave B P2-2a: attached short -mmodel is NOT parsed as -m + value —
# it passes through untouched (the real binary rejects it with exit 1
# "Missing value for flag --model", a loud fail-closed error), and the
# variant is dropped since there is no --model to merge into.
RUN_ARGS=(run -mmodel --variant high prompt)
assert_args "passthrough: attached -mmodel untouched, variant dropped (P2-2a)" \
    "run" "--auto" "-mmodel" "prompt"

# 15a4. Wave B P2-2b: empty-string --model value is consumed (no stray "")
# and the bare flag passes through so the real binary reports the error.
RUN_ARGS=(run --model "" prompt)
assert_args "passthrough: empty --model value consumed, bare flag kept (P2-2b)" \
    "run" "--auto" "--model" "prompt"

# 15a. Bare `--` ends rewriting: post--- tokens pass through byte-for-byte.
RUN_ARGS=(run --model m -- --dir /tmp --variant high)
assert_args "terminator: post--- tokens untouched, --auto before --" \
    "run" "--model" "m" "--auto" "--" "--dir" "/tmp" "--variant" "high"

# 15b. Pre--- --variant still merges into --model; post--- --variant untouched.
RUN_ARGS=(run --model m --variant high -- --dir /tmp --variant high)
assert_args "terminator: pre--- merge applies, post--- verbatim" \
    "run" "--model" "m#high" "--auto" "--" "--dir" "/tmp" "--variant" "high"

# 15c. Modeless run with terminator: --auto lands right after `run`.
RUN_ARGS=(run --format json -- --dir /tmp)
assert_args "terminator: modeless --auto before --" \
    "run" "--auto" "--format" "json" "--" "--dir" "/tmp"

# 15d. --auto after `--` is a positional token, not a flag: still inject --auto.
RUN_ARGS=(run --model m -- --auto)
assert_args "terminator: post--- --auto not counted as flag" \
    "run" "--model" "m" "--auto" "--" "--auto"

# 16. stdin is relayed byte-for-byte (Paperclip feeds the prompt on stdin).
if printf 'stdin-prompt-bytes-123' | "${SHIM}" run --format json > "${SANDBOX}/relayed"; then
    if [[ "$(cat "${SANDBOX}/relayed")" == "stdin-prompt-bytes-123" ]]; then
        report PASS "stdin: piped prompt relayed to real binary"
    else
        report FAIL "stdin: relayed bytes differ ($(cat "${SANDBOX}/relayed"))"
    fi
else
    report FAIL "stdin: shim exited non-zero on piped input"
fi

# 17. stdout streams through (JSONL from --format json must reach Paperclip).
export MOCK_ECHO='{"type":"step_start","sessionID":"sess-1"}'
if [[ "$("${SHIM}" run --format json < /dev/null)" == '{"type":"step_start","sessionID":"sess-1"}' ]]; then
    report PASS "stdout: real binary output streams through"
else
    report FAIL "stdout: output did not stream through"
fi
export MOCK_ECHO=""

# 18. Exit codes propagate (Paperclip depends on non-zero on failure).
export MOCK_EXIT_CODE=3
set +e
"${SHIM}" run --format json > /dev/null 2>&1
code=$?
set -e
export MOCK_EXIT_CODE=0
if [[ "${code}" -eq 3 ]]; then
    report PASS "exit code: propagated from real binary (3)"
else
    report FAIL "exit code: expected 3, got ${code}"
fi

# 19. Fail-closed: missing real binary aborts instead of running anything.
set +e
OPENCODE_REAL_BIN=/nonexistent/opencode-bin "${SHIM}" run hi > /dev/null 2> "${SANDBOX}/err"
code=$?
set -e
if [[ "${code}" -ne 0 ]] && grep -q "not found" "${SANDBOX}/err"; then
    report PASS "fail-closed: missing real binary exits non-zero"
else
    report FAIL "fail-closed: missing real binary exited ${code}"
fi

# 20. OPENCODE_GO_API_KEY fallback (shim:56-58) + no-clobber guarantee.
# A second mock records the OPENCODE_API_KEY visible to the real binary
# (the argv mock above cannot observe environment).
cat > "${SANDBOX}/opencode-bin-env" <<'MOCKENV'
#!/usr/bin/env bash
printf 'OPENCODE_API_KEY=%s\n' "${OPENCODE_API_KEY:-UNSET}" > "${MOCK_ARGS_FILE}"
printf '%s\n' "$@" >> "${MOCK_ARGS_FILE}"
exit 0
MOCKENV
chmod +x "${SANDBOX}/opencode-bin-env"

# check_go_fallback <name> <expected OPENCODE_API_KEY> <env assignments...>:
# runs the shim with a controlled environment and asserts what the real
# binary would see. Extra args are `env` assignments (VAR=val or -u VAR).
check_go_fallback() {
    local name="$1"
    local expected="$2"
    shift 2
    rm -f "${MOCK_ARGS_FILE}"
    if env "$@" OPENCODE_REAL_BIN="${SANDBOX}/opencode-bin-env" "${SHIM}" run hi > /dev/null 2>&1; then
        local actual
        actual="$(head -n 1 "${MOCK_ARGS_FILE}")"
        if [[ "${actual}" == "OPENCODE_API_KEY=${expected}" ]]; then
            report PASS "${name}"
        else
            report FAIL "${name} (expected OPENCODE_API_KEY=${expected}, got ${actual})"
        fi
    else
        report FAIL "${name} (shim exited non-zero)"
    fi
}

check_go_fallback "go-key: fallback exports OPENCODE_API_KEY" \
    "go-key-123" -u OPENCODE_API_KEY OPENCODE_GO_API_KEY=go-key-123
check_go_fallback "go-key: pre-existing OPENCODE_API_KEY not clobbered" \
    "orig-keep" OPENCODE_API_KEY=orig-keep OPENCODE_GO_API_KEY=go-key-123
check_go_fallback "go-key: neither set leaves key unset" \
    "UNSET" -u OPENCODE_API_KEY -u OPENCODE_GO_API_KEY
check_go_fallback "go-key: empty GO key does not clobber to empty" \
    "UNSET" -u OPENCODE_API_KEY OPENCODE_GO_API_KEY=

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
