# Task 07: Embedding Boundary And Provider Configuration

## Status
- **Status**: ✅ IMPLEMENTED (awaiting human sign-off)
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior Elixir/Phoenix backend engineer.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement embedding boundary and provider wiring using the locked MVP defaults.

## Objective
Add a small internal embedding boundary that supports deterministic fake embeddings for tests and configurable OpenAI-compatible providers for real environments.

## Inputs Required
- [x] Tasks 01-06 approved
- [x] `llms/tasks/0014_knowledge_source_files/plan.md`

## Expected Outputs
- [x] Embedding behavior/interface and provider selection from env config.
- [x] Deterministic fake embedder for dev/test.
- [x] Real provider client path for OpenAI-compatible embedding endpoint.
- [x] Dimension validation with fixed initial dimension `1536`.

## Acceptance Criteria
- [x] Embedding failures produce safe reason tokens and lifecycle updates.
- [x] Provider responses are not leaked in logs/events/tool outputs.
- [x] Embedding logic is swappable without changing search/read contracts.

## Notes
- Current repository wiring does not include pgvector decode support at the Ecto type layer, so Task 07 keeps embeddings at the provider-boundary/lifecycle layer without persisting non-null `vector` values yet. This avoids retrieval-row decode failures and keeps the boundary swappable for Task 08 query work.

## Constraints
- Do not add cloud-only hard dependencies.

## Approval Gate
Human reviewer must approve this task before Task 08 begins.

## Human Review
*[Filled by human reviewer]*
