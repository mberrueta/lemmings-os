# Task 12: Test Implementation

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: Task 11
- **Blocks**: Task 13

## Assigned Agent

`qa-elixir-test-author` - QA-driven Elixir test writer.

## Agent Invocation

Use `qa-elixir-test-author` to implement the approved City coverage for this branch.

## Objective

Add the ExUnit and LiveView tests needed to lock down City persistence, startup integration, resolver behavior, heartbeat/liveness, and real UI behavior.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] `llms/tasks/0002_implement_city_management/11_test_scenarios_and_coverage_plan.md`
- [ ] Tasks 01 through 10 outputs
- [ ] `llms/constitution.md`

## Expected Outputs

- [ ] schema/context tests
- [ ] resolver tests
- [ ] startup and heartbeat tests
- [ ] LiveView tests for city-related pages
- [ ] any supporting factory updates needed for City coverage

## Acceptance Criteria

- [ ] tests are deterministic and DB-sandbox safe
- [ ] tests use factories instead of fixture-style helpers
- [ ] OTP/process tests use `start_supervised/1`
- [ ] LiveView tests are selector-driven
- [ ] stale/live/unknown behavior is covered
- [ ] world scoping is covered

## Technical Notes

### Relevant Code Locations

- `test/lemmings_os/`
- `test/lemmings_os_web/live/`
- `test/support/factory.ex`
- `test/support/data_case.ex`
- `test/support/conn_case.ex`

### Constraints

- No debug prints committed
- No raw HTML assertions when selectors can be used
- Keep timing-sensitive tests stable

## Execution Instructions

### For the Agent

1. Implement the scenario matrix from Task 11.
2. Prefer focused test files and clear `describe` blocks.
3. Add the smallest testability hooks needed if the code requires them.
4. Record any areas that remain difficult to cover and why.

### For the Human Reviewer

1. Review coverage breadth and readability.
2. Confirm test helpers follow the repo conventions.
3. Confirm the branch now has real logic coverage for the highest-risk City paths.
4. Approve before Task 13 begins.

## Execution Summary

### Test Files Modified

| File | Tests Before | Tests After | New Scenarios |
|---|---|---|---|
| `test/lemmings_os/city_test.exs` | 8 | 17 | +9: port validation, slug uniqueness, cross-world slug, boundary liveness, translate_status struct, liveness/2 wrapper |
| `test/lemmings_os/cities_test.exs` | 10 | 24 | +14: sort order, string world_id, empty list, node_name/ids/stale_before filters, not_found cases, create validation, duplicate slug, update validation, heartbeat truncation, stale nil exclusion |
| `test/lemmings_os/runtime_city_heartbeat_test.exs` | 3 | 5 | +2: cached current_city reuse, admin status preservation |
| `test/lemmings_os_web/page_data/cities_page_snapshot_test.exs` | 2 | 10 | +8: no world error, empty snapshot, liveness_tone mapping, default selection, explicit selection, world_id resolution, status_label, navigation path |
| `test/lemmings_os_web/live/cities_live_test.exs` | 2 | 10 | +8: city selection, new form open/cancel, create success/validation error, edit, update, delete |

### Summary

- **Total city-related tests**: 66 (up from 25)
- **Full suite**: 178 tests (162 tests + 16 doctests), 0 failures
- **No production code modified**
- **No new factories or test helpers needed** (existing `:city` and `:world` factories sufficient)
- **All tests deterministic**: liveness tests use explicit DateTime injection, heartbeat tests use `now_fun:` and `:manual` interval, no `Process.sleep/1`
- **All OTP tests use `start_supervised/1`**
- **All LiveView tests use selector-driven assertions** (`has_element?/2`, `form/3`, `element/2`)

### Areas Not Covered (By Design)

- `LemmingsOs.Cities.Runtime` -- already has dedicated tests in `test/lemmings_os/runtime_city_test.exs`
- `LemmingsOs.Config.Resolver` -- already has dedicated tests in `test/lemmings_os/config/resolver_test.exs`
- Multi-city demo Docker Compose behavior -- out of scope for ExUnit
- LiveView validate_city real-time feedback -- low-risk, form validation is standard Phoenix
