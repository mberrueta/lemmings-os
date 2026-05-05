# Task 08: Knowledge Scope Navigation And Deep Links

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer` - Frontend engineer for LiveView navigation and page integration.

## Agent Invocation
Act as `dev-frontend-ui-engineer`. Integrate Knowledge navigation entry points and deep links so operators can move between hierarchy context and specific memories.

## Objective
Connect the Knowledge surface to app navigation and scope selectors, including deep links used by chat notifications for LLM-created memories.

## Inputs Required
- [x] `llms/tasks/0013_memory_store/plan.md`
- [x] Task 07 output
- [x] `lib/lemmings_os_web/components/sidebar_components.ex`
- [x] Router and existing page/tab navigation conventions

## Expected Outputs
- [x] Navigation entry point for Knowledge using the repo-compatible placement selected in Task 07.
- [x] Scope filtering UX on Knowledge page (World/City/Department/Lemming context selection compatible with backend APIs).
- [x] Deep link handling to open a specific created memory from chat notifications.
- [x] URL/state behavior consistent with `push_patch`/`push_navigate` conventions.

## Acceptance Criteria
- [x] Operators can reach Knowledge through the selected repo-compatible navigation entry point.
- [x] Memory deep links resolve reliably and show memory view/edit actions.
- [x] Scope filters never expose out-of-bound data.
- [x] Pagination/filter query params remain stable across refreshes and navigation.

## Technical Notes
### Constraints
- Preserve current route naming and shell layout patterns.
- Follow existing navigation conventions for the selected placement (global nav, tab, or contextual link).

### Scope Boundaries
- No redesign of existing World/City/Department/Lemming pages in this task.

## Execution Instructions
### For the Agent
1. Add route/nav integration and URL param handling.
2. Implement deep-link behavior expected by notification payloads.
3. Keep interactions selector-friendly for Task 10 tests.

### For the Human Reviewer
1. Verify navigation ergonomics and deep-link correctness.
2. Confirm no scope bleed from URL manipulation.

## Execution Summary
Implemented and verified:
- Sidebar and router navigation entry point to `/knowledge`.
- Embedded knowledge surfaces for city, department, and lemming scope tabs.
- Scope selector UX for World/City/Department/Lemming in Knowledge LiveView.
- Memory deep-link (`memory_id`) hydration that opens edit mode for targeted memory.
- Coverage in `knowledge_live_test.exs` and `navigation_live_test.exs` for deep links and knowledge tab routing.

## Human Review
*[Filled by human reviewer]*
