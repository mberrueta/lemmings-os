# Task 02: Knowledge Items Migration And Indexes

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-db-performance-architect` - Database architect for schema design, constraints, and indexes.

## Agent Invocation
Act as `dev-db-performance-architect`. Implement the database foundation for memory-backed Knowledge items in line with `plan.md` and existing migration style.

## Objective
Create the migration(s) for the shared Knowledge item persistence model with memory-first defaults, referential integrity, and query-friendly indexes.

## Inputs Required
- [ ] `llms/tasks/0013_memory_store/plan.md`
- [ ] Existing migrations for `connections`, `secret_bank_secrets`, `artifacts`, and `events`
- [ ] `llms/coding_styles/elixir.md`

## Expected Outputs
- [ ] `knowledge_items` table migration with memory-compatible fields and query-friendly structure.
- [ ] Foreign keys for hierarchy references and future `artifact_id`.
- [ ] Required not-null constraints for stable persistence fields.
- [ ] Indexes for exact-scope CRUD and inherited listing queries.
- [ ] No DB enum/check constraints for product values such as `source`, `status`, or `kind`.

## Acceptance Criteria
- [ ] Model stores `world_id`, optional `city_id`, optional `department_id`, optional `lemming_id`, `title`, `content`, `tags`, `source`, `status`, and creator metadata.
- [ ] Internal discriminator (`kind` or `category`) defaults to memory at the schema/context layer.
- [ ] FK constraints preserve valid references.
- [ ] Product-state validation lives in Ecto changesets/context APIs, not DB check constraints.
- [ ] Indexes support default ordering plus search/filter pagination access paths.
- [ ] Migration does not introduce out-of-scope file/RAG columns beyond nullable `artifact_id`.

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
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
