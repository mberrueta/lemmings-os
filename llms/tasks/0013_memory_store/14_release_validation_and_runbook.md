# Task 14: Release Validation And Runbook

## Status
- **Status**: COMPLETE
- **Approved**: [x] Human sign-off

## Assigned Agent
`rm-release-manager` - Release manager for migration risk and rollout/rollback guidance.

## Agent Invocation
Act as `rm-release-manager`. Prepare release validation guidance for the memory-store slice, including migration safety and rollback notes.

## Objective
Deliver a release checklist and operator runbook for shipping memory store safely in a single PR slice.

## Inputs Required
- [x] Tasks 02 through 13 outputs
- [x] Current deployment/runtime configuration docs
- [x] Existing release task patterns in previous feature folders

## Expected Outputs
- [x] Release checklist covering migration order, smoke checks, and post-deploy validation.
- [x] Rollback and data-risk notes for the new knowledge table and runtime tool path.
- [x] Known limitations and monitoring/watchpoints for first release.

## Acceptance Criteria
- [x] Checklist includes required validation commands and expected outcomes.
- [x] Migration and rollback risks are clearly documented.
- [x] Runbook includes manual checks for `knowledge.store`, UI CRUD, and notifications.
- [x] Release notes are concise and actionable.

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
### Release Checklist
1. Pre-deploy validation
   - Run `mix format --check-formatted`.
   - Run `mix test`.
   - Run `mix precommit`.
   - Expected outcome: all checks pass without warnings/errors.
2. Deploy migration
   - Run `mix ecto.migrate` in target environment.
   - Expected outcome: `knowledge_items` table and indexes are created successfully.
3. Runtime smoke checks
   - Verify Knowledge page loads: `/knowledge`.
   - Verify `knowledge.store` runtime path through an execution that emits a memory.
   - Verify memory lifecycle event rows are created (`knowledge.memory.*`).
4. Post-deploy validation
   - Create/edit/delete memory through UI.
   - Confirm scoped listing behavior (no sibling/cross-world bleed).
   - Confirm best-effort chat notification includes `/knowledge?memory_id=<uuid>` deep link.

### Rollback And Data-Risk Notes
- Schema rollback
  - Roll back migration only if release is rejected before data dependence is established.
  - Data risk: rolling back the table drops stored memories created after deploy.
- Runtime/tool rollback
  - If runtime issues appear, disable use of `knowledge.store` at operational layer while preserving existing memory data.
  - UI can remain read-only operationally if needed by process controls, with create/edit/delete paused.

### Monitoring / Watchpoints (First Release)
- Watch warning logs:
  - `knowledge.memory.notification_failed`
  - `knowledge.memory.event_failed`
- Watch event volume/failure patterns for:
  - `knowledge.memory.created`
  - `knowledge.memory.updated`
  - `knowledge.memory.deleted`
  - `knowledge.memory.created_by_llm`
- Spot-check that event/tool payloads do not include memory content or runtime internals.

### Manual Runbook Checks
- `knowledge.store` happy path:
  - Trigger with valid `title/content/tags`.
  - Confirm persisted memory has `source = llm`, `status = active`, correct scope.
- Rejection matrix:
  - Confirm unsupported fields (`category/type/artifact_id/source_path`) are rejected safely.
  - Confirm out-of-ancestry scope hint returns `tool.knowledge.invalid_scope`.
- UI CRUD:
  - Confirm create/edit/delete flows in `/knowledge`.
  - Confirm scoped tabs and deep links resolve to expected records only.

### Known MVP Limits (Release Notes)
- Memory-only Knowledge family in this slice.
- No archive/unarchive lifecycle.
- No approval gate before LLM-created memory storage.
- Best-effort chat notification: store success does not depend on chat broadcast success.

### Validation Evidence (2026-05-05)
- `mix format --check-formatted` passed.
- `mix test` passed (`205 doctests, 905 tests, 0 failures`).
- `mix precommit` passed (Dialyzer + Credo clean).

## Human Review
*[Filled by human reviewer]*
