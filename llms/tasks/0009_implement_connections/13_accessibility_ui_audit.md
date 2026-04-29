# Task 13: Accessibility UI Audit

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`audit-accessibility`

## Agent Invocation
Act as `audit-accessibility`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/tasks/0009_implement_connections/plan.md`, `lib/lemmings_os_web/AGENTS.md`, and Tasks 01-12, then audit the Connections UI for accessibility issues.

## Objective
Review the Connections UI for keyboard access, focus behavior, labels, semantics, error discoverability, and non-color-only state communication.

## Scope
Review the implemented `/connections` UI, including:

- listing and filters;
- scope/source indicators;
- create/edit forms;
- enable/disable/delete/test controls;
- status badges;
- validation errors;
- flash messages;
- test-result feedback.

## Expected Outputs
- Accessibility findings with file/line references where applicable.
- Fixes for blocking accessibility defects introduced by the Connections UI.
- Validation notes for any checks rerun after fixes.

## Acceptance Criteria
- Interactive controls are keyboard reachable.
- Icon-only buttons have accessible names.
- Forms have appropriate labels and error associations.
- Inherited/local and status indicators are not color-only.
- Validation and test-result feedback are perceivable.
- Stable DOM IDs needed by tests remain intact.
- No broader site-wide accessibility redesign is introduced.

## Review Notes
Reject if the UI relies only on color for critical state, lacks accessible names for action controls, or hides validation/test feedback from assistive technology.
