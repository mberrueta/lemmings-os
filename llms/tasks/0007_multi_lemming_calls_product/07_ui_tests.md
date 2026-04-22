# Task 07: UI Tests

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`qa-elixir-test-author`

## Agent Invocation
Act as `qa-elixir-test-author` following `llms/constitution.md`, `llms/coding_styles/elixir_tests.md`, and Phoenix LiveView testing guidelines from AGENTS.md.

## Objective
Add LiveView tests covering the new collaboration UI surfaces and interactions.

## Inputs Required
- [ ] Task 06 outputs
- [ ] Existing LiveView tests under `test/lemmings_os_web/live/`
- [ ] Stable DOM IDs added in Task 06

## Expected Outputs
- [ ] Department page tests for manager ask entry and lemming-type list.
- [ ] Manager instance tests for delegated-work visibility.
- [ ] Child instance tests for parent relationship visibility.
- [ ] State display tests for completed, failed, dead, and recovery-pending calls.
- [ ] Follow-up/direct-child-input test verifying manager-facing delegated-work visibility updates after direct child input.

## Acceptance Criteria
- [ ] Tests use `Phoenix.LiveViewTest` selectors such as `element/2` and `has_element?/2`.
- [ ] Tests reference stable DOM IDs.
- [ ] Tests avoid raw HTML string assertions.
- [ ] Tests cover outcomes, not implementation details.
- [ ] Tests confirm the manager surface reflects system-driven child-to-parent synchronization without requiring a broad UI redesign.
- [ ] `mix test` passes after UI tests.

## Execution Instructions
1. Add tests near existing department/instance LiveView tests.
2. Use factories and context APIs to set up persisted calls.
3. Keep test fixtures minimal and deterministic.

## Human Review
Review test coverage against product acceptance criteria before docs/ADR updates.
