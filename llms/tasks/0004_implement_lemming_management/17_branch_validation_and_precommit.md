# Task 17: Branch Validation and Precommit

## Status

- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 16
- **Blocks**: Task 18, Task 20
- **Estimated Effort**: M

## Assigned Agent

`dev-backend-elixir-engineer` - backend engineer responsible for final technical validation and quality-gate closure.

## Agent Invocation

Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and run the final quality gates for the Lemming management branch.

## Objective

Prove the branch satisfies the required validation gates before formal review and final audit.

## Inputs Required

- [ ] `llms/tasks/0004_implement_lemming_management/plan.md`
- [ ] Outputs from Tasks 01 through 16
- [ ] Repo quality gates from `AGENTS.md` and `llms/constitution.md`

## Expected Outputs

- [ ] `mix test` result
- [ ] Coverage report generated through the accepted workflow
- [ ] `mix precommit` result
- [ ] Summary of any fixes needed to pass validation

## Acceptance Criteria

- [ ] `mix test` passes
- [ ] Coverage report is generated
- [ ] `mix precommit` passes
- [ ] Any final fixes remain within approved scope and are documented

## Technical Notes

### Constraints

- Human still performs git operations
- Use the repo-approved workflow; fix issues rather than just reporting failures

## Execution Instructions

### For the Agent

1. Run validation only after the implementation and test tasks are approved.
2. Fix any pending issues required to satisfy the gates.
3. Record final validation outcomes clearly for downstream review.

### For the Human Reviewer

1. Confirm the required commands actually ran and passed.
2. Reject if validation is partial or undocumented.

---

## Execution Summary

*[Filled by executing agent after completion]*

### Work Performed

- [What was actually done]

### Outputs Created

- [List of files/artifacts created]

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|

### Blockers Encountered

- [Blocker 1] - Resolution: [How resolved or "Needs human input"]

### Questions for Human

1. [Question needing human input]

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

- [ ] APPROVED - Proceed to next task
- [ ] REJECTED - See feedback below

### Feedback

### Git Operations Performed

```bash
# human-only
```
