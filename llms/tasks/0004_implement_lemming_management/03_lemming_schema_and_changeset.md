# Task 03: Lemming Schema and Changeset

## Status
- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
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
