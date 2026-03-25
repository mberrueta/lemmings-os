# Task 08: Cities Page Department Cards -- Lemming Counts

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
- **Blocked by**: Task 04
- **Blocks**: Task 15
- **Estimated Effort**: S

## Assigned Agent
`dev-frontend-ui-engineer` - frontend engineer for read-model integration and page snapshot updates.

## Agent Invocation
Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and update the Cities page Department cards to include real Lemming definition counts.

## Objective
Extend the `CitiesPageSnapshot` Department card builder to include Lemming counts for each Department. Update the Cities page template to render the Lemming count on Department cards.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/tasks/0004_implement_lemming_management/plan.md` - US-8 acceptance criteria
- [ ] `lib/lemmings_os_web/page_data/cities_page_snapshot.ex` - Current Department card builder
- [ ] `lib/lemmings_os/lemmings.ex` - Task 04 output (list_lemmings or count query)
- [ ] `lib/lemmings_os_web/live/cities_live.html.heex` - Cities page template
- [ ] `test/lemmings_os_web/page_data/cities_page_snapshot_test.exs` - Existing snapshot tests

## Expected Outputs

- [ ] Updated `lib/lemmings_os_web/page_data/cities_page_snapshot.ex` - Lemming count in Department cards
- [ ] Updated `lib/lemmings_os_web/live/cities_live.html.heex` - Lemming count rendered on Department cards
- [ ] Updated snapshot tests

## Acceptance Criteria

- [ ] Each Department card in the Cities page selected city view includes a `lemming_count` field
- [ ] Lemming count is derived from real persistence via a dedicated count query or dedicated context aggregate API
- [ ] Department cards with zero Lemmings show `0` (honest)
- [ ] `department_card` type in `CitiesPageSnapshot` updated to include `lemming_count`
- [ ] Template renders the Lemming count on each Department card
- [ ] Existing Department card fields (name, status, tags, notes_preview) continue to work
- [ ] The implementation does NOT load full Lemming rows just to count them

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os_web/page_data/cities_page_snapshot.ex   # department_card/1 function
lib/lemmings_os_web/live/cities_live.html.heex           # Department card rendering
test/lemmings_os_web/page_data/cities_page_snapshot_test.exs
```

### Patterns to Follow
- The `city_departments_snapshot/1` function already loads departments for a city
- Add a dedicated Lemming count query or context aggregate API for use in `department_card/1`
- Keep the count path efficient -- `Repo.aggregate`, grouped count query, or equivalent aggregate read model rather than loading full Lemming records

### Constraints
- Do NOT add per-status Lemming breakdown on the card (just total count for now)
- Keep the Department card minimal -- count only, not a full Lemming preview
- Do NOT use `length(Lemmings.list_lemmings(...))` or any \"load then count\" approach

## Execution Instructions

### For the Agent
1. Read `cities_page_snapshot.ex`, specifically `department_card/1` and `city_departments_snapshot/1`.
2. Add `alias LemmingsOs.Lemmings` at the top.
3. In `department_card/1`, add a Lemming count for the department using an aggregate path, not a loaded list.
4. Add `lemming_count` to the returned Department card map.
5. Update the Cities page template to render the count on each Department card.
6. Update snapshot tests.

### For the Human Reviewer
1. Verify Lemming counts appear on Department cards.
2. Confirm the count uses real persistence.
3. Reject if the implementation loads full Lemming rows just to count them.

---

## Execution Summary
*Completed by the executing agent*

### Work Performed
- Added an aggregate `Lemmings.lemming_counts_by_department/1` query that groups persisted lemming counts by department for a selected city without loading full lemming rows.
- Extended `CitiesPageSnapshot` department cards to include `lemming_count`, defaulting to `0` when a department has no persisted lemmings.
- Updated the Cities page department list rendering to show the lemming count on each department row.
- Updated snapshot and LiveView tests to verify the persisted count appears in both the read model and the rendered UI.

### Outputs Created
- `lib/lemmings_os/lemmings.ex`
- `lib/lemmings_os_web/page_data/cities_page_snapshot.ex`
- `lib/lemmings_os_web/components/world_components.ex`
- `test/lemmings_os_web/page_data/cities_page_snapshot_test.exs`
- `test/lemmings_os_web/live/cities_live_test.exs`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| The Cities page department rows are rendered through `WorldComponents.city_departments_panel/1`, not directly in `cities_live.html.heex`. | The LiveView template delegates the selected city department card markup to the shared component. |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Added a grouped aggregate API in `Lemmings` instead of counting per department row. | Per-row aggregate queries or `length(Lemmings.list_lemmings(...))`. | A grouped query keeps the count path efficient and avoids loading full lemming rows. |
| Rendered only the total lemming count per department row. | Adding per-status breakdown or previews. | The task explicitly requires a minimal count-only card. |

### Blockers Encountered
- None

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
