# Heretek Crew: Paperclip + OpenCode v2 Stack Notes

## Verified Facts & Research (Phase 0)

### 1. Paperclip Official Dockerfile & Compose
- **Repository**: [paperclipai/paperclip](https://github.com/paperclipai/paperclip)
- **Official Dockerfile**: Located at root `/Dockerfile`. Multi-stage build (`node:24-trixie-slim`), builds `@paperclipai/server`, `@paperclipai/ui`, `@paperclipai/plugin-sdk`, and runner binaries.
- **Official Compose**:
  - `docker/docker-compose.yml`: Multi-container setup with `postgres:17-alpine` and `server` (Paperclip server + UI on port 3100).
  - `docker/docker-compose.quickstart.yml`: Single-container quickstart with SQLite.
- **Official Agent Harnesses in Dockerfile**:
  - Line 177 in official `Dockerfile` installs:
    `npm install --global --omit=dev @anthropic-ai/claude-code@latest @openai/codex@latest opencode-ai @google/gemini-cli@latest @moonshot-ai/kimi-code@latest`
  - Notice: It installs `opencode-ai` (which is OpenCode v1, pinned at 1.19.3). OpenCode v2 is `@opencode/cli` (currently 2.0.31).
- **Decision**: Extend Paperclip's official `docker/docker-compose.yml` and `Dockerfile` (or build an extended image layer on top of Paperclip's Dockerfile) rather than reinventing the stack from scratch.

### 2. OpenCode Package Naming & Version Pinning
- **OpenCode v1**: `opencode-ai` (latest v1: `1.19.3`).
- **OpenCode v2 CLI**: `@opencode/cli` (latest: `2.0.31`).
- **OpenCode v2 Client SDK**: `@opencode/client` (latest: `2.0.31`).
- **Install command**: `npm install -g @opencode/cli@2.0.31`
- **Pinned versions for this stack**:
  - `@opencode/cli`: `2.0.31`
  - `@opencode/client`: `2.0.31`
  - `postgres`: `17-alpine`
  - Node base: `node:24-trixie-slim`

### 3. OpenCode v2 CLI Invocations & Breaking Changes in `opencode_local`
Inspected `packages/adapters/opencode-local/src/server/execute.ts` and tested `@opencode/cli@2.0.31`:
- **CLI Subcommand**: Paperclip invokes `opencode run --format json`.
- **Breaking Flag 1 (`--dir`)**:
  - Paperclip's `execute.ts` line 629 unconditionally appends `--dir <effectiveExecutionCwd>` to `args`.
  - In OpenCode v2: `ERROR: Unrecognized flag: --dir in command opencode run` (exit code 1).
  - In v2, OpenCode runs in the process working directory (`process.cwd()`), which Paperclip already sets when spawning the process.
- **Breaking Flag 2 (`--variant`)**:
  - Paperclip's `execute.ts` line 624 appends `--variant <variant>`.
  - In OpenCode v2: `ERROR: Unrecognized flag: --variant in command opencode run`.
  - In v2, model variants are passed via the model string: `--model provider/model#variant`.
- **Session Resume (`--session`)**:
  - OpenCode v2 natively supports `--session <sessionID>` (or `-s`). Verified working; session resumes seamlessly.
- **Auto-Permissions (`dangerouslySkipPermissions`)**:
  - In v1, Paperclip wrote `"permission": "allow"` into the temporary `opencode.json`.
  - In v2, non-interactive runs reject tool approval requests with:
    `"This non-interactive run cannot ask the user for permission, so the request was rejected"`
    unless either:
    1. The CLI flag `--auto` is passed, or
    2. The v2 permissions array is configured in `opencode.json`:
       `"permissions": [{ "action": "*", "resource": "*", "effect": "allow" }]`
- **Output Parsing**:
  - OpenCode v2 `--format json` outputs JSONL matching Paperclip's `parseOpenCodeJsonl` and `parseOpenCodeStdoutLine`:
    - `type: "step_start"` with `sessionID`
    - `type: "tool_use"` with `part.tool`, `part.state.status`, `part.state.input`, `part.state.output`
    - `type: "step_finish"` with `part.tokens.input`, `part.tokens.output`, `part.tokens.cache.read`, `part.cost`
    - `type: "text"` with `part.text`
  - Token and cost tracking parse cleanly into Paperclip's usage accounting.

### 4. Configuration Precedence & Per-Role Isolation
Inspected OpenCode v2 binary and verified:
- **Paths in v2**:
  - `config`: `$XDG_CONFIG_HOME/opencode` (defaults to `~/.config/opencode`).
  - `OPENCODE_CONFIG_DIR`: Explicit override for the entire config directory.
  - `OPENCODE_CONFIG`: Explicit file path to a custom `opencode.json` / `opencode.jsonc`.
  - `OPENCODE_DISABLE_PROJECT_CONFIG`: When `true` (which Paperclip forces at line 329 in `execute.ts`), OpenCode skips project-level `.opencode/` and `opencode.json` in the git repository.
- **How Per-Role Isolation Works with Paperclip**:
  - Paperclip's `prepareOpenCodeRuntimeConfig` checks `input.env.XDG_CONFIG_HOME`:
    `sourceConfigDir = path.join(resolveXdgConfigHome(input.env), "opencode")`
  - It creates a temp directory `/tmp/paperclip-opencode-config-XXXXXX/opencode`, copies `sourceConfigDir`, injects permissions/providers, and sets `env.XDG_CONFIG_HOME = runtimeConfigHome`.
  - Thus, if an agent's adapter config specifies `env.XDG_CONFIG_HOME = "/roles/<role-name>"` (where `/roles/<role-name>/opencode/opencode.json` lives), Paperclip's temp-config mechanism will copy that specific role's configuration, merge runtime settings, and pass it to OpenCode v2!
  - In addition, setting `OPENCODE_CONFIG_DIR` or `OPENCODE_CONFIG` provides fallback guarantees.

## Open Questions & Compatibility Spike Options (Phase 1)
Because Paperclip's built-in `opencode-local` adapter pushes `--dir` (which fails under OpenCode v2 CLI), we have two paths for compatibility:
- **Option A (Lightweight Wrapper / Shim or In-tree Patch)**:
  - An `opencode` wrapper script or small patch in Paperclip's `opencode-local` adapter that intercepts `--dir <dir>` and `--variant <variant>`, strips `--dir`, converts `--variant` to `--model <model>#<variant>`, and ensures `--auto` is enabled.
- **Option B (Custom Paperclip Adapter / Server Service)**:
  - Create a dedicated Paperclip adapter package or service using `@opencode/client` against a running `opencode serve` backend, per Paperclip's "Creating an Adapter" and UI parser contract docs.
