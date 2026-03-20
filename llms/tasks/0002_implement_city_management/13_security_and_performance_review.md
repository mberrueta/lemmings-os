# Task 13: Security and Performance Review

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: Task 12
- **Blocks**: Task 14

## Assigned Agent

`audit-pr-elixir` - Staff-level PR reviewer for Elixir/Phoenix backends.

## Agent Invocation

Use `audit-pr-elixir` to perform a targeted security and performance review of the City branch before final validation.

## Objective

Catch N+1 risks, missing preloads, query-shape problems, secret-handling mistakes, runtime exposure issues, and scope regressions before the branch is treated as final.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] Tasks 01 through 12 outputs
- [ ] `llms/constitution.md`
- [ ] `llms/project_context.md`
- [ ] relevant City UI/query/runtime code paths

## Expected Outputs

- [ ] review findings with severity ordering
- [ ] file/line references for concrete issues
- [ ] explicit review of N+1 and preload/query-shape behavior
- [ ] explicit review of runtime env and secret handling
- [ ] explicit review of logging/metadata safety and world-scoping correctness

## Acceptance Criteria

- [ ] the review explicitly covers resolver purity, preload discipline, and city list/detail query shape
- [ ] the review explicitly covers compose/runtime env exposure and secret handling
- [ ] the review explicitly covers logging and hierarchy metadata safety
- [ ] any must-fix issues are documented before downstream tasks continue

## Technical Notes

### Constraints

- Findings first, ordered by severity
- Focus on correctness, performance, scope integrity, and security
- This is a real review gate, not a generic summary task

## Execution Instructions

### For the Agent

1. Review the implemented branch in code-review mode.
2. Prioritize bugs, performance regressions, N+1 risk, missing tests, and security mistakes.
3. Reference concrete files/lines for any findings.
4. State explicitly if no findings remain.

### For the Human Reviewer

1. Review any findings carefully before approving.
2. Ensure required fixes are made before Task 14 begins.
3. Confirm the branch still stays within City-foundation scope.
4. Approve only after issues are either fixed or consciously accepted.

