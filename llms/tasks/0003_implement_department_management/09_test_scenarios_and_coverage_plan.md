# Task 09: Test Scenarios and Coverage Plan

## Status

- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
- **Blocked by**: Task 05, Task 06, Task 07, Task 08
- **Blocks**: Task 10
- **Estimated Effort**: M

## Assigned Agent

qa-test-scenarios - test scenario designer for acceptance, regressions, edge cases, and coverage planning.

## Agent Invocation

Act as qa-test-scenarios following llms/constitution.md and define the Department feature test matrix and coverage plan.

## Objective

Convert the approved Department implementation scope into a concrete test plan that covers domain, resolver, snapshot, and LiveView behavior without wasting effort on out-of-scope runtime systems.

## Inputs Required

- [ ] llms/tasks/0003_implement_department_management/plan.md
- [ ] Task 03 output
- [ ] Task 04 output
- [ ] Task 05 output
- [ ] Task 06 output
- [ ] Task 07 output
- [ ] Task 08 output
- [ ] existing tests under test/lemmings_os/ and test/lemmings_os_web/live/
- [ ] llms/coding_styles/elixir_tests.md

## Expected Outputs

- [ ] scenario document or completed task summary defining coverage layers
- [ ] recommended test file map
- [ ] explicit coverage expectations for risky paths

## Acceptance Criteria

- [ ] scenario plan covers schema/changeset, context/lifecycle, resolver, snapshots, and LiveViews
- [ ] delete guard and notes/tag edge cases are covered
- [ ] ownership split between Task 07 and Task 08 is reflected in separate UI test areas
- [ ] plan notes where mock-backed Lemmings tab behavior should be tested honestly

## Technical Notes

### Relevant Code Locations

```
test/lemmings_os/
test/lemmings_os_web/live/
```

### Patterns to Follow

- Outcome-focused tests using explicit DOM IDs for LiveView
- Deterministic DB sandbox coverage

### Constraints

- Do not write implementation tests in this task

## Execution Instructions

### For the Agent

1. Review all implemented surfaces/tasks first.
2. Propose the minimum sufficient test matrix with strong regression value.
3. Highlight any risky gaps that must be covered before PR review.

### For the Human Reviewer

1. Confirm the scenario plan is complete enough to drive Task 10.
2. Reject if key domain or UI paths are left implicit.

---

## Execution Summary

*[Filled by executing agent after completion]*

### Work Performed

- Reviewed the implemented Department surfaces across schema, context, resolver, page snapshots, and LiveView detail/index flows.
- Audited existing test coverage under `test/lemmings_os/` and `test/lemmings_os_web/live/` to identify what is already protected versus what still belongs in Task 10.
- Defined a minimum-sufficient coverage matrix focused on high-regression-value behavior without drifting into out-of-scope runtime orchestration.
- Documented the UI ownership split between Task 07 and Task 08 so follow-up tests do not collapse index and detail concerns together.

### Outputs Created

- Coverage layer plan in this task summary
- Recommended Department test file map for Task 10
- Explicit risky-path expectations for delete guardrails, tag/notes edges, resolver inheritance, and honest mock-backed UI behavior

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| Task 10 will be the task that adds any remaining tests, not this planning task | Task 09 explicitly says to define scenarios and coverage, not to write implementation tests |
| Current accepted Department behavior is the source of truth even if task metadata still shows blocked | Tasks 07 and 08 are already materially implemented in the repository |
| UI tests should rely on explicit IDs and stable data attributes rather than styling classes | Matches the project’s LiveView testing rules and recent Tailwind refactors |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Split UI planning into Task 07 index/navigation coverage and Task 08 detail/tab/settings coverage | One broad Department UI test bucket | Preserves ownership boundaries and makes regressions easier to localize |
| Treat delete guard behavior as a required high-risk path in both context and LiveView layers | Context-only coverage | Operators invoke delete from the UI, so honest denial behavior must be asserted end-to-end |
| Keep the Lemmings tab coverage focused on honest mock-backed messaging and rendered placeholders/previews | Inventing runtime orchestration scenarios | Runtime-backed lemming control is explicitly out of scope for this feature slice |

### Blockers Encountered

- None for planning. The only caveat is that task metadata still says blocked even though the dependent implementation surfaces already exist in the codebase.

### Questions for Human

1. Do you want Task 10 to stop at the minimum sufficient matrix below, or should it also add defensive regression tests for secondary polish states like empty notes/tag rendering and invalid tab params?

### Ready for Next Task

- [x] All outputs complete
- [x] Summary documented
- [x] Questions listed (if any)

### Coverage Layers

| Layer | Scope | Existing Coverage | Task 10 Expectation |
|-------|-------|-------------------|---------------------|
| Schema / changeset | required fields, tag normalization, notes bounds, scoped uniqueness, config bucket casting | `test/lemmings_os/departments/department_test.exs` already covers core normalization/casting/status translation | Add only missing edge assertions for notes/tag boundaries if gaps remain after review |
| Context / lifecycle | world-city scoping, slug lookup, create/update, lifecycle wrappers, delete guard | `test/lemmings_os/departments_test.exs` already covers list/fetch/create/update/lifecycle/delete denial | Ensure both delete guard reasons and operator-facing update paths remain covered |
| Resolver | `World -> City -> Department` inheritance and override precedence | `test/lemmings_os/config/resolver_test.exs` already covers department merges/inheritance | Keep current resolver coverage; add tests only if new config buckets or nil-edge behavior changed |
| Snapshot read models | cities/home truthful department summaries and links | `test/lemmings_os_web/page_data/cities_page_snapshot_test.exs`, `test/lemmings_os_web/page_data/home_dashboard_snapshot_test.exs` already cover current snapshot behavior | Add Department-specific snapshot assertions only if a new page-data surface is introduced |
| LiveView index/navigation | city selection, scoped list/map, detail entry routing | `test/lemmings_os_web/live/departments_live_test.exs` and `test/lemmings_os_web/live/navigation_live_test.exs` cover baseline flow | Keep Task 07 tests focused on index state and route transitions only |
| LiveView detail/tabs/settings | overview metadata, lifecycle buttons, mock-backed lemmings tab, settings effective/local split, V1 save behavior | `test/lemmings_os_web/live/departments_live_test.exs` now covers these primary paths | Task 10 should add only any remaining edge coverage, not duplicate happy paths unnecessarily |

### Recommended Test File Map

| File | Ownership | Coverage Focus |
|------|-----------|----------------|
| `test/lemmings_os/departments/department_test.exs` | schema | tag normalization, notes/tag edge cases, cast/validation contracts |
| `test/lemmings_os/departments_test.exs` | context | lifecycle wrappers, scoped fetches, delete guardrails, CRUD success/failure paths |
| `test/lemmings_os/config/resolver_test.exs` | resolver | effective Department config inheritance and override precedence |
| `test/lemmings_os_web/page_data/cities_page_snapshot_test.exs` | read model | truthful city-scoped department summaries and links into Department UI |
| `test/lemmings_os_web/page_data/home_dashboard_snapshot_test.exs` | read model | truthful topology totals for department counts |
| `test/lemmings_os_web/live/departments_live_test.exs` | UI detail/index | Task 07 and Task 08 acceptance behaviors using explicit DOM IDs |
| `test/lemmings_os_web/live/navigation_live_test.exs` | app navigation | high-level route smoke coverage into Department surfaces |

### Risky Paths That Must Be Covered Before PR Review

1. Delete guardrails must be asserted in both the context and LiveView layers.
   Context should prove `:not_disabled` and `:safety_indeterminate` denial behavior; LiveView should prove the operator remains on the detail page with an honest error.
2. Notes and tags edge cases must be covered at the schema layer.
   This includes blank tags, normalization, deduplication, and safe handling of absent notes.
3. Task 07 and Task 08 UI ownership must stay split.
   Index tests should cover city scoping and navigation; detail tests should cover tabs, lifecycle actions, mock-backed lemmings messaging, and settings.
4. Mock-backed Lemmings behavior should be tested honestly.
   Tests should assert the explicit mock banner/copy and rendered preview list, not imply runtime-backed orchestration.
5. Settings coverage should distinguish effective versus local override values.
   Tests should prove inherited values render separately from local overrides and that the V1 editable subset persists correctly.

---

## Human Review

*[Filled by human reviewer]*

### Review Date

[YYYY-MM-DD]

### Decision

- [ ] ✅ APPROVED - Proceed to next task
- [ ] ❌ REJECTED - See feedback below

### Feedback

### Git Operations Performed

```bash
# human-only
```
