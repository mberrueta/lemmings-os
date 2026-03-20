# Task 03: Departments Context and Lifecycle APIs

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ] Human sign-off
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

*[Filled by executing agent after completion]*

### Work Performed

-

### Outputs Created

-

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| | |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| | | |

### Blockers Encountered

-

### Questions for Human

1.

### Ready for Next Task

- [ ] All outputs complete
- [ ] Summary documented
- [ ] Questions listed (if any)

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
