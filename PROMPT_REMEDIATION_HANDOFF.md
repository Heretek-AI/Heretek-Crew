# REMEDIATION HANDOFF PROMPT — Heretek-Crew Post-Audit Fix Cycle

**Target codebase:** `/home/john/Projects/Heretek-Crew`
**Input:** `AUDIT_REPORT_FINDINGS.md` (adversarial Alpha/Beta/Gamma audit, 2026-10-17 — normative)
**Objective:** Remediate all P0 + P1 findings in priority order, verify empirically (do not trust tests alone), leave tree green on `make test` + `bash scripts/smoke-test.sh --check-only` + `shellcheck`.

---

## 1. Rules of engagement (from `AGENTS.md` — non-negotiable)

1. **Zero-stub:** no `TODO`, `return true`, empty `catch {}`, fake mocks. Fully functional, fail-closed code only.
2. **Least privilege:** every `roles/*/opencode/opencode.json` ends in its dialect deny tail (`shell/*deny` fleet, `bash/*deny` legacy until removed). Never rely on prefix `shell` allows as a sandbox.
3. **No floating versions:** exact pins only. No `:latest`, `@latest`, unversioned installs.
4. **Shell standards:** `set -euo pipefail`, `shellcheck` zero warnings, `--dry-run` + `--help` on state-changing scripts.
5. **Secret hygiene:** never commit keys; `.env` stays gitignored; never echo tokens. New required secrets go in `.env.example` as `CHANGE_ME__` + `:?` guards.
6. **Commands:** use `make test`, `bash scripts/smoke-test.sh --check-only`, never ad-hoc bypasses.

## 2. Execution order (do in this sequence, commit per wave)

### Wave 1 — Broken registration + live CVEs (P0-1, P0-6, P0-7)
- [ ] P0-1: 50 fleet `roles/*/opencode/opencode.json`: `"opencode-harness"` → `"@heretek-ai/opencode-harness"`. Verify with `python3 -c` + `grep -rh plugins` and `opencode plugin list` (or host-test in built image).
- [ ] P0-6: `docker-compose.sidecars.yml:208` `gotenberg:8.15.0` → `8.33.0` minimum (prefer latest 8.3x). Re-run smoke.
- [ ] P0-7: `docker-compose.sidecars.yml:76` `rabbitmq:3.13.7` → `4.3.6-management-alpine`. Run Firecrawl crawl-queue smoke (quorum-queue defaults changed).

### Wave 2 — Sandbox escapes (P0-2, P0-3, P0-4, P0-5 + P1-8 secrets)
- [ ] P0-2: close MCP↔shell overlaps. `k8s-orchestrator` (`kubernetes_*/docker_*` → read/list-only + deny tails), `dba-specialist` (`postgres_*` → read-only URL only), `cloud-platform-eng` (`aws_*` scoping), `mlops-serving-eng` (`docker_*` deny), `git_*`→read verbs where push not required, `filesystem_*` re-root from `/paperclip/workspaces` to role write scope (or remove from docs-scoped roles).
- [ ] Provision: real read-only Postgres role + `POSTGRES_READONLY_URL` (no `:-default`), `GITHUB_TOKEN` scoping, `/paperclip/secrets/kubeconfig-readonly` via read-only volume — or fail `seed --dry-run` if absent. Add all three to `.env.example` + compose with `:?` guards.
- [ ] P0-3: enumerate harness tools (`npm explore @heretek-ai/opencode-harness`), replace `harness_*` allow-all (51 roles) with per-tool allows; add manifest assertion to `smoke-test.sh §3b` + live deny-tail probe.
- [ ] P0-5: `roles/git-drift-coord/opencode/opencode.json`: remove `rebase*`, `push --force-with-lease*`, `worktree*`; scope `git_*` MCP to read verbs; pushes behind human approval (`PAPERCLIP_TOOL_ACTION_SIGNING_SECRET`).
- [ ] P0-4: add negative prefix-probe cases to `smoke-test.sh §3b` (`git status; id`, `npm test && id`, `curl -s http://x; id` must deny). Document shell allows as advisory-only.

### Wave 3 — Claims + topology (P1-1, P1-2, P1-3, P1-9, P1-11)
- [ ] P1-1: reconcile $90 gap. `seed-50-fleet.sh:95` cap `1270000` vs `ROLE_CATALOG_50.md:119` `$12,790`. Re-sum table; fix one side (one-line diff).
- [ ] P1-2: `docker-compose.sidecars.yml:719-720` — drop `external: true` (keep `name: heretek`) OR add `docker network create heretek || true` to Makefile sidecar targets + README.
- [ ] P1-3: decide CI-runner: (a) document as read-only observer (CI via host `act`), or (b) dedicated `ci` net + full socket, proxy out of path. Remove design contradiction either way.
- [ ] P1-9: `docker-compose.prebuilt.yml:29` — `git tag v1.0.0 && git push origin v1.0.0`, or retarget to published `sha-<sha>` digest + quickstart fix.
- [ ] P1-11 + P2-1: delete 6 legacy `roles/{designer,director,pm,programmer,qa,tester}/` if superseded, or migrate to fleet dialect + harness plugin. Goal: `ls roles/ | wc -l` = 50, single dialect.

### Wave 4 — Hardening + version bumps (P1-4, P1-5, P1-6, P1-7, P1-10, P1-12, P2)
- [ ] P1-4: `redis:7.4.1` → `7.4.11-alpine` ×2 + `requirepass`.
- [ ] P1-10: `semgrep:1.97.0→1.181.0`, `qdrant:v1.12.5→v1.19.2` (+verify `mcp-server-qdrant==0.8.1`), `neo4j:5.26.0-bullseye→5.26.30+-trixie`, `minio` via authed `skopeo` digest-pin (note AGPL implication), `jaeger:1.63.0→jaegertracing/jaeger:2.22`, vendor `piston` to `ghcr.io/heretek-ai/piston:<semver>`.
- [ ] P1-5/P1-7: split write+exec synergies (pin exact paths; builds in piston/CI); anchor `fs:write` globs (`**/package-lock.json`, `docs/**/*.md`); add glob-specificity lint rejecting `*substring*`.
- [ ] P1-6/P1-12: remove open `curl`; segment sidecar nets per category; Redis/Qdrant auth; Makefile guard refusing `--profile mobile` + `devsec`/`web-research` co-scheduling; runner workspaces ro except scratch.
- [ ] P2: `dispatch-pipeline.sh` header → provisioner (or implement dispatch); add `REPO_ROOT`+`cd` to `dispatch-pipeline.sh` + `worktree-manager.sh`; close `--session ses-` assumption with live stack run; add per-profile resource table to `SUPPORTING_SERVICES.md`; `age`/`gpg` for `backups/*.sql.gz`; pin `sabotage-qa-tester` to piston/CI.
- [ ] P2-7/P2-8: bump `server-github@2025.4.8`, `@playwright/mcp@0.0.83`; confirm goal-plugin scope (director-only vs fleet).

## 3. Verification gate (every wave)

```bash
make test                                    # 39/39 shim assertions
bash scripts/smoke-test.sh --check-only      # 48+ static assertions
shellcheck -S warning scripts/*.sh
bash -n scripts/*.sh
grep -rn ':latest' docker-compose*.yml docker/Dockerfile || echo "clean"
grep -L 'deny' roles/*/opencode/opencode.json || echo "all tails present"
python3 -c "import re; txt=open('scripts/seed-50-fleet.sh').read(); b=txt[txt.index('role_budget_cents'):txt.index('unknown role')]; v=re.findall(r\"printf '(\d+)'\",b); print(len(v),sum(map(int,v)))"
docker compose -f docker-compose.yml -f docker-compose.sidecars.yml config > /dev/null
```

Plus live negative probes (P0-4) and one `--profile`-matrix `up` + `docker ps --format health` sweep for P3-4 items.

## 4. Deliverables

1. Per-wave commits (Wave 1 → Wave 4), each green on gate above.
2. Updated `AUDIT_REPORT_FINDINGS.md` checkboxes or `REMEDIATION_LOG.md` entries: finding → diff → proof command + output.
3. No new `:latest`, no new `*substring*` globs, no new `*_ *` MCP wildcards without paired deny tail.
4. Handoff back: remaining P2/P3 list with owner + next-bump-cycle versions.

## 5. Non-goals

Do not redesign fleet topology (50 roles / 9 depts / heartbeat policy verified sound). Do not migrate Paperclip base image or Node major. Do not weaken `POST/BUILD/EXEC=0` socket-proxy posture to "fix" CI — use Wave-3 option (a)/(b) instead.

---

**Start:** Wave 1. First command: `grep -n 'opencode-harness' roles/vector-rag-spec/opencode/opencode.json docker/Dockerfile` then apply P0-1 diff across fleet.
