# Task 04: Promotion and Update Flow

## Status
- **Status**: ✅ COMPLETED 
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for context workflows, Ecto.Multi, and filesystem side effects.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement manual workspace-file promotion and explicit update/new behavior in the backend context only.

## Objective
Add `promote_workspace_file/2` and update behavior that copies trusted workspace files into managed artifact storage, computes metadata, and creates or updates durable Artifact rows.

## Inputs Required
- [x] `llms/constitution.md`
- [x] `llms/coding_styles/elixir.md`
- [x] `llms/coding_styles/elixir_tests.md`
- [x] `llms/tasks/0010_implement_artifact_model/plan.md`
- [x] Tasks 01-03 outputs
- [x] `lib/lemmings_os/lemming_instances.ex` existing `artifact_absolute_path/2`
- [x] `lib/lemmings_os/tools/work_area.ex`

## Expected Outputs
- [x] `promote_workspace_file/2` backend API.
- [x] Existing artifact lookup by `world_id + city_id + department_id + lemming_id + filename`.
- [x] Explicit `mode: :update_existing` that overwrites managed file, recomputes checksum/size, keeps same row, and returns safe descriptor.
- [x] Explicit `mode: :promote_as_new` for filename collision avoidance.
- [x] Failure handling that does not persist raw workspace paths or file contents.
- [x] Tests for success, update, promote-as-new, invalid path, missing file, checksum/size changes, and no original path persistence.

## Acceptance Criteria
- [x] Promotion creates `ready` artifacts.
- [x] Original workspace file is copied, not moved.
- [x] Original workspace path is not stored in DB, logs, events, or returned descriptors.
- [x] Same-scope filename update never happens without explicit caller intent.
- [x] Backend promotion requires explicit `mode: :update_existing` or `mode: :promote_as_new` when an existing same-scope filename is present.
- [x] Backend default must not silently update; missing or ambiguous mode fails with a safe error.
- [x] UI may default the selected action to update, but the backend still receives explicit mode intent.
- [x] Multi-step durable operations use `Ecto.Multi` where appropriate.
- [x] No UI changes are made in this task.

## Technical Notes
### Relevant Code Locations
```
lib/lemmings_os/lemming_instances.ex   # Existing workspace artifact path resolver
lib/lemmings_os/tools/work_area.ex     # Safer work area resolver patterns
lib/lemmings_os/artifacts.ex           # Context from Task 03
lib/lemmings_os/artifacts/local_storage.ex # Storage boundary from Task 02
```

### Constraints
- Manual trusted UI/runtime promotion only.
- No automatic LLM/tool promotion.
- Do not scan contents for secrets.
- Do not inject artifact contents into LLM context.
- Do not call Secret Bank.

## Execution Instructions

### For the Agent
1. Read all inputs listed above.
2. Implement backend promotion/update behavior only.
3. Add DataCase tests with temp workspace/storage roots.
4. Run narrow promotion/context tests.
5. Document assumptions, files changed, and test commands in Execution Summary.

### For the Human Reviewer
After agent completes:
1. Verify no silent overwrite path exists.
2. Verify failure behavior does not leak paths/content.
3. Approve before Task 05 begins.

---

## Execution Summary
Implemented `promote_workspace_file/2` in `LemmingsOs.Artifacts` with explicit collision modes and managed-storage copy flow.

### Assumptions
- Promotion receives trusted runtime context plus a workspace-relative path.
- When no same-scope filename collision exists, promotion creates a new artifact regardless of mode.

### Files Changed
- `lib/lemmings_os/artifacts.ex`
- `lib/lemmings_os/artifacts/promotion.ex`
- `test/lemmings_os/artifacts/promotion_test.exs`

### Validation Commands
- `mix format lib/lemmings_os/artifacts.ex lib/lemmings_os/artifacts/promotion.ex test/lemmings_os/artifacts/promotion_test.exs`
- `mix test test/lemmings_os/artifacts/promotion_test.exs`
- `mix test test/lemmings_os/artifacts_test.exs test/lemmings_os/artifacts/promotion_test.exs test/lemmings_os/artifacts/artifact_test.exs test/lemmings_os/artifacts/local_storage_test.exs`
- `mix precommit`
