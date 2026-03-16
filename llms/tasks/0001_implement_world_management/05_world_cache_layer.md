# Task 05: World Cache Layer

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 04
- **Blocks**: Task 06

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to add the dedicated cache layer for stable `World` reads.

## Objective

Introduce a narrow cache for persisted `World` reads so the app does not hit the database for every stable world lookup or snapshot input.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] `llms/tasks/0001_implement_world_management/04_bootstrap_import_and_world_sync.md`
- [ ] Task 02 and Task 04 implementation outputs

## Expected Outputs

- [ ] dedicated cache layer for `World` reads
- [ ] explicit invalidation/refresh behavior on startup bootstrap import/sync and any manual refresh path
- [ ] tests covering cache hit/miss and invalidation behavior
- [ ] any dependency/config additions required for the chosen cache approach

## Acceptance Criteria

- [ ] cache scope stays narrow to persisted `World` reads and related snapshot inputs
- [ ] cache does not become the primary source of truth
- [ ] cache invalidation is explicit on startup import/sync and refresh paths
- [ ] this task does not expand into a general config resolver cache

## Technical Notes

### Relevant Code Locations

- `lib/lemmings_os/`
- `config/`
- `mix.exs`
- `test/`

### Constraints

- Prefer a simple, explicit cache design
- Do not cache unresolved policy or cross-scope behavior
- Keep stale-data risk visible and controlled

## Execution Instructions

### For the Agent

1. Add the smallest viable cache layer for `World`.
2. Make invalidation explicit rather than magical, especially around startup import.
3. Document whether the cache stores only world retrievals or also snapshot inputs.

### For the Human Reviewer

1. Confirm the cache scope is narrow and justified.
2. Confirm invalidation behavior is understandable.
3. Approve before Task 06 begins.
