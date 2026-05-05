# Task 02: Knowledge Items Migration And Indexes

## Status
- **Status**: COMPLETE
- **Approved**: [x] Human sign-off

## Assigned Agent
`dev-db-performance-architect` - Database architect for schema design, constraints, and indexes.

## Agent Invocation
Act as `dev-db-performance-architect`. Implement the database foundation for memory-backed Knowledge items in line with `plan.md` and existing migration style.

## Objective
Create the migration(s) for the shared Knowledge item persistence model with memory-first defaults, referential integrity, and query-friendly indexes.

## Inputs Required
- [x] `llms/tasks/0013_memory_store/plan.md`
- [x] Existing migrations for `connections`, `secret_bank_secrets`, `artifacts`, and `events`
- [x] `llms/coding_styles/elixir.md`

## Expected Outputs
- [x] `knowledge_items` table migration with memory-compatible fields and query-friendly structure.
- [x] Foreign keys for hierarchy references and future `artifact_id`.
- [x] Required not-null constraints for stable persistence fields.
- [x] Indexes for exact-scope CRUD and inherited listing queries.
- [x] No DB enum/check constraints for product values such as `source`, `status`, or `kind`.

## Acceptance Criteria
- [x] Model stores `world_id`, optional `city_id`, optional `department_id`, optional `lemming_id`, `title`, `content`, `tags`, `source`, `status`, and creator metadata.
- [x] Internal discriminator (`kind` or `category`) defaults to memory at the schema/context layer.
- [x] FK constraints preserve valid references.
- [x] Product-state validation lives in Ecto changesets/context APIs, not DB check constraints.
- [x] Indexes support default ordering plus search/filter pagination access paths.
- [x] Migration does not introduce out-of-scope file/RAG columns beyond nullable `artifact_id`.

## Technical Notes
### Constraints
- Follow current UUID/FK/index conventions in this repo.
- Use `:string` columns per repo convention; avoid new enum dependencies.
- Keep DB constraints focused on referential integrity and structural stability rather than product-state enums.

### Scope Boundaries
- No file upload, chunking, pgvector, semantic search, or archive lifecycle in this task.

## Execution Instructions
### For the Agent
1. Implement minimal migration shape needed by plan FR/NFR requirements.
2. Document index rationale in task execution summary.
3. Run narrow migration/tests checks relevant to schema compile and constraint behavior.

### For the Human Reviewer
1. Verify defaults, FK integrity, and required not-null constraints align with the plan.
2. Verify indexes are sufficient but not overbuilt for MVP.

## Execution Summary
### Work Performed
- Added migration: `priv/repo/migrations/20260504120000_create_knowledge_items.exs`.
- Created `knowledge_items` with:
  - Hierarchy scope FKs: `world_id` (required), optional `city_id`, `department_id`, `lemming_id`.
  - Memory fields: `kind`, `title`, `content`, `tags`, `source`, `status`.
  - Future-proof nullable `artifact_id` FK.
  - Creator metadata fields: `creator_type`, `creator_id`, plus optional FKs to creator `lemming`, `lemming_instance`, and `tool_execution`.
- Added structural scope-shape check constraint for valid hierarchy combinations.
- Added indexes for FK joins plus scope-aware pagination/filter paths:
  - `world/source/status/inserted_at/id`.
  - Partial scope feed indexes for world, city, department, and lemming ownership shapes.

### Validation
- Ran `mix format priv/repo/migrations/20260504120000_create_knowledge_items.exs`.
- Ran `mix ecto.migrate` successfully (migration applied).
- Ran `mix precommit` successfully.

### Notes
- No DB enum/check constraints were introduced for `source`, `status`, or `kind`; these remain for schema/context validation.

## Human Review
*[Filled by human reviewer]*
