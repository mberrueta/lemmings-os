# Task 10: Lemming Detail View

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
- **Blocked by**: Task 09
- **Blocks**: Task 13, Task 14
- **Estimated Effort**: M

## Assigned Agent
`dev-frontend-ui-engineer` - frontend engineer for operational detail pages, lifecycle actions, and config display.

## Agent Invocation
Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and implement the Lemming detail/read view showing the stored definition, lifecycle actions, and effective config summary.

## Objective
Create the Lemming detail view accessible from the Department Lemmings tab (Task 09). The view shows the full stored definition (name, slug, description, instructions, status), lifecycle action buttons, and a read-only effective config summary. This can be implemented as a panel within the Departments page or as a separate route.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/tasks/0004_implement_lemming_management/plan.md` - US-2, US-5, US-7 acceptance criteria, UX States for Lemming Detail View
- [ ] `lib/lemmings_os_web/live/departments_live.ex` - Task 09 output (Department page with real Lemming listing)
- [ ] `lib/lemmings_os_web/live/departments_live.html.heex` - Task 09 output
- [ ] `lib/lemmings_os/lemmings.ex` - Task 04 output (fetch/get APIs)
- [ ] `lib/lemmings_os/config/resolver.ex` - Task 05 output (Lemming resolver)
- [ ] `lib/lemmings_os_web/components/world_components.ex` - Department detail pattern

## Expected Outputs

- [ ] Updated or new LiveView module with Lemming detail view
- [ ] Updated or new template rendering Lemming definition
- [ ] Lifecycle action event handlers (activate, archive)
- [ ] Read-only effective config summary section

## Acceptance Criteria

### Definition Display
- [ ] Shows: name, slug, description, instructions (full text, no truncation), status badge
- [ ] Instructions rendered as preformatted or prose text
- [ ] Works for all three statuses (draft, active, archived)
- [ ] Archived lemmings show visual indication of archived state (muted styling)

### Lifecycle Actions
- [ ] "Activate" button visible for draft and archived lemmings
- [ ] "Archive" button visible for active lemmings
- [ ] Activate a draft lemming with instructions: succeeds, status updates, flash shown
- [ ] Activate a draft lemming without instructions: denied with error flash
- [ ] Archive an active lemming: succeeds, status updates, flash shown
- [ ] Reactivate an archived lemming: succeeds (instructions already present)
- [ ] Available actions change based on current status
- [ ] No "Delete" button exposed (or shown disabled with explanatory tooltip)

### Effective Config Summary
- [ ] Config section shows the resolved (merged) values from `Config.Resolver.resolve/1`
- [ ] Lemming must be loaded with preloaded parent chain (`department.city.world`)
- [ ] `tools_config` values shown when present (allowed_tools, denied_tools)
- [ ] When all config buckets are empty/inherited: show "Inheriting all configuration from parents" note
- [ ] Display is read-only -- no editing in this task (Task 13 owns the edit form)

### Navigation
- [ ] Accessible from the Department Lemmings tab (clicking a Lemming in the list)
- [ ] Breadcrumb trail includes: Cities > City > Departments > Department > Lemming
- [ ] Back navigation returns to the Department Lemmings tab

### Not Found
- [ ] Invalid Lemming ID shows "Lemming not found" state

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os_web/live/departments_live.ex       # Department detail pattern to follow
lib/lemmings_os_web/live/departments_live.html.heex # Tab/detail template pattern
lib/lemmings_os_web/components/world_components.ex  # Component patterns
lib/lemmings_os/config/resolver.ex                   # Resolver for effective config
```

### Patterns to Follow
- Follow the Department detail pattern: load entity with preloads, resolve config, assign to socket
- Lifecycle actions follow the `handle_event("department_lifecycle", ...)` pattern from DepartmentsLive
- Config display can be a simple key-value rendering of the resolved config map

### Constraints
- Do NOT implement an edit form in this task (that is Task 13)
- Do NOT implement import/export UI (that is Task 14)
- Config display is read-only summary, not an editable form
- No mock runtime state rendered (current_task, recent_messages, etc.)

### Routing Decision
The detail view can be implemented as:
- A panel/section within the existing Departments page (e.g., adding a `lemming` query param)
- A separate LiveView route (e.g., `/lemmings/:id`)

The agent should follow whichever approach best matches the existing navigation model. The Departments page already uses query params for department selection and tab navigation, so extending it with a `lemming` param is a natural fit. However, a dedicated route may be cleaner for deep linking.

## Execution Instructions

### For the Agent
1. Read the Department detail implementation for the pattern (how detail is loaded, config resolved, lifecycle handled).
2. Implement Lemming detail view with full definition display.
3. Add lifecycle event handlers for activate and archive.
4. Load the Lemming with full parent chain preload for config resolution.
5. Display the effective config summary using the resolver output.
6. Add breadcrumb navigation.
7. Handle the not-found case.

### For the Human Reviewer
1. Verify all definition fields are displayed (name, slug, description, instructions, status).
2. Verify lifecycle actions work correctly (especially activation guard).
3. Verify config summary is read-only and uses the resolver.
4. Verify no mock runtime fields are rendered.
5. Reject if an edit form is included (that belongs to Task 13).

---

## Execution Summary
*[Filled by executing agent after completion]*

### Work Performed
- Replaced the mock-backed `/lemmings` page with persisted data from `Lemmings` and the default persisted world.
- Added real Lemming detail loading with `department.city.world` preload and read-only effective config resolution through `Config.Resolver`.
- Implemented lifecycle actions for `activate` and `archive`, including the `:instructions_required` activation guard flash path.
- Reworked the detail panel to show persisted definition fields only: name, slug, description, instructions, status, hierarchy context, and effective config summary.
- Added honest empty-selection and not-found states.
- Replaced the mock navigation test with persisted records and added dedicated LiveView coverage for the detail page and lifecycle actions.

### Outputs Created
- Updated `lib/lemmings_os_web/live/lemmings_live.ex`
- Updated `lib/lemmings_os_web/live/lemmings_live.html.heex`
- Updated `lib/lemmings_os_web/components/lemming_components.ex`
- Updated `lib/lemmings_os_web/components/core_components.ex`
- Updated `test/lemmings_os_web/live/navigation_live_test.exs`
- Added `test/lemmings_os_web/live/lemmings_live_test.exs`
- Updated gettext catalogs via `mix gettext.extract --merge`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| The existing `/lemmings?lemming=<id>` route should become the persisted detail view | It already existed, is linked from the Department lemmings tab, and avoids introducing another route surface |
| A compact effective-config summary is sufficient for this task | Task 10 calls for read-only config display; Task 13 owns editing |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Kept the detail view on `/lemmings` rather than embedding a second panel inside Departments | Separate Departments panel, dedicated `/lemmings/:id` route | This preserves the existing deep link used by Task 09 and keeps the detail page focused |
| Removed mock runtime fields from the detail page instead of trying to preserve the old registry presentation | Partial reuse of runtime fields | Task scope is persisted definition detail, not runtime activity |
| Added a `muted` badge tone for archived lemmings | Reusing `default` or `warning` | Archived needed an explicitly subdued state without distorting other status tones |

### Blockers Encountered
- `archived` used a `muted` status tone that the shared badge component did not support - Resolution: added `muted` tone support in `CoreComponents.badge/1`

### Questions for Human
1. None

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
