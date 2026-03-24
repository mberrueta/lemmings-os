# Task 02: ToolsConfig Shared Embedded Schema

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
- **Blocked by**: None (can run in parallel with Task 01)
- **Blocks**: Task 03
- **Estimated Effort**: S

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for schema design and embedded changesets.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and create the `LemmingsOs.Config.ToolsConfig` shared embedded schema.

## Objective
Create the new `ToolsConfig` embedded schema module following the exact pattern of `LimitsConfig`, `RuntimeConfig`, `CostsConfig`, and `ModelsConfig`. This is the fifth config bucket, introduced at the Lemming level only in this issue.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/tasks/0004_implement_lemming_management/plan.md` - Frozen contract #9 (ToolsConfig shape)
- [ ] `lib/lemmings_os/config/limits_config.ex` - Embed pattern precedent
- [ ] `lib/lemmings_os/config/runtime_config.ex` - Embed pattern precedent
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style

## Expected Outputs

- [ ] `lib/lemmings_os/config/tools_config.ex` - New ToolsConfig embedded schema

## Acceptance Criteria

- [ ] Module is `LemmingsOs.Config.ToolsConfig`
- [ ] Uses `Ecto.Schema` with `@primary_key false` and `embedded_schema`
- [ ] Has exactly two fields:
  - `allowed_tools` - `{:array, :string}`, default `[]`
  - `denied_tools` - `{:array, :string}`, default `[]`
- [ ] Defines `@fields` module attribute listing both field atoms
- [ ] Has a `changeset/2` function that casts both fields
- [ ] Has a `@type t` typespec
- [ ] Has `@moduledoc` documentation
- [ ] Does NOT include per-tool overrides, approval hints, restriction levels, tool categories, namespaces, or nested structs
- [ ] Follows the exact module structure of `LimitsConfig` (use Ecto.Schema, import Ecto.Changeset, @primary_key false, @fields, embedded_schema, changeset/2)

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/config/limits_config.ex    # Primary pattern to follow
lib/lemmings_os/config/runtime_config.ex   # Secondary pattern reference
lib/lemmings_os/config/costs_config.ex     # Shows nested embed pattern (NOT needed here)
lib/lemmings_os/config/models_config.ex    # Shows list field pattern
```

### Patterns to Follow
- `@primary_key false`
- `@fields ~w(allowed_tools denied_tools)a`
- `changeset/2` that does `cast(config, attrs, @fields)`
- `@type t` typespec matching the embedded_schema fields

### Constraints
- v1 shape is intentionally minimal -- two flat list fields only
- No governance semantics (no merge strategy, no authorization model)
- No nested structs inside ToolsConfig
- This module must be designed to support future upward propagation to Department/City/World without breaking changes

## Execution Instructions

### For the Agent
1. Read `limits_config.ex` and `runtime_config.ex` for the exact module structure.
2. Create `tools_config.ex` in the same `lib/lemmings_os/config/` directory.
3. Keep it minimal: two list fields, a changeset, a typespec, a moduledoc.
4. Do NOT add any validation beyond casting (matching the pattern of other config embeds).

### For the Human Reviewer
1. Confirm the module matches the structural pattern of existing config embeds.
2. Verify only two fields exist (no scope creep).
3. Reject if any governance semantics or nested structs are added.

---

## Execution Summary

### Work Performed
- Added `LemmingsOs.Config.ToolsConfig` as a new embedded schema module under `lib/lemmings_os/config/`.
- Implemented the minimal v1 shape with `allowed_tools` and `denied_tools` array fields, list defaults, and a casting-only `changeset/2`.
- Added a focused unit test covering both explicit casting and default empty-list behavior.

### Outputs Created
- `lib/lemmings_os/config/tools_config.ex`
- `test/lemmings_os/config/tools_config_test.exs`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| `ToolsConfig` should mirror the lightweight casting behavior of the other config embeds and avoid validation in this task. | The task explicitly says to follow the existing config embed pattern and not add validation beyond `cast/3`. |
| Empty lists are the correct default runtime shape for both tool fields. | The frozen contract defines both fields with default `[]`, which also keeps the embed safe for future upward propagation. |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Added a small unit test for the embed changeset. | Leaving the new module untested. | The constitution requires tests for executable logic, and this keeps the task self-contained with minimal overhead. |
| Kept the moduledoc scoped to Lemmings only. | Describing future Department/City/World propagation in the module docs. | The current shipped behavior is Lemming-only; future propagation is architectural context, not module behavior. |

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
