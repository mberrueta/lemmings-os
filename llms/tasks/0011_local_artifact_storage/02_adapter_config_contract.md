# Task 02: Adapter Config Contract

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior Elixir/Phoenix backend engineer for contexts, configuration, behaviours, and safe filesystem boundaries.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement only the adapter behaviour and configuration contract for local Artifact storage.

## Objective
Introduce the backend adapter seam and lock configuration behavior without duplicating the existing `LemmingsOs.Artifacts.LocalStorage` implementation.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/project_context.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `llms/tasks/0011_local_artifact_storage/plan.md`
- [ ] `llms/tasks/0011_local_artifact_storage/01_storage_test_scenarios.md`
- [ ] `lib/lemmings_os/artifacts/local_storage.ex`
- [ ] `config/config.exs`, `config/runtime.exs`, `config/test.exs`

## Expected Outputs
- [ ] `LemmingsOs.Artifacts.Storage.Adapter` behaviour exists.
- [ ] Existing `LemmingsOs.Artifacts.LocalStorage` implements or delegates behind the behaviour.
- [ ] V1 callbacks are write/open/path/existence/health only; no physical delete callback.
- [ ] Config prefers `LEMMINGS_ARTIFACT_STORAGE_ROOT`, optionally falling back to deprecated `LEMMINGS_ARTIFACT_STORAGE_PATH`.
- [ ] Default `max_file_size_bytes` is `100 * 1024 * 1024`.
- [ ] Focused compile/config tests or equivalent assertions are added where useful.

## Acceptance Criteria
- [ ] No new independent local adapter duplicates `LocalStorage` behavior.
- [ ] Canonical refs remain `local://artifacts/<world_id>/<artifact_id>/<safe_filename>`.
- [ ] No physical deletion path is introduced.
- [ ] Public functions added or materially changed have `@doc` where important.
- [ ] Narrow relevant tests pass.

## Technical Notes
### Relevant Code Locations
```text
lib/lemmings_os/artifacts/local_storage.ex   # Existing local backend
lib/lemmings_os/artifacts/storage/           # New behaviour location if introduced
config/runtime.exs                           # Runtime env handling
config/config.exs                            # Defaults
config/test.exs                              # Test defaults
```

### Constraints
- Do not change Artifact context/download behavior in this task.
- Do not implement atomic copy hardening yet unless required by a small interface compile fix.
- Do not persist `LemmingsOs.Events` audit rows.
- Do not perform git operations.

## Execution Instructions
1. Read all inputs.
2. Add the behaviour and wire existing `LocalStorage` to it.
3. Update config/env handling and max-size default.
4. Run targeted compile/tests for touched files.
5. Document changed files, commands, assumptions, and any follow-up constraints.

---

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
