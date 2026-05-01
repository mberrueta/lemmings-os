# Task 03: Artifacts Context Core

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for explicit World-scoped context APIs.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement the core `LemmingsOs.Artifacts` context APIs without promotion or UI.

## Objective
Expose a small explicit-scope context for creating, retrieving, listing, and updating Artifact metadata and lifecycle status.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/tasks/0010_implement_artifact_model/plan.md`
- [ ] `llms/tasks/0010_implement_artifact_model/01_data_model_and_schema.md`
- [ ] `llms/tasks/0010_implement_artifact_model/02_local_artifact_storage.md`
- [ ] Existing context examples such as `lib/lemmings_os/lemming_tools.ex`

## Expected Outputs
- [ ] `LemmingsOs.Artifacts` context module.
- [ ] `create_artifact/2` for trusted metadata creation.
- [ ] `get_artifact/2` with explicit scope and no global lookup.
- [ ] `list_artifacts_for_instance/2`.
- [ ] `list_artifacts_for_scope/2` using an opts keyword list and private multi-clause `filter_query/2`.
- [ ] `update_artifact_status/3`.
- [ ] Safe descriptor/read-model helper that omits storage refs and paths from normal public returns.
- [ ] Tests for scope enforcement and status filtering.

## Acceptance Criteria
- [ ] Every public API requires an explicit persisted hierarchy scope struct or validated scope map, with World boundary enforcement.
- [ ] Default list/get APIs only return `ready`.
- [ ] Any API that can include `archived`, `deleted`, or `error` must be named or optioned explicitly and covered by tests.
- [ ] Functions that can fail return `{:ok, value}` or `{:error, reason}`.
- [ ] Public non-trivial functions include `@doc` and `@spec`.
- [ ] Web code is not changed in this task.

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
*[Filled by executing agent after completion]*
