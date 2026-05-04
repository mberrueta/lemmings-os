# Task 09: Backend Tests For Memory Domain And Tooling

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`qa-elixir-test-author` - QA-driven ExUnit author for backend/runtime tests.

## Agent Invocation
Act as `qa-elixir-test-author`. Implement backend test coverage for memory domain behavior, scope rules, tool runtime integration, and event/notification resilience.

## Objective
Translate Task 01 scenarios into ExUnit coverage for migration-backed domain APIs and `knowledge.store` tool behavior.

## Inputs Required
- [ ] Task 01 scenario matrix
- [ ] Tasks 02 through 06 implementation outputs
- [ ] Existing test patterns in `test/lemmings_os/secret_bank_test.exs`, `connections_test.exs`, and `tools/runtime_test.exs`

## Expected Outputs
- [ ] Context-level tests for create/update/delete/get/list behavior and scope mismatch protection.
- [ ] Query-level tests for inherited visibility and department inclusion of Lemming memories.
- [ ] Runtime/tool tests for `knowledge.store` success/failure and safe result/error contracts.
- [ ] Event payload safety assertions and notification-failure-nonrollback assertions.

## Acceptance Criteria
- [ ] All P0 backend scenarios from Task 01 are automated.
- [ ] Tests assert no cross-world/sibling scope leakage.
- [ ] Tool tests verify unsupported fields and invalid scopes are rejected safely.
- [ ] Tests avoid brittle HTML assertions and focus on outcomes.

## Technical Notes
### Constraints
- Use focused fixtures and stable sentinel content.
- Keep tests deterministic and isolated; restore mutated app env/config.

### Scope Boundaries
- LiveView UI tests are out of scope for this task (handled in Task 10).

## Execution Instructions
### For the Agent
1. Implement tests by risk order (scope safety first).
2. Add doctests for new public modules if examples add clarity.
3. Run narrow suites first, then broader relevant checks.

### For the Human Reviewer
1. Confirm critical scope and runtime failure paths are covered.
2. Verify no unnecessary test complexity was introduced.

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*

