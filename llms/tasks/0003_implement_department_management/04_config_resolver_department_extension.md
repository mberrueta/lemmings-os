# Task 04: Config Resolver Department Extension

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
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
Implemented by Codex with a parallel implementation review from `dev-backend-elixir-engineer`.

### Work Performed
- Extended `LemmingsOs.Config.Resolver.resolve/1` to accept `%Department{city: %City{world: %World{}}}`.
- Kept the resolver pure and additive, reusing the existing bucket merge helpers and preserving the same four-bucket return shape.
- Implemented Department resolution as `World -> City -> Department`, with no new settings abstraction and no source-tracing or cache layer.
- Added focused resolver tests covering Department override precedence and inherited fallback behavior.

### Outputs Created
- `lib/lemmings_os/config/resolver.ex`
- `test/lemmings_os/config/resolver_test.exs`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| Later read-model and UI callers will preload `department.city.world` before calling the resolver | The resolver must remain pure and perform no DB access |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Reused the existing `resolve(city)` path and merged Department overrides on top | Building a parallel Department-specific merge pipeline | Keeps World and City behavior stable and additive while preserving one resolver contract |
| Kept preload requirements in module docs and task notes instead of adding runtime fetching helpers | Fetching parent records inside the resolver | The task explicitly requires a pure, preload-safe in-memory resolver |

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
