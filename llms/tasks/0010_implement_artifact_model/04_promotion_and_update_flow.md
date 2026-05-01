# Task 04: Promotion and Update Flow

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for context workflows, Ecto.Multi, and filesystem side effects.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement manual workspace-file promotion and explicit update/new behavior in the backend context only.

## Objective
Add `promote_workspace_file/2` and update behavior that copies trusted workspace files into managed artifact storage, computes metadata, and creates or updates durable Artifact rows.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0010_implement_artifact_model/plan.md`
- [ ] Tasks 01-03 outputs
- [ ] `lib/lemmings_os/lemming_instances.ex` existing `artifact_absolute_path/2`
- [ ] `lib/lemmings_os/tools/work_area.ex`

## Expected Outputs
- [ ] `promote_workspace_file/2` backend API.
- [ ] Existing artifact lookup by `world_id + city_id + department_id + lemming_id + filename`.
- [ ] Explicit `mode: :update_existing` that overwrites managed file, recomputes checksum/size, keeps same row, and returns safe descriptor.
- [ ] Explicit `mode: :promote_as_new` for filename collision avoidance.
- [ ] Failure handling that does not persist raw workspace paths or file contents.
- [ ] Tests for success, update, promote-as-new, invalid path, missing file, checksum/size changes, and no original path persistence.

## Acceptance Criteria
- [ ] Promotion creates `ready` artifacts.
- [ ] Original workspace file is copied, not moved.
- [ ] Original workspace path is not stored in DB, logs, events, or returned descriptors.
- [ ] Same-scope filename update never happens without explicit caller intent.
- [ ] Backend promotion requires explicit `mode: :update_existing` or `mode: :promote_as_new` when an existing same-scope filename is present.
- [ ] Backend default must not silently update; missing or ambiguous mode fails with a safe error.
- [ ] UI may default the selected action to update, but the backend still receives explicit mode intent.
- [ ] Multi-step durable operations use `Ecto.Multi` where appropriate.
- [ ] No UI changes are made in this task.

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
*[Filled by executing agent after completion]*
