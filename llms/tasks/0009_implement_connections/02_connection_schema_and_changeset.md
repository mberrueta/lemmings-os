# Task 02: Connection Schema and Changeset

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, `llms/tasks/0009_implement_connections/plan.md`, and Task 01, then implement the Connection schema and validation layer.

## Objective
Add the Ecto schema and changeset rules for Connection records without implementing context APIs, runtime resolution, mock provider behavior, or UI.

## Expected Outputs
- New `LemmingsOs.Connections.Connection` schema.
- Schema fields matching the Task 01 data model.
- `@required` and `@optional` field lists.
- `changeset/2` using `cast(attrs, @required ++ @optional)`.
- Localized validation messages through `dgettext("errors", ...)`.
- Status validation for `enabled`, `disabled`, and `invalid`.
- Scope-shape validation for World, City, and Department Connections.
- Basic validation for `slug`, `type`, `provider`, `config`, `secret_refs`, and `metadata`.
- `secret_refs` validation requiring a map of logical secret names to Secret Bank-compatible env-style references, for example `%{"api_key" => "$GITHUB_TOKEN"}`.
- `secret_refs` values must be strings accepted by the current Secret Bank reference parser.
- Raw-looking secret values must not be accepted intentionally as examples or defaults.
- Test factory support for World, City, and Department scoped Connection structs.

## Acceptance Criteria
- Schema maps all fields from the migration.
- Changeset validates required fields and approved statuses.
- Invalid scope shapes are rejected before insert/update where possible.
- `config`, `secret_refs`, and `metadata` default safely to maps.
- `secret_refs` is validated as logical names mapped to Secret Bank-compatible reference strings, not raw credential values.
- Validation does not require or imply any real provider implementation.
- `type: "mock"` and `provider: "mock"` are accepted as the first executable provider pair.
- Public code does not use map access syntax on structs.
- No `String.to_atom/1` is introduced.
- No context, runtime, or UI code is added.

## Review Notes
Reject if this task starts implementing resolution, Secret Bank calls, real provider adapters, or broad runtime behavior.
