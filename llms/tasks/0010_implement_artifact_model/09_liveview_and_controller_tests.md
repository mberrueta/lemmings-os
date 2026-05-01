# Task 09: LiveView and Controller Tests

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

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
*[Filled by executing agent after completion]*
