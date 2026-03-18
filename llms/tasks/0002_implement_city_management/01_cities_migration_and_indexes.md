# Task 01: Cities Migration and Indexes

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: None
- **Blocks**: Task 02

## Assigned Agent

`dev-db-performance-architect` - Database architect for schema design and performance.

## Agent Invocation

Use `dev-db-performance-architect` to design and implement the initial `cities` persistence layer for this issue.

## Objective

Add the `cities` migration with the minimal durable fields needed for the first real City foundation: explicit `world_id` scoping, full BEAM node identity, admin status, heartbeat timestamp, and split scoped config buckets.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] `docs/adr/0017-runtime-topology-city-execution-model.md`
- [ ] `docs/adr/0021-core-domain-schema.md`
- [ ] `docs/architecture.md`
- [ ] `priv/repo/migrations/20260316154848_create_worlds.exs`

## Expected Outputs

- [ ] `cities` migration
- [ ] FK to `worlds`
- [ ] unique constraints for `slug` and `node_name` per world
- [ ] indexes for status and `last_seen_at`
- [ ] split config columns for `limits_config`, `runtime_config`, `costs_config`, and `models_config`
- [ ] migration comment noting why `node_name` stores the full BEAM node identity and why `cities` does not persist the Erlang cookie

## Acceptance Criteria

- [ ] the migration introduces a real `cities` table
- [ ] `cities.world_id` has a real foreign key to `worlds.id`
- [ ] deleting a world cascades to its cities
- [ ] `node_name` is persisted as the full BEAM node identity in `name@host` form
- [ ] `host`, `distribution_port`, and `epmd_port` are nullable hints, not required identity fields
- [ ] `status` and `last_seen_at` are stored separately
- [ ] the migration does not store distributed Erlang cookies or other secrets
- [ ] the migration does not add fake topology fields such as decorative regions or coordinates
- [ ] indexes and constraints are explicit and reviewable
- [ ] DB enforcement stays limited to referential integrity and core uniqueness guarantees
- [ ] the migration does not overreach into Department or Lemming persistence

## Technical Notes

### Relevant Code Locations

- `priv/repo/migrations/`
- `lib/lemmings_os/world.ex`
- `docs/adr/0017-runtime-topology-city-execution-model.md`
- `docs/adr/0021-core-domain-schema.md`

### Constraints

- Keep scope to `City`
- Match the `World` migration style
- Use `:binary_id`
- Keep config storage split by bucket
- Treat `last_seen_at` as operational metadata only
- Do not introduce auto-registration semantics into the persistence model
- Keep referential integrity in the database for hierarchy ownership
- Use a foreign key from `cities.world_id` to `worlds.id`
- Use cascade delete from `worlds` to `cities`
- Avoid adding further business-policy constraints beyond ownership and identity guarantees

## Execution Instructions

### For the Agent

1. Read the plan and listed ADRs first.
2. Implement the `cities` table exactly to the frozen shape in the plan unless a concrete blocker forces a change.
3. Keep indexes focused on real query paths: world-scoped lookup, node identity, admin state, and stale-city queries.
4. Record any assumption about future hierarchy expansion in the task summary.

### For the Human Reviewer

1. Review the chosen columns and indexes carefully.
2. Confirm `node_name` is frozen as full `name@host`.
3. Confirm no secret-bearing or fake-UI-support fields slipped into the migration.
4. Approve before Task 02 begins.
