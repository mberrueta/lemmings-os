# Task 03: Departments Context and Lifecycle APIs

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
- **Blocked by**: Task 02
- **Blocks**: Task 05, Task 06, Task 07, Task 08
- **Estimated Effort**: L

## Assigned Agent

dev-backend-elixir-engineer - senior backend engineer for context boundaries, queries, and business rules.

## Agent Invocation

Act as dev-backend-elixir-engineer following llms/constitution.md and implement the LemmingsOs.Departments context with explicit World/City scoping and lifecycle APIs.

## Objective

Add the Department context contract for listing, retrieval, CRUD, lifecycle transitions, and conservative delete guard behavior.

## Inputs Required

- [ ] llms/constitution.md
- [ ] llms/project_context.md
- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] Task 01 output
- [ ] Task 02 output
- [ ] lib/lemmings_os/cities.ex
- [ ] lib/lemmings_os/worlds.ex
- [ ] llms/coding_styles/elixir.md

## Expected Outputs

- [ ] new LemmingsOs.Departments context module
- [ ] World/City-scoped list/query/get APIs
- [ ] lifecycle wrappers and status setter
- [ ] conservative delete_department/1 guard contract with clear domain errors

## Acceptance Criteria

- [ ] list/read APIs require explicit World and City scope
- [ ] query filtering follows the repo filter_query/2 pattern
- [ ] get_department_by_slug! and/or fetch_department_by_slug are City-scoped
- [ ] lifecycle wrappers delegate through a single status transition path
- [ ] delete_department/1 returns a clear domain error whenever safe removal cannot be confidently established from currently available signals

## Technical Notes

### Relevant Code Locations

```
lib/lemmings_os/cities.ex              # Query and context API precedent
lib/lemmings_os/cities/city.ex         # Status helper precedent
lib/lemmings_os/config/resolver.ex     # Later dependency for preloads
```

### Patterns to Follow

- Explicit scope overloads like Cities
- {:ok, data} / {:error, reason} for failure-returning APIs

### Constraints

- Do not add stats aggregation APIs
- Keep delete-safety policy encapsulated in the context

## Execution Instructions

### For the Agent

1. Read the schema and migration outputs first.
2. Implement the full public API surface agreed in the plan, or document any minimal justified deviation.
3. Keep list/query APIs composable for page snapshot work.
4. Define explicit domain errors for unsafe delete paths.
5. Document any assumption about the currently available "safe removal" signal.

### For the Human Reviewer

1. Confirm API shape is explicit about World and City scope.
2. Verify delete semantics are conservative and honestly documented.
3. Reject any hidden dependency on not-yet-shipped Lemming persistence.

---

## Execution Summary
Implemented by Codex with a parallel implementation review from `dev-backend-elixir-engineer`.

### Work Performed
- Added the new `LemmingsOs.Departments` context with explicit World/City-scoped list, fetch, get, create, update, lifecycle, and delete APIs, plus City-scoped slug lookup.
- Kept list/query APIs composable using the same `filter_query/2` pattern already used in `Cities`.
- Added a private world/city verification path for writes so a City from another World is rejected explicitly rather than relying only on FK existence.
- Added a conservative delete guard that denies hard deletes unless the Department is disabled and, even then, still rejects removal because no runtime-backed safety signal exists yet.
- Added focused context tests for scope, filters, lifecycle wrappers, cross-world protection, and delete guard behavior.

### Outputs Created
- `lib/lemmings_os/departments.ex`
- `lib/lemmings_os/departments/delete_denied_error.ex`
- `test/lemmings_os/departments_test.exs`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| Hard delete should remain unavailable for now even when a Department is disabled | The plan requires conservative rejection whenever safe removal cannot be confidently proven from current signals, and no Lemming/runtime-backed proof exists yet |
| Cross-world mismatch on create should return a domain error instead of an empty changeset | This is a scope violation at the context boundary, not a field-level validation failure |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Returned `{:error, %DeleteDeniedError{...}}` for unsafe delete paths | Returning a generic changeset or bare atom tuple | Gives the context a stable, extensible domain error contract without pretending this is a schema validation failure |
| Added `fetch_city_in_world/2` as a private context helper | Relying only on `world_id`/`city_id` FKs in the schema | FK constraints prove existence but not that the supplied City belongs to the supplied World scope |
| Kept slug lookup APIs City-scoped instead of requiring both World and City | Requiring `world_id` and `city_id` for every slug lookup | The persisted uniqueness contract is `[:city_id, :slug]`, so City scope is sufficient and keeps the API narrower |
| Added context tests now instead of deferring all coverage to the later test phase | Waiting for Task 10 | The constitution requires executable logic changes to ship with tests in the same change set |

### Blockers Encountered
- None

### Questions for Human
1. None.

### Ready for Next Task
- [x] All outputs complete
- [x] Summary documented
- [x] Questions listed (if any)

---

## Human Review

*[Filled by human reviewer]*

### Review Date

[YYYY-MM-DD]

### Decision

- [ ] ✅ APPROVED - Proceed to next task
- [ ] ❌ REJECTED - See feedback below

### Feedback

### Git Operations Performed

```bash
# human-only
```
