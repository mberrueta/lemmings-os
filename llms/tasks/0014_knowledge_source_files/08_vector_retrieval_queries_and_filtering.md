# Task 08: Vector Retrieval Queries And Filtering

## Status
- **Status**: ✅ COMPLETED
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-db-performance-architect` - Database architect for query optimization and retrieval performance.

## Agent Invocation
Act as `dev-db-performance-architect`. Implement pgvector retrieval queries with scope/type/tag/status filtering and ready-only constraints.

## Objective
Deliver efficient retrieval queries for source-file chunks, including ranking, filters, and strict server-side scope enforcement.

## Inputs Required
- [x] Tasks 01-07 approved
- [x] `llms/tasks/0014_knowledge_source_files/plan.md`

## Expected Outputs
- [x] Query layer for similarity search over ready chunks.
- [x] Filtering by scope, source-file type, tags, and top_k limits.
- [x] Index usage validation and query plan sanity.

## Acceptance Criteria
- [x] Cross-World and sibling-scope leakage is prevented at query level.
- [x] Non-ready statuses are excluded from retrieval.
- [x] Results include snippet-ready fields and safe metadata only.

## Completed Implementation
- Added `search_source_file_chunks/3` in [`lib/lemmings_os/knowledge.ex`](/lib/lemmings_os/knowledge.ex) for pgvector similarity retrieval.
- Enforced server-side scope relevance in query joins for world/city/department/lemming visibility.
- Enforced ready-only constraints in SQL filters:
  - `knowledge_items.kind = 'source_file'`
  - `knowledge_items.status = 'ready'`
  - `knowledge_source_files.indexing_status = 'ready'`
  - `knowledge_source_files.extraction_status = 'ready'`
  - `embedding IS NOT NULL`
- Added retrieval filters:
  - `source_file_type`
  - tags containment (`@>`)
  - bounded `top_k` (default `5`, max `20`)
- Added snippet and safe result projection (no storage refs, no vectors, no provider payloads).
- Persisted chunk embeddings during indexing pipeline so vector search operates on stored vectors.

## Query/Type Wiring
- Reused existing migration [`priv/repo/migrations/20260506120000_add_knowledge_source_files_and_chunks.exs`](/priv/repo/migrations/20260506120000_add_knowledge_source_files_and_chunks.exs) and its HNSW index; no new migration created.
- Added pgvector repo type wiring:
  - [`lib/lemmings_os/postgres_types.ex`](/lib/lemmings_os/postgres_types.ex)
  - repo `types` config in `config/dev.exs`, `config/test.exs`, and `config/runtime.exs`
- Added `embedding` field to [`lib/lemmings_os/knowledge/source_file_chunk.ex`](/lib/lemmings_os/knowledge/source_file_chunk.ex).

## Validation
- Added/updated retrieval tests in [`test/lemmings_os/knowledge/source_files_context_test.exs`](/test/lemmings_os/knowledge/source_files_context_test.exs):
  - scope leakage prevention (cross-world/sibling)
  - non-ready exclusion
  - `source_file_type` and tag filters
  - `top_k` max bound behavior
- Verification commands run:
  - `mix test test/lemmings_os/knowledge/source_files_context_test.exs`
  - `mix test test/lemmings_os/knowledge/source_file_chunk_test.exs test/lemmings_os/knowledge/source_files/indexing_worker_test.exs`
  - `mix precommit`

## Constraints
- No tool runtime or UI implementation in this task.

## Approval Gate
Human reviewer must approve this task before Task 09 begins.

## Human Review
*[Filled by human reviewer]*
