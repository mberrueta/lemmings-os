# Task 06: Operator Secret Surfaces

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer`

## Agent Invocation
Act as `dev-frontend-ui-engineer`. Add Secret Bank surfaces to existing World, City, Department, and Lemming detail experiences using the backend APIs from Tasks 02-05.

## Objective
Let the local admin view effective configured Bank keys, create local secrets, replace local values, delete local values, and inspect recent safe activity at each hierarchy scope.

## Expected Outputs
- LiveView/component updates under `lib/lemmings_os_web/**`.
- Stable DOM IDs for forms, buttons, tables/lists, and activity regions.
- The seeded demo secret appears in local development UI as `[configured]` metadata only, never as a revealed value.
- No JavaScript unless existing patterns require it.

## Acceptance Criteria
- World, City, Department, and Lemming detail experiences expose a `Secrets` surface or tab consistent with local UI patterns.
- UI shows Secret Bank key, effective source, `[configured]`, safe timestamps when available, allowed local actions, and recent durable safe activity.
- UI never shows raw values, copied values, exported values, first/last characters, hashes, previews, or reveal controls.
- Inherited secrets are visible but cannot be deleted from child scopes.
- Local secrets can be created, replaced, and deleted from their own scope.
- Replacing a local secret never shows the old value.
- Deleting a local override reveals inherited effective metadata after refresh/update.
- Seeded sample data makes it possible to manually verify inherited/effective display in the UI after running `mix run priv/repo/seeds.exs`.
- Forms use `to_form/2`, imported `<.input>`, stable IDs, and existing LiveView navigation conventions.

## Review Notes
Reject if the UI uses masked real data or implies that saved values can be revealed.
