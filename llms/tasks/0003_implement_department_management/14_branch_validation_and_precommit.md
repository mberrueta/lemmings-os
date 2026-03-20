# Task 14: Branch Validation and Precommit

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 13
- **Blocks**: Task 15
- **Estimated Effort**: M

## Assigned Agent

dev-backend-elixir-engineer - backend engineer responsible for final technical validation and quality-gate closure.

## Agent Invocation

Act as dev-backend-elixir-engineer following llms/constitution.md and run final validation for the Department branch, including the repo coverage workflow and mix precommit.

## Objective

Prove the branch satisfies the required quality gates before the final audit.

## Inputs Required

- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] outputs from Tasks 01-13
- [ ] repo quality gates from AGENTS.md and llms/constitution.md

## Expected Outputs

- [ ] mix test result
- [ ] coverage report generated through the accepted workflow
- [ ] mix precommit result
- [ ] summary of any fixes needed to pass validation

## Acceptance Criteria

- [ ] mix test passes
- [ ] coverage report is generated
- [ ] mix precommit passes
- [ ] any final fixes remain within approved scope and are documented

## Technical Notes

### Constraints

- Human still performs git operations

## Execution Instructions

### For the Agent

1. Run the required validations only after all prior tasks are approved.
2. Fix any pending issues needed to satisfy the quality gates.
3. Record the final validation status clearly for Task 15.

### For the Human Reviewer

1. Confirm the required commands were actually run and passed.
2. Reject if validation is incomplete or undocumented.

---

## Execution Summary

*[Filled by executing agent after completion]*

### Work Performed

-

### Outputs Created

-

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| | |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| | | |

### Blockers Encountered

-

### Questions for Human

1.

### Ready for Next Task

- [ ] All outputs complete
- [ ] Summary documented
- [ ] Questions listed (if any)

---

## Human Review

*[Filled by human reviewer]*

### Review Date

[YYYY-MM-DD]

### Decision

- [ ] ✅ APPROVED - Proceed to next task
- [ ] ❌ REJECTED - See feedback below

### Feedback

### Git Operations Performed

```bash
# human-only
```
