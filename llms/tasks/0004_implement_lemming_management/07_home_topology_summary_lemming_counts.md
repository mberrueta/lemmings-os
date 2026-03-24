# Task 07: Home Topology Summary -- Lemming Counts

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
- **Blocked by**: Task 04
- **Blocks**: Task 15
- **Estimated Effort**: S

## Assigned Agent
`dev-frontend-ui-engineer` - frontend engineer for read-model integration and dashboard surface updates.

## Agent Invocation
Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and update the Home dashboard topology summary card to include real persisted Lemming counts.

## Objective
Extend `HomeDashboardSnapshot.build_topology_card_meta/1` to call `Lemmings.topology_summary/1` and include `lemming_count` and `active_lemming_count` in the topology card meta. Update the Home dashboard template to render Lemming counts alongside City and Department counts.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/tasks/0004_implement_lemming_management/plan.md` - US-8 acceptance criteria
- [ ] `lib/lemmings_os_web/page_data/home_dashboard_snapshot.ex` - Current topology card meta builder
- [ ] `lib/lemmings_os/lemmings.ex` - Task 04 output (topology_summary function)
- [ ] `lib/lemmings_os_web/live/home_live.html.heex` - Home dashboard template
- [ ] `test/lemmings_os_web/page_data/home_dashboard_snapshot_test.exs` - Existing snapshot tests

## Expected Outputs

- [ ] Updated `lib/lemmings_os_web/page_data/home_dashboard_snapshot.ex` - Lemming counts in topology meta
- [ ] Updated `lib/lemmings_os_web/live/home_live.html.heex` - Lemming counts rendered
- [ ] Updated tests for the snapshot

## Acceptance Criteria

- [ ] `build_topology_card_meta/1` calls `LemmingsOs.Lemmings.topology_summary/1` and includes `lemming_count` and `active_lemming_count` in the returned map
- [ ] The topology summary card on the Home dashboard shows Lemming definition count
- [ ] When there are zero Lemmings, the count shows `0` (honest)
- [ ] Existing City and Department counts continue to work
- [ ] Template uses `{}` interpolation and `:if`/`:for` attributes (no `<%= %>` blocks)
- [ ] Snapshot test updated to verify Lemming counts are present

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os_web/page_data/home_dashboard_snapshot.ex   # build_topology_card_meta/1
lib/lemmings_os_web/live/home_live.html.heex                # Topology card rendering
lib/lemmings_os_web/components/home_components.ex           # Home component helpers
test/lemmings_os_web/page_data/home_dashboard_snapshot_test.exs
```

### Patterns to Follow
- Follow the existing `Departments.topology_summary/1` call pattern already in `build_topology_card_meta/1`
- Alias `LemmingsOs.Lemmings` at the top of the module

### Constraints
- Do NOT add runtime instance counts (definitions only)
- Keep the topology card simple -- counts only, no per-status breakdown on the card

## Execution Instructions

### For the Agent
1. Read `home_dashboard_snapshot.ex` to understand the current `build_topology_card_meta/1` flow.
2. Add `alias LemmingsOs.Lemmings` and call `Lemmings.topology_summary/1` alongside the existing Department call.
3. Merge `lemming_count` and `active_lemming_count` into the returned meta map.
4. Update the Home dashboard template to render the Lemming count.
5. Update the snapshot test to verify Lemming counts.

### For the Human Reviewer
1. Verify the topology card meta now includes Lemming counts.
2. Confirm the template renders the new count honestly (0 when empty).
3. Reject if the change breaks existing topology summary behavior.

---

## Execution Summary
*Completed by the frontend agent*

### Work Performed
- Extended `HomeDashboardSnapshot.build_topology_card_meta/1` to merge persisted lemming counts from `Lemmings.topology_summary/1` into the topology card meta.
- Updated `HomeComponents.card_display/1` so the topology summary card renders `lemming_count` alongside the existing city and department counts, while keeping `active_lemming_count` available only in the snapshot meta.
- Updated snapshot and LiveView tests to assert the new lemming counts, including the zero-count case.
- Added the gettext entry for the new topology label in English, Spanish, and the extraction template.

### Outputs Created
- `lib/lemmings_os_web/page_data/home_dashboard_snapshot.ex`
- `lib/lemmings_os_web/components/home_components.ex`
- `test/lemmings_os_web/page_data/home_dashboard_snapshot_test.exs`
- `test/lemmings_os_web/live/home_live_test.exs`
- `priv/gettext/en/LC_MESSAGES/layout.po`
- `priv/gettext/es/LC_MESSAGES/layout.po`
- `priv/gettext/layout.pot`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| The existing Home dashboard template did not need a direct markup change because the topology card already renders through `HomeComponents.dashboard_card/1`. | The requested UI update is fully expressed by the snapshot and card component data contract. |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Kept the topology card as counts only, without introducing any lemming status breakdown. | Adding per-status detail. | The task explicitly asked for simple count-only output. |
| Exposed `active_lemming_count` in snapshot metadata but rendered only `lemming_count` on the card. | Rendering both lemming totals on the card. | The task requires the extra meta field, but the UI should stay count-only without adding a lemming status breakdown. |

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
