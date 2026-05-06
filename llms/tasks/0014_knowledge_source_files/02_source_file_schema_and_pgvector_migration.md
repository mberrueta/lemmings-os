# Task 02: Source File Schema And pgvector Migration

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-db-performance-architect` - Database architect for schema design, constraints, indexes, and Postgres performance.

## Agent Invocation
Act as `dev-db-performance-architect`. Implement database changes for source-file Knowledge, chunk storage, and pgvector retrieval.

## Objective
Add migrations and schema-level persistence structure for source-file Knowledge, including vector-ready chunk indexing with the locked MVP defaults.

## Inputs Required
- [ ] Task 01 approved scenario matrix
- [ ] `llms/tasks/0014_knowledge_source_files/plan.md`
- [ ] Existing `knowledge_items` migration/schema/context

## Expected Outputs
- [ ] Migration updates for source-file-compatible `knowledge_items` behavior.
- [ ] New source-file metadata table.
- [ ] New chunk table with vector column and indexes.
- [ ] pgvector extension/migration support with fixed initial dimension `1536`.

## Acceptance Criteria
- [ ] Source-file rows do not require `artifact_id`.
- [ ] Index strategy supports scope-safe retrieval, status filtering, and vector search.
- [ ] DB design supports ready-only retrieval without full-text/content leakage defaults.
- [ ] Migration approach is compatible with existing memory behavior.

## Constraints
- No business logic implementation in this task.
- Do not introduce external vector DB dependencies.

## Approval Gate
Human reviewer must approve this task before Task 03 begins.

## Human Review
*[Filled by human reviewer]*
