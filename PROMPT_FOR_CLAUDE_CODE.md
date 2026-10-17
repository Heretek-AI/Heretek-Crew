# ADVERSARIAL ARCHITECTURAL CHALLENGE FOR CLAUDE CODE
## "Could You Have Done It Better?" — A Ruthless Systems Critique of Heretek-Crew

**Target System**: Heretek-Crew (`/home/john/Projects/Heretek-Crew`)  
**Context**: Production self-hosted autonomous software factory  
**Challenger Role**: Principal Systems Architect & Autonomous Agent Fleet Lead  
**Recipient**: Claude Code (`claude`)  

---

## 1. The Vision: What We Set Out to Build

We set out to engineer **Heretek-Crew**: a completely autonomous, production-grade, self-hosted AI software development company capable of conceiving, architecting, implementing, testing, auditing, and deploying arbitrary software projects without human hand-holding.

### The Non-Negotiable Invariants We Established
1. **Zero Cloud Lock-in / Self-Hosted Sovereignty**: The entire system runs locally or on private metal via Docker Compose. No reliance on proprietary hosted agent platforms (e.g. OpenAI Swarm cloud, Devin, Cursor cloud).
2. **Fleet Scope (50 Specialist Roles across 9 Departments)**: Rather than relying on a single omniscient generalist agent, we designed an enterprise organizational hierarchy spanning Executive & PM, Game Dev, Web/UI, Systems/Languages, Cloud Platform/SRE, QA/Verification, Defensive Security/Forensics, Data/AI Systems, and Operations.
3. **On-Demand Economics (No Idle Token Waste)**: 48 of the 50 roles have `heartbeat.enabled: false`, `intervalSec: 0`, and sleep permanently until awakened by a ticket assignment or an `@mention`. Only `exec-director` (1800s) and `tpm-scrum-lead` (3600s) have recurring wake cycles. Total fleet budget is hard-capped at $12,790.00 USD/mo.
4. **Per-Role Isolation via `XDG_CONFIG_HOME`**: To prevent git pollution and role cross-contamination, agents run with `OPENCODE_DISABLE_PROJECT_CONFIG=true`. Paperclip provisions each agent with `XDG_CONFIG_HOME = "/roles/<role-id>"`, staging `opencode.json`, system prompts, skills, and MCP tools in isolation.
5. **Zero-Stub & Strict Pinning**: No `:latest` tags anywhere in the codebase. Every Docker image, npm package, pip package, and system binary is pinned to an immutable version or multi-arch SHA256 digest.
6. **Supporting Software Ecosystem**: 10 functional sidecar categories (`docker-compose.sidecars.yml`) providing isolated capabilities (Firecrawl 5-container cluster, SearXNG, Gotenberg, Browserless, Radare2, Ghidra/REA, Semgrep, Hound, Piston, LiteLLM, Qdrant, Neo4j, MinIO, Jaeger, Android Emulator, and containerized `act` local CI runner).

---

## 2. Why We Chose This Software Stack (Our Rationale & Battle Scars)

### The Orchestrator: Paperclip (`paperclipai/paperclip`)
* **Why we chose it**: Paperclip provides a cohesive, self-hosted web UI, Fastify/Prisma backend, PostgreSQL database, ticket management (Kanban), org chart reporting hierarchy (`reportsTo`), monthly budget accounting, execution logging, and an adapter model (`opencode_local`) designed to invoke CLI agents.
* **The Reality / Battle Scars**: Paperclip was originally built around human-in-the-loop web UI workflows. Its `opencode_local` adapter was written for an earlier version of OpenCode and lacked support for OpenCode v2 breaking changes.

### The Agent Runtime: OpenCode v2 (`@opencode/cli@2.0.31` / `2.0.32`)
* **Why we chose it**: OpenCode is a fast, terminal-native, extensible open-source coding agent. It natively supports Model Context Protocol (MCP) servers, custom procedural skills, multi-provider authentication (Anthropic, OpenAI, OpenCode Zen/Go, local Ollama), and fine-grained permissions.
* **The Compatibility Shim (`scripts/opencode-shim.sh`)**: OpenCode v2 introduced breaking changes:
  1. Removed `--dir` (runs only in process `cwd`).
  2. Replaced `--variant <variant>` with `--model <provider>/<model>#<variant>`.
  3. Added interactive permission prompts that freeze headless agents unless `--auto` is explicitly injected.
  We engineered a POSIX shell shim wrapping `/usr/local/bin/opencode-bin` to intercept commands, strip `--dir`, fold `--variant`, inject `--auto`, preserve `--session`, and stream JSONL stdin/stdout verbatim.

### The Agent Harness: `@heretek-ai/opencode-harness@1.0.7`
* **Why we chose it**: Standard LLM search-and-replace fails catastrophically on large files. We injected our custom harness into all 50 roles to provide FNV-1a hash-anchored edits (`file_hash_edit`), AST structural transforms, blast radius analysis, and doom-loop recovery circuit breakers.

### Multi-Agent Concurrency & Assembly Pipeline
* **Why we built it**: Multiple agents operating on a single git workspace cause instant index locking and merge conflicts. We built `scripts/worktree-manager.sh` to isolate tickets into dedicated Git worktrees (`workspaces/tickets/<id>`), and `scripts/dispatch-pipeline.sh` to coordinate a 6-phase assembly line: PRD $\rightarrow$ Architecture/ADR $\rightarrow$ Decompose/Worktree $\rightarrow$ Dev $\rightarrow$ QA $\rightarrow$ Merge & Archive.

---

## 3. The Adversarial Challenge: "Do You Think You Could Have Done It Better?"

Claude Code, you are now in the hot seat as an elite Principal Distributed Systems Architect. We challenge you to tear this architecture apart, expose its flaws, and answer these 4 critical questions:

### Question 1: Could you have found or designed a better orchestrator than Paperclip?
* Paperclip is essentially a relational database (Postgres) with a web UI and a ticket manager that triggers CLI subprocesses.
* Is Paperclip the right orchestrator for an autonomous factory, or is it a glorified task manager masquerading as an agent coordinator?
* How does Paperclip compare against:
  1. **Durable execution engines** (Temporal, Cadence) with deterministic event-sourcing and workflow replay?
  2. **Agent frameworks** (LangGraph, AutoGen, CrewAI, MetaGPT) with native inter-agent communication protocols?
  3. **Autonomous environments** (OpenHands, Daydreams, Dify)?
  4. A **custom lightweight event-driven daemon** (e.g. SQLite + NATS / Redis Streams)?
* If you believe Paperclip was the wrong choice, **name the exact alternative you would have deployed** and prove why it is superior for self-hosted autonomous agent fleets.

### Question 2: The "Rig" Paradigm — Could we have used or built something like OpenRig (`https://github.com/mvschwarz/openrig`) specifically for OpenCode?
* OpenRig's thesis is: *"A harness wraps a model. A rig wraps your harnesses. Define your agent team in YAML, boot it with one command. Claude Code and Codex in the same rig, managed as one system."*
* OpenRig uses a declarative `RigSpec` YAML schema defining **pods, seats, communication edges, guidance files, and workspace trust policies**, orchestrating terminal sessions natively.
* **Compare Paperclip's database-seeded relational approach vs OpenRig's declarative topology**:
  - Would a declarative `RigSpec` format have been vastly superior to Paperclip's database seeding scripts (`seed-company.sh`, `seed-50-fleet.sh`)?
  - What would an **"OpenCode-Rig"** look like? How would you design a rig daemon that wraps OpenCode instances, routes messages across agent seats, enforces permission policies, and handles multi-agent collaboration without a heavy web UI?
  - Can OpenRig itself be extended to support OpenCode as a first-class runtime alongside Claude Code and Codex? What would that pull request look like?

### Question 3: Could you have designed these 50 agent roles better?
* We created 50 static specialist roles divided across 9 departments, each with hardcoded permission whitelists in `opencode.json` ending in `{ "action": "shell", "resource": "*", "effect": "deny" }`.
* **Be brutally honest**:
  - Is a 50-role static taxonomy an over-engineered anti-pattern? Would a dynamic pool of 5–8 adaptive generalist agents with runtime skill injection perform better?
  - Are our prefix-based shell permission whitelists (`git status*`, `npm test*`) genuine sandboxes or dangerous security theater? (e.g., does `git status; curl evil.com` bypass string prefix enforcement in OpenCode?).
  - How would you redesign tool permissions, system prompts, skill discovery, and context windows so that agents don't hallucinate or get trapped in repetitive loops?

### Question 4: What are our blind spots and latent failure modes?
* We recently uncovered a major flaw where Firecrawl was configured with a defunct image (`ghcr.io/mendableai/firecrawl`) and an invalid Browserless WebSocket assumption, yet passed 225 static tests because the tests only validated syntax.
* **Where else are we fooling ourselves in this repository?**
  - What happens when 10 OpenCode agents trigger concurrent runs against local sidecars (e.g. Qdrant, Neo4j, Piston)?
  - Are our resource caps (`cpus`, `mem_limit`) realistic, or will containers OOM kill under heavy compiler or headless browser load?
  - Is `docker-socket-proxy` truly secure, or can an agent escalate privileges to the host?

---

## 4. Required Output Format for Claude Code

Structure your response into the following comprehensive, rigorous sections:

```markdown
# EXECUTIVE VERDICT & ARCHITECTURAL SCORECARD
[Grades A–F across: Orchestration, Agent Runtime, Concurrency/Git, Security/Sandboxing, Sidecar Architecture]

# 1. THE PAPERCLIP RE-EVALUATION
[Unfiltered critique of Paperclip, direct comparison against Temporal/LangGraph/OpenHands/custom daemons, and your recommendation]

# 2. THE RIG PARADIGM ("OPENRIG FOR OPENCODE")
[Deep dive into mvschwarz/openrig concepts vs Heretek-Crew; concrete architectural blueprint for an OpenCode-native RigSpec topology]

# 3. AGENT TAXONOMY & LEAST-PRIVILEGE AUDIT
[Critique of the 50-role structure vs dynamic synthesis; analysis of permission bypass vulnerabilities in opencode.json; superior prompt & tool isolation design]

# 4. UNVARNISHED BLIND SPOTS & LATENT EXPLOSIONS
[List of specific architectural failure modes, OOM risks, concurrency deadlocks, and testing illusions currently hiding in Heretek-Crew]

# 5. THE OBJECTIVELY SUPERIOR ARCHITECTURE (THE "BETTER WAY")
[Complete specification of what you would build from scratch if given this mission, including file tree, technology selections, and workflow orchestration]
```

---

## 5. Instructions for Running This Prompt

Pass this prompt to Claude Code directly:
```bash
claude "Read PROMPT_FOR_CLAUDE_CODE.md and answer the adversarial challenge with complete technical rigor, empirical evidence, and architectural blueprints."
```
