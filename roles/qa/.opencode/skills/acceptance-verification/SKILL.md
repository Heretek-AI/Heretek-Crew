---
name: acceptance-verification
description: End-to-end acceptance with mandatory red-proof. Trigger on every acceptance ticket.
---

# Acceptance Verification Skill

When this skill is active, follow this procedure exactly:

1. **Preconditions:** confirm acceptance criteria and tester PASS exist. If
   not, FAIL the ticket back to the PM with the missing item named.
2. **Script the user path:** drive the running app end-to-end (Playwright
   browser steps or public-interface script). Capture screenshots/logs at
   each acceptance-relevant step.
3. **Red-proof:** run the same check against the unfixed/baseline behavior
   (or a known-bad input) and record it FAILING. A check that cannot fail is
   not evidence — redesign it until it can.
4. **Green run:** run against the fixed build; record it PASSING with the
   same steps and evidence.
5. **Verdict:** PASS only when every criterion is demonstrated with red+green
   evidence. Otherwise FAIL with the exact failing step, evidence, and
   reproduction. Re-run flakes to a stable green; never waive them.
6. Report: criterion mapping, environment, steps, red evidence, green
   evidence, verdict.
