# Task 17: Final PR Audit

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 16
- **Blocks**: None

## Assigned Agent

`audit-pr-elixir` - Staff-level PR reviewer for Elixir/Phoenix backends.

## Agent Invocation

Use `audit-pr-elixir` to perform the final staff-level review of the completed branch.

## Objective

Run a final correctness/regression audit after validation and ADR review are complete.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] Tasks 01 through 16 outputs
- [ ] all changed production and test files

## Expected Outputs

- [ ] review findings ordered by severity
- [ ] explicit note if no findings remain
- [ ] residual risks or testing gaps, if any

## Acceptance Criteria

- [ ] the audit confirms the branch remains read-only at the UI while using a real persisted `World` domain
- [ ] no hidden mock fallback or architectural overclaim remains
- [ ] findings, if any, are concrete and actionable

## Technical Notes

### Constraints

- Prioritize bugs, regressions, and missing tests
- Keep architectural critique grounded in the actual implemented diff

## Execution Instructions

### For the Agent

1. Review the completed branch in code-review mode.
2. Focus first on correctness and regressions.
3. Call out any remaining scope drift or hidden fake authority.

### For the Human Reviewer

1. Review audit findings and resolve required follow-ups.
2. Decide whether the branch is ready for final git operations.
3. Perform all git actions manually.
