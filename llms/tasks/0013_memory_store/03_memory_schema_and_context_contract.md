# Task 03: Memory Schema And Context Contract

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for schemas, contexts, and business logic.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement the Knowledge domain modules and public context contract for memory CRUD.

## Objective
Add memory-focused schema(s), changesets, and context APIs for create/read/update/delete with scope-safe behavior and creator/source metadata handling.

## Inputs Required
- [x] `llms/tasks/0013_memory_store/plan.md`
- [x] Task 02 migration output
- [x] `lib/lemmings_os/secret_bank.ex`
- [x] `lib/lemmings_os/connections.ex`

## Expected Outputs
- [x] New `LemmingsOs.Knowledge` context module (or equivalent repo-compatible naming).
- [x] New schema module(s) for persisted knowledge items.
- [x] Public APIs for user memory CRUD and single-memory retrieval by allowed scope.
- [x] Changeset validations for title/content/tags/source/status and safe defaults.

## Acceptance Criteria
- [x] User-created memories persist with `source = user`.
- [x] Update supports title/content/tags edits and validates inputs clearly.
- [x] Hard delete removes row and returns safe result semantics.
- [x] Context APIs reject invalid scope and scope mismatch consistently.
- [x] Product-state rules such as allowed `source`, `status`, and `kind` values are enforced in changesets/context APIs, not through DB enum/check constraints.
- [x] No `String.to_atom/1` use on external input.

## Technical Notes
### Constraints
- Follow existing context API style used by `SecretBank` and `Connections`.
- Keep runtime-owned fields (`kind`, creator metadata, hierarchy IDs) out of user-editable cast sets.

### Scope Boundaries
- Do not implement tool runtime, LiveView, or event publication in this task.

## Execution Instructions
### For the Agent
1. Implement schema and context contract with clear `@spec` coverage.
2. Add doctests where they improve API usage clarity.
3. Keep errors deterministic and safe for UI/runtime consumers.

### For the Human Reviewer
1. Validate context API naming and shape before list/query and tool integration tasks.
2. Confirm scope consistency checks are implemented at context boundary.

## Execution Summary
### Work Performed
- Added new schema module [`lib/lemmings_os/knowledge/knowledge_item.ex`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/knowledge/knowledge_item.ex:1):
  - `knowledge_items` schema with scope fields, memory fields, tags, source/status, and creator metadata FKs.
  - `changeset/2` for internal create/update validation.
  - `user_update_changeset/2` for user-editable fields only (`title`, `content`, `tags`).
  - Product-state validations in schema layer (`kind`, `source`, `status`) and memory rule (`artifact_id` must be `nil` for memory).
  - Scope-shape and FK constraints aligned with migration.
- Added new context module [`lib/lemmings_os/knowledge.ex`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/knowledge.ex:1):
  - `create_memory/3` with runtime-owned defaults (`kind=memory`, `source=user`, `status=active`).
  - `get_memory/3` with allowed visibility by hierarchy (local or inherited mode).
  - `update_memory/3` and `delete_memory/2` with exact-scope enforcement.
  - `list_memories/2` for exact-scope local list.
  - Scope normalization + DB-backed scope consistency checks to reject invalid/spoofed scopes with deterministic `:invalid_scope` / `:scope_mismatch`.
  - Optional creator metadata handling and UUID validation without atom conversion.
- Added factory support in [`test/support/factory.ex`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/support/factory.ex:1) for `knowledge_item`.
- Added focused context tests in [`test/lemmings_os/knowledge_test.exs`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os/knowledge_test.exs:1) covering defaults, update/delete behavior, scope mismatch rejection, and visibility rules.

### Validation
- `mix test test/lemmings_os/knowledge_test.exs` passed.
- `mix precommit` passed.

## Human Review
*[Filled by human reviewer]*
