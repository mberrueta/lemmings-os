# Task 04: Reference File Domain Context And Lifecycle

## Status

- **Status**: COMPLETED
- **Approved**: [x] Human sign-off

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix contexts, queries, and business logic.

## Agent Invocation

Act as `dev-backend-elixir-engineer`. Add reference-file create/update/list/archive behavior to the Knowledge context.

## Objective

Implement operator-managed reference-file lifecycle APIs inside `LemmingsOs.Knowledge` while preserving existing memory and source-file behavior.

## Implementation Scope

- Add direct upload/register APIs for reference files in the Knowledge context.
- Add metadata update APIs for title, description/content summary, flexible type, tags, and metadata.
- Add archive behavior that sets reference files to archived and excludes them from normal availability.
- Add exact-scope mutation checks using the existing World/City/Department/Lemming scope model.
- Add local/effective list APIs for operator UI and runtime availability use.
- Return safe reference-file read models/descriptors that omit `storage_ref` and raw paths.
- Keep `knowledge.store` memory-only; Lemmings must not mutate reference files.

## Constraints

- Context APIs must require explicit scope structs or scope data; no implicit global queries for World-scoped resources.
- Use `Ecto.Multi` for multi-row writes involving `knowledge_items` and reference-file metadata.
- Do not store original file bytes, converted full bodies, or unbounded reference-file content in `knowledge_items.content`; use only a short description or summary if the existing schema requires content.
- Do not call schemas/repos directly from web or runtime tool layers later.
- Do not implement recover/restore or hard delete unless explicitly approved later.

## Expected Outputs

- Context APIs for create/upload/register, update metadata, archive, list, and descriptor building.
- Scope-safe behavior for active and archived statuses.
- Optional safe descriptor shape available to later tasks.
- Existing memory and source-file tests still pass.

## Suggested Checks

- `mix format`
- Narrow Knowledge context tests
- Existing `test/lemmings_os/knowledge_test.exs`

## Human Approval Gate

Human reviewer validates lifecycle semantics and scope enforcement, then approves Task 05.
