# Task 02: World Schema and Context

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 01
- **Blocks**: Task 03

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to add the persisted `World` schema and domain boundary.

## Objective

Introduce the persisted `World` schema and the `Worlds` domain/context APIs that the rest of this issue will build on.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] `llms/tasks/0001_implement_world_management/01_worlds_migration.md`
- [ ] Task 01 implementation output
- [ ] `llms/project_context.md`

## Expected Outputs

- [ ] `World` schema
- [ ] `Worlds` context/boundary
- [ ] minimum retrieval and bootstrap-facing APIs such as `get_world!/1`, `get_default_world/0`, and bootstrap upsert/import entrypoint or equivalent
- [ ] schema comment or moduledoc note reinforcing that scoped JSONB columns are intentional and preferable to a single `config_jsonb` dump for this issue
- [ ] schema/context tests

## Acceptance Criteria

- [ ] `World` is now a real persisted domain concept
- [ ] The web layer can depend on the context instead of raw bootstrap YAML
- [ ] Context APIs return tuples where failure is possible
- [ ] Tests cover schema and core retrieval behavior

## Technical Notes

### Relevant Code Locations

- `lib/lemmings_os/`
- `test/`
- `test/support/data_case.ex`

### Constraints

- World domain first, no UI work here
- Naming should clearly represent persisted domain ownership
- Keep scope tight to what this issue needs
- Capture the split-JSONB rationale in schema comments or moduledoc, not only in ADR follow-up

## Execution Instructions

### For the Agent

1. Build the persisted `World` boundary on top of Task 01.
2. Keep public APIs small and explicit.
3. Add documentation to important public functions.
4. Record any naming tradeoffs in the summary.

### For the Human Reviewer

1. Confirm the domain boundary is real and not just a helper layer.
2. Review context API shape and naming.
3. Approve before Task 03 begins.
