# Task 09: Connections UI Management Actions

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer`

## Agent Invocation
Act as `dev-frontend-ui-engineer`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, `llms/tasks/0009_implement_connections/plan.md`, `lib/lemmings_os_web/AGENTS.md`, and Tasks 01-08, then add local-admin management actions to the Connections UI.

## Objective
Allow the local admin to create, edit, delete local, enable, disable, and test Connections from the basic UI.

## Expected Outputs
- Create/edit forms using `to_form/2` and `<.form for={@form}>`.
- Imported `<.input>` usage where practical.
- Stable DOM IDs for forms, inputs, buttons, and result regions.
- UI actions for create, update, delete local, enable, disable, and test.
- Safe flash and validation messages.
- Refreshed read model after successful actions.
- Controls that distinguish local Connections from inherited Connections.
- Type-based create/edit flow with default config templates from registry metadata.

## Acceptance Criteria
- Inherited Connections cannot be deleted from a child scope UI.
- Test action updates visible safe status fields.
- Form errors and flash messages do not expose raw secret values or resolved credentials.
- Secret references are entered inside config payload (YAML/JSON), not as separate persisted fields.
- UI remains local-admin oriented and does not add auth/RBAC.
- No real provider-specific credential forms are added.
- No embedded `<script>` tags are added to HEEx.

## Review Notes
Reject if this task adds provider-specific integration setup, stores raw secret values in Connections, or creates approval workflow behavior.
