# Task 07: Download Route and Controller

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for Phoenix controllers, scoped context calls, and safe file responses.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement controlled durable Artifact download/open behavior only.

## Objective
Add an ID-based Artifact download route/controller that checks visible scope and status before resolving managed storage and sending the file.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0010_implement_artifact_model/plan.md`
- [ ] Tasks 01-06 outputs
- [ ] `lib/lemmings_os_web/router.ex`
- [ ] `lib/lemmings_os_web/controllers/instance_artifact_controller.ex`

## Expected Outputs
- [ ] Route `GET /lemmings/instances/:instance_id/artifacts/:artifact_id/download` before existing workspace catch-all route.
- [ ] Controller action that resolves world/scope, instance, Artifact, status, and storage path in safe order.
- [ ] `artifact.read` event on successful read.
- [ ] Safe handling for missing DB rows, wrong scope, bad status, missing physical file, and invalid storage ref.
- [ ] Controller tests for authorized download, wrong scope, rejected status, missing file, and response header safety.

## Acceptance Criteria
- [ ] Scope check happens before internal storage ref/path resolution.
- [ ] `archived`, `deleted`, and `error` Artifacts are not downloadable by default.
- [ ] Response does not expose resolved filesystem path or storage root.
- [ ] Existing workspace route remains functional and separate.
- [ ] File response uses safe content disposition and `x-content-type-options: nosniff`.

## Technical Notes
### Relevant Code Locations
```
lib/lemmings_os_web/router.ex                    # Route order matters
lib/lemmings_os_web/controllers/instance_artifact_controller.ex # Existing scratch route
test/lemmings_os_web/live/instance_live_test.exs # Existing workspace artifact tests
test/lemmings_os_web/controllers/                # Controller tests
```

### Constraints
- Do not implement timeline UI in this task.
- Do not expose `storage_ref` outside the context/storage boundary.
- Do not call Secret Bank.

## Execution Instructions

### For the Agent
1. Read all inputs listed above.
2. Add durable route/controller behavior without breaking the existing catch-all workspace route.
3. Add focused controller tests.
4. Run narrow controller/context tests.
5. Document assumptions, files changed, and test commands in Execution Summary.

### For the Human Reviewer
After agent completes:
1. Verify route order and scope-before-path-resolution behavior.
2. Approve before Task 08 begins.

---

## Execution Summary
*[Filled by executing agent after completion]*
