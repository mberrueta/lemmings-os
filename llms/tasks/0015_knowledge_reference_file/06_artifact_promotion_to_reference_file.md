# Task 06: Artifact Promotion To Reference File

## Status

- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Artifact/Knowledge integration and safe provenance handling.

## Agent Invocation

Act as `dev-backend-elixir-engineer`. Implement explicit operator-approved Artifact promotion into Knowledge reference files.

## Objective

Allow an existing Artifact to be copied or registered into Knowledge-managed reference-file storage while keeping Artifact linkage optional provenance, not the storage contract.

## Implementation Scope

- Add a Knowledge context API for promoting an Artifact into a reference file through explicit operator action.
- Enforce scope compatibility between the selected Artifact and the requested reference-file scope.
- Copy or safely ingest bytes into Knowledge-managed reference-file storage.
- Persist nullable `artifact_id` provenance when available.
- Ensure the resulting reference file remains manageable and readable if the Artifact later becomes unavailable.
- Return safe errors that do not reveal inaccessible Artifacts.

## Constraints

- No automatic LLM/runtime promotion.
- No dependency from reference-file search/read on Artifact storage or Artifact availability after promotion.
- Do not expose Artifact storage refs or workspace paths in reference-file outputs.
- Do not modify Artifact semantics beyond what is required for safe read/copy integration.

## Expected Outputs

- [x] Explicit promotion API with scope checks.
- [x] Safe handling for missing, archived, deleted, or inaccessible Artifacts.
- [x] Tests or test hooks for optional provenance and post-promotion Artifact unavailability.

## Implementation Notes

- Added `Knowledge.promote_artifact_to_reference_file/3` as the explicit operator-managed promotion boundary.
- Enforced explicit operator approval via `operator_approved: true`; otherwise returns `{:error, :operator_approval_required}`.
- Enforced scope compatibility between requested Knowledge scope and promoted Artifact scope.
- Promotion reads Artifact bytes through scoped Artifact APIs and writes copied bytes into Knowledge-managed reference-file storage.
- Persisted optional Artifact provenance with nullable `artifact_id` on the resulting Knowledge item.
- Returned safe Artifact availability errors as `{:error, :artifact_unavailable}` for inaccessible/missing/unavailable Artifact states.
- Confirmed reference-file read behavior remains Knowledge-storage based after promotion, independent of Artifact availability.
- Added backend tests in `test/lemmings_os/knowledge_test.exs` for:
  - explicit approval requirement,
  - optional provenance persistence,
  - safe unavailable Artifact errors,
  - post-promotion Artifact unavailability not breaking reference-file reads.

## Suggested Checks

- `mix format`
- Narrow Knowledge and Artifact integration tests
- Existing Artifact tests

## Human Approval Gate

Human reviewer validates provenance semantics and explicit-approval boundary, then approves Task 07.
