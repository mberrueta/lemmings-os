# Task 16: Release Validation

## Status
- **Status**: PENDING
- **Approved**: [ ]

## Assigned Agent
`rm-release-manager` - Release manager for final validation, release notes, rollback, and operational readiness.

## Agent Invocation
Act as `rm-release-manager`. Perform final release validation for the document tools after implementation and audits are complete.

## Objective
Run or verify the final validation sequence, capture operational notes for Gotenberg, and confirm all approval gates and audits are complete before merge.

## Inputs Required
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] Completed Tasks 01 through 15
- [ ] Audit findings and resolutions
- [ ] Final source/test/docs/deployment diff

## Expected Outputs
- [ ] Final validation results recorded in this task file.
- [ ] Targeted test command results recorded.
- [ ] `mix format` result recorded.
- [ ] `mix precommit` result recorded.
- [ ] Compose/deployment validation notes recorded.
- [ ] Release notes covering env vars, Gotenberg dependency, private exposure, rollback, and known non-goals.

## Acceptance Criteria
- [ ] Narrow tool/config tests pass:
  ```text
  mix test test/lemmings_os/tools/catalog_test.exs
  mix test test/lemmings_os/tools/adapters/documents_test.exs
  mix test test/lemmings_os/tools/runtime_test.exs
  ```
- [ ] `mix format` passes/applies expected formatting.
- [ ] `mix precommit` passes with zero warnings/errors.
- [ ] Security, code review, test style, and accessibility gates are approved or explicitly waived.
- [ ] Release notes do not claim artifact persistence, artifact promotion, remote asset support, templates, email, signatures, or advanced layout support.

## Technical Notes
- If `mix precommit` is expensive or blocked by the environment, record the blocker and the narrower passing checks.
- Human owns git operations.

## Execution Instructions
1. Verify all prior task approvals.
2. Run targeted tests, then `mix format`, then `mix precommit`.
3. Review Compose/deployment notes for Gotenberg.
4. Write final release/rollback notes in this task file.

## Execution Summary

### Work Performed
- [ ] To be completed by the executing agent.

### Outputs Created
- [ ] To be completed by the executing agent.

### Assumptions Made
- [ ] To be completed by the executing agent.

### Decisions Made
- [ ] To be completed by the executing agent.

### Blockers
- [ ] To be completed by the executing agent.

### Questions for Human
- [ ] To be completed by the executing agent.

### Ready for Next Task
- [ ] Yes
- [ ] No

## Human Review
Human reviewer gives final sign-off and performs any git operations.
