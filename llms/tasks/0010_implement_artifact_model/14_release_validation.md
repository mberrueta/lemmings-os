# Task 14: Release Validation

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`rm-release-manager` - Release manager for migration risk, rollout notes, rollback planning, and final validation evidence.

## Agent Invocation
Act as `rm-release-manager`. Prepare final release validation for the Artifact model implementation.

## Objective
Close the Artifact implementation with migration notes, rollback guidance, validation evidence, and final checks against constitution and style guides.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0010_implement_artifact_model/plan.md`
- [ ] Tasks 01-13 outputs
- [ ] Full implementation diff and test results

## Expected Outputs
- [ ] Release/validation summary documented in this task file.
- [ ] Migration risk and rollback notes.
- [ ] Final test command evidence.
- [ ] Residual risk list and human sign-off checklist.

## Acceptance Criteria
- [ ] Re-read and explicitly check `llms/constitution.md`, `llms/coding_styles/elixir.md`, and `llms/coding_styles/elixir_tests.md`.
- [ ] Run narrow relevant tests first and record commands/results.
- [ ] Run `mix test` and record result.
- [ ] Run `mix precommit` and record result.
- [ ] Confirm `mix format` or precommit formatting check passes.
- [ ] Confirm no SecretBank/SecretsBank Artifact access via documented `rg` result from Task 11 or a fresh final check.
- [ ] Confirm docs/ADR are updated and match implementation.
- [ ] Confirm migration rollback impact is clearly stated.

## Technical Notes
### Relevant Commands
```bash
mix test test/lemmings_os/artifacts_test.exs
mix test test/lemmings_os_web/live/instance_live_test.exs
mix test test/lemmings_os_web/controllers
mix test
mix precommit
rg "SecretBank|SecretsBank|secret_bank|resolve_runtime_secret" lib test
```
Adjust narrow test paths to the actual files created during implementation.

### Constraints
- Do not perform git operations.
- Do not hide failures; document blockers clearly.
- Do not approve release if `mix precommit` fails without a documented human waiver.

## Execution Instructions

### For the Agent
1. Read all inputs listed above.
2. Review task summaries and final diff.
3. Run validation commands in narrow-to-broad order.
4. Document exact commands and outcomes.
5. Prepare migration/rollback notes and final residual risks.
6. Do not mark complete unless final validation passes or a blocker is explicitly documented.

### For the Human Reviewer
After agent completes:
1. Review final validation evidence.
2. Execute git operations if satisfied.
3. Provide final release sign-off or request follow-up fixes.

---

## Execution Summary
*[Filled by executing agent after completion]*
