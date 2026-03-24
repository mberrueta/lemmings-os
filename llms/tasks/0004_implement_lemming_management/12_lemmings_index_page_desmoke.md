# Task 12: Lemmings Index Page Desmoke

## Status
- **Status**: BLOCKED
- **Approved**: [ ] Human sign-off
- **Blocked by**: Task 04
- **Blocks**: Task 15
- **Estimated Effort**: M

## Assigned Agent
`dev-frontend-ui-engineer` - frontend engineer for LiveView page desmoke and cross-cutting read surfaces.

## Agent Invocation
Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and replace the mock-backed Lemmings index page (`/lemmings`) with a real persisted cross-department Lemming listing.

## Objective
Desmoke `LemmingsLive` by replacing `MockData.lemmings/0` and `MockData.find_lemming/1` with real persistence calls. The page should show all Lemming definitions across all Departments in the current World, with each entry showing its parent Department and City ancestry.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/tasks/0004_implement_lemming_management/plan.md` - US-11 acceptance criteria, UX States for Lemmings Index Page
- [ ] `lib/lemmings_os_web/live/lemmings_live.ex` - Current mock-backed page
- [ ] `lib/lemmings_os_web/live/lemmings_live.html.heex` - Current mock template
- [ ] `lib/lemmings_os_web/components/lemming_components.ex` - Current mock lemming components
- [ ] `lib/lemmings_os/lemmings.ex` - Task 04 output (context)
- [ ] `lib/lemmings_os/mock_data.ex` - Mock data module (to understand current mock shape)

## Expected Outputs

- [ ] Updated `lib/lemmings_os_web/live/lemmings_live.ex` - Real persistence backed
- [ ] Updated `lib/lemmings_os_web/live/lemmings_live.html.heex` - Definition-oriented template
- [ ] Updated `lib/lemmings_os_web/components/lemming_components.ex` - Definition-oriented components (or removed if inlined)

## Acceptance Criteria

### Data Source
- [ ] Page loads Lemmings from real persistence, not `MockData`
- [ ] No `MockData` calls remain in `LemmingsLive`
- [ ] Uses `Lemmings.list_all_lemmings(world_or_world_id, opts \\ [])` to list all Lemmings across all Departments

### Display
- [ ] Each Lemming entry shows: name, slug, status badge, description preview
- [ ] Each entry shows parent Department name and City name for ancestry context
- [ ] Status badges: draft=default, active=success, archived=muted
- [ ] No mock runtime fields rendered: no `role`, `current_task`, `recent_messages`, `activity_log`, `model`, `accent`

### UX States
- [ ] Loading: skeleton or spinner
- [ ] Empty: "No lemmings defined in any department" with guidance
- [ ] Populated: Lemming list with ancestry context
- [ ] World unavailable: "World not found" error state

### Navigation
- [ ] Clicking a Lemming navigates to its detail view
- [ ] Breadcrumb shows the Lemmings page context
- [ ] Selected Lemming detail may be shown inline (following current mock pattern) or via navigation to the detail view

### Cleanup
- [ ] `MockShell` import can remain if used for shell/breadcrumb infrastructure
- [ ] `MockData` import and calls must be removed
- [ ] Mock Lemming component rendering (`lemmings_page/1`) must be replaced with definition-oriented rendering

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os_web/live/lemmings_live.ex           # Mock page to replace
lib/lemmings_os_web/live/lemmings_live.html.heex    # Mock template
lib/lemmings_os_web/components/lemming_components.ex # Mock components
lib/lemmings_os/mock_data.ex                         # Mock data source
```

### Patterns to Follow
- Follow the Cities/Departments page pattern: load World, then load entities with preloads
- Use the official World-scoped context API `Lemmings.list_all_lemmings/2`

### Constraints
- Do NOT create a new snapshot module unless the data loading is complex enough to warrant one
- Keep the page focused on definition data only -- no pretend runtime state
- The existing `/lemmings?lemming=ID` route pattern for detail selection can be preserved or replaced

### World-Wide Listing
The current context API `list_lemmings/3` is department-scoped. This page depends on the official World-scoped context contract `list_all_lemmings(world_or_world_id, opts)`, which should be implemented in Task 04 and consumed here. The web layer must not assemble the cross-department list ad hoc by iterating departments.

## Execution Instructions

### For the Agent
1. Read `lemmings_live.ex` and the mock data patterns.
2. Load the page from `Lemmings.list_all_lemmings/2`.
3. Replace all mock data calls with real persistence.
4. Update the template to show definition fields with ancestry context.
5. Handle empty state honestly.
6. Update or replace `lemming_components.ex` for definition-oriented rendering.
7. Preserve shell/breadcrumb infrastructure.

### For the Human Reviewer
1. Verify no `MockData` calls remain in the Lemmings page.
2. Verify the rendered fields are definition-oriented, not runtime-oriented.
3. Verify ancestry context (Department, City) is shown for each Lemming.
4. Reject if mock runtime fields are still rendered.
5. Verify the page uses the context-owned `list_all_lemmings/2` contract rather than assembling the list ad hoc in the web layer.

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
