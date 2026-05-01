# Task 04: Artifact Context And Downloads

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for Phoenix contexts, controllers, and scoped APIs.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Wire the hardened storage backend through the Artifact context and durable download controller path.

## Objective
Move trusted Artifact file opening behind scoped context/storage APIs and ensure missing/broken storage failures are safe and recoverable.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/project_context.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0011_local_artifact_storage/plan.md`
- [ ] Tasks 01-03 outputs
- [ ] `lib/lemmings_os/artifacts.ex`
- [ ] `lib/lemmings_os/artifacts/artifact.ex`
- [ ] `lib/lemmings_os/artifacts/promotion.ex`
- [ ] `lib/lemmings_os_web/controllers/instance_artifact_controller.ex`

## Expected Outputs
- [ ] Trusted Artifact context open/download function performs scope/status checks before storage access.
- [ ] Context open/download success returns `{:ok, %{path: path, filename: filename, content_type: content_type, size_bytes: size_bytes}}` for trusted controller use.
- [ ] Controller no longer resolves storage refs and calls `File.read/1` directly.
- [ ] Missing/unreadable/broken managed files return safe 404 responses without leakage.
- [ ] Ready Artifacts are marked `error` with safe metadata where applicable.
- [ ] The read/open mutation that marks a ready Artifact as `error` is documented as an intentional storage consistency repair, not a general read mutation pattern.
- [ ] `Artifact` metadata validation accepts only the approved storage error keys in addition to existing source metadata.
- [ ] Existing `:update_existing` and `:promote_as_new` behavior remains intact.

## Acceptance Criteria
- [ ] Web layer calls context/storage boundary, not raw resolved file paths directly.
- [ ] Controller uses the trusted path only after context scope/status checks succeed.
- [ ] Public descriptors still exclude `storage_ref` and filesystem paths.
- [ ] Failed first-time storage writes do not create misleading ready rows.
- [ ] Failed replacement before safe rename does not corrupt existing valid metadata.
- [ ] Download/read tests cover the intentional missing/unreadable storage repair side effect.
- [ ] Targeted context/controller tests pass.

## Technical Notes
### Relevant Code Locations
```text
lib/lemmings_os/artifacts.ex
lib/lemmings_os/artifacts/artifact.ex
lib/lemmings_os/artifacts/promotion.ex
lib/lemmings_os_web/controllers/instance_artifact_controller.ex
test/lemmings_os/artifacts_test.exs
test/lemmings_os/artifacts/promotion_test.exs
test/lemmings_os_web/controllers/instance_artifact_controller_test.exs
```

### Constraints
- Do not add persistent audit events.
- Do not broaden download authorization rules or UI behavior.
- Do not introduce any other read-path DB mutations beyond the explicit storage-missing/unreadable repair path.
- Do not physically delete files for soft-deleted Artifacts.
- Do not perform git operations.

## Execution Instructions
1. Read all inputs and current controller tests.
2. Add the scoped context/open boundary and wire the controller through it.
3. Extend metadata validation narrowly for storage errors.
4. Add or update focused tests.
5. Run targeted context/controller tests and document results.

---

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
