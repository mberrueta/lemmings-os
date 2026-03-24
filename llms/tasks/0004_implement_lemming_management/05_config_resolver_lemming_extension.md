# Task 05: Config Resolver Lemming Extension

## Status
- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 03
- **Blocks**: Task 09, Task 10
- **Estimated Effort**: M

## Assigned Agent
`dev-backend-elixir-engineer` - backend engineer for resolver logic and preload-safe config assembly.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and extend `LemmingsOs.Config.Resolver` so Lemming participates in `World -> City -> Department -> Lemming` config resolution, including the new `tools_config` bucket.

## Objective
Extend the existing pure in-memory resolver to accept a preloaded Lemming parent chain and produce effective Lemming config with five buckets (the four existing plus `tools_config`). The resolver must remain backward compatible for World, City, and Department scopes.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/tasks/0004_implement_lemming_management/plan.md` - Recommended Resolver Extension section, Frozen Contract #8-#9
- [ ] `lib/lemmings_os/config/resolver.ex` - Current resolver implementation
- [ ] `lib/lemmings_os/lemmings/lemming.ex` - Task 03 output
- [ ] `lib/lemmings_os/config/tools_config.ex` - Task 02 output
- [ ] `test/lemmings_os/config/resolver_test.exs` - Existing resolver tests
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style

## Expected Outputs

- [ ] Updated `lib/lemmings_os/config/resolver.ex` - Lemming scope support added
- [ ] Updated `test/lemmings_os/config/resolver_test.exs` - Lemming resolver tests added

## Acceptance Criteria

### Resolver Behavior
- [ ] New clause: `resolve(%Lemming{department: %Department{city: %City{world: %World{}}}} = lemming)`
- [ ] Merge order: `World -> City -> Department -> Lemming`
- [ ] Return shape for Lemming scope includes five buckets:
  ```elixir
  %{
    limits_config: %LimitsConfig{},
    runtime_config: %RuntimeConfig{},
    costs_config: %CostsConfig{},
    models_config: %ModelsConfig{},
    tools_config: %ToolsConfig{}
  }
  ```
- [ ] `tools_config` for Lemming scope: merges Lemming's local `tools_config` with parent empty/nil (since parents don't have `tools_config` in this issue)
- [ ] World, City, and Department `resolve/1` return shapes are NOT changed -- no `tools_config` key added to their return maps (backward compatible)

### Backward Compatibility
- [ ] Existing `resolve(%World{})` behavior unchanged
- [ ] Existing `resolve(%City{})` behavior unchanged
- [ ] Existing `resolve(%Department{})` behavior unchanged
- [ ] Existing resolver tests still pass

### Implementation Details
- [ ] Resolver remains pure -- no DB access
- [ ] Lemming resolution delegates to Department resolution first, then merges Lemming overrides on top
- [ ] Handle edge cases where Lemming parent chain is partially loaded (same pattern as Department's `%Ecto.Association.NotLoaded{}` handling)
- [ ] `map_to_embed/2` extended to handle `ToolsConfig`
- [ ] `@type resolved_config` updated to include optional `tools_config` key, or a new `@type resolved_lemming_config` introduced
- [ ] `@spec resolve/1` updated to accept `Lemming.t()`
- [ ] Alias `LemmingsOs.Lemmings.Lemming` and `LemmingsOs.Config.ToolsConfig` added

### Tests
- [ ] Lemming with empty config inherits from Department -> City -> World for the four standard buckets
- [ ] Lemming local overrides take precedence over parent values
- [ ] `tools_config` returns the Lemming's local values (or empty struct if nil)
- [ ] `tools_config` is NOT present in World/City/Department resolution results
- [ ] Nil config buckets at Lemming level fall through to parent effective values

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/config/resolver.ex              # Add Lemming clause here
test/lemmings_os/config/resolver_test.exs       # Add Lemming tests here
lib/lemmings_os/config/tools_config.ex          # New embed to support
```

### Patterns to Follow
- Follow the Department resolution pattern: resolve the parent (Department) first, then merge Lemming overrides
- Handle `%Ecto.Association.NotLoaded{}` for the parent chain (Department's World/City not-loaded case)
- `merge_bucket/3` is reusable for all five buckets
- `embed_to_map/1` and `map_to_embed/2` need ToolsConfig clauses

### Constraints
- Do NOT add `tools_config` to World/City/Department resolution
- Do NOT change the existing `resolved_config` type for non-Lemming scopes
- Do NOT add caching, source tracing, or explain output
- ToolsConfig has no nested structs (unlike CostsConfig with Budgets), so `embed_to_map` and `map_to_embed` for ToolsConfig are straightforward

## Execution Instructions

### For the Agent
1. Read the current resolver implementation completely.
2. Add Lemming scope support following the Department pattern.
3. Add `ToolsConfig` to `map_to_embed/2` and handle it in `embed_to_map/1`.
4. For the Lemming clause, resolve the Department chain first, then merge Lemming's four standard buckets on top, and separately resolve `tools_config`.
5. Keep existing resolver tests passing.
6. Add new tests for Lemming resolution covering inheritance, overrides, and `tools_config`.
7. Update `@moduledoc` to mention Lemming scope.

### For the Human Reviewer
1. Confirm Lemming support is additive and does not regress World/City/Department behavior.
2. Verify `tools_config` only appears in Lemming scope results.
3. Check that no "explain" or source-tracing features leaked into scope.
4. Verify the resolver remains pure (no DB access).

---

## Execution Summary
*[Filled by executing agent after completion]*

### Work Performed
- [What was actually done]

### Outputs Created
- [List of files/artifacts created]

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|

### Blockers Encountered
- [Blocker 1] - Resolution: [How resolved or "Needs human input"]

### Questions for Human
1. [Question needing human input]

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
- [ ] APPROVED - Proceed to next task
- [ ] REJECTED - See feedback below

### Feedback

### Git Operations Performed
```bash
# human-only
```
