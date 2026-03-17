# Task 15: Branch Validation and Precommit

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: None
- **Blocks**: Task 16

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to run branch-level validation once implementation and tests are complete.

## Objective

Validate the branch with the required commands and fix any remaining compile/test/precommit issues before ADR review and final audit.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] Tasks 01 through 14 outputs

## Expected Outputs

- [ ] `mix test` results
- [ ] `mix precommit` results
- [ ] any required cleanup/fixes to reach green status

## Acceptance Criteria

- [ ] branch passes `mix test`
- [ ] branch passes `mix precommit`
- [ ] no debug output or validation-only hacks remain

## Technical Notes

### Constraints

- Fix issues rather than documenting around them
- Keep the branch aligned with constitution quality gates

## Execution Instructions

### For the Agent

1. Run the required validation commands.
2. Fix remaining issues in scope.
3. Report exactly what was run and what changed.

### For the Human Reviewer

1. Review validation results.
2. Confirm the branch is ready for ADR/doc review.
3. Approve before Task 16 begins.
