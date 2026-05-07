# Task 04: Source File Domain Context, Lifecycle, And Indexing Orchestration

## Status
- **Status**: ✅ COMPLETE
- **Approved**: [x] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior Elixir/Phoenix backend engineer.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement source-file context APIs, lifecycle transitions, and narrow non-blocking indexing orchestration.

## Objective
Extend the Knowledge domain with source-file create/update/list/delete/archive/retry flows, scope validation, lifecycle states, and non-blocking indexing orchestration after upload/registration.

## Inputs Required
- [x] Tasks 01-03 approved
- [x] `llms/tasks/0014_knowledge_source_files/plan.md`

## Expected Outputs
- [x] Context APIs for source-file item creation and management.
- [x] Lifecycle status transitions (`uploaded` or `pending`, `extracting`, `extracted`, `chunking`, `embedding`, `ready`, `needs_ocr`, `failed`, `archived` or chosen equivalents).
- [x] Verify completed Task 02 schema/status constraints support `needs_ocr`; if not, add the minimal migration/schema update required before lifecycle implementation.
- [x] Optional Artifact provenance ingestion path requiring explicit user action.
- [ ] URL/HTML extraction via Trafilatura is adapter-ready in Task 05, but user-facing URL registration may be deferred unless already present in the UI scope.
- [x] Non-blocking indexing orchestration that starts after upload/registration.
- [x] If Oban is the least-rework path, minimal Oban dependency/config/migration/docs for a dedicated `knowledge_indexing` queue.
- [x] One source-file indexing worker/job boundary that owns extract, chunk, embed, mark ready, mark failed, and mark `needs_ocr`.
- [x] Stage transition flow across extraction, chunking, embedding, indexing, ready, failed, and retry.
- [x] Retry entry point that safely restarts indexing without mixing stale chunks.

## Acceptance Criteria
- [x] Source-file items are scoped with existing World/City/Department/Lemming rules.
- [x] Upload/registration path is non-blocking for users.
- [x] Upload/create creates the Knowledge item and enqueues or schedules source-file indexing without running extractor internals in the request.
- [x] Retry safely enqueues/re-enqueues indexing and leaves later chunk replacement to the indexing pipeline.
- [x] If Oban is added, it is limited to one source-file indexing worker and a dedicated `knowledge_indexing` queue.
- [x] If the repo already has a preferred background pattern, the implementation briefly documents why that pattern or Oban is the least-rework path.
- [x] Tests execute the worker boundary directly or use deterministic Oban testing helpers; no sleeps.
- [x] Failed items are excluded from retrieval candidates.
- [x] Memory-only behavior (`knowledge.store`) remains unchanged.

## Constraints
- Do not implement extraction adapter internals, chunking, embeddings, or tool runtime integration in this task.
- Do not introduce broad job architecture, workflows, batches, cron, unrelated jobs, or multiple queues.

## Approval Gate
Human reviewer must approve this task before Task 05 begins.

## Human Review
*[Filled by human reviewer]*
