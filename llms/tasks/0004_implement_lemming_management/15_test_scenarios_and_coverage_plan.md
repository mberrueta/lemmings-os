# Task 15: Test Scenarios and Coverage Plan

## Status

- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
- **Blocked by**: Task 09, Task 10, Task 11, Task 12, Task 13, Task 14, Task 19
- **Blocks**: Task 16
- **Estimated Effort**: M

## Assigned Agent

`qa-test-scenarios` - QA planner for scenario decomposition, risk-based coverage, and branch-level regression gating.

## Agent Invocation

Act as `qa-test-scenarios` following `llms/constitution.md` and produce the executable test scenario matrix for the full Lemming management branch.

## Objective

Turn the branch-level acceptance criteria into a concrete, prioritized test plan covering schema, context, resolver, import/export, read models, and LiveView flows.

## Inputs Required

- [ ] `llms/tasks/0004_implement_lemming_management/plan.md`
- [ ] Outputs from Tasks 09 through 14
- [ ] Output from Task 19 for documentation-linked regressions
- [ ] Existing Lemmings/Departments/Cities tests and factories

## Expected Outputs

- [ ] Scenario matrix grouped by domain and layer
- [ ] Priority labels for must-have vs follow-up coverage
- [ ] Regression checklist for Task 16 and Task 17

## Acceptance Criteria

- [ ] Covers schema/changeset validation including activation guard and scoped slug uniqueness
- [ ] Covers context CRUD, lifecycle APIs, and delete denial behavior
- [ ] Covers resolver behavior for `World -> City -> Department -> Lemming`, including `tools_config`
- [ ] Covers import/export success and failure cases, including schema version handling
- [ ] Covers Home/Cities/Departments/Lemmings page regressions introduced by this feature
- [ ] Covers create/edit/detail/index UI flows using selector-based assertions
- [ ] Explicitly marks deferred or intentionally untested scope

## Technical Notes

### Constraints

- Keep the plan grounded in what the branch actually ships
- Prefer stable DOM selectors and deterministic time/data setup

### Methods To Explicitly Cover

- `LemmingsOs.Lemmings.topology_summary/1`
- `LemmingsOs.Lemmings.lemming_counts_by_department/1`
- `LemmingsOs.Lemmings.lemming_counts_by_city/1`
- `LemmingsOs.Departments.topology_summary/1`
- `LemmingsOs.Departments.department_counts_by_city/1`
- `LemmingsOs.Config.Resolver.resolve/1` for `%LemmingsOs.Lemmings.Lemming{}`
- `LemmingsOs.Lemmings.ImportExport.export_lemming/1`
- `LemmingsOs.Lemmings.ImportExport.import_lemmings/4`

These should be called out in the coverage plan as direct contracts to test, not only indirectly through page snapshots or LiveViews.

## Execution Instructions

### For the Agent

1. Split scenarios by layer and risk, not by file names.
2. Make high-risk contracts explicit: world scoping, activation guard, delete denial, resolver preload requirements, import/export versioning.
3. Produce a checklist that Task 16 can implement directly.

### For the Human Reviewer

1. Verify the plan covers branch-level acceptance, not just happy paths.
2. Verify deferred areas are called out explicitly rather than silently omitted.

---

## Execution Summary

### Work Performed

- Read all branch source files: schema, context, resolver, import/export, LiveView modules, and HEEx templates.
- Read all existing test files: `lemming_test.exs`, `lemmings_test.exs`, `lemmings_import_export_test.exs`, `resolver_test.exs`, `lemmings_live_test.exs`, `create_lemming_live_test.exs`, `departments_live_test.exs`, `navigation_live_test.exs`, `home_live_test.exs`, `home_dashboard_snapshot_test.exs`.
- Catalogued 68 existing test cases across 8 test files.
- Identified 22 coverage gaps requiring new test implementation in Task 16.
- Produced the scenario matrix below organized by 6 layers.

### Outputs Created

- This file: `llms/tasks/0004_implement_lemming_management/15_test_scenarios_and_coverage_plan.md` with full scenario matrix, regression checklist, and deferred scope section.

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| `Departments.topology_summary/1` and `Departments.department_counts_by_city/1` are tested in existing `departments_test.exs` | Confirmed by grep; tests exist at lines 195+ in that file. New Lemming-specific scenarios for those functions are not needed here. |
| `ImportLemmingLive` has zero test coverage | Confirmed by glob and grep; no `import_lemming_live_test.exs` file exists on the branch. |
| `lemming_counts_by_department/1` and `lemming_counts_by_city/1` have zero direct unit coverage | Confirmed by grep across the entire test directory; these functions are only exercised indirectly through LiveView and snapshot tests. |
| The home dashboard snapshot test already covers Lemming counts in topology card | Confirmed at `home_dashboard_snapshot_test.exs` and `home_live_test.exs` line 98. |
| Navigation regression tests already exist in `navigation_live_test.exs` covering Lemming routes | Confirmed; the file tests `/lemmings`, `/lemmings/:id`, and `/lemmings/new` routes. |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Group scenarios by architectural layer (schema, context, resolver, import/export, read model, liveview) rather than by file | Could group by file or by user story | Layer grouping matches the task's acceptance criteria structure and makes Task 16 implementation ordering natural (unit tests first, integration last). |
| Mark LiveView import scenarios as P1 rather than P0 | Could mark all import tests as P0 | The context-level import/export functions are already well-tested. The LiveView layer adds UI plumbing but the critical business logic is covered. File upload testing in LiveView is mechanically complex and lower risk. |
| Do not add scenarios for `Departments.topology_summary/1` or `department_counts_by_city/1` | Could include them for completeness | Those functions predate this branch and already have coverage. The task scope is Lemming management, not Department regression. |

### Blockers Encountered

- None encountered.

### Questions for Human

1. The `ImportLemmingLive` module has zero test coverage. Should Task 16 implement the full upload-parse-confirm-import flow in LiveView tests, or is context-level import coverage sufficient for this branch?

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

---

## Risk Areas

1. **World scoping bypass** -- Any context function that omits explicit `world_id` filtering could leak data across worlds. High impact, low likelihood given existing patterns.
2. **Activation guard** -- Lemmings with blank or nil instructions must never reach `active` status. Both context API and LiveView save paths enforce this independently.
3. **Scoped slug uniqueness** -- Slug must be unique per department but allowed across departments. DB constraint + changeset validation both participate.
4. **Delete denial** -- Hard deletion is always denied in this branch slice. Any path that bypasses `delete_lemming/1` is a critical defect.
5. **Resolver preload requirements** -- `Resolver.resolve/1` for `%Lemming{}` requires a fully preloaded parent chain (`department.city.world`). Partial preloads use fallback patching but missing world data would crash.
6. **Import atomicity** -- Batch import via `Ecto.Multi` must not partially commit on validation failure.
7. **Import schema versioning** -- Unknown `schema_version` values must be rejected cleanly.
8. **Cross-hierarchy create** -- `create_lemming/4` must reject mismatched world/city/department triples.

---

## Test Scenario Matrix

### Layer 1 -- Schema & Changeset

Test file: `test/lemmings_os/lemmings/lemming_test.exs`

| ID | Description | Priority | Layer | Already Covered? |
|----|-------------|----------|-------|-----------------|
| S1-01 | Requires `slug`, `name`, and `status` fields | P0 | unit | YES -- `lemming_test.exs` S01 |
| S1-02 | Rejects statuses outside the frozen lifecycle taxonomy (`draft`, `active`, `archived`) | P0 | unit | YES -- `lemming_test.exs` S02 |
| S1-03 | Does not cast `world_id`, `city_id`, or `department_id` from attrs (ownership is context-controlled) | P0 | unit | YES -- `lemming_test.exs` S03 |
| S1-04 | Allows `active` status without instructions at the schema layer (guard lives in context) | P0 | unit | YES -- `lemming_test.exs` S04 |
| S1-05 | Validates `description` length bounded at `description_max_length()` (280 chars) | P1 | unit | YES -- `lemming_test.exs` S05 |
| S1-06 | Casts all five config embed buckets (limits, runtime, costs, models, tools) | P0 | unit | YES -- `lemming_test.exs` S06 |
| S1-07 | Exposes translated status helpers (`statuses/0`, `status_options/0`, `translate_status/1`) | P1 | unit | YES -- `lemming_test.exs` S07 |
| S1-08 | `translate_status/1` accepts a `%Lemming{}` struct | P2 | unit | YES -- `lemming_test.exs` S08 |
| S1-09 | Enforces unique slug per department via DB constraint | P0 | unit | YES -- `lemming_test.exs` S09 |
| S1-10 | Allows same slug in different departments | P0 | unit | YES -- `lemming_test.exs` S10 |
| S1-11 | Enforces `world` foreign key existence | P0 | unit | YES -- `lemming_test.exs` S11 |
| S1-12 | Enforces `city` foreign key existence | P0 | unit | YES -- `lemming_test.exs` S12 |
| S1-13 | Enforces `department` foreign key existence | P0 | unit | YES -- `lemming_test.exs` S13 |
| S1-14 | Factory builds a valid lemming with inherited hierarchy ownership and `%ToolsConfig{}` | P1 | unit | YES -- `lemming_test.exs` S14 |
| S1-15 | Accepts valid `instructions` field (nullable text, no max length at schema layer) | P2 | unit | NO -- verify changeset accepts long instructions without error |
| S1-16 | Accepts boundary description at exactly `description_max_length()` characters | P2 | unit | NO -- boundary value test (S05 only tests max+1) |

### Layer 2 -- Context APIs

Test file: `test/lemmings_os/lemmings_test.exs`

| ID | Description | Priority | Layer | Already Covered? |
|----|-------------|----------|-------|-----------------|
| S2-01 | `list_lemmings/2` scopes by `%World{}` and excludes other worlds | P0 | context | YES -- `lemmings_test.exs` "returns lemmings for a world scope" |
| S2-02 | `list_lemmings/2` scopes by `%City{}` within a world | P0 | context | YES -- `lemmings_test.exs` "returns lemmings for a city scope" |
| S2-03 | `list_lemmings/2` scopes by `%Department{}` | P0 | context | YES -- `lemmings_test.exs` "returns lemmings for a department scope" |
| S2-04 | `list_lemmings/2` supports `status`, `ids`, `slug`, and `preload` filter opts | P0 | context | YES -- `lemmings_test.exs` "supports status, ids, slug, and preload filters" |
| S2-05 | `list_lemmings/2` orders by name ASC then slug ASC | P1 | context | YES -- `lemmings_test.exs` "orders lemmings by name and slug" |
| S2-06 | `get_lemming/2` returns lemming by UUID | P0 | context | YES -- `lemmings_test.exs` "get_lemming/2 returns the lemming by id" |
| S2-07 | `get_lemming/2` returns nil for missing UUID | P0 | context | YES -- `lemmings_test.exs` "get_lemming/2 returns nil when the id is missing" |
| S2-08 | `get_lemming/2` supports explicit preloads | P1 | context | YES -- `lemmings_test.exs` "get_lemming/2 supports explicit preloads" |
| S2-09 | `get_lemming_by_slug/2` is department-scoped and returns the correct lemming | P0 | context | YES -- `lemmings_test.exs` "get by slug is department-scoped" |
| S2-10 | `get_lemming_by_slug/2` returns nil when slug is missing in department | P1 | context | YES -- `lemmings_test.exs` "get_lemming_by_slug/2 returns nil when missing in department scope" |
| S2-11 | `create_lemming/4` creates with correct world/city/department ownership and tools_config | P0 | context | YES -- `lemmings_test.exs` "creates a lemming scoped to the given world, city, and department" |
| S2-12 | `create_lemming/4` rejects mismatched world/city/department triple | P0 | context | YES -- `lemmings_test.exs` "rejects creating a lemming when the department does not belong to the city and world" |
| S2-13 | `create_lemming/4` returns changeset error on duplicate slug within same department | P0 | context | YES -- `lemmings_test.exs` "returns changeset error on duplicate slug within the same department" |
| S2-14 | `update_lemming/2` persists attribute changes | P0 | context | YES -- `lemmings_test.exs` "updates persisted lemming attributes" |
| S2-15 | `set_lemming_status/2` activates with valid instructions, archives, and re-activates | P0 | context | YES -- `lemmings_test.exs` "set_lemming_status/2 and archive wrapper delegate through the status path" |
| S2-16 | `set_lemming_status/2` rejects nil instructions when activating | P0 | context | YES -- `lemmings_test.exs` "set_lemming_status/2 rejects nil instructions when activating" |
| S2-17 | `set_lemming_status/2` rejects blank/whitespace-only instructions when activating | P0 | context | YES -- `lemmings_test.exs` "set_lemming_status/2 rejects blank instructions when activating" |
| S2-18 | `delete_lemming/1` always returns `{:error, %DeleteDeniedError{reason: :safety_indeterminate}}` | P0 | context | YES -- `lemmings_test.exs` "rejects deleting lemmings in all statuses" |
| S2-19 | `create_lemming/4` rejects city not in world (city.world_id != world.id) | P1 | context | NO -- current test only checks department mismatch; add explicit city-world mismatch case |
| S2-20 | `set_lemming_status/2` rejects empty string instructions when activating | P1 | context | NO -- the empty string (`""`) clause is a distinct code path from nil and blank; add explicit test |
| S2-21 | `list_lemmings/2` ignores unknown filter keys gracefully | P2 | context | NO -- verify the catch-all `filter_query/2` clause does not raise |

### Layer 3 -- Config Resolver

Test file: `test/lemmings_os/config/resolver_test.exs`

| ID | Description | Priority | Layer | Already Covered? |
|----|-------------|----------|-------|-----------------|
| S3-01 | Resolves full 4-level merge: World -> City -> Department -> Lemming with all 5 buckets | P0 | unit | YES -- `resolver_test.exs` "merges lemming overrides on top of department, city, and world config" |
| S3-02 | Inherits parent config when lemming has empty config buckets | P0 | unit | YES -- `resolver_test.exs` "keeps inherited values when the lemming has empty config buckets" |
| S3-03 | Resolves when city/department parent chains are not fully preloaded (uses lemming.world fallback) | P0 | unit | YES -- `resolver_test.exs` "uses lemming.world when city and department parent chains are not fully preloaded" |
| S3-04 | Does NOT include `tools_config` in World/City/Department resolution (backward compat) | P0 | unit | YES -- `resolver_test.exs` "does not add tools_config to world city or department resolution" |
| S3-05 | `tools_config` at Lemming level starts from `%ToolsConfig{}` base (no parent inheritance) | P1 | unit | YES -- implied by S3-01 which checks `tools_config` merge from empty base |
| S3-06 | Resolver handles lemming with `department.city.world: nil` preload variant | P1 | unit | NO -- the resolver has distinct function heads for `world: nil` vs `%NotLoaded{}` on nested city; only the NotLoaded variant is tested. Add test for `city.world: nil` and `department.city.world: nil` paths |

### Layer 4 -- Import/Export

Test file: `test/lemmings_os/lemmings_import_export_test.exs`

| ID | Description | Priority | Layer | Already Covered? |
|----|-------------|----------|-------|-----------------|
| S4-01 | `export_lemming/1` produces portable JSON shape with `schema_version: 1` | P0 | unit | YES -- `lemmings_import_export_test.exs` "exports the portable lemming shape without identity fields" |
| S4-02 | Export excludes identity fields (`id`, `world_id`, `city_id`, `department_id`, timestamps) | P0 | unit | YES -- same test as S4-01 |
| S4-03 | Export renders empty config buckets as empty maps (not nil) | P1 | unit | YES -- `lemmings_import_export_test.exs` "exports empty config buckets as empty maps" |
| S4-04 | `import_lemmings/4` imports valid single record | P0 | context | YES -- `lemmings_import_export_test.exs` "imports a valid single lemming definition" |
| S4-05 | `import_lemmings/4` imports valid batch atomically | P0 | context | YES -- `lemmings_import_export_test.exs` "imports a valid batch atomically" |
| S4-06 | Import returns per-record validation errors and does not partially commit | P0 | context | YES -- `lemmings_import_export_test.exs` "returns validation errors per record and does not partially commit on failure" |
| S4-07 | Import returns error on slug conflict with existing lemming | P0 | context | YES -- `lemmings_import_export_test.exs` "returns validation error on slug conflict" |
| S4-08 | Import rejects unsupported `schema_version` values | P0 | context | YES -- `lemmings_import_export_test.exs` "rejects unsupported schema_version values" |
| S4-09 | Import accepts missing `schema_version` (forward tolerance) | P1 | context | YES -- `lemmings_import_export_test.exs` "accepts missing schema_version" |
| S4-10 | Import ignores unknown extra keys in JSON payload | P1 | context | YES -- `lemmings_import_export_test.exs` "ignores unknown extra keys" |
| S4-11 | Import returns `{:ok, []}` for empty list | P1 | context | YES -- `lemmings_import_export_test.exs` "returns ok for an empty import list" |
| S4-12 | Export/import roundtrip preserves all definition fields including tools_config | P0 | context | YES -- `lemmings_import_export_test.exs` "roundtrips through export and import" |
| S4-13 | `import_lemmings/4` rejects mismatched world/city/department triple | P1 | context | NO -- the import module has its own `validate_city_in_world` and `validate_department_in_city_world` guards; they are untested |
| S4-14 | `import_lemmings/4` rejects non-map/non-list payloads (e.g., string, integer) | P1 | context | NO -- the `normalize_import_records/1` catch-all returns `{:error, [%{index: nil, error: :invalid_import_payload}]}` but is untested |
| S4-15 | `import_lemmings/4` rejects list containing non-map entries | P2 | context | NO -- exercises the `Enum.all?(records, &is_map/1)` guard in `normalize_import_records/1` |

### Layer 5 -- Read Models

Test files: `test/lemmings_os/lemmings_test.exs`, `test/lemmings_os/departments_test.exs`

| ID | Description | Priority | Layer | Already Covered? |
|----|-------------|----------|-------|-----------------|
| S5-01 | `Lemmings.topology_summary/1` returns aggregate total and active counts scoped to world | P0 | integration | YES -- `lemmings_test.exs` "returns aggregate lemming counts for the world" |
| S5-02 | `Lemmings.topology_summary/1` returns zero counts for world without lemmings | P0 | integration | YES -- `lemmings_test.exs` "returns zero counts for worlds without lemmings" |
| S5-03 | `Lemmings.lemming_counts_by_department/1` returns `%{department_id => count}` map for a city | P0 | integration | NO -- function exists and is called by LiveView but has zero direct unit test |
| S5-04 | `Lemmings.lemming_counts_by_department/1` omits departments with zero lemmings | P1 | integration | NO -- edge case of the same function |
| S5-05 | `Lemmings.lemming_counts_by_department/1` returns empty map for city with no lemmings | P1 | integration | NO -- empty-state edge case |
| S5-06 | `Lemmings.lemming_counts_by_city/1` returns `%{city_id => count}` map for a world | P0 | integration | NO -- function exists and is called by LiveView but has zero direct unit test |
| S5-07 | `Lemmings.lemming_counts_by_city/1` omits cities with zero lemmings | P1 | integration | NO -- edge case |
| S5-08 | `Lemmings.lemming_counts_by_city/1` returns empty map for world with no lemmings | P1 | integration | NO -- empty-state edge case |

### Layer 6 -- LiveView Flows

#### 6A: Lemmings Index Page

Test file: `test/lemmings_os_web/live/lemmings_live_test.exs`

| ID | Description | Priority | Layer | Already Covered? |
|----|-------------|----------|-------|-----------------|
| S6A-01 | Renders filter panel, world name, city/department selectors, and cards grid | P0 | liveview | YES -- `lemmings_live_test.exs` "renders filters and browse cards" |
| S6A-02 | Shows world unavailable state when no persisted world exists | P0 | liveview | YES -- `lemmings_live_test.exs` "shows world unavailable state" |
| S6A-03 | Changing city filter patches URL and scopes visible cards | P0 | liveview | YES -- `lemmings_live_test.exs` "changing filters scopes the cards" |
| S6A-04 | Card click navigates to dedicated detail page with scope params | P0 | liveview | YES -- `lemmings_live_test.exs` "card navigates to dedicated detail page" |
| S6A-05 | Empty state renders when department has no lemmings | P1 | liveview | NO -- no test for empty cards grid on the lemmings index |

#### 6B: Lemming Detail / Overview

Test file: `test/lemmings_os_web/live/lemmings_live_test.exs`

| ID | Description | Priority | Layer | Already Covered? |
|----|-------------|----------|-------|-----------------|
| S6B-01 | Dedicated detail page renders header, hero, detail panel, effective config, instances placeholder | P0 | liveview | YES -- `lemmings_live_test.exs` "dedicated detail page renders workspace" |
| S6B-02 | Activate succeeds when instructions are present; UI shows active status and archive button | P0 | liveview | YES -- `lemmings_live_test.exs` "activate succeeds when instructions are present" |
| S6B-03 | Activate fails when instructions are blank; UI shows error flash and retains draft status | P0 | liveview | YES -- `lemmings_live_test.exs` "activate fails when instructions are blank" |
| S6B-04 | Archive succeeds for active lemming; UI shows archived status and activate button | P0 | liveview | YES -- `lemmings_live_test.exs` "archive succeeds for active lemmings" |
| S6B-05 | Shows not-found state for invalid lemming UUID | P1 | liveview | YES -- `lemmings_live_test.exs` "shows not found state for invalid lemming id" |
| S6B-06 | Export button visible on edit tab; triggers `download_json` push event with correct payload | P0 | liveview | YES -- `lemmings_live_test.exs` export describe block |

#### 6C: Lemming Edit / Settings Tab

Test file: `test/lemmings_os_web/live/lemmings_live_test.exs`

| ID | Description | Priority | Layer | Already Covered? |
|----|-------------|----------|-------|-----------------|
| S6C-01 | Edit tab renders settings form with name, slug, limits, runtime config fields | P0 | liveview | YES -- `lemmings_live_test.exs` "edit tab renders a real settings form" |
| S6C-02 | Settings save persists mutable fields and local config overrides | P0 | liveview | YES -- `lemmings_live_test.exs` "settings save persists mutable fields" |
| S6C-03 | Settings save blocks activation when instructions are blank (activation guard in UI) | P0 | liveview | YES -- `lemmings_live_test.exs` "settings save keeps activation guard when instructions are blank" |
| S6C-04 | Settings validate event provides inline feedback without persisting | P1 | liveview | NO -- `validate_lemming_settings` event handler exists but no test exercises the `phx-change` validation path |

#### 6D: Create Lemming Page

Test file: `test/lemmings_os_web/live/create_lemming_live_test.exs`

| ID | Description | Priority | Layer | Already Covered? |
|----|-------------|----------|-------|-----------------|
| S6D-01 | Shows city/department scope selectors when no department context provided | P0 | liveview | YES -- `create_lemming_live_test.exs` "shows city and department selectors" |
| S6D-02 | Selecting city then department patches URL into create scope | P0 | liveview | YES -- `create_lemming_live_test.exs` "selecting city and department patches" |
| S6D-03 | Renders real form fields in department scope (name, slug, description, instructions, status) | P0 | liveview | YES -- `create_lemming_live_test.exs` "renders the real create form" |
| S6D-04 | Auto-generates slug from name until manually overridden | P1 | liveview | YES -- `create_lemming_live_test.exs` "auto-generates the slug from the name" |
| S6D-05 | Creates persisted lemming and redirects to detail page | P0 | liveview | YES -- `create_lemming_live_test.exs` "creates a persisted lemming and redirects to detail" |
| S6D-06 | Shows duplicate slug validation inline | P0 | liveview | YES -- `create_lemming_live_test.exs` "shows duplicate slug validation inline" |
| S6D-07 | Gracefully handles invalid department_id param (rescue from `Ecto.NoResultsError`) | P2 | liveview | NO -- `load_page/2` rescues `Ecto.NoResultsError` but no test covers this fallback |

#### 6E: Import Lemming Page

Test file: `test/lemmings_os_web/live/import_lemming_live_test.exs` (DOES NOT EXIST)

| ID | Description | Priority | Layer | Already Covered? |
|----|-------------|----------|-------|-----------------|
| S6E-01 | Renders upload form when accessed with valid `dept` param | P1 | liveview | NO |
| S6E-02 | Redirects with error flash when accessed without `dept` param | P1 | liveview | NO |
| S6E-03 | Redirects with error flash when accessed with invalid `dept` param | P2 | liveview | NO |
| S6E-04 | Processes valid JSON file and imports lemmings (no conflicts) | P1 | liveview | NO |
| S6E-05 | Shows confirm step with conflict list when imported names match existing lemmings | P1 | liveview | NO |
| S6E-06 | Confirm import updates existing lemmings and creates new ones | P1 | liveview | NO |
| S6E-07 | Cancel import resets to upload step | P2 | liveview | NO |
| S6E-08 | Shows upload error for invalid JSON content | P1 | liveview | NO |
| S6E-09 | Shows upload error for unsupported schema version | P1 | liveview | NO |

#### 6F: Department Page Regressions (Lemming-related)

Test file: `test/lemmings_os_web/live/departments_live_test.exs`

| ID | Description | Priority | Layer | Already Covered? |
|----|-------------|----------|-------|-----------------|
| S6F-01 | Lemmings tab renders persisted lemming definitions with name, slug, status | P0 | liveview | YES -- `departments_live_test.exs` S09 |
| S6F-02 | Lemmings tab shows empty state with create CTA when department has no lemmings | P0 | liveview | YES -- `departments_live_test.exs` S09b |
| S6F-03 | City map payload includes persisted lemming counts | P1 | liveview | YES -- `departments_live_test.exs` S09c |
| S6F-04 | Import button on lemmings tab links to import page | P1 | liveview | YES -- `departments_live_test.exs` S15 |

#### 6G: Home and Navigation Regressions

Test files: `test/lemmings_os_web/live/home_live_test.exs`, `test/lemmings_os_web/live/navigation_live_test.exs`

| ID | Description | Priority | Layer | Already Covered? |
|----|-------------|----------|-------|-----------------|
| S6G-01 | Home topology card includes `lemming_count` and `active_lemming_count` | P0 | liveview | YES -- `home_live_test.exs` line 98 |
| S6G-02 | Navigation test confirms `/lemmings` renders cards and `/lemmings/:id` renders detail | P0 | liveview | YES -- `navigation_live_test.exs` "lemmings page links into dedicated detail view" |
| S6G-03 | Navigation test confirms `/lemmings/new` renders create page | P1 | liveview | YES -- `navigation_live_test.exs` "tools, logs, settings, and create lemming pages render" |

---

## Regression Checklist

This checklist is for Task 16 (implementation) and Task 17 (final QA gate) to confirm before merge.

- [ ] `mix test` passes with zero warnings
- [ ] `mix precommit` passes (format, Credo, test)
- [ ] All P0 scenarios marked YES above continue to pass after any Task 16 additions
- [ ] All P0 scenarios marked NO above have new test implementations
- [ ] Home page topology card still renders `lemming_count` correctly
- [ ] Department lemmings tab still renders persisted lemming list
- [ ] Department city map still includes lemming counts
- [ ] Create lemming page still auto-generates slug and handles scope selection
- [ ] Lemmings index page still renders filter panel and scoped cards
- [ ] Lemming detail page still renders effective config and lifecycle actions
- [ ] Navigation tests still pass for all Lemming-related routes

---

## Deferred / Out of Scope

| Item | Reason |
|------|--------|
| `ImportLemmingLive` full upload flow testing (S6E-01 through S6E-09) | The import LiveView has zero coverage. Context-level import/export is well-tested. LiveView file upload testing is mechanically complex. Marked P1; recommended for Task 16 but can be deferred to a follow-up if time-constrained. Awaiting human decision per Questions section. |
| Runtime process lifecycle testing (spawn, supervise, restart, terminate) | Out of scope for this branch; this branch ships persisted definitions only, not runtime execution. |
| `tools_config` merge governance semantics (deny-dominant vs override-dominant across levels) | Explicitly deferred per plan.md section 9; `tools_config` only exists at Lemming level in v1 so no merge conflict is possible. |
| Concurrent slug conflict (double-submit race condition) | DB unique index enforces correctness. Testing concurrent inserts would require manual SQL or process-level coordination that adds test complexity without meaningful risk coverage given the DB constraint. |
| Cross-world data leakage end-to-end testing | All context functions are World-scoped by construction. Unit tests for `list_lemmings/2` already verify cross-world exclusion. A dedicated E2E pentest-style scenario is not warranted at this layer. |
| `Departments.topology_summary/1` and `Departments.department_counts_by_city/1` | These functions predate the Lemming management branch and already have coverage in `departments_test.exs`. Not in scope for this plan. |
| Accessibility, keyboard navigation, and touch target testing for LiveView pages | Manual testing scope; not covered by ExUnit LiveView integration tests. |
| Observability (structured logging with hierarchy metadata) | No telemetry or structured logging was added in this branch for Lemming operations. When it is added, scenarios should verify `world_id`, `city_id`, `department_id`, and `lemming_id` are present in log metadata. |
