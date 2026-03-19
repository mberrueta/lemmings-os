# Task 08: World Home Settings City Integration

## Status

- **Status**: COMPLETE
- **Approved**: [X]
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

---

## Execution Summary

### Work Performed

All MockData city authority has been removed from WorldLive, HomeLive, and SettingsLive. Each page now either renders real persisted city data or explicitly degrades when none is available.

### Files Modified

| File | Action | Purpose |
|------|--------|---------|
| `lib/lemmings_os_web/live/world_live.ex` | Modified | Removed mock city code; loads real cities from `Cities.list_cities/1` after snapshot build |
| `lib/lemmings_os_web/live/world_live.html.heex` | Modified | Passes `cities={@cities}` assign to `WorldComponents.world_page` |
| `lib/lemmings_os_web/components/world_components.ex` | Modified | Replaced `#world-map-panel` (mock map) with `#world-cities-panel` (real city list); added `cities` attr to `world_page` and `world_snapshot`; added `city_status_tone/1`, `city_liveness_tone/1`, `city_liveness_label/1` helpers |
| `lib/lemmings_os_web/page_data/settings_page_snapshot.ex` | Modified | Added `city` section that looks up the local node's persisted city row by `node_name`; degrades to `available?: false` when not found |
| `lib/lemmings_os_web/live/settings_live.ex` | Modified | Added `city_status_tone/1` private helper |
| `lib/lemmings_os_web/live/settings_live.html.heex` | Modified | Added `#settings-city-card` showing local runtime city identity, status, node name, and last heartbeat |
| `lib/lemmings_os_web/page_data/home_dashboard_snapshot.ex` | Modified | Added `city_health` card backed by `Cities.list_cities/1` count; removed `"city_network"` from `omitted_sections`; added `build_city_card_meta/1` |
| `lib/lemmings_os_web/components/home_components.ex` | Modified | Added `card_display` clause for `city_health`; added `source_label` for `persisted_cities` |
| `test/lemmings_os_web/live/world_live_test.exs` | Modified | Updated assertions from `#world-map-panel` to `#world-cities-panel` |
| `priv/gettext/world.pot` | Modified | Added `.title_world_cities`, `.subtitle_world_cities`, `.empty_world_cities` |
| `priv/gettext/en/LC_MESSAGES/world.po` | Modified | Added translations for the three new world-domain keys |
| `priv/gettext/es/LC_MESSAGES/world.po` | Modified | Added Spanish translations for the three new world-domain keys |
| `priv/gettext/layout.pot` | Modified | Added 8 new layout-domain keys for settings city card and home city card |
| `priv/gettext/en/LC_MESSAGES/layout.po` | Modified | Added English translations for all 8 new layout keys |
| `priv/gettext/es/LC_MESSAGES/layout.po` | Modified | Added Spanish translations for all 8 new layout keys |

### Acceptance Criteria Verification

- [x] `WorldLive` shows real persisted cities for the current world — overview tab renders `#world-cities-panel` backed by `Cities.list_cities/1`
- [x] `HomeLive` shows only honest city health/counts — new `city_health` card shows persisted city count; no invented topology
- [x] `SettingsLive` shows local node identity and heartbeat freshness — `#settings-city-card` shows the matched city row's name, slug, node_name, and last_seen_at
- [x] Pages degrade explicitly when city/runtime data is unavailable — empty states for zero cities; `available?: false` path for missing city row in settings

### Stable Selectors for QA

| Selector | Page | Condition |
|----------|------|-----------|
| `#world-cities-panel` | World overview tab | Always when snapshot available |
| `#world-cities-empty` | World overview tab | When no cities exist |
| `#world-cities-list` | World overview tab | When cities exist |
| `#world-city-row-{id}` | World overview tab | One per city |
| `#world-city-status-{id}` | World overview tab | Per-city status badge |
| `#world-city-liveness-{id}` | World overview tab | Per-city liveness badge |
| `#settings-city-card` | Settings | Always |
| `#settings-city-status-badge` | Settings | When city available |
| `#settings-city-unavailable` | Settings | When no city row matches node |
| `#settings-city-name` | Settings | When city available |
| `#settings-city-node-name` | Settings | When city available |
| `#settings-city-last-seen-at` | Settings | When city available |
| `#home-card-city_health` | Home | When world is available |

### Intentionally Deferred

- **Department and Lemming child sections** in world_components.ex still use MockData — out of scope per task constraints.
- The mock world map (`MapComponents.world_map`) was removed entirely rather than backed with partial real data; the real city list is a more honest replacement.
- The `WorldLive` cities are not streamed (they are a simple list assign) because the expected city count per world is small; streaming can be added if needed later.

### Mix Validation

- `mix format --check-formatted`: PASS
- `mix test --no-deps-check`: PASS (125 tests, 0 failures)
