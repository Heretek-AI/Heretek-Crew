---
name: zero-stub-implementation
description: Test-first implementation loop with zero-stub enforcement. Trigger on every implementation or fix ticket.
---

# Zero-Stub Implementation Skill

When this skill is active, follow this procedure exactly:

1. **Restate** the ticket's acceptance criteria as a checklist.
2. **Red:** write failing tests that encode each criterion (reproduce the bug
   first for fixes). Run them; confirm they fail for the right reason.
3. **Green:** implement the minimal production change. If a helper does not
   exist, build it completely — never stub, mock emptily, or `TODO` it.
4. **Refactor:** clean up without changing behavior; re-run the suite.
5. **Verify:** run the relevant suite (`npm test` / `vitest` / `pytest` /
   `cargo test`) plus formatter/linter. Scan your own diff for forbidden
   patterns: `TODO`, dummy `return true`, `catch {}`, `|| true`, `set +e`,
   tests without assertions. Remove every occurrence.
6. Report: files changed, tests added, results, and criterion-by-criterion
   mapping for tester/QA review.
