# Task 07: Feature Documentation

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`docs-feature-documentation-author` - Feature documentation writer aligned with actual application behavior.

## Agent Invocation
Act as `docs-feature-documentation-author`. Update operator/self-host documentation for local Artifact storage.

## Objective
Document the local Artifact storage operational contract after implementation is complete.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/project_context.md`
- [ ] `llms/tasks/0011_local_artifact_storage/plan.md`
- [ ] Tasks 01-06 outputs
- [ ] Existing docs under `docs/` and `README.md`
- [ ] Final implemented config behavior from `config/runtime.exs`

## Expected Outputs
- [ ] Docs mention `LEMMINGS_ARTIFACT_STORAGE_ROOT`.
- [ ] Docs explain DB metadata vs filesystem bytes split.
- [ ] Docs explain required persistent volume for Docker/self-host deployments.
- [ ] Docs state DB-only backup is insufficient; DB and artifact volume must both be backed up.
- [ ] Docs state soft-deleted Artifacts are not physically purged in this issue.
- [ ] Docs state S3/MinIO, cleanup/retention, encryption-at-rest beyond FS permissions, scanning, previews, RAG ingestion, cross-City shared storage, and versioning are future work.

## Acceptance Criteria
- [ ] Documentation matches actual implemented env var names and defaults.
- [ ] No docs imply automatic cleanup, cross-City shared storage, object storage support, or content scanning.
- [ ] Docs are operator-readable and concise.
- [ ] Markdown formatting is clean.

## Technical Notes
### Relevant Documentation Locations
```text
docs/features/                 # Feature docs if present
README.md                      # Feature/config links if appropriate
llms/tasks/0011_local_artifact_storage/plan.md
```

### Constraints
- Do not change executable code in this task unless fixing a typo in docs references requires it.
- Do not invent behavior not implemented in Tasks 02-06.
- Do not perform git operations.

## Execution Instructions
1. Read implementation summaries and current docs.
2. Update the narrowest relevant docs.
3. Verify docs reflect actual config and out-of-scope boundaries.
4. Document files changed and any doc gaps.

---

## Execution Summary
- Updated `docs/features/artifacts.md` with the implemented local storage contract.
- Documented `LEMMINGS_ARTIFACT_STORAGE_ROOT`, default max file size, local layout, and local-only backend behavior.
- Documented the Postgres metadata vs filesystem bytes split, persistent volume requirement, and DB-plus-artifact-volume backup requirement.
- Documented soft-delete non-purge behavior and future-work boundaries including S3/MinIO, cleanup/retention, scanning, previews, RAG ingestion, cross-City storage, and versioning.

## Human Review
*[Filled by human reviewer]*
