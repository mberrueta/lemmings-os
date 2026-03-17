# Task 13: Test Scenarios and Coverage Plan

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: None
- **Blocks**: Task 14

## Assigned Agent

`qa-test-scenarios` - Test scenario designer.

## Agent Invocation

Use `qa-test-scenarios` to define the coverage matrix for the persisted-World + bootstrap + read-only UI slice.

## Objective

Produce the scenario-level test plan before final test implementation.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] Tasks 01 through 11 outputs
- [ ] `test/lemmings_os_web/live/navigation_live_test.exs`
- [ ] `test/support/conn_case.ex`
- [ ] `test/support/data_case.ex`

## Expected Outputs

- [ ] scenario matrix for migration/schema/context, bootstrap ingestion, snapshots, and desmoked pages
- [ ] coverage priorities for success, degraded, unavailable, invalid, and unknown states
- [ ] guidance on test file layout

## Acceptance Criteria

- [ ] all frozen statuses are covered
- [ ] all major read-only interactions are covered
- [ ] tests favor selectors and outcomes over brittle text assertions

## Technical Notes

### Constraints

- No implementation code
- Keep scenarios aligned with repo test patterns

## Execution Instructions

### For the Agent

1. Review implemented outputs from prior tasks.
2. Identify the minimum complete test set.
3. Flag any missing selectors or IDs needed for stability.

### For the Human Reviewer

1. Confirm the proposed coverage is sufficient.
2. Approve before Task 14 begins.

## Scope & Assumptions

- Scope covers the persisted `World` foundation, bootstrap ingestion, cache behavior, snapshots,
  and the read-only `/home`, `/world`, `/tools`, and `/settings` slice.
- The frozen bootstrap shape, status taxonomy, and normalized issue contract from
  `llms/tasks/0001_implement_world_management/plan.md` remain the source of truth.
- The goal of this task is to define the minimum complete test set before Task 14 writes any new
  test code.

## Risk Areas

- Data contract drift between migration/schema/context and bootstrap ingestion.
- Silent masking of `degraded`, `unavailable`, `invalid`, or `unknown` states in read-only UI.
- Cache staleness after import or upsert causing `/home`, `/world`, and `/settings` to disagree.
- Selector instability on pages where tests currently depend on nested `data-status` selectors or
  generic card structure.

## Test File Layout Guidance

- Domain and persistence
  - `test/lemmings_os/worlds_test.exs`
  - `test/lemmings_os/world_cache_test.exs`
- Bootstrap ingestion
  - `test/lemmings_os/world_bootstrap/loader_test.exs`
  - `test/lemmings_os/world_bootstrap/shape_validator_test.exs`
  - `test/lemmings_os/world_bootstrap/importer_test.exs`
- Snapshot read models
  - `test/lemmings_os_web/page_data/world_page_snapshot_test.exs`
  - `test/lemmings_os_web/page_data/tools_page_snapshot_test.exs`
  - `test/lemmings_os_web/page_data/home_dashboard_snapshot_test.exs`
  - `test/lemmings_os_web/page_data/settings_page_snapshot_test.exs`
- LiveViews
  - `test/lemmings_os_web/live/world_live_test.exs`
  - `test/lemmings_os_web/live/tools_live_test.exs`
  - `test/lemmings_os_web/live/settings_live_test.exs`
  - `test/lemmings_os_web/live/home_live_test.exs`
  - `test/lemmings_os_web/live/navigation_live_test.exs`

## Scenario Matrix

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| WMS-01 | P0 | Unit | DB | `worlds` migration exposes required columns, defaults, and unique constraints | Migrated test DB | Inspect schema metadata and constraints | `worlds` includes normal columns, JSONB config columns, and uniqueness on `slug` and `bootstrap_path` | Covers Task 01 |
| WMS-02 | P0 | Unit | Validation | `World.changeset/2` enforces required fields and valid status values | Schema module loaded | Build valid and invalid changesets | Missing required fields fail, defaults remain `unknown`, and JSONB config defaults stay `%{}` | Covers Task 02 |
| WMS-03 | P0 | Integration | Context | `fetch_world/1` and `get_default_world/0` return persisted worlds or not-found tuples | Seed one world or none | Fetch by id and as default world | Existing world is returned; empty DB yields `{:error, :not_found}`-style tuples | Covers Task 02 |
| WMS-04 | P0 | Integration | Context/DB | `upsert_world/1` stays idempotent across `id`, `bootstrap_path`, and `slug` matching | Existing world present | Upsert with same identifiers in different combinations | Existing row is updated rather than duplicated | Covers Task 02 |
| WMS-05 | P0 | Integration | Cache | Cache serves stable reads after the first lookup | World already fetched into cache | Delete row from DB and fetch again | Cached world is returned until explicit invalidation | Covers Task 05 |
| WMS-06 | P0 | Integration | Cache | Cache invalidates after world upsert/import | Cached world exists | Update world through context/importer and fetch again | Subsequent reads return refreshed data | Covers Tasks 04-05 |
| WMS-07 | P0 | Unit | Bootstrap | Loader parses valid YAML and preserves source metadata | Valid bootstrap temp file | Load via `Loader.load/1` | Parsed config, `path`, and `source` are preserved | Covers Task 03 |
| WMS-08 | P0 | Unit | Bootstrap | Loader reports missing files as normalized issues | Missing bootstrap path | Load missing path | Returns `bootstrap_file_not_found` with stable fields and actionable hint | Covers Task 03 |
| WMS-09 | P0 | Unit | Bootstrap | Loader reports YAML parse failures as normalized issues | Malformed YAML file | Load malformed file | Returns `bootstrap_yaml_parse_error` with stable fields and actionable hint | Covers Task 03 |
| WMS-10 | P0 | Unit | Validation | Shape validator accepts the frozen bootstrap contract | Frozen-valid config map | Validate config | Returns `{:ok, ...}` with no errors | Covers Task 03 |
| WMS-11 | P0 | Unit | Validation | Shape validator warns on unknown keys and errors on missing or mistyped required fields | Valid config with one mutation | Add unknown key, remove required section, or change a type | Unknown keys become warnings; contract violations become errors | Covers Task 03 |
| WMS-12 | P0 | Integration | Bootstrap | Importer creates a persisted world from valid bootstrap YAML | Empty `worlds` table | Sync default world from valid file | Returns `ok`, stores config sections, hash, path, source, and persisted import metadata | Covers Task 04 |
| WMS-13 | P0 | Integration | Bootstrap | Importer updates the same persisted world when the bootstrap file changes at the same path | Existing imported world | Modify file contents and sync again | Same world id is reused and persisted config changes | Covers Task 04 |
| WMS-14 | P0 | Integration | Bootstrap | Invalid bootstrap input updates persisted import metadata without inventing success | Existing imported world | Remove required section and sync again | Returns `invalid`; persisted world import status becomes `invalid` | Covers Task 04 |
| WMS-15 | P0 | Integration | Bootstrap | Missing bootstrap file returns unavailable result and does not fabricate a world | Missing bootstrap path | Sync default world | Returns `unavailable`; no new persisted world is produced | Covers Task 04 |
| WMS-16 | P1 | Integration | Bootstrap | Persistence failures are surfaced as normalized sync issues | Conflicting persisted data | Sync valid bootstrap that cannot be saved | Returns `bootstrap_persistence_failed` with operator guidance | Covers Task 04 |
| WMS-17 | P0 | Unit | Snapshot | `WorldPageSnapshot.build/1` keeps persisted identity, bootstrap, immediate import, last sync, and runtime separate | Persisted world with valid bootstrap | Build snapshot directly | Sections remain separate and runtime checks include bootstrap/postgres/provider checks | Covers Task 06 |
| WMS-18 | P0 | Unit | Snapshot | `WorldPageSnapshot` covers `unknown`, `invalid`, `degraded`, and `unavailable` states honestly | Worlds with no path, missing file, invalid shape, or missing env | Build snapshots for each state | Status and issues match the underlying source problem | Covers Task 06 |
| WMS-19 | P0 | Unit | Snapshot | `ToolsPageSnapshot` covers runtime empty, runtime unavailable, deferred policy, and partial policy states | Injected runtime/policy fetchers | Build snapshot per state | Status, issue list, and tool policy/runtime entries match the source state | Covers Task 09 |
| WMS-20 | P0 | Unit | Snapshot | `HomeDashboardSnapshot` prunes unsupported cards and keeps only trustworthy signals | No world or partial world/tools snapshots | Build snapshot per scenario | Home cards, alerts, actions, and omitted sections match the real available sources | Covers Task 11 |
| WMS-21 | P1 | Unit | Snapshot | `SettingsPageSnapshot` maps runtime/world/bootstrap info into honest read-only values | World present and world missing cases | Build settings snapshot directly | Read-only values reflect actual state and do not invent editable settings | Covers Task 08 |
| WMS-22 | P0 | LiveView | UI | `/world` empty state exposes import affordance and transitions to a real snapshot after import | No persisted world or importable bootstrap | Open `/world`, click import, inspect rerender | Empty state disappears; status strip and tabbed panels appear | Covers Task 07 |
| WMS-23 | P0 | LiveView | UI | `/world` tab navigation preserves status strip and reveals import/bootstrap/runtime content | Persisted world exists | Switch tabs and inspect selectors | Correct panels render and the status strip remains visible | Covers Task 07 |
| WMS-24 | P0 | LiveView | UI | `/world` renders degraded or unavailable runtime/bootstrap states honestly | World with missing file or missing env | Open `/world` and inspect status chips and runtime checks | No fake healthy state is shown | Covers Tasks 06-07 |
| WMS-25 | P0 | LiveView | UI | `/home` renders unavailable and degraded dashboard states without mock-only sections | No world or partial bootstrap/tools state | Open `/` and inspect cards/alerts | `world_identity` stays present; unsupported cards remain omitted | Covers Task 12 |
| WMS-26 | P1 | LiveView | UI | `/tools` renders unknown, unavailable, deferred, and partial states and filters locally | Runtime/policy fetchers configured | Open `/tools`, filter, and inspect cards | Page and tool-level statuses stay honest and filter narrows visible cards locally | Covers Task 10 |
| WMS-27 | P1 | LiveView | UI | `/settings` remains read-only and reflects world/bootstrap state honestly | World exists or does not exist | Open `/settings` | World/bootstrap/help sections render; editable form is absent | Covers Task 08 |
| WMS-28 | P1 | LiveView | Navigation | Shell navigation keeps stable roots and route-level coverage for `/home`, `/world`, `/tools`, and `/settings` | Clean DB | Visit each route with LiveView | Stable page root IDs and sidebar nav IDs remain present | Covers cross-page shell integrity |
| WMS-29 | P2 | Manual | UX | Read-only pages stay usable on narrow viewports without reintroducing fake controls | Mobile viewport | Inspect `/`, `/world`, `/tools`, and `/settings` manually | Layout remains readable and interaction targets stay available | Optional final pass |

## Acceptance Criteria

- All frozen statuses are covered across domain, snapshot, and LiveView layers:
  `ok`, `degraded`, `unavailable`, `invalid`, and `unknown`.
- Bootstrap ingestion is covered for success, missing file, parse error, shape error, and
  persistence failure.
- Cache behavior is covered for read-through, stale-read prevention after invalidation, and
  world updates through import/upsert flows.
- Read-only pages cover the major operator interactions:
  `/world` tab switching and import,
  `/tools` local filtering,
  `/home` trustworthy overview rendering,
  `/settings` honest read-only rendering.
- LiveView tests prefer stable selectors and outcome assertions over brittle free-text assertions.

## Selector / ID Gaps To Close In Task 14

- `settings` needs explicit stable IDs for:
  - world status block
  - bootstrap status block
  - bootstrap path value
  - sync status value
  - instance/world summary values
- `/world` bootstrap tab needs explicit stable IDs for:
  - provider rows
  - profile rows
  - declared config summary fields
- `/home` would benefit from IDs on the aggregate summary stat cells if strict count/status
  assertions are desired.

## Regression Checklist

- Migration keeps uniqueness on `slug` and `bootstrap_path`.
- `World` defaults remain `unknown` and JSONB config fields remain `%{}`.
- `upsert_world/1` remains idempotent and does not create duplicates.
- Cache invalidation still happens after import and direct world updates.
- Loader keeps normalized missing-file and parse-error issue payloads.
- Shape validation keeps unknown keys as warnings and contract violations as errors.
- Importer keeps immediate import feedback separate from persisted last-sync metadata.
- `/world` still exposes honest status chips and tabbed sections.
- `/home` still omits fake network, active lemmings, department queues, and recent activity.
- `/tools` still supports local filtering and explicit policy mismatch visibility.
- `/settings` remains read-only and keeps only real world/bootstrap/runtime info.
- Sidebar navigation IDs for the main shell pages remain stable.

## Out Of Scope

- Full CRUD for `City`, `Department`, or `Lemming`
- Editable bootstrap YAML or tool policy authoring
- Auth, admin, or multi-world switching UX
- Tool installation workflows beyond the current read-only snapshot
- Replacing mock city data on `/world` before the Cities slice exists
