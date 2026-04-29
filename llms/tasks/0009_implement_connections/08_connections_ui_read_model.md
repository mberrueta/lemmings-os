# Task 08: Connections UI Read Model

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer`

## Agent Invocation
Act as `dev-frontend-ui-engineer`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, `llms/tasks/0009_implement_connections/plan.md`, `lib/lemmings_os_web/AGENTS.md`, and Tasks 01-07, then implement the basic Connections read-only UI surface.

## Objective
Add local-admin visibility for Connections and their inheritance/source scope without adding management forms yet.

## Expected Outputs
- `/connections` LiveView route if implementation discovery confirms it fits the current navigation structure.
- Sidebar navigation item for Connections.
- LiveView and HEEx template for visible Connection listing.
- Read-only scope inspection for World, City, and Department visible Connections.
- Display of slug, name, type, provider, status, safe config, safe secret ref metadata, last test status, last tested timestamp, and source scope.
- Stable DOM IDs for the page, filters, rows, status badges, and source-scope indicators.

## Acceptance Criteria
- The page begins with `<Layouts.app flash={@flash} ...>`.
- UI uses existing LiveView and component patterns.
- Inherited Connections clearly show their source scope.
- Secret refs are shown only as references or redacted metadata, never as raw resolved values.
- No create/edit/delete/test controls are implemented in this task.
- No auth/RBAC behavior is added.
- No embedded `<script>` tags are added to HEEx.

## Review Notes
Reject if the UI exposes raw secrets, introduces real provider setup flows, or adds auth/RBAC concepts.
