# Task 05: Config Resolver and Effective Config Merge

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 02
- **Blocks**: Task 07, Task 08

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to implement `LemmingsOs.Config.Resolver` and the shared `World -> City` effective-config contract.

## Objective

Centralize effective configuration resolution in one pure in-memory module so schemas, LiveViews, and page snapshots stop duplicating merge behavior.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] `llms/tasks/0002_implement_city_management/02_shared_config_embeds_and_city_schema.md`
- [ ] `lib/lemmings_os/world.ex`
- [ ] `docs/adr/0020-hierarchical-configuration-model.md`

## Expected Outputs

- [ ] `LemmingsOs.Config.Resolver`
- [ ] `resolve(%World{} = world)`
- [ ] `resolve(%City{world: %World{}} = city)`
- [ ] resolver tests
- [ ] merge helpers required by the resolver contract

## Acceptance Criteria

- [ ] the resolver performs no DB access
- [ ] callers must provide preloaded parent chains
- [ ] child overrides parent
- [ ] output is a plain map containing effective config structs for the four buckets
- [ ] no trace, source metadata, or explain output is introduced

## Technical Notes

### Relevant Code Locations

- `lib/lemmings_os/world.ex`
- `lib/lemmings_os/`
- `test/lemmings_os/`

### Constraints

- Keep merge semantics intentionally simple
- Do not push merge logic into schemas or HEEx templates
- Do not implement governance semantics beyond the current issue

## Execution Instructions

### For the Agent

1. Read the resolver contract in the plan carefully.
2. Implement the smallest pure module that satisfies the frozen behavior.
3. Add tests for both `World` and `City` resolution paths.
4. Record any preload assumptions downstream tasks must honor.

### For the Human Reviewer

1. Confirm the resolver stays pure and centralized.
2. Confirm the output contract is plain and reusable.
3. Confirm there is no hidden query or trace behavior.
4. Approve before Task 07 and Task 08 begin.
