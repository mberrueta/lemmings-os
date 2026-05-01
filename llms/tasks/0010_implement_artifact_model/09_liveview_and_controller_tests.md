# Task 09: LiveView and Controller Tests

## Status
- **Status**: ⏳ COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`qa-elixir-test-author` - QA-driven Elixir test writer for ExUnit, LiveView, controller, and integration tests.

## Agent Invocation
Act as `qa-elixir-test-author`. Implement missing tests from the Artifact test plan and source acceptance criteria.

## Objective
Add deterministic outcome-based tests for UI promotion, safe rendering, update/new choices, controlled downloads, status rejection, wrong scope, and leakage regressions.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0010_implement_artifact_model/plan.md`
- [ ] `llms/tasks/0010_implement_artifact_model/test_plan.md`
- [ ] Tasks 01-08 outputs
- [ ] `test/support/factory.ex`
- [ ] Existing LiveView/controller tests

## Expected Outputs
- [ ] LiveView tests for promotion button, click promotion, promoted reference rendering, update/new choice, and notes display.
- [ ] Controller tests for authorized download, wrong scope, deleted/archived/error rejection, missing physical file, and no path leakage.
- [ ] Regression tests proving rendered HTML/events do not expose file contents, storage refs, storage roots, raw workspace paths, full metadata, or notes by default.
- [ ] If not already present, tests proving no automatic LLM context injection of artifact contents.

## Acceptance Criteria
- [ ] Tests use factories and deterministic temp dirs.
- [ ] Tests use stable selectors with `element/2`, `has_element?/2`, and controller response assertions.
- [ ] Tests avoid large raw HTML assertions except targeted leakage checks.
- [ ] No external network is used.
- [ ] Narrow test command passes.

## Technical Notes
### Relevant Code Locations
```
test/lemmings_os_web/live/instance_live_test.exs       # LiveView timeline tests
test/lemmings_os_web/controllers/                      # Controller tests
test/lemmings_os/artifacts_test.exs                    # Context tests if created
test/lemmings_os/artifacts/local_storage_test.exs      # Storage tests if created
```

### Constraints
- Do not broaden production behavior beyond what tests require for accepted source criteria.
- Do not add fixture-style helpers or `*_fixture` functions.
- Do not use sleeps for LiveView behavior unless an existing helper pattern requires it.

## Execution Instructions

### For the Agent
1. Read all inputs listed above.
2. Identify acceptance criteria not covered by Tasks 01-08 tests.
3. Add focused tests and only minimal production fixes if needed to satisfy intended behavior.
4. Run the narrow relevant test files.
5. Document assumptions, files changed, and test commands in Execution Summary.

### For the Human Reviewer
After agent completes:
1. Verify test failures would be actionable.
2. Confirm leakage assertions cover sentinel values.
3. Approve before Task 10 begins.

---

## Execution Summary
Implemented focused LiveView and controller coverage for missing Artifact scenarios and leakage regressions.

### Scenario Coverage Added
- `UI-03` update/new choice:
  - Added UI support and tests to render both explicit collision actions:
    - `Update Artifact`
    - `Promote as New Artifact`
  - Test: `S08m` now asserts both action buttons.
- `UI-03`/`PRO-06` promote-as-new flow:
  - Test: `S08n` submits `mode=promote_as_new` and asserts a second Artifact row is created for the same filename.
- `UI-05`/`SEC-*` safe rendering regression:
  - Test: `S08o` verifies Artifact reference summary excludes file content, `storage_ref`, workspace path sentinel, metadata sentinel, and note text in summary.
  - Notes remain available via `<details>` control and dedicated notes element.
- `DL-02` wrong-scope/wrong-instance guard:
  - Added controller test `DL02b` ensuring artifact ids from another instance are rejected (`404`).
- `DL-04`/`DL-05` leakage regression:
  - Extended missing-file download test to assert no storage path/ref leakage in response headers as well as body.

### Files Changed
- `lib/lemmings_os_web/components/instance_components.ex`
  - Added `artifact-promote-as-new-button-<tool_execution_id>` submit action (`mode=promote_as_new`) for collision state.
- `test/lemmings_os_web/live/instance_live_test.exs`
  - Extended `S08m`.
  - Added `S08n`, `S08o`.
- `test/lemmings_os_web/controllers/instance_artifact_controller_test.exs`
  - Added `DL02b`.
  - Strengthened `DL04` header leakage assertions.

### Assumptions
- “notes by default” interpreted as not included in the compact Artifact reference summary line; notes remain behind the existing `<details>` UI pattern.
- Existing `test/lemmings_os/lemming_calls_runtime_test.exs` already covers “no automatic artifact content injection unless explicitly referenced” (`S02d`), so no new runtime test was required in this task.
