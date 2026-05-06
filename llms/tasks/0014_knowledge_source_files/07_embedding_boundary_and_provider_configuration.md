# Task 07: Embedding Boundary And Provider Configuration

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior Elixir/Phoenix backend engineer.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement embedding boundary and provider wiring using the locked MVP defaults.

## Objective
Add a small internal embedding boundary that supports deterministic fake embeddings for tests and configurable OpenAI-compatible providers for real environments.

## Inputs Required
- [ ] Tasks 01-06 approved
- [ ] `llms/tasks/0014_knowledge_source_files/plan.md`

## Expected Outputs
- [ ] Embedding behavior/interface and provider selection from env config.
- [ ] Deterministic fake embedder for dev/test.
- [ ] Real provider client path for OpenAI-compatible embedding endpoint.
- [ ] Dimension validation with fixed initial dimension `1536`.

## Acceptance Criteria
- [ ] Embedding failures produce safe reason tokens and lifecycle updates.
- [ ] Provider responses are not leaked in logs/events/tool outputs.
- [ ] Embedding logic is swappable without changing search/read contracts.

## Constraints
- Do not add cloud-only hard dependencies.

## Approval Gate
Human reviewer must approve this task before Task 08 begins.

## Human Review
*[Filled by human reviewer]*
