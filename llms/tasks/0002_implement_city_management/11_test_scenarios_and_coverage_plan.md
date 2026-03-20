# Task 11: Test Scenarios and Coverage Plan

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: Task 07, Task 08, Task 09, Task 10
- **Blocks**: Task 12

## Assigned Agent

`qa-test-scenarios` - Test scenario designer.

## Agent Invocation

Use `qa-test-scenarios` to define the test matrix for City foundations, runtime presence, UI behavior, and demo-level risks.

## Objective

Enumerate the exact deterministic scenarios that require automated coverage before the City branch can be accepted.

## Inputs Required

- [x] `llms/tasks/0002_implement_city_management/plan.md`
- [x] Tasks 01 through 10 outputs
- [x] `llms/constitution.md`
- [x] `test/`

## Expected Outputs

- [x] scenario matrix for schema/context behavior
- [x] scenario matrix for resolver behavior
- [x] startup/first-city scenarios
- [x] heartbeat and stale-liveness scenarios
- [x] LiveView selector coverage plan
- [x] checklist for security/performance review focus areas

## Acceptance Criteria

- [x] the scenario set covers domain, runtime, UI, and demo behavior
- [x] scenarios are deterministic and aligned with DB sandbox testing
- [x] the plan explicitly covers stale/unknown/alive behavior
- [x] the plan calls out N+1, preload, and runtime exposure risks for review
- [x] the plan does not assume Department or Lemming desmoke

## Technical Notes

### Relevant Code Locations

- `test/lemmings_os/`
- `test/lemmings_os_web/live/`
- `test/support/`

### Constraints

- Use factories rather than fixture-style helpers
- Prefer selector-driven LiveView verification
- Keep timing-sensitive behavior testable without sleep-heavy flows

## Execution Instructions

### For the Agent

1. Read the final approved implementation tasks before drafting scenarios.
2. Split scenarios by layer: data, runtime, read models, LiveViews, demo behavior.
3. Call out what should be unit, integration, or LiveView coverage.
4. Include a focused checklist for the later security/performance review.

### For the Human Reviewer

1. Confirm the scenario set is complete enough for the branch risk profile.
2. Confirm timing-sensitive areas are testable deterministically.
3. Confirm the later review tasks have the right focus list.
4. Approve before Task 12 begins.

---

## Execution Summary

### Scope and Assumptions

**Scope**: All City-domain behavior introduced by tasks 01-10 of the `0002_implement_city_management` feature. This covers persistence, context APIs, config resolution, runtime identity, heartbeat/liveness, read models, LiveView CRUD flows, and cross-page integration (World, Settings).

**Assumptions**:

1. Department and Lemming persistence is NOT in scope. Mock children previews exist but are explicitly non-authoritative and not tested for correctness beyond presence.
2. All time-sensitive liveness scenarios use `now_fun` injection or explicit `:now` option -- no `Process.sleep` or wall-clock dependence.
3. All test data is created via `insert(:city, ...)` and `insert(:world, ...)` factories from `LemmingsOs.Factory`.
4. The heartbeat GenServer is started via `start_supervised/1` with `:manual` interval for deterministic control.
5. DB sandbox (`async: false` where needed) is used for all integration/LiveView tests that share world/city state.
6. Element selectors reference IDs from `cities_live.html.heex` (e.g., `#cities-page`, `#city-form`, `#city-detail-panel`, `#city-liveness-status`).
7. Docker compose demo behavior is validated manually or via the demo runbook, not via ExUnit.

---

### Risk Areas

| Risk | Likelihood | Impact | Notes |
|---|---|---|---|
| World-scoping bypass (IDOR) | Low | Critical | All context APIs require `%World{}` or `world_id`; test must verify cross-world isolation |
| Heartbeat flakiness from wall-clock | Medium | High | Must use `now_fun` injection; no sleep-based assertions |
| N+1 in city list with preloads | Medium | Medium | `list_cities` with `:preload` option; snapshot builds preload `:world` |
| Stale liveness threshold boundary off-by-one | Medium | Medium | `DateTime.compare` equality case maps to "alive"; must test exact boundary |
| Changeset leaking internal errors to UI | Low | Medium | LiveView re-renders changeset errors; no stack traces in flash |
| Duplicate slug/node_name uniqueness race | Low | Medium | DB constraint enforced; changeset maps constraint to friendly error |
| Config resolver with nil/empty child buckets | Medium | Medium | Nil child bucket must fall through to parent; empty struct must not zero out parent |
| `upsert_runtime_city` lookup chain correctness | Medium | High | Three-level fallback (id, node_name, slug) must be tested independently |

---

### Scenario Matrix

#### Domain 1: City Schema and Changeset (`LemmingsOs.Cities.City`)

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| SC-01 | P0 | Unit | Validation | Valid changeset with all required fields | None | Build changeset with slug, name, node_name (name@host format), status="active" | Changeset is valid | |
| SC-02 | P0 | Unit | Validation | Missing required field: slug | None | Build changeset without slug | Changeset invalid, error on `:slug` | |
| SC-03 | P0 | Unit | Validation | Missing required field: name | None | Build changeset without name | Changeset invalid, error on `:name` | |
| SC-04 | P0 | Unit | Validation | Missing required field: node_name | None | Build changeset without node_name | Changeset invalid, error on `:node_name` | |
| SC-05 | P0 | Unit | Validation | Missing required field: status | None | Build changeset without status | Changeset invalid, error on `:status` | |
| SC-06 | P0 | Unit | Validation | Invalid node_name format (no @) | None | Build changeset with node_name="nohostpart" | Changeset invalid, format error on `:node_name` | Regex: `^[^@\s]+@[^@\s]+$` |
| SC-07 | P1 | Unit | Validation | Invalid node_name format (spaces) | None | Build changeset with node_name="city @host" | Changeset invalid | |
| SC-08 | P0 | Unit | Validation | Invalid status value | None | Build changeset with status="running" | Changeset invalid, inclusion error on `:status` | Valid: active, disabled, draining |
| SC-09 | P1 | Unit | Validation | Valid status values accepted | None | Test each of "active", "disabled", "draining" | All produce valid changesets | |
| SC-10 | P1 | Unit | Validation | distribution_port must be > 0 | None | Build changeset with distribution_port=0 | Changeset invalid | |
| SC-11 | P1 | Unit | Validation | epmd_port must be > 0 | None | Build changeset with epmd_port=-1 | Changeset invalid | |
| SC-12 | P1 | Unit | Validation | Optional fields accept nil | None | Build changeset with host=nil, distribution_port=nil, epmd_port=nil, last_seen_at=nil | Changeset valid | |
| SC-13 | P0 | Unit | Validation | Config embeds default to struct | None | Insert city without explicit config | All four config fields default to their struct values | `defaults_to_struct: true` |
| SC-14 | P1 | Unit | Validation | Config embed cast accepts nested map | None | Build changeset with limits_config=%{max_cities: 10} | Changeset valid, embed populated | |

#### Domain 2: City Liveness Helper (`City.liveness/2` and `City.liveness/3`)

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| LV-01 | P0 | Unit | Liveness | City with nil last_seen_at returns "unknown" | City with last_seen_at=nil | Call `liveness(city, now, 90)` | Returns "unknown" | |
| LV-02 | P0 | Unit | Liveness | City seen within threshold returns "alive" | City with last_seen_at = now - 30s | Call `liveness(city, now, 90)` | Returns "alive" | 30 < 90 threshold |
| LV-03 | P0 | Unit | Liveness | City seen beyond threshold returns "stale" | City with last_seen_at = now - 120s | Call `liveness(city, now, 90)` | Returns "stale" | 120 > 90 threshold |
| LV-04 | P0 | Unit | Liveness | Exact boundary: last_seen_at == threshold cutoff | City with last_seen_at = now - 90s exactly | Call `liveness(city, now, 90)` | Returns "alive" | `DateTime.compare` `:eq` maps to alive |
| LV-05 | P1 | Unit | Liveness | One second past boundary returns "stale" | City with last_seen_at = now - 91s | Call `liveness(city, now, 90)` | Returns "stale" | |
| LV-06 | P1 | Unit | Liveness | `liveness/2` (no explicit now) calls utc_now internally | City with recent last_seen_at | Call `liveness(city, 90)` | Returns "alive" | Convenience wrapper |
| LV-07 | P1 | Unit | Validation | `statuses/0` returns canonical list | None | Call `City.statuses()` | Returns `["active", "disabled", "draining"]` | |
| LV-08 | P1 | Unit | Validation | `livenesses/0` returns canonical list | None | Call `City.livenesses()` | Returns `["alive", "stale", "unknown"]` | |
| LV-09 | P1 | Unit | Validation | `translate_status/1` returns translated strings for all statuses | None | Call for each status including nil | Returns non-empty translated strings | Uses dgettext |
| LV-10 | P1 | Unit | Validation | `status_options/0` returns pairs for form selects | None | Call `City.status_options()` | Returns list of `{value, label}` tuples for 3 statuses | |

#### Domain 3: Cities Context (`LemmingsOs.Cities`)

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| CX-01 | P0 | Integration | DB | `list_cities/2` returns cities scoped to world | Two worlds, each with cities | Call list_cities for world_a | Returns only world_a cities | World scoping is mandatory |
| CX-02 | P0 | Integration | DB | `list_cities/2` returns empty list for world with no cities | World with no cities | Call list_cities(world) | Returns `[]` | |
| CX-03 | P0 | Integration | DB | `list_cities/2` accepts world_id binary | World with cities | Call list_cities(world.id) | Returns same results as struct variant | |
| CX-04 | P1 | Integration | DB | `list_cities/2` filters by status | World with active and disabled cities | Call list_cities(world, status: "active") | Returns only active cities | filter_query/2 |
| CX-05 | P1 | Integration | DB | `list_cities/2` filters by node_name | World with multiple cities | Call list_cities(world, node_name: "alpha@localhost") | Returns matching city only | |
| CX-06 | P1 | Integration | DB | `list_cities/2` filters by ids | World with 3 cities | Call list_cities(world, ids: [city_a.id, city_c.id]) | Returns 2 matching cities | |
| CX-07 | P1 | Integration | DB | `list_cities/2` filters by stale_before cutoff | World with fresh and stale cities | Call list_cities(world, stale_before: cutoff) | Returns only stale cities | |
| CX-08 | P1 | Integration | DB | `list_cities/2` supports preload option | World with city | Call list_cities(world, preload: [:world]) | City has world preloaded | |
| CX-09 | P1 | Integration | DB | `list_cities/2` ignores unknown filter keys | World with city | Call list_cities(world, unknown_key: "value") | Returns all cities, no crash | filter_query catch-all clause |
| CX-10 | P0 | Integration | DB | `list_cities/2` default order is inserted_at asc, id asc | World with 3 cities inserted in known order | Call list_cities(world) | Cities returned in insertion order | |
| CX-11 | P0 | Integration | DB | `fetch_city/2` returns ok tuple for valid world-scoped id | World with city | Call fetch_city(world, city.id) | Returns `{:ok, city}` | |
| CX-12 | P0 | Integration | DB | `fetch_city/2` returns error for missing id | World with no matching city | Call fetch_city(world, random_uuid) | Returns `{:error, :not_found}` | |
| CX-13 | P0 | Integration | DB | `fetch_city/2` enforces world scoping | City in world_a | Call fetch_city(world_b, city.id) | Returns `{:error, :not_found}` | IDOR prevention |
| CX-14 | P0 | Integration | DB | `get_city!/2` raises for missing city | Empty world | Call get_city!(world, random_uuid) | Raises `Ecto.NoResultsError` | |
| CX-15 | P1 | Integration | DB | `get_city_by_slug/2` returns city for valid slug | World with city slug="ops" | Call get_city_by_slug(world, "ops") | Returns city struct | |
| CX-16 | P1 | Integration | DB | `get_city_by_slug/2` returns nil for unknown slug | World with no matching slug | Call get_city_by_slug(world, "nonexistent") | Returns nil | |
| CX-17 | P0 | Integration | DB | `create_city/2` persists with world_id from World struct | World | Call create_city(world, valid_attrs) | Returns `{:ok, city}` with city.world_id == world.id | world_id set by context, not form |
| CX-18 | P0 | Integration | DB | `create_city/2` returns changeset error for invalid attrs | World | Call create_city(world, %{}) | Returns `{:error, changeset}` | |
| CX-19 | P0 | Integration | DB | `create_city/2` enforces slug uniqueness per world | World with existing slug="ops" | Call create_city(world, %{slug: "ops", ...}) | Returns `{:error, changeset}` with unique constraint error | DB index: cities_world_id_slug_index |
| CX-20 | P0 | Integration | DB | `create_city/2` enforces node_name uniqueness per world | World with existing node_name | Call create_city with duplicate node_name | Returns `{:error, changeset}` | DB index: cities_world_id_node_name_index |
| CX-21 | P1 | Integration | DB | Slug uniqueness is world-scoped (same slug in different worlds is OK) | Two worlds | Create city with slug="ops" in each world | Both succeed | |
| CX-22 | P0 | Integration | DB | `update_city/2` persists changes | Existing city | Call update_city(city, %{name: "New Name"}) | Returns `{:ok, city}` with updated name | |
| CX-23 | P1 | Integration | DB | `update_city/2` returns changeset error for invalid change | Existing city | Call update_city(city, %{status: "bogus"}) | Returns `{:error, changeset}` | |
| CX-24 | P0 | Integration | DB | `delete_city/2` removes the city | Existing city | Call delete_city(city) | Returns `{:ok, city}`, city no longer in DB | |
| CX-25 | P0 | Integration | DB | `heartbeat_city/2` writes last_seen_at without changing status | City with status="disabled" | Call heartbeat_city(city, seen_at) | last_seen_at updated, status still "disabled" | |
| CX-26 | P1 | Integration | DB | `heartbeat_city/2` truncates to second precision | City | Call heartbeat_city(city, datetime_with_microseconds) | Stored value is truncated to seconds | |
| CX-27 | P1 | Integration | DB | `stale_cities/2` returns cities with last_seen_at before cutoff | World with fresh and stale cities | Call stale_cities(world, cutoff) | Returns only stale cities | |
| CX-28 | P1 | Integration | DB | `stale_cities/2` excludes cities with nil last_seen_at | World with never-seen city | Call stale_cities(world, cutoff) | Does not include nil-last_seen_at city | |

#### Domain 4: Upsert Runtime City (`LemmingsOs.Cities.upsert_runtime_city/2`)

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| UP-01 | P0 | Integration | DB | Creates new city when no match found | World with no cities | Call upsert_runtime_city(world, valid_attrs) | Returns `{:ok, city}`, city persisted | |
| UP-02 | P0 | Integration | DB | Updates existing city matched by id | World with existing city | Call upsert_runtime_city(world, %{id: city.id, ...changes...}) | Returns `{:ok, updated_city}` | Lookup priority: id first |
| UP-03 | P0 | Integration | DB | Updates existing city matched by node_name | World with existing city | Call upsert_runtime_city(world, %{node_name: city.node_name, ...}) without id | Returns `{:ok, updated_city}` | Lookup priority: node_name second |
| UP-04 | P1 | Integration | DB | Updates existing city matched by slug | World with existing city | Call upsert_runtime_city(world, %{slug: city.slug, ...}) without id or matching node_name | Returns `{:ok, updated_city}` | Lookup priority: slug third |
| UP-05 | P1 | Integration | DB | Handles string-keyed attrs (not just atom keys) | World | Call upsert_runtime_city(world, %{"node_name" => "x@y", ...}) | attr_value helper resolves both | |

#### Domain 5: Config Resolver (`LemmingsOs.Config.Resolver`)

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| CR-01 | P0 | Unit | Config | `resolve(%World{})` returns world config as-is | World with populated config buckets | Call resolve(world) | Returns map with 4 config struct keys matching world values | |
| CR-02 | P0 | Unit | Config | `resolve(%World{})` fills nil buckets with default structs | World with nil limits_config | Call resolve(world) | limits_config is `%LimitsConfig{}` (defaults) | |
| CR-03 | P0 | Unit | Config | `resolve(%City{world: %World{}})` merges child over parent | City with runtime_config override, world preloaded | Call resolve(city) | Child override wins for set fields; parent values preserved for unset fields | |
| CR-04 | P0 | Unit | Config | City with nil config bucket inherits parent entirely | City with nil limits_config, world with populated limits_config | Call resolve(city) | limits_config equals world's limits_config | merge_bucket/3 nil clause |
| CR-05 | P1 | Unit | Config | City override with all-nil fields inherits parent (pruning) | City with limits_config where all fields are nil | Call resolve(city) | limits_config equals world's limits_config | prune_nil_values removes empty |
| CR-06 | P1 | Unit | Config | Deep merge for nested config (CostsConfig.budgets) | World with budgets.monthly_usd=100, City with budgets.daily_tokens=500 | Call resolve(city) | Effective budgets has both monthly_usd=100 and daily_tokens=500 | Nested struct merge |
| CR-07 | P1 | Unit | Config | City scalar override replaces parent scalar | World with runtime_config.idle_ttl_seconds=3600, City with idle_ttl_seconds=120 | Call resolve(city) | idle_ttl_seconds=120 | |
| CR-08 | P1 | Unit | Config | Resolve requires world preloaded on city | City with world=NotLoaded | Call resolve(city) | Pattern match fails / FunctionClauseError | No DB access inside resolver |
| CR-09 | P2 | Unit | Config | Both world and city configs nil for a bucket | Both nil | Call resolve(city) | Returns default struct for that bucket | |

#### Domain 6: Cities.Runtime (Startup Identity)

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| RT-01 | P0 | Integration | Runtime | `runtime_city_attrs/0` resolves node_name from config | Application env set with `runtime_city: %{node_name: "primary@localhost"}` | Call runtime_city_attrs() | Returns map with node_name="primary@localhost", derived slug and name | |
| RT-02 | P1 | Unit | Runtime | Slug derived from node_name: lowercased, special chars replaced | Config with node_name="MyCity_1@host.local" | Call runtime_city_attrs() | slug="mycity-1" | derive_slug/1 |
| RT-03 | P1 | Unit | Runtime | Name derived from slug: capitalized words | Slug = "my-city" | Call runtime_city_attrs() | name="My City" | derive_name/1 |
| RT-04 | P1 | Unit | Runtime | Host derived from node_name after @ | Config with node_name="city@192.168.1.1" | Call runtime_city_attrs() | host="192.168.1.1" | derive_host/1 |
| RT-05 | P0 | Integration | Runtime | `sync_runtime_city/0` creates city for default world | World persisted, runtime_city config set | Call sync_runtime_city() | Returns `{:ok, city}` with matching node_name | |
| RT-06 | P0 | Integration | Runtime | `sync_runtime_city/0` returns error when no default world | No world persisted | Call sync_runtime_city() | Returns `{:error, :default_world_not_found}` | |
| RT-07 | P0 | Integration | Runtime | `sync_runtime_city!/0` raises when no default world | No world persisted | Call sync_runtime_city!() | Raises with descriptive message | |
| RT-08 | P1 | Integration | Runtime | `sync_runtime_city/0` upserts (idempotent on second call) | World persisted, runtime city already synced | Call sync_runtime_city() twice | Second call updates existing row, does not create duplicate | |
| RT-09 | P0 | Integration | Runtime | `fetch_runtime_city/0` finds existing runtime city | Runtime city synced | Call fetch_runtime_city() | Returns `{:ok, city}` | |
| RT-10 | P1 | Integration | Runtime | `fetch_runtime_city/0` returns not_found when no city row | World persisted but no city | Call fetch_runtime_city() | Returns `{:error, :runtime_city_not_found}` | |
| RT-11 | P1 | Integration | Runtime | `fetch_runtime_city/0` returns error when no world | No world | Call fetch_runtime_city() | Returns `{:error, :default_world_not_found}` | |

#### Domain 7: Heartbeat Worker (`LemmingsOs.Cities.Heartbeat`)

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| HB-01 | P0 | Integration | Runtime | Heartbeat updates last_seen_at via now_fun | City persisted, heartbeat started with `interval_ms: :manual`, `now_fun` returning fixed time, `current_city` set | Call `Heartbeat.heartbeat(pid)` | Returns `:ok`, city.last_seen_at matches now_fun value | Existing test validates this |
| HB-02 | P0 | Integration | Runtime | Heartbeat does NOT mutate status | City with status="disabled" | Call heartbeat | status remains "disabled" after heartbeat | |
| HB-03 | P0 | Integration | Runtime | Heartbeat creates runtime city when no local row exists | World persisted, runtime_city config set, no current_city | Start heartbeat without current_city, call heartbeat | Returns `:ok`, city row created | Existing test validates this |
| HB-04 | P0 | Integration | Runtime | Heartbeat returns error when no default world | No world, runtime config set | Start heartbeat, call heartbeat | Returns `{:error, :default_world_not_found}` | Existing test validates this |
| HB-05 | P1 | Integration | Runtime | Heartbeat logs error on failure with structured metadata | No world | Call heartbeat, capture log | Log contains "runtime city heartbeat failed" and event metadata | |
| HB-06 | P1 | Integration | Runtime | Heartbeat logs success with world_id, city_id, node_name | City persisted | Call heartbeat, capture log at debug | Log contains event="runtime_city.heartbeat" and IDs | |
| HB-07 | P1 | Integration | Runtime | Manual interval prevents auto-scheduling | Start with interval_ms: :manual | Wait briefly | No `:heartbeat` message received automatically | schedule_next/1 returns state unchanged |
| HB-08 | P1 | Integration | Runtime | Heartbeat caches current_city in state after first lookup | No current_city initially, city synced | Call heartbeat twice | Second call does not re-fetch from runtime module | |
| HB-09 | P2 | Integration | Runtime | Heartbeat clears current_city on world-not-found error | current_city was cached, world deleted | Call heartbeat | Returns error, state.current_city set to nil | |

#### Domain 8: CitiesPageSnapshot (Read Model)

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| PS-01 | P0 | Integration | ReadModel | Builds snapshot with real city cards and derived liveness | World with fresh and stale cities | Call build(world: world, now: now, freshness_threshold_seconds: 90) | Snapshot has correct city_count, alive/stale liveness per city | Existing test validates this |
| PS-02 | P0 | Integration | ReadModel | selected_city defaults to first city when no city_id | World with cities | Call build(world: world) without city_id | selected_city.id == first city by insertion order | |
| PS-03 | P0 | Integration | ReadModel | selected_city matches requested city_id | World with two cities | Call build(world: world, city_id: second_city.id) | selected_city.id == second_city.id | |
| PS-04 | P0 | Integration | ReadModel | Falls back to first city when city_id is invalid | World with cities | Call build(world: world, city_id: "nonexistent-uuid") | selected_city.id == first city | Existing test validates this |
| PS-05 | P0 | Integration | ReadModel | `liveness_tone` mapping: alive=success, stale=warning, unknown=default | Various city states | Check liveness_tone on city cards | Correct tone values | |
| PS-06 | P0 | Integration | ReadModel | `liveness_label` uses gettext translation | Various city states | Check liveness_label on city cards | Non-empty translated strings | |
| PS-07 | P1 | Integration | ReadModel | Empty world returns empty snapshot | World with no cities | Call build(world: world) | empty?=true, cities=[], selected_city=nil | |
| PS-08 | P0 | Integration | ReadModel | selected_city includes effective_config from Resolver | City with world preloaded, city has runtime_config override | Build snapshot | selected_city.effective_config reflects merged config | |
| PS-09 | P1 | Integration | ReadModel | selected_city includes mock_children from CitiesMockChildrenSnapshot | City selected | Build snapshot | selected_city.mock_children.source == "mock" | |
| PS-10 | P1 | Integration | ReadModel | Returns `{:error, :not_found}` when no world can be resolved | No world persisted, no world_id given | Call build() | Returns `{:error, :not_found}` | |
| PS-11 | P1 | Integration | ReadModel | Accepts explicit world_id option | World persisted | Call build(world_id: world.id) | Builds snapshot for that world | |
| PS-12 | P1 | Integration | ReadModel | city_card.path contains correct link | City persisted | Build snapshot | city.path == "/cities?city={city.id}" | |
| PS-13 | P2 | Integration | ReadModel | freshness_threshold_seconds defaults from app config | App config set | Call build without explicit threshold | Uses config value | |

#### Domain 9: CitiesLive -- Read Flows (LiveView)

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| LR-01 | P0 | E2E | UI | Cities page renders list and detail panels | World with 2 cities | `live(conn, ~p"/cities")` | `#cities-page`, `#cities-list-panel`, `#city-detail-panel` present | Existing test covers partial |
| LR-02 | P0 | E2E | UI | City card links rendered per city | World with 2 cities (city_a, city_b) | `live(conn, ~p"/cities")` | `#city-card-link-{city_a.id}` and `#city-card-link-{city_b.id}` present | |
| LR-03 | P0 | E2E | UI | City selection via query param | World with 2 cities | `live(conn, ~p"/cities?city={city_b.id}")` | `#city-detail-panel` shows city_b data, `#city-admin-status[data-status='...']` matches city_b.status | |
| LR-04 | P0 | E2E | UI | Liveness badge rendered with correct data-status | Fresh city (alive) and stale city | `live(conn, ~p"/cities?city={stale_city.id}")` | `#city-liveness-status[data-status='stale']` present | |
| LR-05 | P0 | E2E | UI | Empty state rendered when no world exists | No world persisted | `live(conn, ~p"/cities")` | `#cities-page-empty-state` present | Existing test validates this |
| LR-06 | P1 | E2E | UI | Empty state rendered when world has no cities | World with no cities | `live(conn, ~p"/cities")` | `#cities-list-empty-state` present | |
| LR-07 | P1 | E2E | UI | City detail shows metadata fields | City with all fields populated | Select city | `#city-slug-field`, `#city-node-name-field`, `#city-host-field`, `#city-distribution-port-field`, `#city-epmd-port-field`, `#city-last-seen-at-field` present | |
| LR-08 | P1 | E2E | UI | Effective config panel rendered for selected city | City selected | `live(conn, ~p"/cities?city={city.id}")` | `#city-effective-config-panel` present | |
| LR-09 | P1 | E2E | UI | Mock children panels rendered for selected city | City selected | `live(conn, ~p"/cities?city={city.id}")` | `#city-departments-panel` and `#city-active-lemmings-panel` present | Mock-backed, not authoritative |
| LR-10 | P1 | E2E | UI | Breadcrumb includes city name when selected | City selected | Check shell_breadcrumb | Breadcrumb contains city link with city name | |
| LR-11 | P1 | E2E | UI | Stream-based city list uses phx-update="stream" | World with cities | Inspect DOM | `#cities-list[phx-update='stream']` present | |

#### Domain 10: CitiesLive -- CRUD Flows (LiveView)

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| CF-01 | P0 | E2E | UI | New city form opens on "new_city" event | World with cities, cities page loaded | Click `#cities-new-button` | `#city-form-overlay` and `#city-form` appear, form_mode=:new | |
| CF-02 | P0 | E2E | UI | Create city succeeds with valid input | Form open in :new mode | Fill name, slug, node_name, status, submit `#city-form` | Flash info message, form closes, city appears in list | |
| CF-03 | P0 | E2E | UI | Create city fails with validation error (missing fields) | Form open in :new mode | Submit form with empty fields | Form re-renders with changeset errors, no flash | |
| CF-04 | P0 | E2E | UI | Create city fails with duplicate slug | Existing city with slug="ops" | Submit form with slug="ops" | Form re-renders with unique constraint error | |
| CF-05 | P0 | E2E | UI | Validate event shows live validation feedback | Form open | Change field values via phx-change="validate_city" | Form updates with validation state | |
| CF-06 | P0 | E2E | UI | Edit city form opens with existing data | City exists | Click `#city-edit-button` | `#city-form` appears pre-filled with city data, form_mode=:edit | |
| CF-07 | P0 | E2E | UI | Update city succeeds with valid changes | Edit form open | Change name, submit | Flash info message, form closes, detail shows updated name | |
| CF-08 | P1 | E2E | UI | Update city fails with invalid changes | Edit form open | Change status to invalid value, submit | Form re-renders with error | |
| CF-09 | P0 | E2E | UI | Delete city with confirm | City exists | Click `#city-delete-button` (has data-confirm) | Flash info message, city removed from list, redirects to /cities | |
| CF-10 | P1 | E2E | UI | Cancel form closes form overlay | Form open | Click `#city-form-cancel-button` | Form overlay disappears, form/form_mode/form_city_id reset to nil | |
| CF-11 | P1 | E2E | UI | Edit city for non-existent city shows error flash | Snapshot loaded | Send edit_city event with bogus id | Flash error ".flash_city_not_found" | |
| CF-12 | P1 | E2E | UI | Delete city for non-existent city shows error flash | Snapshot loaded | Send delete_city event with bogus id | Flash error ".flash_city_not_found" | |
| CF-13 | P2 | E2E | UI | Create city when no world exists shows error | No world | Attempt save_city in :new mode | Flash error ".flash_city_save_error" | |

#### Domain 11: World/Settings City Integration

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| WI-01 | P0 | E2E | UI | WorldLive shows real city summary list | World with cities | `live(conn, ~p"/world")` | Cities rendered with real names, liveness | load_world_cities/1 |
| WI-02 | P0 | E2E | UI | WorldLive navigate_city routes to cities page | World with city | Send "navigate_city" event with city_id | Navigates to `/cities?city={city_id}` | push_navigate |
| WI-03 | P1 | E2E | UI | WorldLive shows empty cities when no cities exist | World with no cities | Load world page | Cities list is empty | |
| WI-04 | P1 | Integration | ReadModel | SettingsPageSnapshot city section shows runtime city | World and runtime city persisted, node_name matches local node | Call SettingsPageSnapshot.build() | city.available?=true, city data populated | |
| WI-05 | P1 | Integration | ReadModel | SettingsPageSnapshot city section shows unavailable when no match | World persisted, no matching city row | Call SettingsPageSnapshot.build() | city.available?=false, all city fields nil | |
| WI-06 | P1 | Integration | ReadModel | SettingsPageSnapshot city section shows unavailable when no world | No world | Call SettingsPageSnapshot.build() | city.available?=false | |

#### Domain 12: Stale Behavior (Deterministic Liveness)

| ID | Priority | Layer | Area | Scenario | Preconditions | Steps | Expected Result | Notes |
|---|---|---|---|---|---|---|---|---|
| SB-01 | P0 | Integration | Liveness | City transitions alive to stale when heartbeat stops | City with last_seen_at=now | Advance now by >90s (threshold), rebuild snapshot | City card shows liveness="stale", tone="warning" | Deterministic via :now option |
| SB-02 | P0 | Integration | Liveness | City shows "unknown" when never heartbeated | City with last_seen_at=nil | Build snapshot | City card shows liveness="unknown", tone="default" | |
| SB-03 | P0 | Integration | Liveness | Fresh heartbeat restores "alive" after stale period | Stale city, then heartbeat_city with recent time | Rebuild snapshot with new now | City shows liveness="alive" | |
| SB-04 | P1 | Integration | Liveness | Multiple cities show mixed liveness states simultaneously | 3 cities: one alive, one stale, one unknown | Build snapshot | Each city has correct independent liveness | |

---

### Acceptance Criteria (Given/When/Then)

#### City Schema

- **Given** a city changeset with all required fields in valid format, **when** the changeset is validated, **then** it is valid.
- **Given** a city changeset missing any required field (slug, name, node_name, status), **when** the changeset is validated, **then** it contains an error on the missing field.
- **Given** a city changeset with node_name lacking "@" separator, **when** the changeset is validated, **then** it contains a format error on `:node_name`.
- **Given** a city changeset with status not in ["active", "disabled", "draining"], **when** the changeset is validated, **then** it contains an inclusion error on `:status`.
- **Given** a city changeset with distribution_port=0 or negative, **when** the changeset is validated, **then** it contains a number validation error.

#### City Liveness

- **Given** a city with `last_seen_at=nil`, **when** `City.liveness(city, now, 90)` is called, **then** it returns `"unknown"`.
- **Given** a city with `last_seen_at` exactly equal to `now - threshold`, **when** `City.liveness(city, now, threshold)` is called, **then** it returns `"alive"` (boundary is inclusive).
- **Given** a city with `last_seen_at` one second older than the threshold, **when** `City.liveness(city, now, threshold)` is called, **then** it returns `"stale"`.

#### Cities Context

- **Given** two worlds each with cities, **when** `list_cities(world_a)` is called, **then** only world_a's cities are returned.
- **Given** a city in world_a, **when** `fetch_city(world_b, city.id)` is called, **then** `{:error, :not_found}` is returned.
- **Given** an existing city with slug "ops" in a world, **when** `create_city(world, %{slug: "ops", ...})` is called, **then** `{:error, changeset}` is returned with a uniqueness error.
- **Given** a city with status "disabled", **when** `heartbeat_city(city, seen_at)` is called, **then** `last_seen_at` is updated and `status` remains "disabled".

#### Config Resolver

- **Given** a world with `limits_config.max_cities=4` and a city with `limits_config=nil`, **when** `Resolver.resolve(city)` is called, **then** the effective `limits_config.max_cities=4`.
- **Given** a world with `runtime_config.idle_ttl_seconds=3600` and a city with `runtime_config.idle_ttl_seconds=120`, **when** `Resolver.resolve(city)` is called, **then** the effective `idle_ttl_seconds=120`.
- **Given** a city without its world preloaded (`world: #Ecto.Association.NotLoaded`), **when** `Resolver.resolve(city)` is called, **then** a `FunctionClauseError` is raised (no implicit DB access).

#### Heartbeat Worker

- **Given** a heartbeat worker started with `interval_ms: :manual` and `current_city: city`, **when** `Heartbeat.heartbeat(pid)` is called, **then** `last_seen_at` is set to the `now_fun` return value.
- **Given** a heartbeat worker with no default world, **when** `Heartbeat.heartbeat(pid)` is called, **then** `{:error, :default_world_not_found}` is returned and an error is logged.

#### CitiesLive (UI)

- **Given** a world with two cities, **when** the operator visits `/cities`, **then** both city cards are rendered in `#cities-list` and the first city is selected by default.
- **Given** a world with a stale city (last_seen_at 300s ago, threshold 90s), **when** the operator visits `/cities?city={stale_city.id}`, **then** `#city-liveness-status[data-status='stale']` is present.
- **Given** the operator clicks "New City", **when** the form overlay appears, **then** `#city-form` is rendered with empty fields and a "Create" submit button.
- **Given** the operator fills valid city data and submits, **when** the form is processed, **then** a success flash appears, the form closes, and the new city appears in the list.
- **Given** the operator clicks "Delete" on a city and confirms, **when** the delete is processed, **then** a success flash appears and the city is removed.
- **Given** no world exists, **when** the operator visits `/cities`, **then** `#cities-page-empty-state` is rendered.

#### World/Settings Integration

- **Given** a world with cities, **when** the operator sends "navigate_city" from the World page, **then** the browser navigates to `/cities?city={city_id}`.
- **Given** a runtime city matching the local node_name, **when** `SettingsPageSnapshot.build()` is called, **then** `city.available?` is `true` and city metadata is populated.

---

### Regression Checklist

These items must pass before the City branch is merged:

1. [ ] All existing `navigation_live_test.exs` tests pass (cities page may require world/city setup now)
2. [ ] `mix test` passes with zero warnings
3. [ ] `mix precommit` passes (format, credo, test)
4. [ ] Coverage report generated via `mix coveralls.html`
5. [ ] City schema changeset tests cover all required/optional field boundaries
6. [ ] City liveness tests cover alive/stale/unknown with deterministic time injection
7. [ ] Cities context tests verify world scoping on every public retrieval function
8. [ ] Config resolver tests verify child-overrides-parent with nil, empty, and populated buckets
9. [ ] Heartbeat tests use `start_supervised/1`, `interval_ms: :manual`, and `now_fun` injection
10. [ ] LiveView tests verify CRUD flows (create, edit, delete) with selector-based assertions
11. [ ] LiveView tests verify empty states (no world, no cities)
12. [ ] WorldLive integration test verifies `navigate_city` routes correctly
13. [ ] No `Process.sleep` calls in any city-related test
14. [ ] No mock data leaks into city-domain tests (all data from factories)
15. [ ] DB sandbox mode used for all tests; `async: false` where world/city cache interaction requires it
16. [ ] Gettext translations compile without warnings for new city keys

---

### Security and Performance Checklist (for Task 13 Review)

#### Security

- [ ] **World-scoping enforcement**: All `Cities` context public functions require explicit `%World{}` or `world_id`. No function allows cross-world retrieval without scoping.
- [ ] **IDOR via fetch_city**: Verify `fetch_city(world_b, city_in_world_a.id)` returns `:not_found`, not the city.
- [ ] **world_id not trusted from form params**: `create_city/2` sets `world_id` from the `%World{}` struct, not from user-submitted form data. The changeset does not cast `world_id`.
- [ ] **last_seen_at not exposed in operator forms**: The changeset `@optional` list includes `last_seen_at` but it must not be settable from the city form UI. Verify the form does not include a `last_seen_at` input.
- [ ] **Changeset error messages**: Verify that changeset errors rendered in the UI do not leak internal schema names, constraint names, or stack traces.
- [ ] **No atom creation from external input**: `attr_value/2` and `filter_query/2` do not call `String.to_atom/1` on user input. Status values are validated against a fixed list.
- [ ] **Config embeds**: Verify that user-submitted config override maps cannot inject unexpected keys into the embedded schema structs.

#### Performance

- [ ] **N+1 on city list**: `list_cities/2` does a single query. When preloads are needed (e.g., `:world` for resolver), they use Ecto preload, not per-city queries.
- [ ] **CitiesPageSnapshot preload**: `build/1` calls `list_cities(world, preload: [:world])` -- single query with preload, not N+1.
- [ ] **Heartbeat write frequency**: Heartbeat interval is 30s by default. Verify it does not write on every LiveView mount or page load.
- [ ] **stale_cities query**: Uses indexed columns (`world_id`, `last_seen_at`). Verify the query plan uses the `cities(world_id, last_seen_at)` index.
- [ ] **Stream-based rendering**: City list uses `stream(:cities, ...)` for efficient DOM updates, not full re-renders.
- [ ] **Snapshot build per handle_params**: `load_snapshot/2` is called on mount and handle_params. Verify it does not trigger redundant queries on initial load (mount + handle_params double-call pattern in LiveView).

#### Observability

- [ ] **Heartbeat logs include structured metadata**: `world_id`, `city_id`, `node_name` present in log metadata for both success and failure paths.
- [ ] **Runtime sync logs**: `Runtime.sync_runtime_city/0` logs with event="runtime_city.attach" and hierarchy IDs on success.
- [ ] **No sensitive data in logs**: Config payloads, model API keys, and agent data are not logged by heartbeat or sync operations.

---

### Out of Scope

The following are explicitly excluded from this test scenario plan:

1. **Department and Lemming persistence tests** -- mock children previews are acknowledged but not tested for data correctness.
2. **Docker compose integration tests** -- compose demo is validated manually via the demo runbook (Task 15), not via ExUnit.
3. **Distributed Erlang clustering tests** -- no multi-node test setup required.
4. **Secure remote city attachment** -- deferred to a future issue.
5. **Config explainability or source-trace** -- not implemented in this issue.
6. **Load/stress testing** -- out of scope for this branch.
7. **Browser-level E2E tests (Playwright/Wallaby)** -- LiveView tests use Phoenix.LiveViewTest, not browser automation.
8. **Migration rollback testing** -- migration correctness is assumed from schema match; rollback is a manual DBA concern.
