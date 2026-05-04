# Task 04: Effective Memory Listing And Pagination

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for query/read-model implementation.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement effective-scope listing and filtering queries for memory visibility.

## Objective
Add listing/query APIs that support inherited visibility, department inclusion of local Lemming memories, text search on title/tags, source/status filtering, and local Ecto pagination.

## Inputs Required
- [ ] `llms/tasks/0013_memory_store/plan.md`
- [ ] Task 03 context contract
- [ ] Existing visibility patterns in `LemmingsOs.Connections`

## Expected Outputs
- [ ] Effective visibility list/read model per scope (World/City/Department/Lemming).
- [ ] Search/filter support for title/tags text query and source/status filters.
- [ ] Stable pagination response using `limit`, `offset`, count query, default size 25.
- [ ] Ownership metadata in list rows (local vs inherited and owner scope labels).

## Acceptance Criteria
- [ ] Department listing includes inherited World/City/Department memories plus descendant Lemming-owned memories in same department.
- [ ] Sibling and cross-world memories are excluded from all listings.
- [ ] Results are stably ordered for deterministic pagination.
- [ ] Query API does not require a pagination dependency.

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
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*

