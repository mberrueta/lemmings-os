# Task 03: Local Storage Hardening

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for filesystem safety, tuple-return APIs, and deterministic tests.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Harden `LemmingsOs.Artifacts.LocalStorage` only.

## Objective
Make the local storage backend safe and complete: atomic writes, max-size enforcement, permissions, structured open/path/existence APIs, and health checks.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/project_context.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0011_local_artifact_storage/plan.md`
- [ ] Task 01 scenario matrix
- [ ] Task 02 output
- [ ] `lib/lemmings_os/artifacts/local_storage.ex`
- [ ] `test/lemmings_os/artifacts/local_storage_test.exs`

## Expected Outputs
- [ ] Writes/copies use a temp file in the target directory and atomic rename.
- [ ] Max file size is enforced during write/copy.
- [ ] `size_bytes` and SHA-256 are computed from managed storage.
- [ ] Best-effort directory/file permissions are applied where supported.
- [ ] `open/2`, `exists?/2`, `path_for/2`, and `health_check/1` return explicit tuples.
- [ ] `open/2` contract is `{:ok, %{path: path, filename: filename, content_type: content_type, size_bytes: size_bytes}} | {:error, reason_token}`.
- [ ] Path safety preserves traversal, absolute path, separator, null byte, control char, and symlink-escape rejection.
- [ ] Any trusted storage path is resolved/expanded and verified to remain inside the configured storage root before it is opened or returned.
- [ ] Focused storage tests cover success and failure paths.

## Acceptance Criteria
- [ ] Failed writes do not leave a ready-looking final managed file.
- [ ] Successful writes do not leave temp files behind.
- [ ] `open/2` returns an internal trusted path only after storage ref validation and root-bound resolution.
- [ ] Structured errors never include absolute paths, root path, raw workspace paths, file contents, or exception dumps.
- [ ] Symlinks inside the storage root that point outside the root are rejected before open/path return.
- [ ] Health check verifies root create/writable/temp create/remove behavior.
- [ ] Targeted local storage tests pass.

## Technical Notes
### Relevant Code Locations
```text
lib/lemmings_os/artifacts/local_storage.ex
test/lemmings_os/artifacts/local_storage_test.exs
```

### Constraints
- Do not change controller/download behavior in this task.
- Do not add dependencies.
- Keep permission tests tolerant of OS/container differences.
- Do not persist `LemmingsOs.Events` audit rows.
- Do not perform git operations.

## Execution Instructions
1. Read all inputs and current tests.
2. Harden storage internals behind existing public helpers where possible.
3. Add focused unit tests for new backend behavior.
4. Run targeted storage tests.
5. Document files changed, commands, residual risks, and assumptions.

---

## Execution Summary
- Hardened `LemmingsOs.Artifacts.LocalStorage` writes to stream through a temp file in the destination directory and atomically rename into place.
- Enforced configured `max_file_size_bytes` during copy and return `:file_too_large` without leaving a final managed file.
- Kept checksum and size calculation based on the managed destination file.
- Added best-effort private permissions for storage directories and files.
- Implemented explicit tuple-return `open/2`, `exists?/2`, `path_for/2`, and writable `health_check/1` behavior.
- Added focused tests for temp cleanup, oversized writes, permissions, symlink rejection, open shape, and health checks.

## Human Review
*[Filled by human reviewer]*
