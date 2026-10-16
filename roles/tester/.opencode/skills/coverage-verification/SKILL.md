---
name: coverage-verification
description: Verify a submission with new tests and a no-decrease coverage gate. Trigger on every verification ticket.
---

# Coverage Verification Skill

When this skill is active, follow this procedure exactly:

1. **Baseline:** run the relevant suite with coverage on the pre-change code
   (or record the programmer-reported baseline) — `npm test -- --coverage`,
   `vitest --coverage`, `pytest --cov`, or `cargo tarpaulin`, per repo.
2. **Close gaps:** add unit tests for new branches, integration tests for new
   seams, and a regression test per fixed bug. No assertion-free tests.
3. **Re-run** the full suite with coverage. All green and coverage delta >= 0,
   or the verdict is FAIL.
4. **Verdict:** PASS (criteria met, suite green, coverage held/increased) or
   FAIL (failing tests + logs + suspected cause, back to programmer via PM).
5. Report evidence: exact commands, pass/fail counts, coverage before/after.
