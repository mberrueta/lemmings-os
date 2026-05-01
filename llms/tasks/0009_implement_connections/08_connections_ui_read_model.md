# Task 08: Connections UI Read Model

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer`

## Agent Invocation
Act as `dev-frontend-ui-engineer`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, `llms/tasks/0009_implement_connections/plan.md`, `lib/lemmings_os_web/AGENTS.md`, and Tasks 01-07, then implement the basic Connections read-only UI surface.

## Objective
Add local-admin visibility for Connections and their inheritance/source scope.

## Expected Outputs
- Connections surface embedded in World/City/Department views (connections tab), not a standalone `/connections` route.
- Shared UI component in `LemmingsOsWeb.ConnectionsComponents`.
- Visible connection listing for World/City/Department scopes.
- Display of source scope, type, status, and `last_test`.
- Stable DOM IDs for rows, status badges, source indicators, and action controls.

## Acceptance Criteria
- The page begins with `<Layouts.app flash={@flash} ...>`.
- UI uses existing LiveView and component patterns.
- Inherited Connections clearly show their source scope.
- UI does not render resolved secret values.
- No auth/RBAC behavior is added.
- No embedded `<script>` tags are added to HEEx.

## Review Notes
Reject if the UI exposes raw secrets, introduces real provider setup flows, or adds auth/RBAC concepts.
