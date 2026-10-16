# Ecosystem Repository Evaluation: Triad Adversarial Council Report

**Target Platform**: Heretek-Crew (Paperclip Orchestrator + OpenCode v2 2.0.31 + 50 Fleet Roles + Docker Sidecars)  
**Evaluation Council**: The Fleet Capability Advocate ("The Builder") vs. The Security & Reliability Skeptic ("The Gatekeeper") $\rightarrow$ Principal Systems Architect ("The Arbiter")  
**Date**: October 2026  
**Status**: Completed & Verified  

---

## 1. Executive Summary & Verdict Scorecard

A total of **41 open-source repositories** across 6 domains were subjected to adversarial cross-examination. Each tool was evaluated under strict architectural invariants:
- **Zero-Stub Policy**: No placeholder skills, mock returns, or unfinished wrappers.
- **Principle of Least Privilege (PoLP)**: Explicit command allowlists ending with `{ "action": "shell", "resource": "*", "effect": "deny" }`.
- **Strict Version Pinning**: Zero `:latest` tags; every package, binary, and image pinned.
- **On-Demand Execution**: 48/50 roles wake strictly on assignment/mention.
- **Sidecar Isolation**: Compute-heavy or privileged services run isolated on the `heretek` network.

### Verdict Tally
| Verdict | Count | Architectural Action |
| :--- | :---: | :--- |
| **`ADOPT IMMEDIATELY`** | **7** | Production-ready; integrate directly into role specs, CI gates, or sidecars. |
| **`ADAPT / EXTRACT CONCEPTS`** | **15** | Extract procedural prompts, patterns, or heuristics into zero-dependency `SKILL.md` files. |
| **`WATCHLIST`** | **10** | Promising innovation; requires version stability, license verification, or benchmark bake-offs. |
| **`REJECT`** | **9** | Redundant with existing stack, severe security/supply chain risk, or domain mismatch. |
| **Total** | **41** | |

---

## 2. Complete Repository Decision Matrix

| # | Repository | Category | Verdict | Target Role(s) | Integration Mechanism | Key Rationale |
|---|---|---|---|---|---|---|
| 1 | `vercel-labs/skills` | Skills & Packs | **ADAPT** | All 50 roles | Pinned CLI `skills@0.2.7` | Distro utility; restrict to allowlisted URLs; disable telemetry |
| 2 | `mattpocock/skills` | Skills & Packs | **ADAPT** | `ts-node-fullstack`, `static-analysis-lead` | 4–6 zero-dep `SKILL.md` files | Cherry-pick TS/refactoring patterns; avoid ritual stacking |
| 3 | `anthropics/skills` | Skills & Packs | **ADOPT** | All 50 roles | Standard spec baseline | Conformance baseline for frontmatter & discovery metadata |
| 4 | `addyosmani/agent-skills` | Skills & Packs | **ADAPT** | `system-architect`, `ts-node-fullstack` | Per-role `SKILL.md` slices | Extract DEFINE$\rightarrow$SHIP lifecycle & performance heuristics |
| 5 | `alirezarezvani/claude-skills` | Skills & Packs | **WATCHLIST** | `compliance-auditor` (≤5 skills) | SkillSpector-gated cherry-pick | Massive 380-skill sprawl with high surface area; audit first |
| 6 | `obra/superpowers` | Skills & Packs | **ADAPT** | `exec-director`, `system-architect` | Isolated experimental pilot | Disable telemetry; keep worktree manipulations isolated |
| 7 | `OthmanAdi/planning-with-files` | Skills & Packs | **ADOPT** | `tpm-scrum-lead`, `system-architect` | Core infrastructure `SKILL.md` | Disk-persisted context surviving compaction in long runs |
| 8 | `phuryn/pm-skills` | Skills & Packs | **ADAPT** | `product-director`, `tpm-scrum-lead` | PM `SKILL.md` subset | Epic decomposition and acceptance criteria templates |
| 9 | `virgiliojr94/book-to-skill` | Skills & Packs | **ADAPT** | `tech-docs-lead` | Offline build-time tool | Ingest proprietary architecture manuals into clean skills |
| 10 | `NVIDIA/SkillSpector` | Skills & Packs | **ADOPT** | `static-analysis-lead`, `appsec-engineer` | CI/CD SARIF security gate | 71 security patterns; blocks prompt-injection before skills land |
| 11 | `nextlevelbuilder/ui-ux-pro-max-skill` | UI/UX & Design | **ADAPT** | `ui-ux-designer` | Vendored `SKILL.md` | Comprehensive design critique; pin to exact release tag |
| 12 | `leonxlnx/taste-skill` | UI/UX & Design | **ADOPT** | `design-system-eng`, `ui-ux-designer` | `SKILL.md` + Browserless | Art-direction, type scale, and anti-slop visual check |
| 13 | `pbakaus/impeccable` | UI/UX & Design | **ADAPT** | `design-system-eng`, `ui-ux-designer` | Pinned `npx impeccable@1.4.0` | 59 deterministic UI detectors; run before LLM critique |
| 14 | `DietrichGebert/ponytail` | UI/UX & Design | **WATCHLIST** | None in Category B | Revisit as lint rule | Useful for CSS de-bloating, but duplicates Tailwind linters |
| 15 | `nexu-io/open-design` | UI/UX & Design | **REJECT** | None | — | 3.5 GB monorepo, 1,178 issues; duplicates Browserless/Figma |
| 16 | `nexu-io/html-anything` | UI/UX & Design | **ADAPT** | `tech-docs-lead` | CLI + Gotenberg | Clean HTML component rendering pipeline |
| 17 | `cathrynlavery/diagram-design` | UI/UX & Design | **ADOPT** | `tech-docs-lead`, `system-architect` | Vendored `SKILL.md` | 45 self-contained HTML+SVG diagrams (no Mermaid limits) |
| 18 | `blader/humanizer` | UI/UX & Design | **ADOPT** | `brand-copy-spec`, `tech-docs-lead` | Micro `SKILL.md` (~238 KB) | De-AI microcopy; strips LLM tells & filler words |
| 19 | `viettranx/3dviz-pro-max` | 3D & Gaming | **ADAPT** | `graphics-shader-eng` | `SKILL.md` + Browserless capture | 223 Three.js/WebGL recipes; run execution via Piston |
| 20 | `Donchitos/Claude-Code-Game-Studios` | 3D & Gaming | **ADAPT** | `game-systems-dev`, `engine-systems-eng` | Trimmed specialist slices | Extract visual evidence gates for Unity/Godot/Unreal |
| 21 | `heygen-com/hyperframes` | 3D & Gaming | **ADOPT** | `tech-artist-pipeline` | Pinned CLI + MCP | Programmatic video generation; renders trailers & cutscenes |
| 22 | `smixs/creative-director-skill` | 3D & Gaming | **REJECT** | None | — | Ad-agency ideation focus; stale since Aug 2026; CC-BY-4.0 |
| 23 | `mvschwarz/openrig` | 3D & Gaming | **REJECT** | None in Category C | — | Miscategorized orchestrator/harness; overlaps Paperclip |
| 24 | `alibaba/open-code-review` | Review & Arch | **WATCHLIST** | `static-analysis-lead` (Pilot) | Pinned CLI + MCP | Hybrid deterministic + LLM review; pilot token precision first |
| 25 | `tt-a1i/archify` | Review & Arch | **ADAPT** | `system-architect` | Diagram-as-code viz aid | Extract structural visualization without heavy dependencies |
| 26 | `danium/lateral-thinking` | Review & Arch | **REJECT** | None | — | Unanchored prompt collection; no code or tool integration |
| 27 | `3xpyth0n/ideon` | Review & Arch | **REJECT** | None | — | AGPL-3.0 copyleft risk + off-domain visual canvas |
| 28 | `pascalorg/editor` | Review & Arch | **REJECT** | None | — | Building/BIM architecture software; domain mismatch |
| 29 | `feder-cr/invisible_dots` | Review & Arch | **REJECT** | None | — | Anti-bot stealth patches in C++; ToS and abuse risk |
| 30 | `spectrayan/spector` | Review & Arch | **WATCHLIST** | `vector-rag-spec` | Bake-off vs codebase-memory | Java 25 codebase indexing; run benchmark bake-off first |
| 31 | `titanwings/distilly` | Review & Arch | **WATCHLIST** | `ux-research-analyst` | Scoped privacy pilot | Context distillation tool; evaluate persona leakage risk |
| 32 | `topoteretes/cognee` | Memory & Graphs | **REJECT** | None | — | Monolithic second stack; completely duplicates Neo4j + Qdrant |
| 33 | `supermemoryai/supermemory` | Memory & Graphs | **WATCHLIST** | `vector-rag-spec` | Managed API evaluation | Complex self-host (Cloudflare/Drizzle); test as API only |
| 34 | `MemoriLabs/Memori` | Memory & Graphs | **WATCHLIST** | `observability-eng` | Execution trace pilot | Captures tool outcomes; verify Apache-2.0 license text |
| 35 | `NevaMind-AI/memU` | Memory & Graphs | **ADAPT** | `system-architect`, `git-drift-coord` | Lightweight SQLite sidecar | 500-line core; cleanest local memory architecture |
| 36 | `semantica-agi/semantica` | Memory & Graphs | **REJECT** | None | — | Heavy polyglot graph framework; overlaps existing sidecars |
| 37 | `EverMind-AI/EverOS` | Memory & Graphs | **WATCHLIST** | `vector-rag-spec` | Alternative to memU | Modern SQLite/LanceDB design; track project maturity |
| 38 | `dolthub/dolt` | Data & Storage | **WATCHLIST** | `dba-specialist`, `data-pipeline-eng` | Sidecar profile candidate | Git-for-data; evaluate Doltgres (Postgres wireline) first |
| 39 | `K-Dense-AI/scientific-agent-skills` | Domain Specialists | **ADAPT** | `data-pipeline-eng` | 5–10 curated skills | 471 MB bulk repo; extract specific DB and matrix skills |
| 40 | `coreyhaines31/marketingskills` | Domain Specialists | **ADAPT** | `ux-research-analyst` | Pinned CRO/SEO subset | Conversion rate optimization & user research checklists |
| 41 | `career-ops-hq/career-ops` | Domain Specialists | **REJECT** | None | — | Job search automation; domain mismatch for engineering fleet |

---

## 3. Top 5 High-Impact Adoptions

1. **`NVIDIA/SkillSpector` (#10)**:
   - **Why**: The only dedicated security gate scanning agent skills for prompt-injection, data exfiltration, and malicious execution patterns across 71 detection rules with SARIF output.
   - **Integration**: Placed into CI/CD validation before any skill lands in `roles/`.
2. **`OthmanAdi/planning-with-files` (#7)**:
   - **Why**: Solves the context-window compaction problem in long-running Paperclip tickets by persisting state to `task_plan.md`, `findings.md`, and `progress.md`.
   - **Integration**: Installed as a standard skill for `tpm-scrum-lead`, `system-architect`, and complex engineering roles.
3. **`anthropics/skills` Spec Baseline (#3)**:
   - **Why**: Establishes strict metadata, frontmatter, and discovery standards across all 50 roles to prevent skill sprawl.
   - **Integration**: Used as the template standard for all generated `SKILL.md` files.
4. **`pbakaus/impeccable` (#13) + `leonxlnx/taste-skill` (#12)**:
   - **Why**: Creates a deterministic visual design loop: 59 automated layout detectors combined with typography/spacing rules, verified via headless screenshots in `browserless`.
   - **Integration**: Merged into `impeccable-taste` skill for `design-system-eng` and `ui-ux-designer`.
5. **`alibaba/open-code-review` (#24 — Pilot)**:
   - **Why**: Bridges static AST analysis (ast-grep, Semgrep) with multi-pass semantic LLM code review (NPEs, concurrency, security reachability).
   - **Integration**: Piloted under `static-analysis-lead`.
