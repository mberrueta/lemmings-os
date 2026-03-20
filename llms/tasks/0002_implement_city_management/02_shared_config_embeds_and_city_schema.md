# Task 02: Shared Config Embeds and City Schema

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 01
- **Blocks**: Task 03, Task 05

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to introduce the shared config bucket types and the `LemmingsOs.City` schema.

## Objective

Make City schema-backed, reuse the same four scoped config shapes across `World` and `City`, and freeze the schema-level contract for full BEAM node identity, admin status, and local override config.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] `llms/tasks/0002_implement_city_management/01_cities_migration_and_indexes.md`
- [ ] `lib/lemmings_os/world.ex`
- [ ] `docs/adr/0020-hierarchical-configuration-model.md`
- [ ] `docs/adr/0021-core-domain-schema.md`
- [ ] `llms/constitution.md`

## Expected Outputs

- [ ] shared config modules or embed types for `limits_config`, `runtime_config`, `costs_config`, and `models_config`
- [ ] narrow `World` typing updates if required to share those shapes
- [ ] `LemmingsOs.City` schema
- [ ] `City.changeset/2`
- [ ] City status helpers such as `statuses/0`, `status_options/0`, and `translate_status/1`
- [ ] schema tests

## Acceptance Criteria

- [ ] `City` persists the four scoped config buckets using the shared World/City config shapes
- [ ] `node_name` is validated as full `name@host`, not a shorthand label
- [ ] `status` is validated as admin/lifecycle state only
- [ ] `last_seen_at` is not treated as declarative config
- [ ] `world_id` is not modeled as user-cast form input
- [ ] the task does not broaden into a general config redesign beyond the four frozen buckets

## Technical Notes

### Relevant Code Locations

- `lib/lemmings_os/world.ex`
- `lib/lemmings_os/`
- `test/lemmings_os/`

### Constraints

- Follow constitution rules for `@required` / `@optional`
- Internationalize validation messages
- Keep any `World` refactor limited to sharing the four config shapes
- Do not add Department/Lemming associations unless directly useful now

## Execution Instructions

### For the Agent

1. Read the plan and World schema first.
2. Introduce the smallest shared config typing layer that satisfies the frozen World/City contract.
3. Add the City schema with explicit admin-state and identity validation.
4. Record whether any narrow World typing changes were required.

### For the Human Reviewer

1. Confirm the shared config approach stayed narrow.
2. Confirm `node_name` validation is explicit.
3. Confirm the schema did not conflate admin status with liveness.
4. Approve before Task 03 and Task 05 begin.

