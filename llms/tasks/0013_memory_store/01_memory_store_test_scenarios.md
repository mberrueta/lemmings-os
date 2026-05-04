# Task 01: Memory Store Test Scenarios

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`qa-test-scenarios` - Test scenario designer for acceptance criteria, edge cases, and regressions.

## Agent Invocation
Act as `qa-test-scenarios`. Convert `llms/tasks/0013_memory_store/plan.md` into a concrete scenario matrix before implementation starts.

## Objective
Define the minimum complete scenario matrix for memory data model rules, scope inheritance, `knowledge.store`, chat notification behavior, event safety, and Knowledge UI flows.

## Inputs Required
- [ ] `llms/tasks/0013_memory_store/plan.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] Existing Secret Bank, Connections, and Tools Runtime tests for pattern alignment

## Expected Outputs
- [ ] Risk-ranked scenario matrix with IDs and test layers (unit/integration/LiveView/manual).
- [ ] Traceability from FR/AC items in `plan.md` to scenario IDs.
- [ ] Explicit regression checklist for scope boundaries and leak prevention.

## Acceptance Criteria
- [ ] Scenarios cover all AC-1 through AC-10 in `plan.md`.
- [ ] Department listing scenarios include inherited World/City memories plus local Lemming memories.
- [ ] `knowledge.store` invalid input and invalid scope paths are fully covered.
- [ ] Notification resilience scenarios verify memory persistence is not rolled back on publish failure.
- [ ] Scenario plan is implementation-ready for Tasks 09 and 10.

## Technical Notes
### Constraints
- This task defines what to test; it does not add or modify production code.
- Keep scenarios outcome-based and selector-based for LiveView assertions.

### Scope Boundaries
- Do not design semantic search, file knowledge, chunking, or vector behavior in this matrix.

## Execution Instructions
### For the Agent
1. Build P0/P1/P2 scenario coverage tied to the plan's FR/AC sections.
2. Identify required fixtures/factories and safe sentinel content patterns.
3. Produce a matrix that can be implemented directly by `qa-elixir-test-author`.

### For the Human Reviewer
1. Confirm coverage is complete for scope safety and runtime/tool behavior.
2. Approve before schema or runtime implementation tasks begin.

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
