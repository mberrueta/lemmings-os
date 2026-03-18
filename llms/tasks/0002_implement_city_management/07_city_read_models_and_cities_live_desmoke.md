# Task 07: City Read Models and CitiesLive Desmoke

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 03, Task 05, Task 06
- **Blocks**: Task 08, Task 09, Task 11

## Assigned Agent

`dev-frontend-ui-engineer` - Frontend engineer for Phoenix LiveView.

## Agent Invocation

Use `dev-frontend-ui-engineer` to replace mock-backed city listing with real city read models and LiveView rendering.

## Objective

Make `CitiesLive` the real operator-facing city page backed by persisted city data, derived liveness, and honest read models instead of `MockData`.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] `llms/tasks/0002_implement_city_management/03_cities_context_and_crud_apis.md`
- [ ] `llms/tasks/0002_implement_city_management/05_config_resolver_and_effective_config_merge.md`
- [ ] `llms/tasks/0002_implement_city_management/06_heartbeat_worker_and_presence_model.md`
- [ ] `lib/lemmings_os_web/live/cities_live.ex`
- [ ] `lib/lemmings_os_web/components/world_components.ex`

## Expected Outputs

- [ ] city page snapshot/read-model module(s)
- [ ] updated `CitiesLive`
- [ ] updated `cities_live.html.heex`
- [ ] real data path replacing `MockData` on the Cities page
- [ ] selector-friendly DOM IDs for tests

## Acceptance Criteria

- [ ] `CitiesLive` no longer depends on `LemmingsOs.MockData`
- [ ] city liveness shown on the page comes from heartbeat freshness
- [ ] effective config display uses resolver-backed data where relevant
- [ ] the page remains honest if topology/map visuals cannot be supported with real data
- [ ] Department/Lemming child sections, if still shown, remain explicitly mock-backed via the City read model rather than being presented as persisted/runtime-authoritative
- [ ] key elements have stable IDs for LiveView tests

## Technical Notes

### Relevant Code Locations

- `lib/lemmings_os_web/live/cities_live.ex`
- `lib/lemmings_os_web/live/cities_live.html.heex`
- `lib/lemmings_os_web/components/world_components.ex`
- `lib/lemmings_os/mock_data.ex`
- `test/lemmings_os_web/live/`

### Constraints

- Use LiveView streams for collections
- Preserve the layout shell conventions
- Do not add fake persisted fields just to keep the current mock map
- Keep the UI read-first and operationally honest
- City desmoke does not require Department or Lemming desmoke
- Do not pass raw `MockData` through top-level LiveView assigns in an ad hoc way
- Any remaining Department/Lemming child data must stay isolated behind a read-model or snapshot adapter and remain clearly non-authoritative

## Execution Instructions

### For the Agent

1. Replace mock city inputs with a dedicated read model.
2. Simplify the visualization if the current map requires fake geometry.
3. Ensure liveness and admin status are rendered separately.
4. If child Department/Lemming sections must remain visible, expose them only through explicit mock-backed adapter fields in the City read model.
5. Document any removed mock-only affordances.

### For the Human Reviewer

1. Confirm the City page is now real-data-backed.
2. Confirm the UI did not preserve fake authority for the sake of visual continuity.
3. Confirm testable DOM IDs are present.
4. Approve before Task 08, Task 09, and Task 11 begin.
