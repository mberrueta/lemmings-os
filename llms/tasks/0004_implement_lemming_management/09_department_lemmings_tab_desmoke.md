# Task 09: Department Lemmings Tab Desmoke

## Status
- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 04, Task 05
- **Blocks**: Task 10, Task 11
- **Estimated Effort**: M

## Assigned Agent
`dev-frontend-ui-engineer` - frontend engineer for LiveView page desmoke and read-model-driven UI.

## Agent Invocation
Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and replace the mock-backed Department Lemmings tab with a real persisted Lemming listing.

## Objective
Replace the `MockData.lemmings_for_department/1` call in `DepartmentsLive` with a real `Lemmings.list_lemmings/3` call. Update the Lemmings tab template to render persisted Lemming definition data (name, slug, status badge, description preview) instead of mock runtime fields (role, current_task, model).

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/tasks/0004_implement_lemming_management/plan.md` - US-1 acceptance criteria, UX States for Department Lemmings Tab
- [ ] `lib/lemmings_os_web/live/departments_live.ex` - Current DepartmentsLive (has `department_lemming_preview` using MockData)
- [ ] `lib/lemmings_os_web/live/departments_live.html.heex` - Current Lemmings tab template
- [ ] `lib/lemmings_os/lemmings.ex` - Task 04 output (context)
- [ ] `lib/lemmings_os/lemmings/lemming.ex` - Task 03 output (schema)
- [ ] `lib/lemmings_os_web/components/world_components.ex` - Existing component patterns

## Expected Outputs

- [ ] Updated `lib/lemmings_os_web/live/departments_live.ex` - Real Lemming listing replaces mock data
- [ ] Updated `lib/lemmings_os_web/live/departments_live.html.heex` - Lemmings tab shows definition data
- [ ] Possibly updated `lib/lemmings_os_web/components/world_components.ex` or new `lib/lemmings_os_web/components/lemming_components.ex` - Lemming list item component

## Acceptance Criteria

- [ ] `department_lemming_preview` assign is replaced with `department_lemmings` (real persisted data)
- [ ] Lemmings tab loads via `Lemmings.list_lemmings(world_id, department_id)`
- [ ] No `MockData` calls remain in the Department Lemmings tab path
- [ ] Each Lemming list item shows: name, slug, status badge, description preview
- [ ] Status badges use appropriate tones: draft=default, active=success, archived=muted
- [ ] Empty state: "No lemmings defined yet" with a CTA to create the first Lemming
- [ ] Populated state: ordered by `inserted_at` ascending (from context query)
- [ ] Clicking a Lemming navigates to the Lemming detail view (link target for Task 10)
- [ ] No mock runtime fields rendered: no `role`, `current_task`, `recent_messages`, `activity_log`
- [ ] Template uses `{}` interpolation and `:if`/`:for` attributes

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os_web/live/departments_live.ex       # department_lemming_preview function
lib/lemmings_os_web/live/departments_live.html.heex # Lemmings tab section
lib/lemmings_os_web/components/lemming_components.ex # Existing mock lemming components (to be reworked)
lib/lemmings_os/mock_data.ex                        # MockData to remove dependency on
```

### Patterns to Follow
- Replace `department_lemming_preview/1` with a function that calls `Lemmings.list_lemmings/3`
- Follow the same pattern used for loading departments in `load_departments/2`
- Navigation to Lemming detail can use query params (e.g., `?lemming=ID`) or a dedicated route

### Constraints
- Do NOT implement the full Lemming detail view in this task (that is Task 10)
- Do NOT implement the Create Lemming form (that is Task 11)
- The CTA button to create a Lemming should link to the create flow but does not need to work until Task 11
- Keep the `MockData` module itself intact -- other pages may still use it; only remove the Lemmings tab dependency

## Execution Instructions

### For the Agent
1. Read `departments_live.ex`, focusing on `department_lemming_preview/1` and `assign_department_detail/3`.
2. Replace the mock data loading with `Lemmings.list_lemmings(world_id, department_id)`.
3. Rename the assign from `department_lemming_preview` to `department_lemmings` for clarity.
4. Update the Lemmings tab template to render definition fields instead of mock runtime fields.
5. Add empty state handling with a CTA button.
6. Add navigation links from each Lemming to its detail view (target for Task 10).

### For the Human Reviewer
1. Verify no `MockData` calls remain in the Lemmings tab code path.
2. Verify the rendered fields are definition-oriented (name, slug, status, description), not runtime-oriented.
3. Confirm the empty state CTA exists.
4. Reject if mock runtime fields are still rendered.

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
