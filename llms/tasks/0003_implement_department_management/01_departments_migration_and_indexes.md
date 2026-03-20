# Task 01: Departments Migration and Indexes

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off
- **Blocked by**: None
- **Blocks**: Task 02, Task 03
- **Estimated Effort**: M

## Assigned Agent
`dev-db-performance-architect` - database architect for migrations, indexes, relational integrity, and query-shape safety.

## Objective
Add the `departments` table with the agreed ownership, lifecycle, metadata, config buckets, and indexing strategy, without overreaching into runtime or stats concerns.

## Expected Outputs

- [x] new migration creating `departments`
- [x] FK, unique index, and supporting indexes aligned with the plan
- [x] migration notes captured in the task summary, including any DB-level tradeoffs

## Acceptance Criteria

- [x] `departments` contains `world_id`, `city_id`, `slug`, `name`, `status`, `notes`, `tags`, four config buckets, and timestamps
- [x] `slug` uniqueness is enforced on `[:city_id, :slug]`
- [x] `tags` defaults to `[]`
- [x] migration does not add fake stats fields, runtime counters, or geometry columns
- [x] migration is compatible with existing `worlds` / `cities` persistence conventions

## Execution Summary

### Work Performed
- Reviewed the approved Department persistence contract in the plan and task file.
- Inspected `worlds` and `cities` schemas and migrations to match UUID, timestamp, JSONB bucket, FK, and index conventions.
- Added a new `departments` migration with explicit `world_id` and `city_id` ownership, lifecycle metadata, tags, notes, and four config buckets.
- Added the requested unique and supporting indexes while leaving status validation at the application layer.

### Outputs Created
- `priv/repo/migrations/20260320120000_create_departments.exs`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| `status` should default to `active` | `cities` already defaults administrative status to `active` and Department should follow the same persistence convention |
| `notes` should remain unconstrained at the DB layer for now | The plan requires only a bounded application-level limit, but does not freeze an exact max length yet |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Kept Department status validation at the application layer | Adding a DB check constraint for status values | Matches the approved follow-up to avoid DB-level validation in this branch |
| Kept `notes` as nullable `:text` without a DB length check | `:string`, or `CHECK (char_length(notes) <= N)` | Avoids prematurely freezing a limit before Task 02 defines the exact changeset validation contract |
| Added `world_id`, `city_id`, `[:city_id, :slug]`, and `[:world_id, :city_id, :status]` indexes | Only composite indexes, or fewer supporting indexes | Matches the approved plan’s minimum query and FK support strategy without adding speculative indexes |

### Blockers Encountered
- None

### Questions for Human
1. None.
