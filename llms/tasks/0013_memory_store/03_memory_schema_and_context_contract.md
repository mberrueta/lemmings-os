# Task 03: Memory Schema And Context Contract

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for schemas, contexts, and business logic.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement the Knowledge domain modules and public context contract for memory CRUD.

## Objective
Add memory-focused schema(s), changesets, and context APIs for create/read/update/delete with scope-safe behavior and creator/source metadata handling.

## Inputs Required
- [ ] `llms/tasks/0013_memory_store/plan.md`
- [ ] Task 02 migration output
- [ ] `lib/lemmings_os/secret_bank.ex`
- [ ] `lib/lemmings_os/connections.ex`

## Expected Outputs
- [ ] New `LemmingsOs.Knowledge` context module (or equivalent repo-compatible naming).
- [ ] New schema module(s) for persisted knowledge items.
- [ ] Public APIs for user memory CRUD and single-memory retrieval by allowed scope.
- [ ] Changeset validations for title/content/tags/source/status and safe defaults.

## Acceptance Criteria
- [ ] User-created memories persist with `source = user`.
- [ ] Update supports title/content/tags edits and validates inputs clearly.
- [ ] Hard delete removes row and returns safe result semantics.
- [ ] Context APIs reject invalid scope and scope mismatch consistently.
- [ ] Product-state rules such as allowed `source`, `status`, and `kind` values are enforced in changesets/context APIs, not through DB enum/check constraints.
- [ ] No `String.to_atom/1` use on external input.

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
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
