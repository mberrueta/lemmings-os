# Task 03: Connection Context CRUD

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, `llms/tasks/0009_implement_connections/plan.md`, and Tasks 01-02, then implement exact-scope Connection management APIs.

## Objective
Create the initial `LemmingsOs.Connections` context for local admin management of Connections at their exact owning scope.

This task is about CRUD and status transitions only. Hierarchy inheritance and runtime-facing safe lookup are later tasks.

## Expected Outputs
- New `LemmingsOs.Connections` context module.
- Public APIs for create, update, delete local, get local, list local, get local by `type`, enable, disable, and mark invalid.
- Explicit World-scoped API shape; no implicit global queries.
- Support for World, City, and Department scope structs/maps using existing hierarchy conventions.
- `Ecto.Multi` where an operation changes a Connection and records a durable event.
- Public `@doc` documentation for important context APIs.
- Safe lifecycle event recording for create, update, delete, enable, disable, and marked-invalid through `LemmingsOs.Events`.
- Raw map scope validation with ownership checks against `cities` and `departments`.

## Acceptance Criteria
- Fallible context functions return `{:ok, value}` or `{:error, reason}` tuples.
- Local CRUD operations enforce exact-scope ownership.
- Invalid scope shapes fail closed (`{:error, :invalid_scope}` for mutating APIs, `[]`/`nil` for read APIs).
- Delete only deletes a local Connection at the requested scope.
- Enable, disable, and invalid status changes are explicit operations.
- Context APIs require explicit World scope or hierarchy scope with World identity.
- No public API can list or mutate Connections across World boundaries.
- Event payloads include safe hierarchy and Connection metadata only.
- Lifecycle events are recorded for create, update, delete, enable, disable, and marked-invalid operations.
- No hierarchy nearest-wins resolver is implemented in this task.
- No Secret Bank resolution is implemented in this task.

## Review Notes
Reject if this task adds runtime credential resolution, real provider behavior, Tool Runtime changes, or UI.
