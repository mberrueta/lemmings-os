# Task 17: Source File Release Validation

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`rm-release-manager` - Release manager for migration risk, rollout readiness, and validation evidence.

## Agent Invocation
Act as `rm-release-manager`. Prepare final release validation evidence, runbook notes, and rollout/rollback guidance for source-file Knowledge.

## Objective
Close the task sequence with final validation, migration/rollout risk assessment, and operator-facing release notes.

## Inputs Required
- [ ] Tasks 01-16 approved
- [ ] Final code diff and audit outcomes
- [ ] Runtime/config documentation updates

## Expected Outputs
- [ ] Final validation checklist and execution evidence.
- [ ] Rollout/rollback notes for migrations and service dependencies.
- [ ] Post-release monitoring checklist for retrieval/indexing health.

## Acceptance Criteria
- [ ] Narrow relevant checks were run first; `mix format` and `mix precommit` pass.
- [ ] Migration and configuration prerequisites are documented.
- [ ] Human reviewer has enough evidence for final merge/release decision.

## Constraints
- This task does not introduce new feature scope.

## Approval Gate
Human reviewer performs final sign-off after this task.

## Human Review
*[Filled by human reviewer]*
