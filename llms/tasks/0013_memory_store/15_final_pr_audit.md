# Task 15: Final PR Audit

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`audit-pr-elixir` - PR reviewer for Elixir/Phoenix correctness, design, safety, and tests.

## Agent Invocation
Act as `audit-pr-elixir`. Perform final branch-level audit for the complete memory-store implementation.

## Objective
Provide final code review closure for correctness, maintainability, scope boundaries, and test quality before merge.

## Inputs Required
- [ ] Tasks 02 through 14 outputs
- [ ] `llms/tasks/0013_memory_store/plan.md`
- [ ] Final diff and test/audit results

## Expected Outputs
- [ ] Severity-ranked findings list with file/line references.
- [ ] Required follow-up fixes (if any) before merge.
- [ ] Explicit merge recommendation with residual risk callouts.

## Acceptance Criteria
- [ ] No unresolved high-severity correctness/security issues remain.
- [ ] Scope, event safety, and runtime contracts match approved plan.
- [ ] Test coverage is sufficient for touched surfaces.
- [ ] Final recommendation clearly states merge readiness.

## Technical Notes
### Constraints
- Review in strict code-review mode: findings first, concise summary second.
- Confirm final code follows repository style and AGENTS constraints.

### Scope Boundaries
- New feature work is out of scope; only audit and targeted fix recommendations.

## Execution Instructions
### For the Agent
1. Review full diff and validation results.
2. Report issues by severity with concrete references.
3. Provide concise merge/no-merge recommendation.

### For the Human Reviewer
1. Approve final audit closure and decide merge timing.

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
