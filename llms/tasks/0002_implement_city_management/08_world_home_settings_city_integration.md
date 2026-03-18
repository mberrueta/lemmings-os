# Task 08: World Home Settings City Integration

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 06, Task 07
- **Blocks**: Task 11

## Assigned Agent

`dev-frontend-ui-engineer` - Frontend engineer for Phoenix LiveView.

## Agent Invocation

Use `dev-frontend-ui-engineer` to update the World, Home, and Settings surfaces so they consume real city data.

## Objective

Remove remaining mock city authority from the current operator shell and replace it with honest city summaries, liveness, and local runtime diagnostics.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] `llms/tasks/0002_implement_city_management/07_city_read_models_and_cities_live_desmoke.md`
- [ ] `lib/lemmings_os_web/page_data/home_dashboard_snapshot.ex`
- [ ] `lib/lemmings_os_web/page_data/settings_page_snapshot.ex`
- [ ] `lib/lemmings_os_web/live/world_live.ex`

## Expected Outputs

- [ ] updated world/home/settings read models or page-data modules
- [ ] updated UI components using real city data
- [ ] removal of remaining city-related `MockData` dependencies on those pages
- [ ] stable selectors and IDs needed by later QA tasks

## Acceptance Criteria

- [ ] `WorldLive` shows real persisted cities for the current world
- [ ] `HomeLive` shows only honest city health/counts and does not invent topology
- [ ] `SettingsLive` shows local node identity and heartbeat freshness when available
- [ ] pages degrade explicitly when city/runtime data is unavailable

## Technical Notes

### Relevant Code Locations

- `lib/lemmings_os_web/page_data/home_dashboard_snapshot.ex`
- `lib/lemmings_os_web/page_data/settings_page_snapshot.ex`
- `lib/lemmings_os_web/live/world_live.ex`
- `lib/lemmings_os_web/live/home_live.ex`
- `lib/lemmings_os_web/live/settings_live.ex`

### Constraints

- Do not invent counts, regions, or activity data
- Preserve the existing status taxonomy
- Keep config merge logic out of the UI
- Do not broaden this task into Department or Lemming desmoke

## Execution Instructions

### For the Agent

1. Audit all remaining city mentions on World/Home/Settings.
2. Replace only the city-related mock authority touched by this issue.
3. Keep unavailable/degraded behavior explicit.
4. Record any surfaces intentionally deferred because they would require broader hierarchy persistence.

### For the Human Reviewer

1. Confirm the affected pages no longer imply fake city authority.
2. Confirm the local node diagnostics are useful and honest.
3. Confirm no resolver logic leaked into HEEx or LiveViews.
4. Approve before Task 11 proceeds.
