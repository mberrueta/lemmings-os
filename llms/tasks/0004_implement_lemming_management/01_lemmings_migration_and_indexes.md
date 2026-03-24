# Task 01: Lemmings Migration and Indexes

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off
- **Blocked by**: None
- **Blocks**: Task 03
- **Estimated Effort**: M

## Assigned Agent
`dev-db-performance-architect` - database architect for migrations, indexes, relational integrity, and query-shape safety.

## Agent Invocation
Act as `dev-db-performance-architect` following `llms/constitution.md` and create the `lemmings` table migration with foreign keys, indexes, and constraint review.

## Objective
Add the `lemmings` table with the agreed ownership columns (`world_id`, `city_id`, `department_id`), metadata fields (`slug`, `name`, `description`, `instructions`, `status`), five config buckets (the four existing plus `tools_config`), and the indexing strategy from the frozen contract.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/tasks/0004_implement_lemming_management/plan.md` - Spec and frozen contracts (sections: Frozen Contracts, Recommended Table Shape, Recommended Indexes/Constraints, Recommended Migration Notes)
- [ ] `priv/repo/migrations/20260320120000_create_departments.exs` - Migration convention precedent

## Expected Outputs

- [ ] New migration file: `priv/repo/migrations/YYYYMMDDHHMMSS_create_lemmings.exs`
- [ ] Migration notes captured in the task execution summary

## Acceptance Criteria

- [ ] `lemmings` table contains all columns from the frozen contract:
  - `id` (binary_id PK)
  - `world_id` (FK to worlds, NOT NULL, on_delete: :delete_all)
  - `city_id` (FK to cities, NOT NULL, on_delete: :delete_all)
  - `department_id` (FK to departments, NOT NULL, on_delete: :delete_all)
  - `slug` (string, NOT NULL)
  - `name` (string, NOT NULL)
  - `description` (text, nullable)
  - `instructions` (text, nullable)
  - `status` (string, NOT NULL, default "draft")
  - `limits_config` (map/jsonb, NOT NULL, default %{})
  - `runtime_config` (map/jsonb, NOT NULL, default %{})
  - `costs_config` (map/jsonb, NOT NULL, default %{})
  - `models_config` (map/jsonb, NOT NULL, default %{})
  - `tools_config` (map/jsonb, NOT NULL, default %{})
  - `timestamps(type: :utc_datetime)`
- [ ] Indexes match the frozen contract:
  - FK index on `lemmings(world_id)`
  - FK index on `lemmings(city_id)`
  - FK index on `lemmings(department_id)`
  - Unique index on `lemmings(department_id, slug)`
  - Composite index on `lemmings(world_id, city_id, department_id, status)`
- [ ] Default status is `"draft"` (not `"active"` -- Lemmings are definitions, not operational units)
- [ ] Migration follows the exact style of `20260320120000_create_departments.exs`
- [ ] Migration does NOT add runtime fields (`agent_module`, `started_at`, `stopped_at`, etc.)
- [ ] `description` and `instructions` use `:text` type (unbounded text)

## Technical Notes

### Relevant Code Locations
```
priv/repo/migrations/20260320120000_create_departments.exs  # Style precedent
priv/repo/migrations/20260318120000_create_cities.exs        # Earlier precedent
```

### Patterns to Follow
- UUID primary key: `primary_key: false` + `add :id, :binary_id, primary_key: true`
- FK references: `references(:table, type: :binary_id, on_delete: :delete_all)`
- Config buckets: `:map` type with `null: false, default: %{}`
- Timestamps: `timestamps(type: :utc_datetime)`

### Constraints
- Do NOT add status validation at the DB level (application layer owns this)
- Do NOT add `tags` or `notes` field aliasing from Department -- Lemmings have different metadata
- `description` is nullable at DB level (optional field)
- `instructions` is nullable at DB level (draft lemmings may lack instructions)

## Execution Instructions

### For the Agent
1. Read the Department migration for style reference.
2. Create the migration file with a timestamp after `20260320120000`.
3. Include all columns, FKs, and indexes from the frozen contract.
4. Add a comment noting that `tools_config` is the fifth bucket unique to Lemmings in this issue.
5. Document any DB-level tradeoffs in the execution summary.

### For the Human Reviewer
1. Confirm all frozen contract columns are present.
2. Verify FK cascade behavior matches Department convention (`:delete_all`).
3. Reject if runtime fields are included.
4. Reject if default status is anything other than `"draft"`.

---

## Execution Summary
*[Filled by executing agent after completion]*

### Work Performed
- [What was actually done]

### Outputs Created
- [List of files/artifacts created]

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|

### Blockers Encountered
- [Blocker 1] - Resolution: [How resolved or "Needs human input"]

### Questions for Human
1. [Question needing human input]

### Ready for Next Task
- [ ] All outputs complete
- [ ] Summary documented
- [ ] Questions listed (if any)

---

## Human Review
*[Filled by human reviewer]*

### Review Date
[YYYY-MM-DD]

### Decision
- [ ] APPROVED - Proceed to next task
- [ ] REJECTED - See feedback below

### Feedback

### Git Operations Performed
```bash
# human-only
```
