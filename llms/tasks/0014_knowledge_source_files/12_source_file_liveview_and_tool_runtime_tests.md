# Task 12: Source File LiveView And Tool Runtime Tests

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`qa-elixir-test-author` - QA-driven ExUnit author for LiveView and runtime-tool coverage.

## Agent Invocation
Act as `qa-elixir-test-author`. Implement LiveView and tool-runtime integration tests for source-file Knowledge.

## Objective
Add UI and tool integration tests that validate behavior from user upload through search/read results with scope-safe denial paths.

## Inputs Required
- [ ] Tasks 01-11 approved
- [ ] Existing Knowledge LiveView and runtime tool tests

## Expected Outputs
- [ ] LiveView tests for upload/list/filter/status/retry/detail flows.
- [ ] Tool runtime tests for `knowledge.search` and `knowledge.read` success/failure paths.
- [ ] Assertions on stable DOM IDs and safe output boundaries.

## Acceptance Criteria
- [ ] UI tests avoid brittle raw HTML assertions.
- [ ] Tool tests validate envelope format and safe error behavior.
- [ ] Unauthorized search/read attempts return safe denial behavior.

## Constraints
- Do not broaden scope beyond source-file Knowledge behavior.

## Approval Gate
Human reviewer must approve this task before Task 13 begins.

## Human Review
*[Filled by human reviewer]*
