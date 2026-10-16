---
name: task-decomposition
description: Decompose a Director directive into gated tickets with acceptance criteria. Trigger on every new directive or bug report.
---

# Task Decomposition Skill

When this skill is active, follow this procedure exactly:

1. **Parse the directive:** extract objective, constraints, success criteria.
   If any is missing, ask the Director — do not invent it.
2. **Triage:** classify as feature / bug / refactor / design. For bugs, add a
   reproduction ticket (tester or qa) before the fix ticket (programmer).
3. **Decompose** into the smallest tickets that each deliver one verifiable
   outcome. Assign each to exactly one role (programmer / tester / qa /
   designer) with explicit acceptance criteria.
4. **Order with gates:** implementation → coverage verdict → acceptance
   verdict. State the gate order on every ticket chain.
5. **Emit a tracking table** (ticket, assignee, criteria, status) in your
   completion report and update it on every status change.
