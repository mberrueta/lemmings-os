# Task 11: Create Lemming Page Desmoke

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
- **Blocked by**: Task 04, Task 09
- **Blocks**: Task 15
- **Estimated Effort**: M

## Assigned Agent
`dev-frontend-ui-engineer` - frontend engineer for form-driven LiveView pages and changeset-backed forms.

## Agent Invocation
Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and replace the mock-backed Create Lemming page with a real changeset-backed form that persists Lemming definitions through the `Lemmings` context.

## Objective
Desmoke `CreateLemmingLive` (or integrate creation into the Department Lemmings tab) by replacing the mock form fields (`model`, `role`, `system_prompt`) with real Lemming schema fields (`name`, `slug`, `description`, `instructions`, `status`) backed by changeset validation and persistence.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/tasks/0004_implement_lemming_management/plan.md` - US-3 acceptance criteria, UX States for Create Form
- [ ] `lib/lemmings_os_web/live/create_lemming_live.ex` - Current mock create page
- [ ] `lib/lemmings_os_web/live/create_lemming_live.html.heex` - Current mock template
- [ ] `lib/lemmings_os/lemmings.ex` - Task 04 output (create_lemming function)
- [ ] `lib/lemmings_os/lemmings/lemming.ex` - Task 03 output (schema, changeset)
- [ ] `lib/lemmings_os_web/live/departments_live.ex` - Task 09 output (for navigation context)

## Expected Outputs

- [ ] Updated or replaced `lib/lemmings_os_web/live/create_lemming_live.ex` (or equivalent in DepartmentsLive)
- [ ] Updated template for the create form
- [ ] Possibly updated `lib/lemmings_os_web/router.ex` if routing changes

## Acceptance Criteria

### Form Fields
- [ ] Form includes: name (required), slug (auto-generated from name or manually entered), description (optional), instructions (optional), status (defaults to "draft")
- [ ] Slug is auto-generated from name using `Helpers.slugify/1` when not manually overridden
- [ ] Config buckets default to empty structs (inherit everything from parent)
- [ ] Mock fields (`model`, `role`, `system_prompt`) are removed

### Department Context
- [ ] The create form knows which Department (and by extension, which City and World) the Lemming belongs to
- [ ] `world_id` and `city_id` are set by the context from the Department, not from form params
- [ ] The form is accessible from the Department Lemmings tab CTA ("Create Lemming" / "New Lemming")

### Validation
- [ ] Live validation on `phx-change` with inline errors
- [ ] Required field validation: name, slug
- [ ] Slug uniqueness error shown when conflicting slug exists in the same Department
- [ ] Validation messages are internationalized via `dgettext`

### Persistence
- [ ] On save: `Lemmings.create_lemming(world_id, city_id, department_id, attrs)` is called
- [ ] On success: flash message shown, redirect to Lemming detail or Department Lemmings tab
- [ ] On validation error: inline errors on affected fields, form data preserved
- [ ] Submit button disabled during save

### No Mock Dependencies
- [ ] No `MockData` calls
- [ ] No `@available_tools` mock list
- [ ] No `toggle_tool` event handler (mock concept)

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os_web/live/create_lemming_live.ex       # Mock page to replace
lib/lemmings_os_web/live/create_lemming_live.html.heex # Mock template to replace
lib/lemmings_os_web/live/departments_live.ex           # Department context for navigation
lib/lemmings_os_web/router.ex                          # Route: /lemmings/new
```

### Patterns to Follow
- Follow the Department settings form pattern from `DepartmentsLive` for changeset-backed forms
- Use `to_form(changeset, as: :lemming)` for form binding
- Use `phx-change="validate"` and `phx-submit="save"` events
- Auto-slug: compute slug from name on change, allow manual override

### Routing Decision
The current route is `/lemmings/new` which lacks Department context. Options:
1. Keep `/lemmings/new` with query params `?department=ID&city=ID`
2. Move creation into the Department Lemmings tab as an inline form or modal
3. Add a Department-scoped route like `/departments?city=X&dept=Y&tab=lemmings&action=new`

The agent should choose the approach that best fits the existing navigation model. Option 3 is most consistent with how the Departments page already works.

### Constraints
- Do NOT add config bucket editing in the create form (defaults to empty structs, config editing is Task 13)
- Keep the form focused on the core definition fields
- The create flow must have Department context available

## Execution Instructions

### For the Agent
1. Read `create_lemming_live.ex` to understand the current mock implementation.
2. Read the Department settings form pattern from `departments_live.ex` for changeset-backed form conventions.
3. Replace the mock form with a changeset-backed form using real Lemming schema fields.
4. Ensure the form knows its target Department (via route params or navigation context).
5. Implement `validate` and `save` event handlers using the Lemmings context.
6. Add auto-slug generation from name.
7. Handle success (flash + redirect) and error (inline validation) states.
8. Remove all mock dependencies.

### For the Human Reviewer
1. Verify no mock fields remain (model, role, system_prompt, tools).
2. Verify the form creates real persisted records via the context.
3. Verify the form has Department context for scoping.
4. Verify slug auto-generation works.
5. Reject if config bucket editing is added (belongs to Task 13).

---

## Execution Summary
*[Filled by executing agent after completion]*

### Work Performed
- Replaced the mock-backed `CreateLemmingLive` with a real changeset-backed create flow using `Lemmings.create_lemming/4`.
- Added Department-scoped create context through `/lemmings/new?dept=<department_id>`.
- Upgraded the no-context entry at `/lemmings/new` to load the default world plus real city and department selectors, patching into the scoped create flow instead of showing only a dead-end warning.
- Implemented live validation, auto-slug generation from name, manual slug override preservation, and real persistence.
- Reworked the create page UI to use existing panel/input/button/stat components instead of the mock tools workflow.
- Updated the Department Lemmings empty-state CTA to navigate with Department context.
- Added dedicated LiveView coverage for missing-context, real form rendering, auto-slug, create success, and duplicate slug validation.
- Updated `en` and `es` translations for the new create flow strings.

### Outputs Created
- Updated `lib/lemmings_os_web/live/create_lemming_live.ex`
- Updated `lib/lemmings_os_web/live/create_lemming_live.html.heex`
- Updated `lib/lemmings_os_web/components/lemming_components.ex`
- Updated `lib/lemmings_os_web/components/world_components.ex`
- Added `test/lemmings_os_web/live/create_lemming_live_test.exs`
- Updated `test/lemmings_os_web/live/navigation_live_test.exs`
- Updated `priv/gettext/en/LC_MESSAGES/lemmings.po`
- Updated `priv/gettext/es/LC_MESSAGES/lemmings.po`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
- Using `?dept=` on `/lemmings/new` is acceptable for this task. | It preserves the existing route surface while giving the form the Department context it needs. |
- Entering `/lemmings/new` without Department context should stay honest instead of crashing. | The sidebar still links to the generic route, so an empty-state guard is safer than implicit fake defaults. |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
- Kept the route as `/lemmings/new?dept=ID`. | Department tab inline form; a new nested route. | Lowest-diff option that still gives real Department context and matches current navigation patterns. |
- Derived World and City from the persisted Department preload instead of trusting query params. | Passing `world` and `city` through params and re-validating them. | Keeps the API simpler and aligned with the domain contract that Department owns its parent scope. |
- Left the generic `/lemmings/new` route available with a world/city/department scope picker. | Forcing a redirect or removing the route. | Avoids breaking the sidebar entrypoint while still guiding operators toward the correct Department-scoped create flow. |

### Blockers Encountered
- The page had no existing dedicated LiveView test coverage. - Resolution: added `test/lemmings_os_web/live/create_lemming_live_test.exs` to lock the new contract.

### Questions for Human
1. The sidebar still links to `/lemmings/new` without Department context. If the product later wants a global creation flow beyond the default world, that route will need a broader world-selection decision.

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
