# Task 03: Artifacts Context Core

## Status
- **Status**: ✅ COMPLETED
- **Approved**: [x] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for explicit World-scoped context APIs.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement the core `LemmingsOs.Artifacts` context APIs without promotion or UI.

## Objective
Expose a small explicit-scope context for creating, retrieving, listing, and updating Artifact metadata and lifecycle status.

## Inputs Required
- [x] `llms/constitution.md`
- [x] `llms/coding_styles/elixir.md`
- [x] `llms/tasks/0010_implement_artifact_model/plan.md`
- [x] `llms/tasks/0010_implement_artifact_model/01_data_model_and_schema.md`
- [x] `llms/tasks/0010_implement_artifact_model/02_local_artifact_storage.md`
- [x] Existing context examples such as `lib/lemmings_os/lemming_tools.ex`

## Expected Outputs
- [x] `LemmingsOs.Artifacts` context module.
- [x] `create_artifact/2` for trusted metadata creation.
- [x] `get_artifact/2` with explicit scope and no global lookup.
- [x] `list_artifacts_for_instance/2`.
- [x] `list_artifacts_for_scope/2` using an opts keyword list and private multi-clause `filter_query/2`.
- [x] `update_artifact_status/3`.
- [x] Safe descriptor/read-model helper that omits storage refs and paths from normal public returns.
- [x] Tests for scope enforcement and status filtering.

## Acceptance Criteria
- [x] Every public API requires an explicit persisted hierarchy scope struct or validated scope map, with World boundary enforcement.
- [x] Default list/get APIs only return `ready`.
- [x] Any API that can include `archived`, `deleted`, or `error` must be named or optioned explicitly and covered by tests.
- [x] Functions that can fail return `{:ok, value}` or `{:error, reason}`.
- [x] Public non-trivial functions include `@doc` and `@spec`.
- [x] Web code is not changed in this task.

## Technical Notes
### Relevant Code Locations
```
lib/lemmings_os/lemming_tools.ex       # Context pattern with explicit world/instance scope
lib/lemmings_os/events.ex              # Scope normalization ideas
lib/lemmings_os/worlds/world.ex        # World struct
lib/lemmings_os/cities/city.ex         # City struct
lib/lemmings_os/departments/department.ex # Department struct
lib/lemmings_os/lemmings/lemming.ex    # Lemming struct
```

### Constraints
- Do not implement workspace promotion in this task.
- Do not resolve storage refs for downloads here except through internal storage boundary if needed by tests.
- Do not call Secret Bank.

## Execution Instructions

### For the Agent
1. Read all inputs listed above.
2. Implement context APIs with explicit scope clauses.
3. Add focused DataCase tests for scope enforcement and status filtering.
4. Run narrow context tests.
5. Document assumptions, files changed, and test commands in Execution Summary.

### For the Human Reviewer
After agent completes:
1. Verify no global Artifact lookup exists.
2. Verify list APIs use opts and `filter_query/2` per constitution.
3. Approve before Task 04 begins.

---

## Execution Summary
Implemented explicit-scope `LemmingsOs.Artifacts` context APIs for create/get/list/update with safe descriptors and default `ready` filtering.

### Assumptions
- Public read models should omit `storage_ref` by default.
- Inclusion of non-`ready` statuses must be explicit via options.

### Files Changed
- `lib/lemmings_os/artifacts.ex`
- `test/lemmings_os/artifacts_test.exs`

### Validation Commands
- `mix format lib/lemmings_os/artifacts.ex test/lemmings_os/artifacts_test.exs`
- `mix test test/lemmings_os/artifacts_test.exs`
- `mix test test/lemmings_os/artifacts_test.exs test/lemmings_os/artifacts/artifact_test.exs test/lemmings_os/artifacts/local_storage_test.exs`
- `mix precommit`
