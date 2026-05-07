# Task 02: Source File Schema And pgvector Migration

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-db-performance-architect` - Database architect for schema design, constraints, indexes, and Postgres performance.

## Agent Invocation
Act as `dev-db-performance-architect`. Implement database changes for source-file Knowledge, chunk storage, and pgvector retrieval.

## Objective
Add migrations and schema-level persistence structure for source-file Knowledge, including vector-ready chunk indexing with the locked MVP defaults.

## Inputs Required
- [x] Task 01 approved scenario matrix
- [x] `llms/tasks/0014_knowledge_source_files/plan.md`
- [x] Existing `knowledge_items` migration/schema/context

## Expected Outputs
- [x] Migration updates for source-file-compatible `knowledge_items` behavior.
- [x] New source-file metadata table.
- [x] New chunk table with vector column and indexes.
- [x] pgvector extension/migration support with fixed initial dimension `1536`.

## Acceptance Criteria
- [x] Source-file rows do not require `artifact_id`.
- [x] Index strategy supports scope-safe retrieval, status filtering, and vector search.
- [x] DB design supports ready-only retrieval without full-text/content leakage defaults.
- [x] Migration approach is compatible with existing memory behavior.

## Constraints
- No business logic implementation in this task.
- Do not introduce external vector DB dependencies.

## Approval Gate
Human reviewer must approve this task before Task 03 begins.

## Execution Summary
### Work Performed
- Added migration [`20260506120000_add_knowledge_source_files_and_chunks.exs`](/priv/repo/migrations/20260506120000_add_knowledge_source_files_and_chunks.exs) to:
- Enable pgvector extension (`CREATE EXTENSION IF NOT EXISTS vector`).
- Add `knowledge_items` constraints for source-file compatibility (`kind` and `status` by `kind`).
- Create `knowledge_source_files` metadata table with constraints and indexes.
- Create `knowledge_source_file_chunks` table with vector column (`embedding vector(1536)`), uniqueness constraints, and HNSW vector index.
- Add source-file-specific scope/status indexes on `knowledge_items` for retrieval filtering.
- Extended [`KnowledgeItem` schema](/lib/lemmings_os/knowledge/knowledge_item.ex) to allow `kind = "source_file"` and source-file lifecycle statuses while preserving memory invariants.
- Added new schemas:
- [`SourceFile`](/lib/lemmings_os/knowledge/source_file.ex)
- [`SourceFileChunk`](/lib/lemmings_os/knowledge/source_file_chunk.ex)
- Added factory support for new entities in [`test/support/factory.ex`](/test/support/factory.ex).
- Added focused schema tests:
- [`knowledge_item_test.exs`](/test/lemmings_os/knowledge/knowledge_item_test.exs)
- [`source_file_test.exs`](/test/lemmings_os/knowledge/source_file_test.exs)
- [`source_file_chunk_test.exs`](/test/lemmings_os/knowledge/source_file_chunk_test.exs)

### Validation Run
- `mix test test/lemmings_os/knowledge/knowledge_item_test.exs test/lemmings_os/knowledge/source_file_test.exs test/lemmings_os/knowledge/source_file_chunk_test.exs`
- `mix format`
- `mix precommit`

### Notes
- No external vector DB dependencies were introduced.
- Ecto schema field type `:vector` is not available without adding pgvector Elixir type support, so the chunk schema keeps `embedding` at DB level via migration and indexes while omitting it from typed schema fields for now.

## Human Review
*[Filled by human reviewer]*
