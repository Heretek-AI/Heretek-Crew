---
name: design-critique
description: Structured visual critique of implemented UI against spec. Trigger when reviewing any UI build or screenshot.
---

# Design Critique Skill

When this skill is active, follow this procedure exactly:

1. **Gather:** open the running UI via the browser, capture screenshots at
   the spec's breakpoints (mobile, tablet, desktop minimum).
2. **Compare** each screen against the spec across five axes: layout/alignment,
   spacing rhythm, typography scale, color/token usage, responsive behavior.
3. **Accessibility pass:** contrast ratios, visible focus order, keyboard-only
   path, form labels/ARIA roles. Any failure is a REVISE blocker.
4. **Verdict:** APPROVE (no deltas) or REVISE (annotated delta list: element,
   expected, actual, screenshot reference, token to apply).
5. Report evidence: screenshots per breakpoint, axis-by-axis findings, and the
   APPROVE/REVISE verdict. Never approve unseen UI.
