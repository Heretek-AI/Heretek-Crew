---
name: adversarial-mutation-sabotage
description: Deliberately mutates conditions and injects network faults to verify test suites catch failures and services recover gracefully.
---

# Adversarial Mutation Sabotage Procedure

1. Read the target service code and identify critical logic branches.
2. Formulate chaos scenarios:
   - Sudden database connection drop during write transaction.
   - Malformed JSON/Protobuf payload with boundary-exceeding numbers or negative integers.
   - Downstream service returns continuous 503 or 10-second timeout.
3. Author isolated chaos test in `tests/chaos/`.
4. Run mutation testing:
   - For Rust: `cargo mutants`.
   - For TypeScript: `npx stryker run`.
5. Verify test suites catch the mutations (mutation score > 85%).
6. Generate Resilience Audit Report in `docs/qa/RESILIENCE.md`.
