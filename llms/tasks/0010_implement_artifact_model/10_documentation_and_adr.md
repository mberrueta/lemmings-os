# Task 10: Documentation and ADR

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`docs-feature-documentation-author` - Feature documentation writer aligned with implemented application behavior.

## Agent Invocation
Act as `docs-feature-documentation-author`. Document actual implemented Artifact behavior after inspecting code and tests.

## Objective
Add operator/developer documentation for Artifacts and update architecture references for durable promoted runtime outputs.

## Inputs Required
- [ ] `llms/tasks/0010_implement_artifact_model/plan.md`
- [ ] Tasks 01-09 outputs
- [ ] Implemented Artifact code/tests
- [ ] `docs/adr/0008-lemming-persistence-model.md`
- [ ] `docs/adr/0005-tool-execution-model.md` only if implementation touches its concerns

## Expected Outputs
- [ ] `docs/features/artifacts.md`.
- [ ] Updated `docs/adr/0008-lemming-persistence-model.md`.
- [ ] Optional `docs/adr/0005-tool-execution-model.md` update only if needed.
- [ ] Any relevant operator/developer docs updated where they mention generated outputs/workspace files.

## Acceptance Criteria
- [ ] Docs explain File vs Artifact, manual promotion, scope/provenance, storage, type/status model, timeline behavior, download/open behavior, security/privacy rules, observability events, out of scope, and future work.
- [ ] ADR 0008 states Artifact metadata is in Postgres and bytes are outside Postgres in managed file storage.
- [ ] Docs state Artifact contents are not stored in Postgres, ETS, DETS, logs, or LLM context.
- [ ] Docs mention config/env var for local artifact storage root.
- [ ] Docs match actual implementation rather than aspirational behavior.

## Technical Notes
### Relevant Code Locations
```
docs/features/                       # Feature docs
docs/adr/0008-lemming-persistence-model.md
docs/adr/0005-tool-execution-model.md
```

### Constraints
- Do not add undocumented behavior.
- Do not claim external storage/S3 support.
- Do not document automatic promotion or future workflows as implemented.

## Execution Instructions

### For the Agent
1. Inspect implemented code/tests first.
2. Write concise documentation aligned with actual behavior.
3. Run a docs-only format/check if available; otherwise no code checks required.
4. Document assumptions, files changed, and validation in Execution Summary.

### For the Human Reviewer
After agent completes:
1. Verify docs do not overstate feature scope.
2. Approve before Task 11 begins.

---

## Execution Summary
*[Filled by executing agent after completion]*
