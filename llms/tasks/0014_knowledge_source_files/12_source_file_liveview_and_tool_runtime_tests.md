# Task 12: Source File LiveView And Tool Runtime Tests

## Status
- **Status**: ✅ COMPLETED
- **Approved**: [x] Human sign-off

## Assigned Agent
`qa-elixir-test-author` - QA-driven ExUnit author for LiveView and runtime-tool coverage.

## Agent Invocation
Act as `qa-elixir-test-author`. Implement LiveView and tool-runtime integration tests for source-file Knowledge.

## Objective
Add UI and tool integration tests that validate behavior from user upload through search/read results with scope-safe denial paths.

## Inputs Required
- [x] Tasks 01-11 approved
- [x] Existing Knowledge LiveView and runtime tool tests

## Expected Outputs
- [x] LiveView tests for upload/list/filter/status/retry/detail flows.
- [x] Tool runtime tests for `knowledge.search` and `knowledge.read` success/failure paths.
- [x] Assertions on stable DOM IDs and safe output boundaries.

## Acceptance Criteria
- [x] UI tests avoid brittle raw HTML assertions.
- [x] Tool tests validate envelope format and safe error behavior.
- [x] Unauthorized search/read attempts return safe denial behavior.

## Constraints
- Do not broaden scope beyond source-file Knowledge behavior.

## Approval Gate
Human reviewer must approve this task before Task 13 begins.

## Human Review
*[Filled by human reviewer]*

## Execution Summary
- Added LiveView source-file filter coverage using stable selectors in:
  - `test/lemmings_os_web/live/knowledge_live_test.exs`
  - Verifies query/status/type filters and failure-status badge visibility.
- Added runtime denial-path coverage in:
  - `test/lemmings_os/tools/runtime_test.exs`
  - Verifies `knowledge.read` returns safe `tool.knowledge.not_found` for cross-scope existing chunk refs.
  - Verifies `knowledge.search` returns `tool.knowledge.invalid_scope` for out-of-ancestry scope hints.
- Existing runtime and LiveView tests already covered edit/retry/archive and search/read success/failure envelopes; this task filled the remaining scope-safe denial and UI filter gaps.
