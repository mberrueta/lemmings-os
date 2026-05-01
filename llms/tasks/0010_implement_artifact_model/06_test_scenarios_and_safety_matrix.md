# Task 06: Test Scenarios and Safety Matrix

## Status
- **Status**: ✅ COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`qa-test-scenarios` - Test scenario designer for acceptance, edge-case, and regression coverage.

## Agent Invocation
Act as `qa-test-scenarios`. Create an implementation-aware test scenario matrix; do not write production code.

## Objective
Document the full test coverage required for the Artifact model across schema, storage, context, promotion, events, download route, UI, security, accessibility, and final validation.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0010_implement_artifact_model/plan.md`
- [ ] Tasks 01-05 outputs
- [ ] Existing test patterns under `test/`

## Expected Outputs
- [ ] `llms/tasks/0010_implement_artifact_model/test_plan.md` or equivalent scenario matrix.
- [ ] Scenario IDs grouped by test layer.
- [ ] Explicit leakage/security matrix with sentinel values.
- [ ] Required narrow test commands for later implementation and validation tasks.

## Acceptance Criteria
- [ ] Covers all acceptance criteria from the source plan.
- [ ] Covers wrong-scope, archived/deleted/error, missing physical file, path traversal, symlink escape, and safe failure handling without durable Artifact lifecycle events.
- [ ] Covers UI promotion/update/new flows and safe descriptor rendering.
- [ ] Covers no Secret Bank access and no automatic LLM context injection.
- [ ] References `llms/coding_styles/elixir_tests.md` expectations: factories, deterministic data, stable selectors, no external network.

## Technical Notes
### Relevant Code Locations
```
test/lemmings_os/                  # DataCase patterns
test/lemmings_os_web/live/         # LiveView test patterns
test/lemmings_os_web/controllers/  # Controller test patterns
test/support/factory.ex            # Factory patterns
```

### Constraints
- Do not implement tests in this task unless explicitly requested by the human.
- Do not change production code.

## Execution Instructions

### For the Agent
1. Read all inputs listed above.
2. Create the scenario matrix in the task directory.
3. Include scenario-to-acceptance mapping and recommended commands.
4. Document assumptions and any coverage risks in Execution Summary.

### For the Human Reviewer
After agent completes:
1. Verify all source-plan acceptance criteria map to scenarios.
2. Approve before Task 07 begins.

---

## Execution Summary
Implemented the Artifact test scenario and safety matrix deliverable for Task 06.

### Deliverables Added
- Added `llms/tasks/0010_implement_artifact_model/test_plan.md` with:
  - Scope/assumptions and risk-based test areas.
  - Scenario ID groups by layer (`SCH`, `STO`, `CTX`, `PRO`, `OBS`, `DL`, `UI`, `SEC`, `REL`).
  - Implementation-aware scenario matrix covering schema, storage, context, promotion/update, observability, download route, LiveView UI, security, and release validation.
  - Explicit acceptance-criteria-to-scenario mapping from `plan.md`.
  - Leakage/security sentinel matrix including secret/path/storage-ref/content/note sentinel values.
  - Given/When/Then acceptance bullets for high-risk behaviors.
  - Required narrow test commands plus final `mix test` and `mix precommit`.

### Key Coverage Confirmations
- Includes wrong-scope access, archived/deleted/error status filtering, missing physical file handling, traversal/symlink escape rejection, and safe failure behavior without durable Artifact lifecycle events.
- Includes UI promotion/update/new flow coverage and safe descriptor rendering constraints.
- Includes explicit checks for:
  - no Secret Bank access in Artifact modules
  - no automatic LLM context injection of Artifact contents
  - no leakage of `storage_ref`, resolved filesystem paths, workspace paths, notes, full metadata, or file contents in public outputs/logging.
