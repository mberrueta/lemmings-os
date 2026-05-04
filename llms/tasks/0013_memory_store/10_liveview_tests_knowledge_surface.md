# Task 10: LiveView Tests For Knowledge Surface

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`qa-elixir-test-author` - QA-driven ExUnit/LiveView test author.

## Agent Invocation
Act as `qa-elixir-test-author`. Implement LiveView/UI test coverage for the Knowledge surface and memory navigation flows.

## Objective
Add LiveView test coverage for memory CRUD interactions, filters/pagination UX, deep-link behavior, and notification-to-link workflows.

## Inputs Required
- [ ] Task 01 scenario matrix
- [ ] Tasks 07 and 08 implementation outputs
- [ ] Existing LiveView test style in `world_live_test.exs`, `cities_live_test.exs`, `departments_live_test.exs`, and `navigation_live_test.exs`

## Expected Outputs
- [ ] LiveView tests for create/edit/delete and validation states.
- [ ] Tests for scope filter behavior and inherited/local labels.
- [ ] Tests for deep-link navigation to memory detail/edit view.
- [ ] Tests for chat notification visible path/link behavior where applicable.

## Acceptance Criteria
- [ ] Tests use stable selectors and `Phoenix.LiveViewTest` helpers.
- [ ] Tests verify no memory scope boundary violations via UI parameters.
- [ ] Empty/filter-empty/pagination states are covered.
- [ ] Tests do not depend on brittle full-HTML snapshots.

## Technical Notes
### Constraints
- Reuse factory helpers and existing LiveView test idioms.
- Keep assertions outcome-focused and user-observable.

### Scope Boundaries
- No backend domain tests in this task (covered in Task 09).

## Execution Instructions
### For the Agent
1. Cover high-risk operator flows and error states first.
2. Assert accessibility-critical attributes when already part of UI behavior.
3. Run focused LiveView suites before broader validation.

### For the Human Reviewer
1. Validate selector stability and flow coverage quality.
2. Confirm deep-link and filter behaviors match the approved UX.

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*

