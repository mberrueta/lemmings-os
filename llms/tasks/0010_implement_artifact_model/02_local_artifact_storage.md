# Task 02: Local Artifact Storage

## Status
- **Status**: ✅ COMPLETED 
- **Approved**: [x] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix contexts, filesystem boundaries, and tests.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement only the local Artifact storage boundary.

## Objective
Add configurable local managed storage for Artifact files, including safe storage refs, internal resolution, copy, checksum, and size calculation.

## Inputs Required
- [x] `llms/constitution.md`
- [x] `llms/coding_styles/elixir.md`
- [x] `llms/coding_styles/elixir_tests.md`
- [x] `llms/tasks/0010_implement_artifact_model/plan.md`
- [x] `llms/tasks/0010_implement_artifact_model/01_data_model_and_schema.md`
- [x] `lib/lemmings_os/tools/work_area.ex`
- [x] Existing config files under `config/`

## Expected Outputs
- [x] Config for `:artifact_storage` with `backend: :local` and env-overridable root path.
- [x] `LemmingsOs.Artifacts.LocalStorage` or equivalent module.
- [x] Safe copy into `<root>/<world_id>/<artifact_id>/<filename>`.
- [x] SHA-256 checksum and size calculation.
- [x] Opaque `local://artifacts/<world_id>/<artifact_id>/<filename>` storage refs.
- [x] Internal trusted resolution from storage ref to filesystem path.
- [x] Unit tests for storage path generation, invalid path rejection, copy, checksum, and size.

## Acceptance Criteria
- [x] Database-facing values never contain raw workspace paths or resolved filesystem paths.
- [x] Storage root path is not logged or emitted in events.
- [x] Path traversal, absolute paths, backslash paths, drive-letter paths, null bytes, and symlink escapes are rejected where applicable.
- [x] Tests use temporary directories and restore app env after each test.
- [x] No Artifact context API or UI is implemented in this task.

## Technical Notes
### Relevant Code Locations
```
lib/lemmings_os/tools/work_area.ex     # Existing safe path handling patterns
config/config.exs                      # App config defaults
config/runtime.exs                     # Runtime env config if needed
test/lemmings_os/tools/work_area_test.exs # Filesystem test patterns
```

### Constraints
- Do not store file bytes in DB.
- Do not add external storage backends.
- Do not add dependencies.
- Do not inspect file contents beyond checksum calculation.
- Do not call Secret Bank.

## Execution Instructions

### For the Agent
1. Read all inputs listed above.
2. Implement storage functions as a narrow internal boundary with typed tuple returns.
3. Add deterministic tests using temp directories.
4. Run narrow storage tests.
5. Document assumptions, files changed, and test commands in Execution Summary.

### For the Human Reviewer
After agent completes:
1. Verify path/ref behavior cannot leak or escape storage root.
2. Confirm env/config defaults are documented enough for later docs task.
3. Approve before Task 03 begins.

---

## Execution Summary
Implemented local artifact storage boundary with config + runtime override and focused unit tests.

### Assumptions
- `store_copy/4` receives a trusted absolute source path from runtime/UI code.
- Artifact storage backend for this phase is fixed to `:local`.

### Files Changed
- `config/config.exs`
- `config/runtime.exs`
- `lib/lemmings_os/artifacts/local_storage.ex`
- `test/lemmings_os/artifacts/local_storage_test.exs`

### Validation Commands
- `mix format lib/lemmings_os/artifacts/local_storage.ex test/lemmings_os/artifacts/local_storage_test.exs config/config.exs config/runtime.exs`
- `mix test test/lemmings_os/artifacts/local_storage_test.exs`
- `mix precommit`
