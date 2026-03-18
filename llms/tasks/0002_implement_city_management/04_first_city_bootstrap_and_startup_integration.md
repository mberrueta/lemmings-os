# Task 04: First-City Bootstrap and Startup Integration

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: Task 03
- **Blocks**: Task 06, Task 10

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to wire first-city creation and runtime presence into the world/bootstrap startup flow.

## Objective

Define and integrate the canonical startup/runtime identity contract for this issue.

This task covers the narrow startup path where the first city is bootstrap-created or matched, and the local runtime attaches its presence and identity to persisted City data. It is not a general provisioning or runtime-management task.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] `llms/tasks/0002_implement_city_management/03_cities_context_and_crud_apis.md`
- [ ] `lib/lemmings_os/application.ex`
- [ ] `lib/lemmings_os/world_bootstrap/importer.ex`
- [ ] `lib/lemmings_os/worlds.ex`

## Expected Outputs

- [ ] startup integration for first-city upsert/attach
- [ ] explicit runtime env contract for full BEAM `node_name`
- [ ] integration with the existing world bootstrap/import path
- [ ] startup tests covering success and honest failure behavior

## Acceptance Criteria

- [ ] startup resolves the persisted default world first
- [ ] the first city is created or updated during the same startup path
- [ ] runtime nodes upsert presence/identity against persisted city rows
- [ ] the branch does not reframe the design as automatic city discovery
- [ ] startup fails honestly if the world cannot be resolved

## Technical Notes

### Relevant Code Locations

- `lib/lemmings_os/application.ex`
- `lib/lemmings_os/world_bootstrap/importer.ex`
- `config/runtime.exs`
- `config/dev.exs`

### Constraints

- Keep this local-node only
- Do not require distributed Erlang membership management
- Freeze `node_name` as full `name@host`
- Do not persist cookies or secret material
- Later demo/container tasks must consume the runtime identity contract defined here rather than redefine it
- Keep this task focused on startup identity and presence, not general runtime management

## Execution Instructions

### For the Agent

1. Read the plan sections on City creation model and runtime identity first.
2. Integrate with the existing world bootstrap path rather than creating a separate startup subsystem.
3. Keep the runtime contract explicit and env-driven.
4. Treat this task as the canonical definition point for runtime identity semantics used by later tasks.
5. Document any unresolved edge around operator-created cities versus startup matching.

### For the Human Reviewer

1. Confirm the startup flow preserves the intended product model.
2. Confirm no hidden auto-discovery semantics were introduced.
3. Confirm the `node_name` env/runtime contract is explicit and reviewable.
4. Approve before Task 06 and Task 10 begin.
