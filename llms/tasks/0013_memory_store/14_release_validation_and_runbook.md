# Task 14: Release Validation And Runbook

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`rm-release-manager` - Release manager for migration risk and rollout/rollback guidance.

## Agent Invocation
Act as `rm-release-manager`. Prepare release validation guidance for the memory-store slice, including migration safety and rollback notes.

## Objective
Deliver a release checklist and operator runbook for shipping memory store safely in a single PR slice.

## Inputs Required
- [ ] Tasks 02 through 13 outputs
- [ ] Current deployment/runtime configuration docs
- [ ] Existing release task patterns in previous feature folders

## Expected Outputs
- [ ] Release checklist covering migration order, smoke checks, and post-deploy validation.
- [ ] Rollback and data-risk notes for the new knowledge table and runtime tool path.
- [ ] Known limitations and monitoring/watchpoints for first release.

## Acceptance Criteria
- [ ] Checklist includes required validation commands and expected outcomes.
- [ ] Migration and rollback risks are clearly documented.
- [ ] Runbook includes manual checks for `knowledge.store`, UI CRUD, and notifications.
- [ ] Release notes are concise and actionable.

## Technical Notes
### Constraints
- Use existing `mix precommit` and repo validation conventions.
- Keep release guidance aligned with implemented behavior only.

### Scope Boundaries
- No feature redesign or new code paths in this task.

## Execution Instructions
### For the Agent
1. Collect implementation/test/audit outcomes from prior tasks.
2. Draft release plan, smoke checks, and rollback guidance.
3. Flag any unresolved risks requiring explicit human sign-off.

### For the Human Reviewer
1. Approve rollout/rollback plan before final PR audit.

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*

