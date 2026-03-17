# Task 06: World Snapshot and Runtime Checks

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: Task 05
- **Blocks**: Task 07

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to build the World read model on top of persisted domain state plus bootstrap/runtime signals.

## Objective

Create the `WorldPageSnapshot`-style read model that separates persisted world identity, declared bootstrap config, immediate import result, last sync status, and runtime health checks.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] `llms/tasks/0001_implement_world_management/05_world_cache_layer.md`
- [ ] Task 04 and Task 05 implementation outputs
- [ ] `config/runtime.exs`
- [ ] `lib/lemmings_os/application.ex`

## Expected Outputs

- [ ] world snapshot builder/read model
- [ ] explicit separation between immediate import result and last sync status in the snapshot contract
- [ ] runtime checks aligned to the frozen status taxonomy
- [ ] tests covering `ok`, `degraded`, `unavailable`, `invalid`, and `unknown` outputs

## Acceptance Criteria

- [ ] The snapshot clearly separates persisted domain, bootstrap config, immediate import result, last sync status, and runtime health
- [ ] Runtime checks are cheap and explicit
- [ ] Missing runtime sources become `unavailable` or `unknown`, not fake precision

## Technical Notes

### Relevant Code Locations

- `lib/lemmings_os/`
- `config/runtime.exs`
- `test/`

### Constraints

- No raw Ecto structs or raw YAML maps in the web layer
- Keep health probes lightweight

## Execution Instructions

### For the Agent

1. Build an operator-facing snapshot, not a raw composition map.
2. Apply the frozen status taxonomy exactly.
3. Record any deferred runtime sources explicitly.

### For the Human Reviewer

1. Confirm the snapshot is trustworthy and compositional.
2. Confirm runtime checks are safe to run.
3. Approve before Task 07 begins.
