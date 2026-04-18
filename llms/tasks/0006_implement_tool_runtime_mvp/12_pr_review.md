# Task 12: PR Review

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`audit-pr-elixir`

## Agent Invocation
Act as `audit-pr-elixir` following `llms/constitution.md` and perform the final PR review for Tool Runtime MVP on `feat/0006_tool_runtime_mvp`.

## Objective
Review the full branch after implementation, tests, and ADR updates are complete, and issue an approve/request-changes verdict.

## Inputs Required

- [ ] `llms/tasks/0006_implement_tool_runtime_mvp/plan.md`
- [ ] Tasks 01 through 11 outputs
- [ ] Full branch diff

## Expected Outputs

- [ ] Final PR review with findings and verdict

## Acceptance Criteria

- [ ] Review verifies the branch remains within the four-tool MVP slice
- [ ] Review verifies runtime correctness, workspace boundary safety, transcript visibility, observability, and test coverage
- [ ] Review verifies ADR/docs align with shipped behavior
- [ ] Findings are concrete and actionable

## Execution Instructions

### For the Agent
1. Review the branch against the plan and all task outputs.
2. Report findings by severity.
3. Issue a final verdict.

### For the Human Reviewer
1. Review the findings and verdict.
2. Decide whether the branch is ready for merge or needs follow-up work.

---

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
