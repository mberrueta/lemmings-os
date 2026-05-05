# Task 10: LiveView Tests For Knowledge Surface

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`qa-elixir-test-author` - QA-driven ExUnit/LiveView test author.

## Agent Invocation
Act as `qa-elixir-test-author`. Implement LiveView/UI test coverage for the Knowledge surface and memory navigation flows.

## Objective
Add LiveView test coverage for memory CRUD interactions, filters/pagination UX, deep-link behavior, and notification-to-link workflows.

## Inputs Required
- [x] Task 01 scenario matrix
- [x] Tasks 07 and 08 implementation outputs
- [x] Existing LiveView test style in `world_live_test.exs`, `cities_live_test.exs`, `departments_live_test.exs`, and `navigation_live_test.exs`

## Expected Outputs
- [x] LiveView tests for create/edit/delete and validation states.
- [x] Tests for scope filter behavior and inherited/local labels.
- [x] Tests for deep-link navigation to memory detail/edit view.
- [x] Tests for chat notification visible path/link behavior where applicable.

## Acceptance Criteria
- [x] Tests use stable selectors and `Phoenix.LiveViewTest` helpers.
- [x] Tests verify no memory scope boundary violations via UI parameters.
- [x] Empty/filter-empty/pagination states are covered.
- [x] Tests do not depend on brittle full-HTML snapshots.

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
Implemented and validated LiveView/UI coverage enhancements:
- Extended `test/lemmings_os_web/live/knowledge_live_test.exs` with:
  - department scoped view assertions for local/descendant ownership labels.
  - UI scope-boundary safety for `scope_type=lemming` params (sibling lemming memories hidden).
  - pagination behavior assertions using stable selectors (`#knowledge-page-next`, `#knowledge-page-prev`, `#knowledge-page-range`).
- Extended `test/lemmings_os_web/live/instance_live_test.exs` with:
  - assistant transcript bubble rendering of notification deep-link CTA to `/knowledge?memory_id=...` (`#message-knowledge-link-<id>`).

Focused validation executed:
- `mix test test/lemmings_os_web/live/knowledge_live_test.exs test/lemmings_os_web/live/instance_live_test.exs` (pass)

## Human Review
*[Filled by human reviewer]*
