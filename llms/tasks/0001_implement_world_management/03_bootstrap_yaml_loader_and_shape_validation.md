# Task 03: Bootstrap YAML Loader and Shape Validation

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: Task 02
- **Blocks**: Task 04

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to implement bootstrap YAML loading and frozen shape validation.

## Objective

Add `default.world.yaml`, path resolution, YAML loading, and frozen bootstrap shape validation as ingestion input to the domain.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] `llms/tasks/0001_implement_world_management/02_world_schema_and_context.md`
- [ ] Task 02 implementation output
- [ ] `config/runtime.exs`
- [ ] `mix.exs`

## Expected Outputs

- [ ] shipped `default.world.yaml`
- [ ] `LemmingsOs.WorldBootstrap.PathResolver`
- [ ] `LemmingsOs.WorldBootstrap.Loader`
- [ ] `LemmingsOs.WorldBootstrap.ShapeValidator`
- [ ] path resolution contract using `LEMMINGS_WORLD_BOOTSTRAP_PATH` with fallback to `priv/default.world.yaml`
- [ ] unit tests for valid, invalid, missing, and warning-producing YAML inputs

## Acceptance Criteria

- [ ] The bootstrap YAML shape matches the frozen contract
- [ ] Path resolution checks `LEMMINGS_WORLD_BOOTSTRAP_PATH` first and otherwise resolves the shipped default world file
- [ ] Unknown extra keys produce warnings
- [ ] Raw parser errors are normalized before leaving the bootstrap layer
- [ ] This task does not treat YAML as the final system-of-record

## Technical Notes

### Relevant Code Locations

- `config/runtime.exs`
- `priv/`
- `lib/lemmings_os/`
- `test/`

### Constraints

- Bootstrap only as ingestion input
- Keep validation naming clearly non-canonical
- Record any YAML parser decision explicitly
- Bootstrap loading in this issue must not implement hierarchical merge semantics, policy resolution, or cross-scope inheritance behavior

## Execution Instructions

### For the Agent

1. Reuse the frozen YAML shape exactly.
2. Normalize warnings and invalid states using the plan’s frozen warning structure.
3. Keep the outputs ready for import/sync in Task 04.
4. Use `LEMMINGS_WORLD_BOOTSTRAP_PATH` as the bootstrap override env var and document the fallback path resolution clearly.

### For the Human Reviewer

1. Review the bootstrap contract implementation carefully.
2. Confirm warning output is operator-safe.
3. Approve before Task 04 begins.
