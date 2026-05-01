# Task 10: Staff Elixir PR Audit

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`audit-pr-elixir` - Staff-level PR reviewer for Elixir/Phoenix correctness, design, security, performance, logging, and tests.

## Agent Invocation
Act as `audit-pr-elixir`. Perform a staff-level Elixir/Phoenix review of the full local Artifact storage implementation.

## Objective
Catch correctness, style, maintainability, performance, logging, and regression issues before release validation.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/project_context.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0011_local_artifact_storage/plan.md`
- [ ] Tasks 01-09 outputs
- [ ] Full implementation diff and test results

## Expected Outputs
- [ ] Findings-first staff audit documented in this task file.
- [ ] Constitution/style compliance checklist.
- [ ] Review of adapter design, context boundaries, scoped APIs, filesystem safety, metadata validation, telemetry/logging, docs alignment, and test quality.
- [ ] Focused fixes and tests for confirmed findings where safe.

## Acceptance Criteria
- [ ] Findings are ordered by severity with file/line references.
- [ ] Explicit World/scope boundaries are verified.
- [ ] Tuple-return and public-doc expectations are checked.
- [ ] No map access syntax on structs or unsafe atom creation is introduced.
- [ ] Tests are deterministic and aligned with style guide.
- [ ] Targeted tests pass after any fixes.

## Technical Notes
### Relevant Code Locations
```text
lib/lemmings_os/artifacts*
lib/lemmings_os_web/controllers/instance_artifact_controller.ex
config/*.exs
test/lemmings_os/artifacts*
test/lemmings_os_web/controllers/instance_artifact_controller_test.exs
docs/
```

### Constraints
- Do not perform git operations.
- Do not broaden feature scope.
- Do not hide failures; document blockers clearly.

## Execution Instructions
1. Read all inputs.
2. Review implementation against plan, constitution, and coding styles.
3. Document findings first.
4. Implement narrow fixes only for confirmed in-scope issues.
5. Run targeted tests and document results.

---

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
