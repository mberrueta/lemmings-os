# Task 01: Worlds Migration

## Status

- **Status**: ⏳ PENDING
- **Approved**: [ ]
- **Blocked by**: None
- **Blocks**: Task 02

## Assigned Agent

`dev-db-performance-architect` - Database architect for schema design and performance.

## Agent Invocation

Use `dev-db-performance-architect` to design and implement the initial `worlds` persistence layer for this issue.

## Objective

Add the `worlds` migration with the minimal durable fields needed for this issue’s persisted `World` foundation, using normal identity/bootstrap/import columns plus scoped JSONB config columns.

## Inputs Required

- [ ] `llms/tasks/0001_implement_world_management/plan.md`
- [ ] `docs/adr/0002-agent-hierarchy-model.md`
- [ ] `docs/adr/0021-core-domain-schema.md`
- [ ] `priv/repo/migrations/`

## Expected Outputs

- [ ] `worlds` migration
- [ ] normal columns for identity, bootstrap linkage, and import metadata
- [ ] scoped JSONB columns for `limits_config`, `runtime_config`, `costs_config`, and `models_config`
- [ ] migration comment noting why scoped JSONB columns are preferred over the previously considered single `config_jsonb` approach
- [ ] Chosen persisted fields documented in the task summary
- [ ] Indexes and constraints appropriate for the initial `World` scope

## Acceptance Criteria

- [ ] The migration introduces a real `worlds` table
- [ ] The table supports at least durable world identity for this issue
- [ ] The table uses scoped JSONB config columns instead of a single giant `config` blob
- [ ] Scoped JSONB columns store world-level declarative config only, not runtime-derived state or full bootstrap payload dumps
- [ ] The migration does not persist `tools_config` or `cities_config`
- [ ] Bootstrap linkage columns on `worlds` are limited to current-state operational metadata, not import-history modeling
- [ ] The migration does not overreach into full hierarchy persistence
- [ ] World identity and lookup constraints are explicit and reviewable
- [ ] The migration includes a code comment capturing that this design is preferred over the previously considered single `config_jsonb` option

## Technical Notes

### Relevant Code Locations

- `priv/repo/migrations/`
- `docs/adr/0021-core-domain-schema.md`

### Constraints

- Keep scope to `World`
- Do not add `City` / `Department` / `Lemming` persistence unless strictly required
- Keep bootstrap metadata minimal and justified
- Do not collapse declarative world config into a single catch-all JSONB blob
- Scoped JSONB columns are for world-level declarative config only
- Do not persist parser warnings, runtime snapshots, tool installation state, or full bootstrap payload dumps inside scoped config JSONB columns
- Do not persist tool installation/effective tool state in `worlds`
- Do not turn `worlds` into an import-history table; if multiple sources or sync history are needed later, that should become a separate table
- Leave an implementation comment in the migration explaining why split JSONB columns are preferred over the previously considered single `config_jsonb` option

## Execution Instructions

### For the Agent

1. Read the plan and ADRs first.
2. Use the plan’s recommended `worlds` column split unless a concrete blocker forces a change.
3. Add indexes/constraints that align with world identity and retrieval.
4. Record assumptions about future hierarchy expansion.

### For the Human Reviewer

1. Review the chosen fields carefully.
2. Confirm the migration is minimal but real.
3. Approve before Task 02 begins.
