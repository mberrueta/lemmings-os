# Task 02: Connection Schema and Changeset

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, `llms/tasks/0009_implement_connections/plan.md`, and Task 01, then implement the Connection schema and validation layer.

## Objective
Add the Ecto schema and changeset rules for the simplified Connection record.

## Expected Outputs
- New `LemmingsOs.Connections.Connection` schema.
- Schema fields matching Task 01 simplified model.
- `@required` and `@optional` field lists.
- `changeset/2` using `cast(attrs, @required ++ @optional)`.
- Localized validation messages through `dgettext("errors", ...)`.
- Status validation for `enabled`, `disabled`, and `invalid`.
- Scope-shape validation for World, City, and Department Connections.
- Validation for `type`, `status`, and `config`.
- Registry-backed type validation through `LemmingsOs.Connections.TypeRegistry`.
- Type-specific config validation through the registry module.
- Test factory support for World, City, and Department scoped Connection structs.

## Acceptance Criteria
- Schema maps `world_id`, `city_id`, `department_id`, `type`, `status`, `config`, and `last_test`.
- Changeset validates required fields and approved statuses.
- Invalid scope shapes are rejected before insert/update where possible.
- `config` defaults safely to `%{}` and is validated as a map.
- Validation does not require or imply any real provider implementation.
- `type: "mock"` is accepted as the first executable provider type.
- Public code does not use map access syntax on structs.
- No `String.to_atom/1` is introduced.
- No context, runtime, or UI code is added.

## Review Notes
Reject if this task starts implementing resolution, Secret Bank calls, real provider adapters, or broad runtime behavior.
