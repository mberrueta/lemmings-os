# Task 08: Vector Retrieval Queries And Filtering

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-db-performance-architect` - Database architect for query optimization and retrieval performance.

## Agent Invocation
Act as `dev-db-performance-architect`. Implement pgvector retrieval queries with scope/type/tag/status filtering and ready-only constraints.

## Objective
Deliver efficient retrieval queries for source-file chunks, including ranking, filters, and strict server-side scope enforcement.

## Inputs Required
- [ ] Tasks 01-07 approved
- [ ] `llms/tasks/0014_knowledge_source_files/plan.md`

## Expected Outputs
- [ ] Query layer for similarity search over ready chunks.
- [ ] Filtering by scope, source-file type, tags, and top_k limits.
- [ ] Index usage validation and query plan sanity.

## Acceptance Criteria
- [ ] Cross-World and sibling-scope leakage is prevented at query level.
- [ ] Non-ready statuses are excluded from retrieval.
- [ ] Results include snippet-ready fields and safe metadata only.

## Constraints
- No tool runtime or UI implementation in this task.

## Approval Gate
Human reviewer must approve this task before Task 09 begins.

## Human Review
*[Filled by human reviewer]*
