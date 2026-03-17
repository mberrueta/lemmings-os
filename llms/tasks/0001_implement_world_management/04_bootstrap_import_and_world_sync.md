# Task 04: Bootstrap Import and World Sync

## Status

- **Status**: COMPLETE
- **Approved**: [x]
- **Blocked by**: Task 03
- **Blocks**: Task 05

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to connect bootstrap YAML ingestion to the persisted `World` domain.

## Objective

Create the importer/sync flow that loads bootstrap YAML, validates it, and creates or updates the persisted `World` record as part of application startup.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] `llms/tasks/0001_implement_world_management/03_bootstrap_yaml_loader_and_shape_validation.md`
- [ ] Task 02 and Task 03 implementation outputs
- [ ] `lib/lemmings_os/application.ex`

## Expected Outputs

- [ ] `LemmingsOs.WorldBootstrap.Importer` or `Sync`
- [ ] domain-facing import/upsert integration with `Worlds`
- [ ] application startup integration for bootstrap import
- [ ] persisted bootstrap/import metadata as justified
- [ ] explicit distinction between immediate import result and persisted last sync status
- [ ] tests covering create, update, invalid bootstrap input, and import failure behavior

## Acceptance Criteria

- [ ] Bootstrap YAML can create or update the persisted `World`
- [ ] application startup attempts bootstrap import for the default world in this issue
- [ ] Immediate import result is exposed as a normalized operation outcome
- [ ] Last sync status is represented as persisted or queryable state separate from the immediate import result
- [ ] Persisted world identity becomes the durable basis for later read models
- [ ] Failures remain explicit and do not silently fall back to mock data
- [ ] This task does not attempt to add import history beyond the current-state metadata needed on `worlds`

## Technical Notes

### Relevant Code Locations

- `lib/lemmings_os/`
- `lib/lemmings_os/application.ex`
- `test/`

### Constraints

- No full ADR-0020 resolver stack
- Import behavior should not be mistaken for full hierarchical config resolution
- Bootstrap import in this issue must not implement hierarchical merge semantics, policy resolution, or cross-scope inheritance behavior
- Do not introduce multi-source or import-history modeling here; if needed later, that should be a separate table/design
- For this issue, prefer unconditional startup create-or-update sync over file mtime comparison or selective merge heuristics

## Execution Instructions

### For the Agent

1. Keep persisted `World` as the center and bootstrap as input.
2. Implement startup import as the default path for this issue, including `Application` wiring or equivalent supervised startup behavior.
3. Use idempotent create-or-update semantics for the persisted default world.
4. Record the boot-time import behavior clearly in the summary.

### For the Human Reviewer

1. Confirm the direction is domain-centered, not YAML-centered.
2. Review import/update semantics carefully.
3. Approve before Task 05 begins.
