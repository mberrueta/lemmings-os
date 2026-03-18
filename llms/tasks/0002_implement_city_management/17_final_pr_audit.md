# Task 17: Final PR Audit

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 16
- **Blocks**: None

## Assigned Agent

`audit-pr-elixir` - Staff-level PR reviewer for Elixir/Phoenix backends.

## Agent Invocation

Use `audit-pr-elixir` to perform the final PR audit for the City branch.

## Objective

Verify the branch is ready for human review with scope control, correctness, security, performance, testing, documentation, and ADR alignment all intact.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] Tasks 01 through 16 outputs
- [ ] test results
- [ ] precommit results
- [ ] coverage report
- [ ] final ADR/doc/runbook updates

## Expected Outputs

- [ ] final PR audit findings or explicit no-findings result
- [ ] residual risk summary
- [ ] recommendation on whether the branch is ready for human merge review

## Acceptance Criteria

- [ ] the audit checks branch scope against the approved City plan
- [ ] the audit checks correctness, regressions, missing tests, and remaining operator risk
- [ ] no unresolved high-severity issues remain
- [ ] any remaining lower-severity risks are documented explicitly

## Technical Notes

### Constraints

- Findings first if any exist
- Focus on bugs, regressions, missing coverage, runtime assumptions, and scope drift
- Keep the review grounded in the actual final branch state

## Execution Instructions

### For the Agent

1. Review the final branch in code-review mode.
2. Prioritize correctness and risk over summaries.
3. Call out any residual mismatch with the approved plan.
4. State explicitly if no findings remain.

### For the Human Reviewer

1. Review the final audit and residual risks.
2. Decide whether the branch is ready for manual git and PR handling.
3. If approved, use the audit as the final handoff checkpoint.

