# Task 16: Branch Validation and Precommit

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 15
- **Blocks**: Task 17

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to run final branch validation and fix any remaining issues on the final documented branch state.

## Objective

Make the branch pass the repo quality gates after implementation, tests, docs, and review-driven fixes are complete.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] Tasks 01 through 15 outputs
- [ ] `llms/constitution.md`
- [ ] final code, test, compose, and docs changes

## Expected Outputs

- [ ] successful `mix test`
- [ ] successful `mix precommit`
- [ ] coverage report artifact, if supported by the repo's configured coverage tooling
- [ ] any last fixes required to satisfy validation

## Acceptance Criteria

- [ ] validation runs on the final branch state, not a pre-doc snapshot
- [ ] no unresolved issues remain from the security/performance review
- [ ] all tests pass
- [ ] `mix precommit` passes with zero warnings/errors
- [ ] coverage report is generated using the repo's accepted coverage workflow

## Technical Notes

### Constraints

- Follow the constitution quality gates
- Use targeted test execution while iterating, then run the full required commands
- Do not use destructive git operations

## Execution Instructions

### For the Agent

1. Resolve any last issues before running final validation.
2. Run the required commands on the fully updated branch.
3. Record what was run and what needed fixing.
4. Leave the branch in a review-ready state for final audit.

### For the Human Reviewer

1. Review the final validation results.
2. Confirm the coverage report was generated.
3. Confirm no known issues were deferred silently.
4. Approve before Task 17 begins.
