# Task 04: Effective Memory Listing And Pagination

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for query/read-model implementation.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement effective-scope listing and filtering queries for memory visibility.

## Objective
Add listing/query APIs that support inherited visibility, department inclusion of local Lemming memories, text search on title/tags, source/status filtering, and local Ecto pagination.

## Inputs Required
- [x] `llms/tasks/0013_memory_store/plan.md`
- [x] Task 03 context contract
- [x] Existing visibility patterns in `LemmingsOs.Connections`

## Expected Outputs
- [x] Effective visibility list/read model per scope (World/City/Department/Lemming).
- [x] Search/filter support for title/tags text query and source/status filters.
- [x] Stable pagination response using `limit`, `offset`, count query, default size 25.
- [x] Ownership metadata in list rows (local vs inherited and owner scope labels).

## Acceptance Criteria
- [x] Department listing includes inherited World/City/Department memories plus descendant Lemming-owned memories in same department.
- [x] Sibling and cross-world memories are excluded from all listings.
- [x] Results are stably ordered for deterministic pagination.
- [x] Query API does not require a pagination dependency.

## Technical Notes
### Constraints
- Follow existing `Ecto.Query` patterns and keep APIs world-scoped by ownership.
- Keep filters MVP-simple; no advanced syntax or ranking.

### Scope Boundaries
- No LiveView rendering or tool catalog changes in this task.

## Execution Instructions
### For the Agent
1. Build query helpers for exact-scope and inherited-scope relevance.
2. Return read-model rows that frontend can render without extra DB lookups.
3. Document pagination and sorting contract explicitly.

### For the Human Reviewer
1. Verify department behavior matches plan AC-6.
2. Verify list response is sufficient for UI display and filtering.

## Execution Summary
### Work Performed
- Extended [`LemmingsOs.Knowledge`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/knowledge.ex:1) with `list_effective_memories/2` that returns paginated effective rows:
  - `entries` (read-model rows)
  - `total_count`
  - `limit` (default `25`, max `100`)
  - `offset` (default `0`)
- Switched pagination execution to `Repo.paginate/2` via `:scrivener_ecto`, while preserving the task response contract (`entries`, `total_count`, `limit`, `offset`).
- Added effective visibility query behavior per scope:
  - World: world-owned memories.
  - City: world + city memories.
  - Department: world + city + department + same-department lemming memories.
  - Lemming: world + city + department + own lemming memories.
- Added filter support in listing query:
  - `q`/`query` text filter over `title` and `tags`.
  - `source` filter (`user`/`llm`).
  - `status` filter (`active` in current MVP).
- Added stable ordering for deterministic pagination: `inserted_at DESC, id DESC`.
- Added ownership metadata in each row:
  - `owner_scope` and `owner_scope_label`
  - `local?`, `inherited?`, `descendant?`
- Kept exact-scope `list_memories/2` behavior intact while aligning its filtering to shared helpers.

### Tests
- Extended [`test/lemmings_os/knowledge_test.exs`](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os/knowledge_test.exs:1) with Task-04 focused scenarios:
  - Department inherited + descendant lemming inclusion.
  - Sibling exclusion.
  - Filter behavior for `q` and `source`.
  - Pagination defaults and page disjointness.
  - Invalid scope failure (`{:error, :invalid_scope}`).

### Validation
- `mix test test/lemmings_os/knowledge_test.exs` passed.
- `mix precommit` passed.

## Human Review
*[Filled by human reviewer]*
