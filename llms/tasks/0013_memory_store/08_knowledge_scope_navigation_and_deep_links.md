# Task 08: Knowledge Scope Navigation And Deep Links

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer` - Frontend engineer for LiveView navigation and page integration.

## Agent Invocation
Act as `dev-frontend-ui-engineer`. Integrate Knowledge navigation entry points and deep links so operators can move between hierarchy context and specific memories.

## Objective
Connect the Knowledge surface to app navigation and scope selectors, including deep links used by chat notifications for LLM-created memories.

## Inputs Required
- [ ] `llms/tasks/0013_memory_store/plan.md`
- [ ] Task 07 output
- [ ] `lib/lemmings_os_web/components/sidebar_components.ex`
- [ ] Router and existing page/tab navigation conventions

## Expected Outputs
- [ ] Navigation entry point for Knowledge using the repo-compatible placement selected in Task 07.
- [ ] Scope filtering UX on Knowledge page (World/City/Department/Lemming context selection compatible with backend APIs).
- [ ] Deep link handling to open a specific created memory from chat notifications.
- [ ] URL/state behavior consistent with `push_patch`/`push_navigate` conventions.

## Acceptance Criteria
- [ ] Operators can reach Knowledge through the selected repo-compatible navigation entry point.
- [ ] Memory deep links resolve reliably and show memory view/edit actions.
- [ ] Scope filters never expose out-of-bound data.
- [ ] Pagination/filter query params remain stable across refreshes and navigation.

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
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
