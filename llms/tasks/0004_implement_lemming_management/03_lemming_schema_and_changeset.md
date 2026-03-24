# Task 03: Lemming Schema and Changeset

## Status
- **Status**: COMPLETE
- **Approved**: [x] Human sign-off
- **Blocked by**: Task 01, Task 02
- **Blocks**: Task 04, Task 05
- **Estimated Effort**: M

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for schema design, changesets, and validation rules.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and create the `LemmingsOs.Lemmings.Lemming` schema with changeset rules, status helpers, and the factory definition.

## Objective
Create the Lemming schema module following the Department schema pattern exactly: associations, config embeds (including the new ToolsConfig), changeset with validation, status helpers, and the ExMachina factory.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/tasks/0004_implement_lemming_management/plan.md` - Frozen contracts #1-#10, Recommended Schema Shape
- [ ] `lib/lemmings_os/departments/department.ex` - Schema pattern precedent
- [ ] `lib/lemmings_os/config/tools_config.ex` - Task 02 output (ToolsConfig embed)
- [ ] `test/support/factory.ex` - Factory pattern precedent
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style

## Expected Outputs

- [ ] `lib/lemmings_os/lemmings/lemming.ex` - Lemming schema module
- [ ] Updated `test/support/factory.ex` - Added `:lemming` factory

## Acceptance Criteria

- [ ] Module is `LemmingsOs.Lemmings.Lemming`
- [ ] Uses `@primary_key {:id, :binary_id, autogenerate: true}` and `@foreign_key_type :binary_id`
- [ ] Schema name is `"lemmings"`
- [ ] Fields match frozen contract:
  - `slug` (string), `name` (string), `status` (string), `description` (string), `instructions` (string)
- [ ] Associations:
  - `belongs_to :world, LemmingsOs.Worlds.World`
  - `belongs_to :city, LemmingsOs.Cities.City`
  - `belongs_to :department, LemmingsOs.Departments.Department`
- [ ] Five config embeds with `on_replace: :update, defaults_to_struct: true`:
  - `limits_config`, `runtime_config`, `costs_config`, `models_config`, `tools_config`
- [ ] `@required ~w(slug name status)a`
- [ ] `@optional ~w(description instructions)a`
- [ ] `@statuses ~w(draft active archived)` -- NOT the Department statuses
- [ ] Changeset rules:
  - `cast(attrs, @required ++ @optional)`
  - `validate_required(@required)`
  - `validate_inclusion(:status, @statuses)`
  - `validate_length(:description, max: ...)` -- bounded, similar to Department notes
  - Cast all 5 config embeds
  - `assoc_constraint(:world)`, `assoc_constraint(:city)`, `assoc_constraint(:department)`
  - `unique_constraint(:slug, name: :lemmings_department_id_slug_index)`
- [ ] Ownership fields (`world_id`, `city_id`, `department_id`) are NOT cast from form attrs
- [ ] Status helpers: `statuses/0`, `status_options/0`, `translate_status/1`
- [ ] `translate_status/1` uses `dgettext("default", ".lemming_status_draft")` etc.
- [ ] `@type t` typespec defined
- [ ] `@moduledoc` present
- [ ] Factory produces valid Lemmings with `world`, `city`, `department` associations and default status `"draft"`

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/departments/department.ex   # Primary pattern to follow
lib/lemmings_os/config/tools_config.ex      # New embed (Task 02 output)
test/support/factory.ex                      # Factory pattern
```

### Patterns to Follow
- Mirror `Department` schema structure exactly for the common patterns
- Use `Gettext` backend for status translations: `use Gettext, backend: LemmingsOs.Gettext`
- Import `Ecto.Changeset`
- Factory should build a `:department` parent (which auto-builds `:city` and `:world`)
- Factory default status should be `"draft"` (not `"active"` like Department)

### Constraints
- No `tags` field (Lemmings do not have tags in this issue)
- No `notes` field (Lemmings use `description` instead)
- No runtime fields (`agent_module`, `started_at`, etc.)
- No `language` field (language is City-level)
- `instructions` is nullable -- a draft lemming may not have instructions yet
- The activation guard (instructions required for active status) belongs in the context (Task 04), not in the changeset -- keep the changeset simple and let the context enforce business rules

## Execution Instructions

### For the Agent
1. Read `department.ex` thoroughly for the exact structural pattern.
2. Create the `lib/lemmings_os/lemmings/` directory and `lemming.ex` file.
3. Follow the Department changeset pattern but use Lemming-specific fields, statuses, and five config embeds.
4. Add the factory to `test/support/factory.ex` following the `department_factory` pattern.
5. The factory should build a `:department` as the parent, inheriting its world and city.

### For the Human Reviewer
1. Verify the schema matches the frozen contract field list exactly.
2. Confirm statuses are `["draft", "active", "archived"]` -- NOT Department statuses.
3. Confirm default status is `"draft"`.
4. Verify ToolsConfig is the fifth embed.
5. Reject if activation guard logic is in the changeset (belongs in context).

---

## Execution Summary

### Work Performed
- Added `LemmingsOs.Lemmings.Lemming` with the persisted schema shape, hierarchy associations, five config embeds, lifecycle status helpers, and the schema changeset rules for this slice.
- Added a `:lemming` ExMachina factory that derives `world` and `city` from its built `:department` parent and defaults status to `\"draft\"`.
- Added schema tests covering required fields, status validation, ownership casting boundaries, embed casting, helper translations, database constraints, and the factory shape.

### Outputs Created
- `lib/lemmings_os/lemmings/lemming.ex`
- `test/lemmings_os/lemmings/lemming_test.exs`
- Updated `test/support/factory.ex`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| Lemming operator-facing description length should use the same 280-character bound as Department notes. | The task calls for a bounded description similar to Department notes, and reusing that limit keeps the operator metadata constraints aligned. |
| A nil lemming status should translate to an unknown label for UI safety even though `nil` is not a valid persisted value. | Existing City and Department status helpers provide a nil-safe fallback for rendering code paths, so the Lemming schema follows the same UI-facing pattern. |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Kept the activation guard out of the changeset and added a test proving `active` can be set without `instructions` at the schema layer. | Enforcing instructions presence in `changeset/2`. | The task explicitly reserves that business rule for the context lifecycle APIs in Task 04. |
| Added `description_max_length/0` as a small helper, mirroring `Department.notes_max_length/0`. | Inlining the numeric bound only in the test. | This keeps the bound explicit and testable without scattering a magic number. |

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
