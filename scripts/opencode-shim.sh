#!/usr/bin/env bash
#
# opencode-shim.sh — OpenCode v2 CLI compatibility shim for Paperclip.
#
# Paperclip's built-in `opencode-local` adapter was written against the
# OpenCode v1 CLI and unconditionally appends two flags that OpenCode v2
# (`@opencode/cli@2.0.31`) rejects with
#   "ERROR: Unrecognized flag: --dir in command opencode run" (exit 1):
#     --dir <path> / --dir=<path>      (v2 uses the process working directory,
#                                       which Paperclip already sets when it
#                                       spawns the child process)
#     --variant <variant>              (v2 expresses variants inside the model
#                                       string: --model provider/model#variant)
# Additionally, unattended v2 runs reject tool-approval requests unless the
# run is explicitly non-interactive, so this shim injects `--auto` (the v2
# equivalent of Paperclip's old `"permission": "allow"` opencode.json hack).
#
# Installation (see docker/Dockerfile): the real v2 binary lives at
# /usr/local/bin/opencode-bin and this file is installed as
# /usr/local/bin/opencode, i.e. earlier on Paperclip's PATH.
#
# Rewriting rules (applied ONLY to the `run` subcommand):
#   1. Drop `--dir <path>` and `--dir=<path>`.
#      A `--dir` whose following token looks like another flag (or is absent)
#      is dropped on its own; the following flag is never swallowed.
#   2. Capture `--variant <v>` / `--variant=<v>` (space and equals forms) and
#      merge it into `--model <m>` / `--model=<m>` as `<m>#<v>`, regardless of
#      whether --model appears before or after --variant. A model that already
#      carries a `#variant` suffix is left untouched. A --variant with no
#      --model cannot be expressed in v2 and is dropped (passing it through
#      would make the real binary exit 1).
#   3. Ensure exactly one `--auto` (an explicit `--auto=<bool>` is respected
#      and never duplicated). It is inserted immediately after the --model
#      value when a model is present — preserving Paperclip's canonical order
#      `run --format json --model <m>#<v> --auto <prompt>` — otherwise right
#      after `run`.
#   4. A bare `--` ends rewriting: `--` and everything after it is appended
#      verbatim (no --dir stripping, no --variant merging, no --auto
#      detection past the terminator). --auto injection (rule 3) still
#      applies to the pre-`--` prefix and lands before the `--`.
#   5. Every other subcommand (models, debug, auth, mcp, ...) and every other
#      flag passes through byte-for-byte, including anything after `--`.
#
# Streaming & signals: the shim never touches stdin/stdout (Paperclip feeds
# the prompt via stdin and parses `--format json` JSONL from stdout) and
# finishes with `exec`, so the real binary replaces this process and owns
# signal handling directly.
#
# Fail-closed: if the real binary cannot be resolved (or resolves to this
# shim itself, i.e. a botched install), the shim aborts non-zero instead of
# silently running the wrong binary.
set -euo pipefail

# --- Resolve the real OpenCode v2 binary (fail closed) ---------------------
resolve_real_bin() {
    if [[ -n "${OPENCODE_REAL_BIN:-}" ]]; then
        # An explicit override that points nowhere is a misconfiguration:
        # fail closed instead of exec-ing a dangling path.
        if [[ -x "${OPENCODE_REAL_BIN}" ]]; then
            printf '%s\n' "${OPENCODE_REAL_BIN}"
            return 0
        fi
        return 1
    fi
    if [[ -x /usr/local/bin/opencode-bin ]]; then
        printf '%s\n' '/usr/local/bin/opencode-bin'
        return 0
    fi
    local found
    if found="$(command -v opencode-bin 2>/dev/null)"; then
        printf '%s\n' "${found}"
        return 0
    fi
    return 1
}

REAL_BIN=""
if ! REAL_BIN="$(resolve_real_bin)"; then
    echo "opencode-shim: ERROR: real OpenCode binary not found." >&2
    echo "opencode-shim: looked for \$OPENCODE_REAL_BIN, /usr/local/bin/opencode-bin," >&2
    echo "opencode-shim: and opencode-bin on PATH. Refusing to continue." >&2
    exit 127
fi

# Guard against a botched install where the real binary resolves to this shim.
SELF_CANON="$0"
TARGET_CANON="${REAL_BIN}"
if command -v realpath >/dev/null 2>&1; then
    SELF_CANON="$(realpath -m "$0" 2>/dev/null || printf '%s' "$0")"
    TARGET_CANON="$(realpath -m "${REAL_BIN}" 2>/dev/null || printf '%s' "${REAL_BIN}")"
fi
if [[ "${TARGET_CANON}" == "${SELF_CANON}" ]]; then
    echo "opencode-shim: ERROR: real binary resolves to the shim itself (${REAL_BIN})." >&2
    echo "opencode-shim: refusing to exec to avoid infinite recursion." >&2
    exit 127
fi

# No arguments, or any subcommand other than `run`: transparent pass-through.
if [[ $# -eq 0 || "${1:-}" != "run" ]]; then
    exec "${REAL_BIN}" "$@"
fi

# --- Rewrite `opencode run ...` --------------------------------------------
args=("${@:2}") # everything after `run`
out=()          # rewritten args (excluding the leading `run`)
model_value=""
model_index=-1  # index into out[] of the model value (or --model=value token)
model_is_eq=0    # 1 when the model was given as --model=value
variant=""
have_auto=0

i=0
while [[ "${i}" -lt "${#args[@]}" ]]; do
    arg="${args[${i}]}"
    next=""
    if [[ "$((i + 1))" -lt "${#args[@]}" ]]; then
        next="${args[$((i + 1))]}"
    fi
    case "${arg}" in
        --)
            # End-of-options terminator: everything from here on passes
            # through byte-for-byte (no --dir stripping, no --variant
            # merging, no --auto detection). --auto injection (below) still
            # applies to the pre--- prefix and lands before this `--`.
            out+=("${arg}")
            j=$((i + 1))
            while [[ "${j}" -lt "${#args[@]}" ]]; do
                out+=("${args[${j}]}")
                j=$((j + 1))
            done
            i="${#args[@]}"
            ;;
        --dir)
            # v2 runs in the process cwd (already set by Paperclip): drop the
            # flag and its path value — but never swallow a following flag.
            if [[ -n "${next}" && "${next}" != -* ]]; then
                i=$((i + 2))
            else
                i=$((i + 1))
            fi
            ;;
        --dir=*)
            i=$((i + 1))
            ;;
        --variant)
            if [[ -n "${next}" && "${next}" != -* ]]; then
                variant="${next}"
                i=$((i + 2))
            else
                i=$((i + 1))
            fi
            ;;
        --variant=*)
            variant="${arg#--variant=}"
            i=$((i + 1))
            ;;
        --model)
            if [[ -n "${next}" && "${next}" != -* ]]; then
                model_value="${next}"
                model_is_eq=0
                out+=("${arg}" "${next}")
                model_index=$((${#out[@]} - 1))
                i=$((i + 2))
            else
                # Broken invocation (`--model` with no value): pass through
                # untouched and let the real binary report the error.
                out+=("${arg}")
                i=$((i + 1))
            fi
            ;;
        --model=*)
            model_value="${arg#--model=}"
            model_is_eq=1
            out+=("${arg}")
            model_index=$((${#out[@]} - 1))
            i=$((i + 1))
            ;;
        --auto | --auto=*)
            have_auto=1
            out+=("${arg}")
            i=$((i + 1))
            ;;
        *)
            out+=("${arg}")
            i=$((i + 1))
            ;;
    esac
done

# Merge --variant into --model as model#variant (order-independent: the loop
# above already collected both regardless of which came first).
if [[ -n "${variant}" && -n "${model_value}" && "${model_index}" -ge 0 ]]; then
    if [[ "${model_value}" != *#* ]]; then
        merged="${model_value}#${variant}"
        if [[ "${model_is_eq}" -eq 1 ]]; then
            out["${model_index}"]="--model=${merged}"
        else
            out["${model_index}"]="${merged}"
        fi
    fi
fi
# NOTE: a --variant with no --model is intentionally dropped here: v2 has no
# --variant flag, so passing it through would fail the run with exit 1.

# Inject --auto exactly once. Placed right after the --model value when a
# model is present (Paperclip's canonical order), else right after `run`;
# both positions are clean option boundaries, never after an unknown token.
if [[ "${have_auto}" -eq 0 ]]; then
    if [[ "${model_index}" -ge 0 ]]; then
        insert_at=$((model_index + 1))
        out=("${out[@]:0:${insert_at}}" "--auto" "${out[@]:${insert_at}}")
    else
        out=("--auto" "${out[@]}")
    fi
fi

# exec: replace this process so stdin/stdout stream untouched and signals
# (SIGTERM/SIGINT from Paperclip timeouts and Docker stop) go to OpenCode.
exec "${REAL_BIN}" run "${out[@]}"
