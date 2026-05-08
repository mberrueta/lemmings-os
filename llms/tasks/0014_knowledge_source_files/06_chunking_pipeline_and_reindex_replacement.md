# Task 06: Chunking Pipeline And Reindex Replacement

## Status
- **Status**: ✅ IMPLEMENTED (awaiting human sign-off)
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior Elixir/Phoenix backend engineer.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement source-file chunking and deterministic reindex replacement.

## Objective
Split extracted content into ordered chunks and persist chunk metadata with stable refs and safe replacement behavior.

## Inputs Required
- [x] Tasks 01-05 approved
- [x] `llms/tasks/0014_knowledge_source_files/plan.md`

## Expected Outputs
- [x] Chunking service using MVP defaults: size `1,200`, overlap `200`, max chunks `500`.
- [x] Stable `chunk_ref` generation strategy.
- [x] Safe reindex flow that replaces stale chunk sets.

## Acceptance Criteria
- [x] Chunk ordering and overlap are correct.
- [x] Empty chunks are not persisted.
- [x] Reindex flow avoids mixed old/new retrieval results.

## Constraints
- No embedding provider calls in this task.

## Approval Gate
Human reviewer must approve this task before Task 07 begins.

## Human Review
*[Filled by human reviewer]*
