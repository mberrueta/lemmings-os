# Task 05: Backend Tests Persistence And Adapters

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`qa-elixir-test-author`

## Agent Invocation
Act as `qa-elixir-test-author` following `llms/constitution.md` and implement backend tests for persistence, work area behavior, and MVP tool adapters.

## Objective
Add deterministic backend tests for the persistence and adapter work from Tasks 01 and 02.

## Inputs Required

- [ ] `llms/tasks/0006_implement_tool_runtime_mvp/plan.md`
- [ ] Task 01 outputs
- [ ] Task 02 outputs
- [ ] Existing backend/runtime test patterns
- [ ] `test/support/factory.ex`

## Expected Outputs

- [ ] ExUnit coverage for new persistence behavior
- [ ] ExUnit coverage for work area behavior
- [ ] ExUnit coverage for the four MVP tool adapters

## Acceptance Criteria

- [ ] Tests cover durable tool execution persistence
- [ ] Tests cover world-scoped access for new public APIs
- [ ] Tests cover work area persistence and spawn-time behavior
- [ ] Tests cover filesystem path boundary handling
- [ ] Tests cover normalized adapter success/error behavior

## Technical Notes

### Constraints
- Deterministic tests only
- No real external web calls

## Execution Instructions

### For the Agent
1. Add backend tests for persistence and adapters.
2. Use factories and existing runtime test conventions.
3. Cover edge/error cases from the plan.

### For the Human Reviewer
1. Verify persistence and adapter coverage is complete.
2. Verify workspace path boundaries are tested.
3. Verify no real external dependency is exercised.

---

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
