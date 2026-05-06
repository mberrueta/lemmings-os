# Task 04: Source File Domain Context, Lifecycle, And Indexing Orchestration

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior Elixir/Phoenix backend engineer.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement source-file context APIs and lifecycle transitions.

## Objective
Extend the Knowledge domain with source-file create/update/list/delete/archive/retry flows, scope validation, lifecycle states, and non-blocking indexing orchestration after upload/registration.

## Inputs Required
- [ ] Tasks 01-03 approved
- [ ] `llms/tasks/0014_knowledge_source_files/plan.md`

## Expected Outputs
- [ ] Context APIs for source-file item creation and management.
- [ ] Lifecycle status transitions (`pending`, `extracting`, `chunking`, `embedding`, `ready`, `failed`, `archived` or chosen equivalents).
- [ ] Optional Artifact provenance ingestion path requiring explicit user action.
- [ ] Non-blocking indexing orchestration that starts after upload/registration.
- [ ] Stage transition flow across extraction, chunking, embedding, indexing, ready, failed, and retry.
- [ ] Retry entry point that safely restarts indexing without mixing stale chunks.

## Acceptance Criteria
- [ ] Source-file items are scoped with existing World/City/Department/Lemming rules.
- [ ] Upload/registration path is non-blocking for users.
- [ ] Failed items are excluded from retrieval candidates.
- [ ] Memory-only behavior (`knowledge.store`) remains unchanged.

## Constraints
- Do not implement Tika, chunking, embeddings, or tool runtime integration in this task.

## Approval Gate
Human reviewer must approve this task before Task 05 begins.

## Human Review
*[Filled by human reviewer]*
