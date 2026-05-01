# Task 05: Artifact Instrumentation and Safe Logging

## Status
- **Status**: ✅ COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-logging-daily-guardian` - Logging quality guardian for safe structured metadata hygiene.

## Agent Invocation
Act as `dev-logging-daily-guardian`. Add lightweight, safe Artifact observability without introducing durable audit/event persistence.

## Objective
Add lightweight, safe Artifact observability without introducing durable audit/event persistence.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/tasks/0010_implement_artifact_model/plan.md`
- [ ] Tasks 01-04 outputs
- [ ] Existing Artifact context/promotion code and tests

## Expected Outputs
- [ ] Durable Artifact audit wrappers are removed or unused.
- [ ] Artifact lifecycle code does not write to the `events` table.
- [ ] Durable Artifact event tests are removed.
- [ ] Minimal instrumentation tests are added only if actual non-durable instrumentation behavior exists.
- [ ] Task and docs references are updated to the reduced scope.

## Acceptance Criteria
- [ ] No durable Artifact audit/event rows are required.
- [ ] No Artifact lifecycle writes to `events`.
- [ ] Logs/telemetry, if present, use allowlisted safe fields only.
- [ ] Payloads/log metadata exclude file contents, `storage_ref`, resolved paths, raw workspace paths, notes, full metadata, and secrets.
- [ ] Reason values are normalized to safe reason tokens if logged.

## Technical Notes
### Constraints
- Do not add a replacement durable Artifact event wrapper.
- Do not emit durable `artifact.read`.
- Do not call Secret Bank from Artifact code.
- Keep existing Artifact schema/storage/promotion/download/UI behavior unchanged.

## Execution Instructions

### For the Agent
1. Remove durable Artifact event/audit helper usage.
2. Remove Artifact lifecycle writes to durable `events`.
3. Remove durable event tests for Artifact operations.
4. Update task/docs references to match reduced scope.
5. Run required validation commands and record exact outcomes.

### For the Human Reviewer
After agent completes:
1. Verify no Artifact lifecycle path writes to `events`.
2. Verify durable event assertions were removed from Artifact tests.
3. Verify docs/task scope reflects instrumentation-only behavior.

---

## Execution Summary
Implemented scope reduction by removing Artifact durable audit/event persistence from this PR slice.

### Code Changes
- Removed durable event helper alias and durable-emission hooks from:
  - `lib/lemmings_os/artifacts.ex`
  - `lib/lemmings_os/artifacts/promotion.ex`
- Deleted durable Artifact event wrapper module:
  - `lib/lemmings_os/artifacts/audit_events.ex`

### Test Changes
- Removed durable event test file asserting `events` table lifecycle rows:
  - `test/lemmings_os/artifacts/audit_events_test.exs`
- No replacement instrumentation tests were added because this patch does not add new non-durable instrumentation behavior.

### Docs/Plan Changes
- Renamed Task 05 to **Artifact Instrumentation and Safe Logging** and rewrote objective/acceptance criteria for non-durable scope.
- Updated plan/task docs to remove durable Artifact lifecycle event requirements and `artifact.read` durable emission expectations.
- Added future-work note that platform audit/event design must be handled separately.

### Validation Commands
- `mix format lib/lemmings_os/artifacts.ex lib/lemmings_os/artifacts/promotion.ex`
- `mix test test/lemmings_os/artifacts_test.exs test/lemmings_os/artifacts/promotion_test.exs`
- `mix test`
- `mix precommit`
- `rg -n "SecretBank|SecretsBank|secret_bank|resolve_runtime_secret" lib/lemmings_os/artifacts* test/lemmings_os/artifacts*`

### Validation Results
- `mix format ...`: success
- `mix test test/lemmings_os/artifacts_test.exs test/lemmings_os/artifacts/promotion_test.exs`: success (`10 doctests, 17 tests, 0 failures`)
- `mix test`: success (`159 doctests, 743 tests, 0 failures`)
- `mix precommit`: success (dialyzer, credo, and checks passed)
- `rg ...`: no matches in Artifact code/tests (Artifact code has no Secret Bank calls)
