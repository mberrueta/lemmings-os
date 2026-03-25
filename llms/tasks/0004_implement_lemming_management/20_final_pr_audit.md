# Task 20: Final PR Audit

## Status

- **Status**: COMPLETE
- **Approved**: [x] Human sign-off
- **Blocked by**: Task 18, Task 19
- **Blocks**: None
- **Estimated Effort**: S

## Assigned Agent

`audit-pr-elixir` - final PR reviewer for release-readiness, residual risk, and merge recommendation.

## Agent Invocation

Act as `audit-pr-elixir` following `llms/constitution.md` and perform the final PR audit for the Lemming management branch.

## Objective

Provide the last independent review pass after validation, review, and ADR/doc work are complete, so the human can decide whether the branch is ready to merge.

## Inputs Required

- [ ] `llms/tasks/0004_implement_lemming_management/plan.md`
- [ ] Outputs from Tasks 01 through 19
- [ ] Final branch diff

## Expected Outputs

- [ ] Final findings or explicit no-findings statement
- [ ] Residual risk summary
- [ ] Final merge-readiness recommendation

## Acceptance Criteria

- [ ] Audit considers implementation, tests, docs, and validation outcomes together
- [ ] Findings are ordered by severity
- [ ] Residual risks and acceptable follow-ups are explicit
- [ ] Final recommendation states whether the branch is merge-ready

## Technical Notes

### Constraints

- Findings first, summary second

## Execution Instructions

### For the Agent

1. Review the final branch state, not intermediate task slices.
2. Re-check prior risks after validation and ADR/doc updates.
3. State clearly whether the branch is merge-ready.

### For the Human Reviewer

1. Decide whether to merge based on the final audit and all prior approvals.

---

## Execution Summary

### Work Performed

- Reviewed the full branch diff (90 files, ~12,500 lines added/changed) against `main`.
- Verified `mix test` passes: 37 doctests, 299 tests, 0 failures.
- Verified `mix format --check-formatted` passes with no drift.
- Verified `mix credo` passes with no issues.
- Read all prior task execution summaries (Tasks 17-19).
- Audited implementation (context, schema, migration, resolver, import/export), LiveView layers, tests, factory, router, page snapshots, and docs.
- Identified findings ordered by severity below.

### Findings

#### MAJOR

**M1. `inheriting_all_configuration?` always returns false due to empty-list handling in `prune_override`**

- **Where**: `/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os_web/live/lemmings_live.ex`, lines 332-375
- **Why it matters**: `prune_override/1` strips `nil` values and recursively prunes empty maps, but it does not strip empty lists. `ToolsConfig` defaults to `%ToolsConfig{allowed_tools: [], denied_tools: []}`. After `Map.from_struct/1`, that becomes `%{allowed_tools: [], denied_tools: []}`. Since `[]` is not `nil` and not a map, `prune_override` keeps both keys, so the tools bucket never prunes to `%{}`. This means `inheriting_all_configuration?/1` always returns `false` for every lemming, even when no local overrides exist. The UI will never show the "inheriting all configuration" state.
- **Suggested fix**: Add a clause to `prune_override` that strips empty-list values: `{_key, []}, acc -> acc`. Alternatively, handle `[]` alongside `nil` in the reduce clause. Add a test that asserts a freshly-inserted lemming with no config overrides returns `inheriting? == true`.

**M2. `world_components.ex` still calls `MockData.lemmings_for_department/1`**

- **Where**: `/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os_web/components/world_components.ex`, line 621
- **Why it matters**: The plan goal explicitly states "a real Department-scoped Lemming listing replacing the current mock-backed `department_lemming_preview`". The `department_room/1` component still calls `MockData.lemmings_for_department(assigns.department.id)` to render lemming sprites. This means the World page visualization of lemmings within departments remains mock-backed, not persisted-data-backed. This is a plan-completeness gap.
- **Suggested fix**: Replace with `Lemmings.list_lemmings(assigns.department)` (requires the department struct to be available, which it already is). If the sprite component expects mock-shaped data, adapt the mapping.

**M3. Duplicated hierarchy validation helpers across `Lemmings` and `ImportExport`**

- **Where**: `/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/lemmings.ex` lines 281-292; `/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/lemmings/import_export.ex` lines 160-171
- **Why it matters**: `validate_city_in_world/2` and `validate_department_in_city_world/3` are copy-pasted between the two modules. If one gets a bug fix (like the error atom being corrected), the other may be missed. This is a maintenance hazard.
- **Suggested fix**: Extract these into a shared private helper in the `Lemmings` context and delegate from `ImportExport`, or have `ImportExport.import_lemmings/4` delegate to `Lemmings.create_lemming/4` for all validation (which it already does inside `import_records/4`, making the pre-validation in `ImportExport` redundant-but-advisory). At minimum, label this as a follow-up.

#### MINOR

**m1. `get_lemming/2` is not World-scoped**

- **Where**: `/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/lemmings.ex` lines 72-79
- **Why it matters**: The constitution states "Context APIs for World-scoped resources MUST require an explicit `world_id` (or `%World{}` struct) as a parameter." `get_lemming/2` takes a UUID and optional opts but does not require a World scope. The existing `get_department!` follows the same pattern (ID-only), so this is a pre-existing convention in the codebase, but it is worth noting for consistency with the constitution's intent.
- **Suggested fix**: Accept as-is for this branch since it follows the established `get_department!` pattern. Consider a follow-up to add `world_id` scoping to both `get_lemming` and `get_department!` for defense-in-depth.

**m2. `Jason.encode!` in `export_lemming` event handler**

- **Where**: `/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os_web/live/lemmings_live.ex` line 106
- **Why it matters**: `Jason.encode!/2` will raise on encoding failure. The data comes from a persisted Ecto struct (already validated), so the risk is low, but if a config embed contains a value that Jason cannot serialize (e.g., a tuple or PID that leaked in), this would crash the LiveView process. The constitution flags `Jason.encode!/1` in hot paths with bad data risk.
- **Suggested fix**: Risk is low given the data source is a controlled export map. Acceptable as-is. If paranoid, wrap in `Jason.encode/2` and handle `:error`.

**m3. `CreateLemmingLive` and `ImportLemmingLive` use `get_department!/2` with rescue**

- **Where**: `/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os_web/live/create_lemming_live.ex` lines 76-108; `/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os_web/live/import_lemming_live.ex` lines 148-173
- **Why it matters**: Using `get_department!/2` with a `rescue Ecto.NoResultsError` is an anti-pattern per the constitution. The `fetch_department/2` function exists and returns `{:ok, dept} | {:error, :not_found}`, which would be cleaner.
- **Suggested fix**: Replace `get_department!/2 ... rescue Ecto.NoResultsError` with `case Departments.fetch_department(id, preload: ...) do {:ok, dept} -> ...; {:error, :not_found} -> ... end`. This is a style/safety improvement, not blocking.

**m4. `ToolsConfig.changeset/2` does not validate list element types**

- **Where**: `/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/config/tools_config.ex` lines 24-27
- **Why it matters**: `allowed_tools` and `denied_tools` are `{:array, :string}` fields cast from user input. Ecto will coerce types at the DB layer, but there is no application-level validation that elements are non-empty strings or follow a naming convention. An import payload with `"allowed_tools": [null, 123, ""]` would silently persist.
- **Suggested fix**: Add `validate_change/3` or a custom validator for list elements if tool names have a required format. Acceptable to defer.

#### NITS

**n1. Resolver has many pattern-matching clauses for Lemming association loading states**

- **Where**: `/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/config/resolver.ex` lines 117-171
- **Why it matters**: Five separate function heads handle various combinations of `%Ecto.Association.NotLoaded{}` and `nil` on the Lemming's nested associations. This is correct but verbose. A single entry clause that normalizes the chain before delegating to the terminal resolver clause would reduce surface area.
- **Suggested fix**: Extract a `normalize_lemming_chain/1` helper that ensures all parents are loaded, then have one resolver clause for the fully-loaded case. Low priority.

### Residual Risk Summary

| Risk | Severity | Mitigation |
|------|----------|------------|
| `inheriting_all_configuration?` always returns false (M1) | Medium | UI cosmetic -- shows "has overrides" badge when none exist. No data corruption. Fix is a one-line clause addition. |
| `department_room` still mock-backed (M2) | Medium | Affects World page visualization only. Core Lemming CRUD, listing, and import/export all use real data. Scoped follow-up. |
| Duplicated validation helpers (M3) | Low | Both copies are identical and tested. Risk is divergence over time. |
| `get_lemming` not World-scoped (m1) | Low | Matches existing `get_department!` pattern. No cross-world leakage risk in current UI flows. |
| `get_department!` with rescue (m3) | Low | Functional, just not idiomatic. No user-facing impact. |

### Merge-Readiness Recommendation

**MERGE-READY with caveats.**

The branch is in a clean, passing state: 37 doctests, 299 tests, 0 failures, clean formatting, clean Credo. The core implementation -- schema, migration, context APIs, config resolver extension, import/export, LiveView CRUD, lifecycle management, and test coverage -- is solid and well-structured.

The three MAJOR findings (M1, M2, M3) are all non-blocking for a merge:

- M1 is a UI cosmetic issue (badge state) with a one-line fix.
- M2 is a plan-completeness gap on a component not central to Lemming management itself.
- M3 is a maintenance concern, not a correctness issue.

All three can be addressed in an immediate follow-up commit before or after merge at the human's discretion. None introduce data corruption, security exposure, or runtime failure risk.

### Outputs Created

- Updated `llms/tasks/0004_implement_lemming_management/20_final_pr_audit.md` (this file)

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| The `department_room` component in `world_components.ex` is in scope for the plan's desmoke goals | The plan explicitly calls out replacing mock-backed lemming listings, and this component renders lemmings for a department on the World page. |
| The `get_department!` with rescue pattern is a pre-existing convention, not introduced by this branch | The Departments context already had this pattern before this branch. |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Classify M1 as MAJOR not BLOCKER | Could require fix before merge | The impact is cosmetic (badge display), not data integrity. A one-line fix can land immediately. |
| Classify M2 as MAJOR not BLOCKER | Could block merge until World page desmoke is complete | The component is on the World page, not the Lemmings page. Core Lemming management flows all use real data. |
| Recommend MERGE-READY | Could recommend NOT READY pending M1/M2 fixes | All quality gates pass, the core feature is complete and tested, and the remaining issues are low-risk follow-ups. |

### Blockers Encountered

- None.

### Questions for Human

1. Do you want M1 (prune_override empty-list fix) and M2 (department_room desmoke) addressed in this branch before merge, or tracked as immediate follow-up work?

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

- [ ] APPROVED - Proceed to merge / next branch step
- [ ] REJECTED - See feedback below

### Feedback

### Git Operations Performed

```bash
# human-only
```
