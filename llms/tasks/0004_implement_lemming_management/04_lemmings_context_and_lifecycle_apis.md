# Task 04: Lemmings Context and Lifecycle APIs

## Status
- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 03
- **Blocks**: Task 06, Task 07, Task 08, Task 09, Task 10, Task 11, Task 12
- **Estimated Effort**: L

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for context boundaries, queries, lifecycle transitions, and business rules.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and implement the `LemmingsOs.Lemmings` context with explicit World/Department scoping, lifecycle APIs, delete guardrails, and the `DeleteDeniedError`.

## Objective
Create the full Lemmings context module mirroring the rigor of `LemmingsOs.Departments`: explicit hierarchy scoping, opts-based list filters, private `filter_query/2`, lifecycle wrappers with the activation guard, and the unconditional delete denial.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/tasks/0004_implement_lemming_management/plan.md` - Recommended Context Contract, Frozen Contracts #6 (instructions guard), #11 (delete)
- [ ] `lib/lemmings_os/departments.ex` - Context pattern precedent (primary reference)
- [ ] `lib/lemmings_os/departments/delete_denied_error.ex` - Error pattern precedent
- [ ] `lib/lemmings_os/lemmings/lemming.ex` - Task 03 output
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style

## Expected Outputs

- [ ] `lib/lemmings_os/lemmings.ex` - Lemmings context module
- [ ] `lib/lemmings_os/lemmings/delete_denied_error.ex` - Delete denied error
- [ ] `test/lemmings_os/lemmings_test.exs` - Context tests (constitution requires tests with executable logic)

## Acceptance Criteria

### Public API Surface
- [ ] `list_lemmings(world_or_world_id, department_or_department_id, opts \\ [])` - Department-scoped listing
- [ ] `list_all_lemmings(world_or_world_id, opts \\ [])` - World-scoped cross-department listing for `/lemmings`
- [ ] `fetch_lemming(id, opts \\ [])` - `{:ok, lemming}` or `{:error, :not_found}`
- [ ] `get_lemming!(id, opts \\ [])` - raises on not found
- [ ] `fetch_lemming_by_slug(department_or_department_id, slug)` - Department-scoped slug lookup
- [ ] `get_lemming_by_slug!(department_or_department_id, slug)` - raises on not found
- [ ] `create_lemming(world_or_world_id, city_or_city_id, department_or_department_id, attrs)` - hierarchy-validated creation
- [ ] `update_lemming(lemming, attrs)` - operator update
- [ ] `delete_lemming(lemming)` - always denied with `DeleteDeniedError`
- [ ] `set_lemming_status(lemming, status)` - generic status transition
- [ ] `activate_lemming(lemming)` - transition to active with instructions guard
- [ ] `archive_lemming(lemming)` - transition to archived
- [ ] `topology_summary(world_or_world_id)` - aggregate counts for topology cards

### Business Rules
- [ ] `create_lemming` validates Department belongs to the specified City and World (similar to `create_department` validating City belongs to World)
- [ ] `create_lemming` returns `{:error, :department_not_in_world}` or similar when hierarchy is invalid
- [ ] `activate_lemming` validates that `instructions` is present and non-empty before allowing transition to `active`
- [ ] `activate_lemming` returns `{:error, :instructions_required}` when instructions are nil or blank
- [ ] `delete_lemming` unconditionally returns `{:error, %DeleteDeniedError{reason: :safety_indeterminate}}`
- [ ] List ordering: `inserted_at` ascending, then `id` ascending (matching Department convention)
- [ ] All failure-returning APIs use `{:ok, data}` / `{:error, reason}` tuples

### Query Patterns
- [ ] Private `filter_query/2` with multi-clause pattern matching on `:status`, `:ids`, `:slug`, `:preload`
- [ ] `list_lemmings` requires explicit World and Department scope
- [ ] `list_all_lemmings` requires explicit World scope and returns cross-department rows ordered by `inserted_at` ascending, then `id` ascending
- [ ] `topology_summary` returns `%{lemming_count: N, active_lemming_count: N}`

### DeleteDeniedError
- [ ] Module: `LemmingsOs.Lemmings.DeleteDeniedError`
- [ ] Fields: `lemming_id`, `reason`
- [ ] Reason type: `:safety_indeterminate` only (no `:not_disabled` -- Lemmings are definitions, not operational units)
- [ ] `message/1` uses `dgettext("errors", ".lemming_delete_denied_safety_indeterminate")`

### Tests
- [ ] Context tests cover: list/fetch/get scoping, create with hierarchy validation, create with slug conflict, update, lifecycle transitions, activation guard (with and without instructions), delete denial, topology summary
- [ ] Tests use the factory from Task 03

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/departments.ex                      # Primary pattern to follow
lib/lemmings_os/departments/delete_denied_error.ex   # Error pattern
test/lemmings_os/departments_test.exs                # Test pattern
```

### Patterns to Follow
- `departments_query/3` pattern with struct/id overloads -> `lemmings_query/3`
- Add a dedicated World-scoped query path for `list_all_lemmings/2`; do not force the web layer to assemble this by iterating departments
- `normalize_world_id/1` private helper for World struct/id normalization
- Hierarchy validation: `fetch_department_in_world/3` private helper (validates Department belongs to City belongs to World)
- `normalize_topology_summary/1` for nil-safe count normalization
- `@doc` with `@spec` and executable examples on all public functions

### Constraints
- Lemmings do NOT have a `:not_disabled` delete denial reason (unlike Departments)
- The delete function does NOT check status -- it unconditionally denies
- `activate_lemming` must check `instructions` presence using `LemmingsOs.Helpers.blank?/1`
- Do NOT add import/export functions here -- those belong to Task 06
- Context tests must use `start_supervised` if any OTP processes are involved (none expected here)

## Execution Instructions

### For the Agent
1. Read `departments.ex` and `departments/delete_denied_error.ex` thoroughly.
2. Create `lib/lemmings_os/lemmings.ex` following the same module structure.
3. Create `lib/lemmings_os/lemmings/delete_denied_error.ex` (simpler than Department version -- only one reason).
4. Implement `list_all_lemmings/2` as an official World-scoped API for the `/lemmings` page.
5. Implement hierarchy validation for `create_lemming`: verify Department belongs to the City, and City belongs to the World.
6. Implement the activation guard in `activate_lemming`: check `instructions` is present and non-blank.
7. Write comprehensive context tests in `test/lemmings_os/lemmings_test.exs`.
8. All public functions must have `@doc`, `@spec`, and at least one executable example.

### For the Human Reviewer
1. Confirm API shape matches the recommended contract from the plan.
2. Verify hierarchy validation catches cross-world/cross-city mismatches.
3. Verify `list_all_lemmings/2` exists as a context-owned API rather than being deferred to the web layer.
4. Verify activation guard correctly checks `instructions` presence.
5. Verify delete is unconditional denial -- no status checking.
6. Reject if import/export functions are included (those are Task 06).

---

## Execution Summary

### Work Performed
- Added the `LemmingsOs.Lemmings` context with explicit World- and Department-scoped list APIs, fetch/get helpers, create/update lifecycle APIs, and topology aggregation.
- Implemented hierarchy validation in `create_lemming/4` so the supplied Department must belong to the supplied City and World scope before insert.
- Added `LemmingsOs.Lemmings.DeleteDeniedError` and wired `delete_lemming/1` to unconditionally deny hard deletion with `:safety_indeterminate`.
- Added context tests covering listing, scoping, hierarchy validation, slug conflicts, lifecycle transitions, the instructions activation guard, delete denial, and topology summary behavior.

### Outputs Created
- `lib/lemmings_os/lemmings.ex`
- `lib/lemmings_os/lemmings/delete_denied_error.ex`
- `test/lemmings_os/lemmings_test.exs`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| `create_lemming/4` should return a single hierarchy-mismatch atom for both cross-city and cross-world mismatches. | The task allows `:department_not_in_world` or similar, and a single explicit atom keeps the public error surface stable while still enforcing the full hierarchy contract. |
| `fetch_lemming/2` remains ID-based and unscoped, while collection APIs own the explicit World/Department boundaries. | This matches the existing Department pattern, where fetch-by-id is a direct lookup and scoped list APIs enforce boundary traversal. |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Used `:department_not_in_city_world` as the hierarchy validation error atom. | Returning separate `:department_not_in_world` and `:department_not_in_city` atoms. | The create contract validates the full three-level ownership relationship, so one explicit mismatch atom avoids leaking internal branching into the public API. |
| Added `list_all_lemmings/2` as a first-class World-scoped query instead of asking callers to iterate departments. | Deferring cross-department listing assembly to the web layer. | The task explicitly requires the context to own the cross-department query for the `/lemmings` page. |

### Blockers Encountered
- None.

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
- [ ] APPROVED - Proceed to next task
- [ ] REJECTED - See feedback below

### Feedback

### Git Operations Performed
```bash
# human-only
```
