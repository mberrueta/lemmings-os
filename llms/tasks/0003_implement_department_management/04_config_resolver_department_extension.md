# Task 04: Config Resolver Department Extension

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 02
- **Blocks**: Task 06, Task 07, Task 08
- **Estimated Effort**: M

## Assigned Agent

dev-backend-elixir-engineer - backend engineer for resolver logic and preload-safe config assembly.

## Agent Invocation

Act as dev-backend-elixir-engineer following llms/constitution.md and extend LemmingsOs.Config.Resolver so Department participates in World -> City -> Department.

## Objective

Extend the existing pure in-memory resolver to accept a preloaded Department parent chain and produce effective Department config without introducing a new config system.

## Inputs Required

- [ ] llms/constitution.md
- [ ] llms/project_context.md
- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] Task 02 output
- [ ] lib/lemmings_os/config/resolver.ex
- [ ] lib/lemmings_os/cities/city.ex

## Expected Outputs

- [ ] resolver support for %Department{city: %City{world: %World{}}}
- [ ] any supporting preload or helper adjustments needed by later read models
- [ ] clear notes on what is still excluded: source tracing, explain output, cache, advanced governance semantics

## Acceptance Criteria

- [ ] resolver remains pure and performs no DB access
- [ ] return shape stays identical to existing four-bucket result shape
- [ ] merge order is World -> City -> Department
- [ ] no parallel resolver or alternate settings abstraction is introduced

## Technical Notes

### Relevant Code Locations

```
lib/lemmings_os/config/resolver.ex     # Existing merge logic
lib/lemmings_os/cities/city.ex         # Existing scope precedent
```

### Patterns to Follow

- Pattern matching by scope struct
- Deep merge behavior should remain consistent with current City implementation

### Constraints

- No per-field source trace output
- No DB access inside the resolver

## Execution Instructions

### For the Agent

1. Read the current resolver implementation completely.
2. Add Department scope support with the same style and merge semantics.
3. Keep the existing resolver contract stable for World and City callers.
4. Document preload expectations clearly for UI/read-model tasks.

### For the Human Reviewer

1. Confirm Department support is additive and does not regress World/City behavior.
2. Check that no "explain" or source-tracing features leaked into scope.

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
