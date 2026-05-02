# Task 06: Storage Test Coverage

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`qa-elixir-test-author` - QA-driven Elixir test writer for ExUnit unit, integration, controller, and telemetry tests.

## Agent Invocation
Act as `qa-elixir-test-author`. Implement or complete ExUnit coverage for local Artifact storage after backend work is in place.

## Objective
Convert the scenario matrix and implementation behavior into deterministic ExUnit coverage across storage, Artifact context, controller/downloads, metadata validation, and observability safety.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/project_context.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0011_local_artifact_storage/plan.md`
- [ ] Tasks 01-05 outputs
- [ ] Existing tests under `test/lemmings_os/artifacts*`
- [ ] `test/lemmings_os_web/controllers/instance_artifact_controller_test.exs`

## Expected Outputs
- [ ] Storage unit tests for atomic write, temp cleanup, max size, checksum/size, path safety, open/path/existence, and health check.
- [ ] Storage/context tests assert `open/2` success shape: `{:ok, %{path: path, filename: filename, content_type: content_type, size_bytes: size_bytes}}`.
- [ ] Schema/context tests for safe storage error metadata and rejected unsafe metadata.
- [ ] Promotion/update tests for unchanged metadata on failed replacement.
- [ ] Controller tests for safe downloads, wrong scope/status, missing/broken storage, and leakage prevention.
- [ ] Telemetry/log tests or assertions for safe metadata and no durable `Events` persistence.
- [ ] Narrow-to-broad test command evidence.

## Acceptance Criteria
- [ ] Tests are deterministic, use factories/temp dirs, and restore app env in `on_exit`.
- [ ] No external network or timing-sensitive assertions.
- [ ] No broad raw HTML assertions except targeted leakage checks.
- [ ] Tests fail for the main regressions identified in Task 01.
- [ ] Targeted tests pass.

## Technical Notes
### Relevant Code Locations
```text
test/lemmings_os/artifacts/local_storage_test.exs
test/lemmings_os/artifacts/artifact_test.exs
test/lemmings_os/artifacts/promotion_test.exs
test/lemmings_os/artifacts_test.exs
test/lemmings_os_web/controllers/instance_artifact_controller_test.exs
```

### Constraints
- Do not introduce fixture-style helpers or `*_fixture` naming.
- Keep permission tests platform-tolerant.
- Do not perform git operations.

## Execution Instructions
1. Read all inputs and scenario matrix.
2. Add focused tests in the appropriate test layers.
3. Run narrow relevant tests first.
4. Run broader tests only as needed for confidence.
5. Document commands, outputs, files changed, and residual gaps.

---

## Execution Summary
- Expanded ExUnit coverage across storage, schema, context, promotion, controller, config, and observability layers.
- Covered adapter callback contract/no delete callback, canonical refs, unsafe names/refs, symlink rejection across write/path/open/existence, temp cleanup, max size, permissions, open shape, health checks, storage error metadata, failed promotion/update behavior, safe downloads, repair-to-error behavior, telemetry metadata, safe logs, and no durable audit persistence.
- Targeted artifact/config/controller suite passed with `20 doctests, 71 tests, 0 failures`.

## Human Review
*[Filled by human reviewer]*
