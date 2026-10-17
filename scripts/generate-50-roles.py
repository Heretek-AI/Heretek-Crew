#!/usr/bin/env python3
"""generate-50-roles.py — scaffold the 50-agent Heretek fleet on disk.

Parses the authoritative specifications in roles-catalog/0*.md (the single
source of truth) and generates, for each of the 50 canonical roles:

    roles/<role-id>/
    ├── AGENTS.md                              # charter, chain of command, workflow
    ├── opencode/opencode.json                 # OpenCode v2 config (least privilege)
    └── .opencode/
        ├── agents/<role-id>.md                # agent system prompt + frontmatter
        └── skills/<skill-name>/SKILL.md       # procedural skill + frontmatter

Normalization applied to every parsed opencode.json (fail-closed):
  * injects "model" (default anthropic/claude-sonnet-4-5, overridable via
    MODEL_DEFAULT) when the catalog block omits it,
  * re-appends {"action": "shell", "resource": "*", "effect": "deny"} so the
    permissions array always ends with deny-all shell,
  * pins every mcp.servers npx/uvx command to exact registry versions
    (npx pkg@ver, uvx pkg==ver; sole tracked exception @morluto/rea-mcp,
    unpublished upstream) and dies on any other unpinned package,
  * pins Role 26 (android-mobile-spec) mobile MCP to
    npx -y @mobile-next/mobile-mcp@0.1.2 (catalog text names mobile-mcp;
    the fleet spec mandates the scoped pinned package),
  * rejects any generated config containing ":latest".

Usage:
    python3 scripts/generate-50-roles.py [--root PATH] [--help]

Exit codes: 0 when all 50 roles generate cleanly; 1 on any structural
deviation (missing role, empty permissions/skills, unparseable JSON, TODO
markers, :latest pins). Safe to re-run: output files are rewritten
deterministically and no unrelated paths are touched or deleted.
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

MODEL_FALLBACK = "anthropic/claude-sonnet-4-5"
# Fleet cap as stated in roles-catalog/ROLE_CATALOG_50.md and the fleet brief.
# The per-role matrix in the catalog sums to 1270000, which equals the cap;
# a mismatch (e.g. after a catalog edit) is reported as a WARNING (per-role
# values are authoritative) rather than failing.
DOCUMENTED_FLEET_CAP_CENTS = 1270000
DENY_ALL_SHELL = {"action": "shell", "resource": "*", "effect": "deny"}
# Wave 2 (P0-2/P0-3) MCP sandbox scoping: bare-namespace MCP allow-all
# entries are replaced with read-verb-scoped allows + same-namespace deny
# tails. Verb sets grounded in the pinned servers' real tool lists,
# enumerated empirically 2026-10-17 (see scope tables below); the runtime
# enforcer's exact <server>_<tool> vs bare-<tool> mapping is still a tracked
# product decision (REMEDIATION_LOG.md), so allows use the namespaced form
# and every namespace ends in an explicit deny (fail-closed either way).
#
# Harness manifest: npm pack @heretek-ai/opencode-harness@1.0.7 ->
# dist/index.js EXTENDED_HARNESS_TOOL_NAMES (14 tools; the live
# setupOpenCodeV2Harness path registers all 14).
HARNESS_TOOL_NAMES = [
    "file_hash_read",
    "file_hash_edit",
    "ast_structural_search",
    "ast_structural_rewrite",
    "ui_geometry_audit",
    "repo_map",
    "blast_radius",
    "file_outline",
    "symbol_references",
    "rename_symbol",
    "verify_scoped",
    "architecture_audit",
    "checkpoint_create",
    "checkpoint_rollback",
]
# Git read verbs: the 8 tools carrying readOnlyHint:true in
# @cyanheads/git-mcp-server@2.15.3 (28 tools total; the other 20 mutate
# history, refs, index, or working tree and stay denied fleet-wide — no
# role retains git_push/commit via MCP; local commits stay on shell
# allows where already granted, pushes are human-approval-gated).
GIT_READ_TOOLS = [
    "git_blame",
    "git_changelog_analyze",
    "git_diff",
    "git_log",
    "git_reflog",
    "git_show",
    "git_status",
    "git_wrapup_instructions",
]
# Filesystem read verbs (server-filesystem@1.0.0: 10 read tools named
# read_*/list_*/directory_tree/search_files/get_file_info; write/edit/
# create/move stay denied).
FS_READ_VERBS = [
    "filesystem_read*",
    "filesystem_list*",
    "filesystem_directory*",
    "filesystem_search*",
    "filesystem_get*",
]
FS_WRITE_DENIES = [
    "filesystem_write*",
    "filesystem_edit*",
    "filesystem_create*",
    "filesystem_move*",
]
# mcp-server-kubernetes==0.1.6 tools: kubectl_describe,
# kubectl_get_by_name, kubectl_get_by_kind_in_namespace,
# kubectl_previous_logs (read) + kubectl_exec_into_pod (exec primitive,
# denied — the shell layer never allowed exec either).
K8S_READ = [
    "kubernetes_kubectl_get*",
    "kubernetes_kubectl_describe*",
    "kubernetes_kubectl_previous_logs*",
]
K8S_DENIES = ["kubernetes_kubectl_exec*", "kubernetes_*"]
# docker-mcp==0.2.0 tools: list-containers + get-logs (read) vs
# create-container + deploy-compose (write, denied).
DOCKER_READ = ["docker_list*", "docker_get*"]
DOCKER_DENIES = ["docker_create*", "docker_deploy*", "docker_*"]
# server-postgres@0.6.2 exposes exactly one tool, `query`, which
# self-enforces BEGIN TRANSACTION READ ONLY; the allow names it, the deny
# closes the namespace, and the URL must be the read-only role (seed gate
# + compose :? guard enforce provisioning).
PG_READ = ["postgres_query*"]
PG_DENIES = ["postgres_*"]
# aws-mcp@1.0.2 tools: list-credentials + select-profile (read) vs
# run-aws-code (arbitrary-AWS-code primitive, denied at this layer;
# write containment is enforced by the IAM policy on the configured
# profile — see cloud-platform-eng / cloud-sec-auditor charters).
AWS_READ = ["aws_list*", "aws_select*"]
AWS_DENIES = ["aws_run*", "aws_*"]


def _allow(action):
    return {"action": action, "resource": "*", "effect": "allow"}


def _deny(action):
    return {"action": action, "resource": "*", "effect": "deny"}


def scope_mcp_permissions(role_id, perms):
    """Replace bare-namespace MCP allows with scoped allows + deny tails."""
    scoped = []
    for p in perms:
        if not isinstance(p, dict) or p.get("effect") != "allow":
            scoped.append(p)
            continue
        action = p.get("action")
        if action == "harness_*":
            scoped.extend(_allow("harness_" + t) for t in HARNESS_TOOL_NAMES)
            scoped.append(_deny("harness_*"))
        elif action == "git_*":
            scoped.extend(_allow(t) for t in GIT_READ_TOOLS)
            scoped.append(_deny("git_*"))
        elif action == "filesystem_*" and role_id in (
            "binary-reverse-eng",
            "firmware-sec-analyst",
        ):
            scoped.extend(_allow(v) for v in FS_READ_VERBS)
            scoped.extend(_deny(v) for v in FS_WRITE_DENIES)
            scoped.append(_deny("filesystem_*"))
        elif action == "filesystem_*" and role_id == "brand-copy-spec":
            # Docs-scoped role: the filesystem MCP server entry is removed
            # in normalize_config below; its allow is dropped here.
            continue
        elif action == "filesystem_*":
            # No other role may carry filesystem MCP.
            die(
                "role '%s' carries filesystem_* outside the allowlist "
                "(remove the MCP server instead)" % role_id
            )
        elif action == "kubernetes_*" and role_id == "k8s-orchestrator":
            scoped.extend(_allow(v) for v in K8S_READ)
            scoped.extend(_deny(v) for v in K8S_DENIES)
        elif action == "docker_*" and role_id in (
            "k8s-orchestrator",
            "mlops-serving-eng",
        ):
            scoped.extend(_allow(v) for v in DOCKER_READ)
            scoped.extend(_deny(v) for v in DOCKER_DENIES)
        elif action == "postgres_*" and role_id == "dba-specialist":
            scoped.extend(_allow(v) for v in PG_READ)
            scoped.extend(_deny(v) for v in PG_DENIES)
        elif action == "aws_*" and role_id in (
            "cloud-platform-eng",
            "cloud-sec-auditor",
        ):
            scoped.extend(_allow(v) for v in AWS_READ)
            scoped.extend(_deny(v) for v in AWS_DENIES)
        elif action in ("kubernetes_*", "docker_*", "postgres_*", "aws_*"):
            die(
                "role '%s' carries %s outside its allowlisted role "
                "(fail-closed)" % (role_id, action)
            )
        else:
            scoped.append(p)
    return scoped


# Pinned MCP supply chain (P1-7): exact versions resolved live against the
# npm/PyPI registries 2026-10-17 (catalog "verified v" annotations agree).
# normalize_config() rewrites every mcp.servers command through this map and
# dies on any unpinned npx/uvx package not listed here. npx pins use pkg@ver,
# uvx pins use pkg==ver (uv tool-run requirement syntax, verified live).
MCP_NPX_PINS = {
    "@executeautomation/playwright-mcp-server": "@executeautomation/playwright-mcp-server@1.0.12",
    "@cyanheads/git-mcp-server": "@cyanheads/git-mcp-server@2.15.3",
    "mcp-openapi-schema-explorer": "mcp-openapi-schema-explorer@1.3.5",
    "aws-mcp": "aws-mcp@1.0.2",
    "@modelcontextprotocol/server-github": "@modelcontextprotocol/server-github@2025.4.8",
    "@modelcontextprotocol/server-postgres": "@modelcontextprotocol/server-postgres@0.6.2",
    "@modelcontextprotocol/server-filesystem": "@modelcontextprotocol/server-filesystem@1.0.0",
    "@modelcontextprotocol/server-memory": "@modelcontextprotocol/server-memory@1.0.0",
    "@upstash/context7-mcp": "@upstash/context7-mcp@4.4.2",
    "ollama-mcp": "ollama-mcp@2.1.0",
    "codebase-memory-mcp": "codebase-memory-mcp@0.12.1",
}
MCP_UVX_PINS = {
    "mcp-clickhouse": "mcp-clickhouse==0.7.0",
    "r2mcp": "r2mcp==0.2.5",
    "mcp-server-redis": "mcp-server-redis==0.1.1",
    "kafka-mcp-server": "kafka-mcp-server==0.1.1",
    "mcp-server-duckdb": "mcp-server-duckdb==1.1.0",
    "mcp-server-kubernetes": "mcp-server-kubernetes==0.1.6",
    "docker-mcp": "docker-mcp==0.2.0",
    "k6-mcp-server": "k6-mcp-server==2.2.0",
    "prometheus-mcp-server": "prometheus-mcp-server==1.6.2",
    "mcp-server-qdrant": "mcp-server-qdrant==0.8.1",
}
# Sole unpinned exception (product decision pending): @morluto/rea-mcp is not
# published on npm (registry 404 2026-10-17; upstream ships `rea-agents`
# instead). Left as-is and tracked; any OTHER unpinned package fails the run.
MCP_UNPINNED_EXCEPTIONS = {"@morluto/rea-mcp"}


def pin_mcp_command(role_id, server_name, command):
    """Rewrite one mcp.servers command argv through the pin maps (fail-closed)."""
    if not isinstance(command, list) or not command:
        die("role '%s' mcp server '%s' has no command argv" % (role_id, server_name))
    if command[0] == "npx":
        try:
            y = command.index("-y")
        except ValueError:
            die(
                "role '%s' mcp server '%s' npx argv lacks -y: %r"
                % (role_id, server_name, command)
            )
        if y + 1 >= len(command):
            die(
                "role '%s' mcp server '%s' npx -y has no package: %r"
                % (role_id, server_name, command)
            )
        pkg = command[y + 1]
        if "@" in pkg.rsplit("/", 1)[-1]:
            return command  # already pinned (pkg@ver)
        if pkg in MCP_UNPINNED_EXCEPTIONS:
            return command  # tracked exception, see map comment
        if pkg not in MCP_NPX_PINS:
            die(
                "role '%s' mcp server '%s' unpinned npx package '%s'"
                % (role_id, server_name, pkg)
            )
        return command[: y + 1] + [MCP_NPX_PINS[pkg]] + command[y + 2 :]
    if command[0] == "uvx":
        if len(command) < 2:
            die(
                "role '%s' mcp server '%s' uvx argv has no package"
                % (role_id, server_name)
            )
        pkg = command[1]
        if "==" in pkg:
            return command  # already pinned (pkg==ver)
        if pkg in MCP_UNPINNED_EXCEPTIONS:
            return command
        if pkg not in MCP_UVX_PINS:
            die(
                "role '%s' mcp server '%s' unpinned uvx package '%s'"
                % (role_id, server_name, pkg)
            )
        return [command[0], MCP_UVX_PINS[pkg]] + command[2:]
    if command == ["codebase-memory-mcp"]:
        # Bare binary (pre-pin form): resolve via pinned npx so the exact
        # registry artifact runs (npm bin codebase-memory-mcp exists @0.12.1).
        return ["npx", "-y", MCP_NPX_PINS["codebase-memory-mcp"]]
    return command


# Canonical 50 role IDs in catalog order (Roles 01-50).
EXPECTED_IDS = [
    "exec-director",
    "product-director",
    "tpm-scrum-lead",
    "system-architect",
    "tech-docs-lead",
    "ux-research-analyst",
    "game-systems-dev",
    "graphics-shader-eng",
    "engine-systems-eng",
    "game-ai-dev",
    "physics-sim-eng",
    "tech-artist-pipeline",
    "ui-ux-designer",
    "design-system-eng",
    "a11y-specialist",
    "fe-perf-eng",
    "mobile-web-eng",
    "brand-copy-spec",
    "rust-systems-spec",
    "go-backend-eng",
    "python-backend-spec",
    "ts-node-fullstack",
    "cpp-lowlevel-eng",
    "java-kotlin-eng",
    "ios-mobile-spec",
    "android-mobile-spec",
    "cloud-platform-eng",
    "k8s-orchestrator",
    "sre-incident-eng",
    "observability-eng",
    "dba-specialist",
    "cache-streaming-eng",
    "e2e-browser-qa",
    "api-contract-tester",
    "load-stress-tester",
    "sabotage-qa-tester",
    "static-analysis-lead",
    "release-qa-officer",
    "appsec-engineer",
    "cloud-sec-auditor",
    "binary-reverse-eng",
    "firmware-sec-analyst",
    "threat-modeler",
    "compliance-auditor",
    "data-pipeline-eng",
    "vector-rag-spec",
    "mlops-serving-eng",
    "analytics-metrics-eng",
    "dependency-patcher",
    "git-drift-coord",
]

# Org-chart wiring (None = reports to the Human Board). Source: fleet brief.
REPORTS_TO = {
    "exec-director": None,
    "product-director": "exec-director",
    "system-architect": "exec-director",
    "tpm-scrum-lead": "product-director",
    "tech-docs-lead": "product-director",
    "ux-research-analyst": "product-director",
    "game-systems-dev": "tpm-scrum-lead",
    "graphics-shader-eng": "tpm-scrum-lead",
    "engine-systems-eng": "tpm-scrum-lead",
    "game-ai-dev": "tpm-scrum-lead",
    "physics-sim-eng": "tpm-scrum-lead",
    "tech-artist-pipeline": "tpm-scrum-lead",
    "ui-ux-designer": "tpm-scrum-lead",
    "design-system-eng": "tpm-scrum-lead",
    "a11y-specialist": "tpm-scrum-lead",
    "fe-perf-eng": "tpm-scrum-lead",
    "mobile-web-eng": "tpm-scrum-lead",
    "brand-copy-spec": "tpm-scrum-lead",
    "rust-systems-spec": "tpm-scrum-lead",
    "go-backend-eng": "tpm-scrum-lead",
    "python-backend-spec": "tpm-scrum-lead",
    "ts-node-fullstack": "tpm-scrum-lead",
    "cpp-lowlevel-eng": "tpm-scrum-lead",
    "java-kotlin-eng": "tpm-scrum-lead",
    "ios-mobile-spec": "tpm-scrum-lead",
    "android-mobile-spec": "tpm-scrum-lead",
    "cloud-platform-eng": "system-architect",
    "k8s-orchestrator": "system-architect",
    "sre-incident-eng": "system-architect",
    "observability-eng": "system-architect",
    "dba-specialist": "system-architect",
    "cache-streaming-eng": "system-architect",
    "e2e-browser-qa": "tpm-scrum-lead",
    "api-contract-tester": "tpm-scrum-lead",
    "load-stress-tester": "tpm-scrum-lead",
    "sabotage-qa-tester": "tpm-scrum-lead",
    "static-analysis-lead": "tpm-scrum-lead",
    "release-qa-officer": "tpm-scrum-lead",
    "appsec-engineer": "system-architect",
    "cloud-sec-auditor": "system-architect",
    "binary-reverse-eng": "system-architect",
    "firmware-sec-analyst": "system-architect",
    "threat-modeler": "system-architect",
    "compliance-auditor": "system-architect",
    "data-pipeline-eng": "system-architect",
    "vector-rag-spec": "system-architect",
    "mlops-serving-eng": "system-architect",
    "analytics-metrics-eng": "system-architect",
    "dependency-patcher": "tpm-scrum-lead",
    "git-drift-coord": "tpm-scrum-lead",
}

# Fleet-brief skill names cross-referenced to catalog skill names where the
# brief uses a shorthand (documentation aid only; files use catalog names).
SKILL_ALIASES = {
    "android-mobile-spec": [
        ("android-compose-architecture", "jetpack-compose-state-hoisting"),
    ],
    "binary-reverse-eng": [
        ("r2-disassembly-analysis", "radare2-defensive-disassembly"),
    ],
}

# High-value integration endpoints surfaced verbatim in the role charter so
# operators can grep a role directory for its mandated tooling.
INTEGRATION_NOTES = {
    "android-mobile-spec": [
        "Primary MCP: mobile-next/mobile-mcp via `npx -y @mobile-next/mobile-mcp@0.1.2` "
        "(device discovery, UI hierarchy dump, tap/swipe, text input, screenshots, adb shell).",
        "Emulator: budtmo/docker-android over ADB at 127.0.0.1:5555 "
        "(in-compose address `docker-android:5555`; env ADB_HOST=docker-android ADB_PORT=5555).",
        "Automated UI exploration: google/artemis (`artemis explore --apk <debug.apk> --timeout 180s`).",
    ],
    "binary-reverse-eng": [
        "Primary MCP: morluto/rea via `npx -y @morluto/rea-mcp` "
        "(120+ RE tools bridging Ghidra, Binary Ninja, Radare2 and APK tooling).",
        "Disassembler MCP: r2mcp via `uvx r2mcp` (Radare2 control-flow, strings, imports).",
        "Plugin: opencode-rea (`@heretek-ai/opencode-rea`) for in-turn decompilation support.",
        "Headless Ghidra decompilation passes with GHIDRA_INSTALL_DIR=/opt/ghidra and semantic symbol renaming.",
    ],
}

ROLE_HEADER_RE = re.compile(r"^## Role (\d+): (.+?) \(`([^`]+)`\)", re.M)
BUDGET_RE = re.compile(r"\*\*Monthly Budget\*\*:\s*\$(\d+\.\d{2})\s*USD")
TITLE_DEPT_RE = re.compile(r"\*\*Title & Department\*\*:\s*(.+?)\s*\|\s*(.+)")
SENIORITY_RE = re.compile(r"- \*\*Seniority & Reporting Chain\*\*:\s*(.+)")
DELEGATION_RE = re.compile(r"- \*\*Delegation Triggers\*\*:\s*(.+)")
WAKE_RE = re.compile(r"- \*\*Wake Policy\*\*:\s*(.+)")
SECTION_RE = re.compile(r"^### (\d+)\.\s*(.+?)\s*$", re.M)
SKILL_RE = re.compile(r"#### Skill:\s*`([^`]+)`\s*\n```markdown\n(.*?)\n```", re.S)
JSON_FENCE_RE = re.compile(r"```json\n(.*?)\n```", re.S)
MD_FENCE_RE = re.compile(r"```markdown\n(.*?)\n```", re.S)
FRONTMATTER_RE = re.compile(
    r"^---\s*\nname:\s*(.+?)\s*\ndescription:\s*(.+?)\s*\n---\s*\n(.*)$", re.S
)
TODO_RE = re.compile(r"\bTODO\b")


def die(msg):
    print("error: " + msg, file=sys.stderr)
    sys.exit(1)


def get_section(block, num):
    """Return (title, body) of the ### <num>. section inside a role block."""
    matches = list(SECTION_RE.finditer(block))
    for i, m in enumerate(matches):
        if m.group(1) == str(num):
            start = m.end()
            end = matches[i + 1].start() if i + 1 < len(matches) else len(block)
            return m.group(2).strip(), block[start:end].strip()
    return "", ""


def parse_skill_fence(skill_id, fenced):
    m = FRONTMATTER_RE.match(fenced.strip())
    if not m:
        die("skill '%s' body lacks valid frontmatter (name/description)" % skill_id)
    name, description, body = m.group(1).strip(), m.group(2).strip(), m.group(3).strip()
    if name != skill_id:
        die(
            "skill fence name mismatch: header '%s' vs frontmatter '%s'"
            % (skill_id, name)
        )
    if len(body) < 100:
        die(
            "skill '%s' procedural body suspiciously short (%d chars)"
            % (name, len(body))
        )
    if TODO_RE.search(fenced):
        die("skill '%s' contains TODO marker (zero-stub violation)" % name)
    return {"name": name, "description": description, "body": body}


def parse_role_block(block, dept_file):
    m = ROLE_HEADER_RE.search(block)
    if not m:
        die("role block without header in %s" % dept_file)
    num, header_title, role_id = int(m.group(1)), m.group(2).strip(), m.group(3).strip()

    bm = BUDGET_RE.search(block)
    if not bm:
        die("role '%s' has no Monthly Budget line" % role_id)
    budget_cents = int(round(float(bm.group(1)) * 100))
    if budget_cents <= 0:
        die("role '%s' has non-positive budget" % role_id)

    tm = TITLE_DEPT_RE.search(block)
    title = tm.group(1).strip() if tm else header_title
    department = tm.group(2).strip() if tm else "Unknown"
    seniority = SENIORITY_RE.search(block)
    delegation = DELEGATION_RE.search(block)
    wake = WAKE_RE.search(block)

    _t2, sec2 = get_section(block, 2)
    _t3, sec3 = get_section(block, 3)
    _t5, sec5 = get_section(block, 5)

    skills = []
    for sm in SKILL_RE.finditer(block):
        skills.append(parse_skill_fence(sm.group(1).strip(), sm.group(2)))
    if not skills:
        die("role '%s' defines no skills" % role_id)

    jm = JSON_FENCE_RE.search(block)
    if not jm:
        die("role '%s' has no opencode.json fenced block" % role_id)
    try:
        raw_config = json.loads(jm.group(1))
    except json.JSONDecodeError as exc:
        die("role '%s' opencode.json is invalid JSON: %s" % (role_id, exc))

    idx7 = block.find("### 7.")
    if idx7 < 0:
        die("role '%s' has no section 7 (system prompt)" % role_id)
    pm = MD_FENCE_RE.search(block[idx7:])
    if not pm:
        die("role '%s' system prompt fenced block not found" % role_id)
    system_prompt = pm.group(1).strip()
    if len(system_prompt) < 100:
        die("role '%s' system prompt suspiciously short" % role_id)
    if TODO_RE.search(system_prompt):
        die("role '%s' system prompt contains TODO marker" % role_id)

    return {
        "num": num,
        "role_id": role_id,
        "title": title,
        "department": department,
        "budget_cents": budget_cents,
        "seniority": seniority.group(1).strip() if seniority else "",
        "delegation": delegation.group(1).strip() if delegation else "",
        "wake": wake.group(1).strip() if wake else "",
        "responsibilities": sec2,
        "mcp_spec": sec3,
        "plugins_spec": sec5,
        "skills": skills,
        "raw_config": raw_config,
        "system_prompt": system_prompt,
        "dept_file": dept_file,
        "block": block,
    }


def normalize_config(role):
    """Apply fail-closed normalization to the parsed opencode.json."""
    role_id = role["role_id"]
    model = os.environ.get("MODEL_DEFAULT", MODEL_FALLBACK).strip()
    if not model or "/" not in model:
        die("MODEL_DEFAULT must be provider/model form, got '%s'" % model)
    cfg = dict(role["raw_config"])
    cfg["$schema"] = "https://opencode.ai/config.json"
    cfg["model"] = model

    perms = cfg.get("permissions")
    if not isinstance(perms, list) or not perms:
        die("role '%s' permissions array is missing or empty" % role_id)
    perms = [
        p
        for p in perms
        if not (
            isinstance(p, dict)
            and p.get("action") == "shell"
            and p.get("resource") == "*"
            and p.get("effect") == "deny"
        )
    ]
    harness_present = any(
        isinstance(p, dict) and p.get("action", "").startswith("harness_")
        for p in perms
    )
    if not harness_present:
        perms = scope_mcp_permissions(
            role_id,
            perms + [{"action": "harness_*", "resource": "*", "effect": "allow"}],
        )
    else:
        perms = scope_mcp_permissions(role_id, perms)
    perms.append(dict(DENY_ALL_SHELL))
    cfg["permissions"] = perms

    skills = cfg.get("skills")
    if not isinstance(skills, list) or not skills:
        die("role '%s' skills array is missing or empty" % role_id)

    if "plugins" not in cfg or not cfg["plugins"]:
        die("role '%s' plugins list is missing or empty" % role_id)
    if (
        "opencode-harness" not in cfg["plugins"]
        and "@heretek-ai/opencode-harness" not in cfg["plugins"]
    ):
        cfg["plugins"].append("@heretek-ai/opencode-harness")
    mcp = cfg.get("mcp")
    if not isinstance(mcp, dict) or not mcp.get("servers"):
        die("role '%s' mcp.servers mapping is missing or empty" % role_id)

    if role_id == "android-mobile-spec":
        mobile = mcp["servers"].get("mobile")
        if mobile is None:
            die("role 'android-mobile-spec' lost its mobile MCP server entry")
        mobile["command"] = ["npx", "-y", "@mobile-next/mobile-mcp@0.1.2"]
        env = mobile.get("env") or {}
        env.setdefault("ADB_HOST", "docker-android")
        env.setdefault("ADB_PORT", "5555")
        mobile["env"] = env

    # Wave 2 (P0-2) filesystem MCP roots: the catalog grants the RE roles
    # the shared-workspace root; generation re-roots to the read-only
    # sample scope (/paperclip/workspaces/binaries, the :ro sample mount
    # used by the ghidra/radare2 sidecars) and drops the docs-scoped
    # brand-copy-spec server entirely (its reads go through git MCP,
    # writes through fs:write).
    if role_id in ("binary-reverse-eng", "firmware-sec-analyst"):
        fs_srv = mcp["servers"].get("filesystem")
        if not isinstance(fs_srv, dict) or not isinstance(fs_srv.get("command"), list):
            die("role '%s' lost its filesystem MCP server entry" % role_id)
        if fs_srv["command"][-1:] == ["/paperclip/workspaces"]:
            fs_srv["command"][-1] = "/paperclip/workspaces/binaries"
        elif fs_srv["command"][-1:] != ["/paperclip/workspaces/binaries"]:
            die("role '%s' has an unexpected filesystem MCP root" % role_id)
    if role_id == "brand-copy-spec" and "filesystem" in mcp["servers"]:
        del mcp["servers"]["filesystem"]

    # Wave 2 (P0-2) filesystem server allowlist: only the two RE roles may
    # declare a filesystem MCP server (re-rooted above). Any other role
    # carrying one (e.g. catalog drift) loses it here — a server without a
    # matching scoped allow is dead config and a latent bypass risk.
    if role_id not in ("binary-reverse-eng", "firmware-sec-analyst"):
        if "filesystem" in mcp["servers"]:
            del mcp["servers"]["filesystem"]

    # Wave 2 (P0-5): git-drift-coord loses the history-rewrite shell
    # primitives (worktree / rebase / push --force-with-lease). Detection
    # stays on status/branch/merge-base/diff/log; any push is
    # human-approval-gated (PAPERCLIP_TOOL_ACTION_SIGNING_SECRET).
    if role_id == "git-drift-coord":
        cfg["permissions"] = [
            p
            for p in cfg.get("permissions", [])
            if not (
                isinstance(p, dict)
                and p.get("action") == "shell"
                and p.get("effect") == "allow"
                and p.get("resource")
                in (
                    "git worktree*",
                    "git rebase*",
                    "git push --force-with-lease*",
                )
            )
        ]
        if any(
            isinstance(p, dict)
            and p.get("action") == "shell"
            and p.get("effect") == "allow"
            and str(p.get("resource")).startswith("git push")
            for p in cfg["permissions"]
        ):
            die("role 'git-drift-coord' retains a git push shell allow")

    for server_name, server in mcp["servers"].items():
        if not isinstance(server, dict):
            die("role '%s' mcp server '%s' is not a mapping" % (role_id, server_name))
        server["command"] = pin_mcp_command(role_id, server_name, server.get("command"))

    ordered = {
        "$schema": cfg["$schema"],
        "model": cfg["model"],
        "permissions": cfg["permissions"],
        "skills": cfg["skills"],
        "plugins": cfg["plugins"],
        "mcp": cfg["mcp"],
    }
    for key in cfg:
        if key not in ordered:
            ordered[key] = cfg[key]
    text = json.dumps(ordered, indent=2) + "\n"
    if ":latest" in text:
        die("role '%s' generated config contains ':latest' pin" % role_id)
    return text


def mention_role_ids(role, known):
    """All other known role IDs referenced in this role's catalog block."""
    found = []
    for rid in known:
        if rid != role["role_id"] and ("`%s`" % rid) in role["block"]:
            found.append(rid)
    return sorted(found)


def write_allow_paths(perms):
    return sorted(
        {
            p["resource"]
            for p in perms
            if isinstance(p, dict)
            and p.get("effect") == "allow"
            and str(p.get("action", "")).startswith("fs:write")
            and p.get("resource") != "*"
        }
    )


def shell_allow_cmds(perms):
    return [
        p["resource"]
        for p in perms
        if isinstance(p, dict)
        and p.get("action") == "shell"
        and p.get("effect") == "allow"
        and p.get("resource") != "*"
    ]


def render_agents_md(role, perms, known):
    rid = role["role_id"]
    dollars = role["budget_cents"] / 100.0
    reports_to = REPORTS_TO[rid]
    reports_line = (
        "Human Board / Human Stakeholders (top of fleet, no reportsTo key)"
        if reports_to is None
        else "`%s`" % reports_to
    )
    collaborators = mention_role_ids(role, known)
    write_paths = write_allow_paths(perms)
    shell_cmds = shell_allow_cmds(perms)

    lines = []
    lines.append("# %s (`%s`) — Agent Charter" % (role["title"], rid))
    lines.append("")
    lines.append(
        "> Department: %s | Fleet role %02d/50 | Monthly budget: $%.2f USD (%d cents)"
        % (role["department"], role["num"], dollars, role["budget_cents"])
    )
    lines.append(
        "> Model: %s | Runtime config: `/roles/%s/opencode/opencode.json` via `XDG_CONFIG_HOME=/roles/%s`"
        % (
            os.environ.get("MODEL_DEFAULT", MODEL_FALLBACK).strip() or MODEL_FALLBACK,
            rid,
            rid,
        )
    )
    lines.append(
        "> Source of truth: `roles-catalog/%s` (Role %02d). Fleet wake model: on-demand via "
        "Paperclip assignment and @mention; recurring heartbeats exist only for `exec-director` "
        "(1800s) and `tpm-scrum-lead` (3600s)." % (role["dept_file"], role["num"])
    )
    lines.append("")
    lines.append("## 1. Identity & Scope")
    lines.append("")
    lines.append(
        "- **Title & Department**: %s | %s" % (role["title"], role["department"])
    )
    if role["seniority"]:
        lines.append("- **Seniority & Reporting Chain**: %s" % role["seniority"])
    if role["delegation"]:
        lines.append("- **Delegation Triggers**: %s" % role["delegation"])
    lines.append("")
    lines.append("## 2. Chain of Command")
    lines.append("")
    lines.append("- **Reports to**: %s" % reports_line)
    if collaborators:
        lines.append(
            "- **Handoff destinations / collaborators**: %s"
            % ", ".join("`%s`" % c for c in collaborators)
        )
    else:
        lines.append(
            "- **Handoff destinations / collaborators**: none declared in catalog; "
            "escalate via Paperclip to the reporting lead above."
        )
    lines.append(
        "- **Execution posture**: on-demand worker. This role wakes when a ticket is assigned "
        "to it or its username is @mentioned; it never polls and never self-dispatches fleet work."
    )
    lines.append("")
    lines.append("## 3. Core Responsibilities & Workflows")
    lines.append("")
    lines.append(
        role["responsibilities"]
        if role["responsibilities"]
        else "See catalog specification for full responsibility matrix."
    )
    lines.append("")
    lines.append("## 4. MCP Servers & Tool Access")
    lines.append("")
    lines.append(
        role["mcp_spec"]
        if role["mcp_spec"]
        else "See catalog specification for MCP server details."
    )
    lines.append("")
    if rid in INTEGRATION_NOTES:
        lines.append("### Mandated integration endpoints (do not downgrade)")
        lines.append("")
        for note in INTEGRATION_NOTES[rid]:
            lines.append("- %s" % note)
        lines.append("")
    lines.append("## 5. Skills")
    lines.append("")
    for sk in role["skills"]:
        lines.append(
            "- `%s` — %s (procedure: `.opencode/skills/%s/SKILL.md`)"
            % (sk["name"], sk["description"], sk["name"])
        )
    if rid in SKILL_ALIASES:
        lines.append("")
        lines.append(
            "Skill-name cross-reference (fleet brief shorthand → catalog skill file):"
        )
        lines.append("")
        for brief_name, catalog_name in SKILL_ALIASES[rid]:
            lines.append("- `%s` is covered by `%s`." % (brief_name, catalog_name))
    lines.append("")
    if role["plugins_spec"]:
        lines.append("## 6. Plugins & Extensions")
        lines.append("")
        lines.append(role["plugins_spec"])
        lines.append("")
    lines.append("## 7. Per-Ticket Workflow (mandatory sequence)")
    lines.append("")
    lines.append(
        "1. **Triage the assignment.** Read the Paperclip ticket end to end, restate the objective "
        "and its acceptance criteria in the run transcript, and locate prior art via the "
        "codebase knowledge graph before asserting anything about repository structure."
    )
    lines.append(
        "2. **Execute the role skill.** Follow `.opencode/skills/<skill>/SKILL.md` step by step; "
        "do not skip verification sub-steps."
    )
    if write_paths:
        lines.append(
            "3. **Confine every write.** Filesystem writes are permitted only under: %s. "
            "Anything outside these scopes is rejected by the role permissions — fail closed, "
            "do not work around the denial."
            % ", ".join("`%s`" % p for p in write_paths)
        )
    else:
        lines.append(
            "3. **Read-only posture.** This role has no filesystem write scope: produce findings, "
            "advisories, or sign-off artifacts through the permitted reporting channel only."
        )
    if shell_cmds:
        lines.append(
            "4. **Verify with the allowed toolchain.** Run, at minimum: %s. "
            "Every command must exit cleanly; a failing verification blocks the handoff."
            % ", ".join("`%s`" % c for c in shell_cmds)
        )
    else:
        lines.append(
            "4. **Verification is evidence review.** This role has no shell execution scope: "
            "validate exclusively from inspectable artifacts (reports, logs, CI transcripts). "
            "An assertion without an inspectable artifact is invalid."
        )
    lines.append(
        "5. **Self-check for stubs.** Reject the run if any deliverable contains placeholders, "
        "unimplemented branches, or unverified claims; complete the implementation instead."
    )
    if reports_to is None:
        lines.append(
            "6. **Publish the decision.** Record the outcome as a durable artifact and dispatch "
            "follow-up directives downward to `product-director` and `system-architect`."
        )
    else:
        lines.append(
            "6. **Hand off.** Report completion, artifacts, and verification evidence to `%s` "
            "via Paperclip; flag blockers immediately instead of stalling." % reports_to
        )
    lines.append("")
    lines.append("## 8. Non-Negotiables & Zero-Stub Policy")
    lines.append("")
    lines.append(
        "- **Zero stubs**: no placeholder functions, no empty mocks, no `TODO: add later`, "
        "no dummy return values, no swallowed errors. Every interface and procedure ships complete."
    )
    lines.append(
        "- **Fail closed**: in invalid states reject immediately with a descriptive domain error; "
        "never default to permissive behavior."
    )
    lines.append(
        "- **Least privilege**: the `permissions` array in `opencode/opencode.json` ends with "
        "deny-all shell; only the explicitly listed commands above may execute."
    )
    lines.append(
        "- **Pinned versions**: no `:latest` tags in MCP commands, plugins, or packages."
    )
    lines.append(
        "- **No unilateral scope expansion**: never rewrite files outside section 7 step 3 scopes, "
        "never deploy to production, never apply destructive infrastructure changes from agent runtime."
    )
    lines.append("")
    lines.append("## 9. Completion Protocol & Quality Gates")
    lines.append("")
    lines.append(
        "- Deliverable exists at its mandated path, complete and internally consistent."
    )
    lines.append("- Role toolchain verification from step 4 passes with zero failures.")
    lines.append(
        "- Change set is minimal (confined blast radius) and committed on a clean branch with a "
        "descriptive message."
    )
    lines.append(
        "- Handoff report posted to the reporting lead with artifact paths and verification evidence."
    )
    lines.append("")
    lines.append("## 10. Budget & Wake Policy")
    lines.append("")
    lines.append(
        "- **Monthly budget cap**: $%.2f USD (%d cents)."
        % (dollars, role["budget_cents"])
    )
    if role["wake"]:
        lines.append("- **Catalog wake policy**: %s" % role["wake"])
    lines.append(
        "- **Fleet wake model**: on-demand on assignment/@mention%s."
        % (
            " plus a recurring heartbeat"
            if rid in ("exec-director", "tpm-scrum-lead")
            else "; no recurring heartbeat"
        )
    )
    lines.append("")
    return "\n".join(lines)


def render_agent_md(role):
    rid = role["role_id"]
    dollars = role["budget_cents"] / 100.0
    reports_to = REPORTS_TO[rid]
    desc = ("%s | %s" % (role["title"], role["department"])).replace("\n", " ").strip()
    parts = []
    parts.append("---")
    parts.append("name: %s" % rid)
    parts.append("description: %s" % desc)
    parts.append("---")
    parts.append("")
    parts.append(role["system_prompt"])
    parts.append("")
    parts.append("## Runtime Binding (Heretek-Crew Fleet)")
    parts.append("")
    parts.append("- Role ID: `%s` (fleet role %02d/50)." % (rid, role["num"]))
    parts.append(
        "- Model: `%s`."
        % (os.environ.get("MODEL_DEFAULT", MODEL_FALLBACK).strip() or MODEL_FALLBACK)
    )
    parts.append(
        "- Monthly budget cap: $%.2f USD (%d cents)." % (dollars, role["budget_cents"])
    )
    parts.append(
        "- Reports to: %s."
        % (
            "Human Board (no reportsTo key)"
            if reports_to is None
            else "`%s`" % reports_to
        )
    )
    parts.append(
        "- Isolated config: `/roles/%s/opencode/opencode.json` loaded via `XDG_CONFIG_HOME=/roles/%s`."
        % (rid, rid)
    )
    parts.append("")
    return "\n".join(parts)


def render_skill_md(skill):
    parts = []
    parts.append("---")
    parts.append("name: %s" % skill["name"])
    parts.append("description: %s" % skill["description"])
    parts.append("---")
    parts.append("")
    parts.append(skill["body"])
    parts.append("")
    return "\n".join(parts)


def main():
    ap = argparse.ArgumentParser(
        description="Scaffold the 50-agent Heretek fleet under roles/<role-id>/ "
        "from roles-catalog/0*.md (single source of truth)."
    )
    ap.add_argument(
        "--root",
        default=None,
        help="Repository root (default: parent of this script's directory).",
    )
    args = ap.parse_args()

    script_dir = Path(__file__).resolve().parent
    root = Path(args.root).resolve() if args.root else script_dir.parent
    catalog_dir = root / "roles-catalog"
    roles_dir = root / "roles"
    if not catalog_dir.is_dir():
        die("catalog directory not found: %s" % catalog_dir)

    dept_files = sorted(catalog_dir.glob("0*.md"))
    if len(dept_files) != 9:
        die("expected 9 department files (0*.md), found %d" % len(dept_files))

    roles = {}
    for dept_file in dept_files:
        text = dept_file.read_text(encoding="utf-8")
        headers = list(ROLE_HEADER_RE.finditer(text))
        for i, h in enumerate(headers):
            end = headers[i + 1].start() if i + 1 < len(headers) else len(text)
            role = parse_role_block(text[h.start() : end], dept_file.name)
            rid = role["role_id"]
            if rid in roles:
                die("duplicate role id parsed: '%s'" % rid)
            roles[rid] = role

    parsed = set(roles)
    expected = set(EXPECTED_IDS)
    if parsed != expected:
        die(
            "role set mismatch: missing=%s unexpected=%s"
            % (sorted(expected - parsed), sorted(parsed - expected))
        )

    model = os.environ.get("MODEL_DEFAULT", MODEL_FALLBACK).strip() or MODEL_FALLBACK
    total_cents = sum(roles[rid]["budget_cents"] for rid in EXPECTED_IDS)
    print("[generate] parsed 50/50 roles from %d catalog files" % len(dept_files))
    print("[generate] model=%s" % model)
    print("[generate] per-role budgets (cents):")
    for rid in EXPECTED_IDS:
        print("  %-22s %6d" % (rid, roles[rid]["budget_cents"]))
    print(
        "[generate] total fleet budget: %d cents ($%.2f USD)"
        % (total_cents, total_cents / 100.0)
    )
    if total_cents != DOCUMENTED_FLEET_CAP_CENTS:
        print(
            "[generate] WARNING: catalog per-role budgets sum to %d cents, "
            "which differs from the documented fleet cap of %d cents; "
            "per-role catalog values are authoritative and are used verbatim."
            % (total_cents, DOCUMENTED_FLEET_CAP_CENTS)
        )

    files_written = 0
    for rid in EXPECTED_IDS:
        role = roles[rid]
        config_text = normalize_config(role)
        perms = json.loads(config_text)["permissions"]
        base = roles_dir / rid
        (base / "opencode").mkdir(parents=True, exist_ok=True)
        (base / ".opencode" / "agents").mkdir(parents=True, exist_ok=True)

        (base / "opencode" / "opencode.json").write_text(config_text, encoding="utf-8")
        files_written += 1
        (base / "AGENTS.md").write_text(
            render_agents_md(role, perms, expected), encoding="utf-8"
        )
        files_written += 1
        (base / ".opencode" / "agents" / (rid + ".md")).write_text(
            render_agent_md(role), encoding="utf-8"
        )
        files_written += 1
        for skill in role["skills"]:
            skill_dir = base / ".opencode" / "skills" / skill["name"]
            skill_dir.mkdir(parents=True, exist_ok=True)
            (skill_dir / "SKILL.md").write_text(
                render_skill_md(skill), encoding="utf-8"
            )
            files_written += 1

    print(
        "[generate] wrote %d files across 50 roles under %s"
        % (files_written, roles_dir)
    )
    print(
        "[generate] done: roles=50 files=%d budget_total_cents=%d"
        % (files_written, total_cents)
    )


if __name__ == "__main__":
    main()
