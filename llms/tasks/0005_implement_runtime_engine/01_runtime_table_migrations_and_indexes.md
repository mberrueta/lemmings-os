# Task 01: Runtime Table Migrations and Indexes

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-db-performance-architect` - database architect for migrations, indexes, relational integrity, and query-shape safety.

## Agent Invocation
Act as `dev-db-performance-architect` following `llms/constitution.md` and create the `lemming_instances` and `lemming_instance_messages` table migrations with foreign keys, indexes, and constraint review.

## Objective
Add the two durable runtime tables required by the first runtime slice:

- `lemming_instances` for runtime execution records
- `lemming_instance_messages` for immutable transcript entries

The instance table stores identity, hierarchy FKs, runtime status, frozen config snapshot, and temporal markers. The message table stores user and assistant transcript rows with provider metadata and token usage tracking. The initial user request is NOT stored on `lemming_instances`; it is persisted only as the first `lemming_instance_messages` row.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contracts #2 and #3, Task Sequence
- [ ] `priv/repo/migrations/20260324120000_create_lemmings.exs` - Migration style precedent

## Expected Outputs

- [ ] `priv/repo/migrations/YYYYMMDDHHMMSS_create_lemming_instances_and_messages.exs`
- [ ] Migration notes captured in the task execution summary

## Acceptance Criteria

### `lemming_instances`
- [ ] Table contains all columns from Frozen Contract #2:
  - `id` (binary_id PK)
  - `lemming_id` (FK to lemmings, NOT NULL, on_delete: :delete_all)
  - `world_id` (FK to worlds, NOT NULL, on_delete: :delete_all)
  - `city_id` (FK to cities, NOT NULL, on_delete: :delete_all)
  - `department_id` (FK to departments, NOT NULL, on_delete: :delete_all)
  - `status` (string, NOT NULL, default "created")
  - `config_snapshot` (map/jsonb, NOT NULL)
  - `started_at` (utc_datetime, nullable)
  - `stopped_at` (utc_datetime, nullable)
  - `last_activity_at` (utc_datetime, nullable)
  - `timestamps(type: :utc_datetime)`
- [ ] There is NO `initial_request` column
- [ ] Default status is `"created"`
- [ ] `config_snapshot` uses `:map` with `null: false`
- [ ] Temporal markers are nullable at DB level
- [ ] Indexes:
  - FK index on `lemming_instances(lemming_id)`
  - FK index on `lemming_instances(world_id)`
  - FK index on `lemming_instances(city_id)`
  - FK index on `lemming_instances(department_id)`
  - Composite index on `lemming_instances(lemming_id, status)`
  - Composite index on `lemming_instances(department_id, status)`

### `lemming_instance_messages`
- [ ] Table contains all columns from Frozen Contract #3:
  - `id` (binary_id PK)
  - `lemming_instance_id` (FK to lemming_instances, NOT NULL, on_delete: :delete_all)
  - `world_id` (FK to worlds, NOT NULL, on_delete: :delete_all)
  - `role` (string, NOT NULL)
  - `content` (text, NOT NULL)
  - `provider` (string, nullable)
  - `model` (string, nullable)
  - `input_tokens` (integer, nullable)
  - `output_tokens` (integer, nullable)
  - `total_tokens` (integer, nullable)
  - `usage` (map/jsonb, nullable)
  - `inserted_at` (utc_datetime)
- [ ] There is NO `updated_at` column
- [ ] `content` uses `:text` type
- [ ] `total_tokens` is included as a nullable integer
- [ ] `usage` is included as a nullable `:map`
- [ ] `timestamps(type: :utc_datetime, updated_at: false)` is used
- [ ] Indexes:
  - FK index on `lemming_instance_messages(lemming_instance_id)`
  - FK index on `lemming_instance_messages(world_id)`
  - Composite index on `lemming_instance_messages(lemming_instance_id, inserted_at)`

## Technical Notes

### Relevant Code Locations
```
priv/repo/migrations/20260324120000_create_lemmings.exs  # Style precedent
```

### Patterns to Follow
- UUID primary key: `primary_key: false` + `add :id, :binary_id, primary_key: true`
- FK references: `references(:table, type: :binary_id, on_delete: :delete_all)`
- Timestamps: `timestamps(type: :utc_datetime)`
- Message timestamps: `timestamps(type: :utc_datetime, updated_at: false)`
- JSONB column: `:map` type

### Constraints
- Do NOT add `initial_request` to `lemming_instances`
- Do NOT add `instance_ref`, `parent_instance_id`, or `last_checkpoint_at`
- Do NOT add `updated_at` to `lemming_instance_messages`
- `config_snapshot` has no default and must be explicitly set at insert
- `usage` must remain optional and application-agnostic

## Execution Instructions

### For the Agent
1. Read the Lemmings migration for style reference.
2. Create both migration files with timestamps after `20260324120000`.
3. Include all columns, FKs, and indexes from Frozen Contracts #2 and #3.
4. Verify there is no `initial_request` column in either migration.
5. Document any DB-level tradeoffs in the execution summary.

### For the Human Reviewer
1. Confirm all Frozen Contract #2 columns are present.
2. Confirm all Frozen Contract #3 columns are present, including `total_tokens` and `usage`.
3. Verify there is no `initial_request` column.
4. Verify FK cascade behavior matches project convention.
5. Verify the message migration uses immutable timestamps only.

---

## Execution Summary
*[Filled by executing agent after completion]*

### Work Performed
- Created a single migration file that adds both `lemming_instances` and `lemming_instance_messages`.
- Matched the table shapes, foreign keys, defaults, and indexes to the frozen runtime contract.
- Ran `mix precommit` and resolved the only issue by formatting the migration file.

### Outputs Created
- `priv/repo/migrations/20260326120000_create_lemming_instances_and_messages.exs`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| One migration file should own both runtime tables | The task explicitly requested a single migration for all DB changes in this PR. |
| `config_snapshot` must be set explicitly by application code | The contract requires no default so the frozen runtime config cannot be implicit. |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Kept only the contract-required indexes | Adding more composites or partial indexes would be premature without confirmed query demand. |
| Used `on_delete: :delete_all` on all hierarchy FKs | Matches the existing ownership model and keeps runtime records aligned with parent lifecycle deletes. |
| Left message rows without `updated_at` | The transcript table is append-only and immutable after insert. |

### Blockers Encountered
- None
- Formatting mismatch on the new migration - Resolved by running `mix format`.

### Questions for Human
- None

### Ready for Next Task
- [x] All outputs complete
- [x] Summary documented
- [x] Questions listed (if any)

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
