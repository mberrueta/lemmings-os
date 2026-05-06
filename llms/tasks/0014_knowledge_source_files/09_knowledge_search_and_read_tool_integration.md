# Task 09: Knowledge Search And Read Tool Integration

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior Elixir/Phoenix backend engineer.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Add source-file support to `knowledge.search` and `knowledge.read` runtime tools.

## Objective
Integrate retrieval and read APIs into the tool runtime envelope with strict scope checks, bounded read output, and safe error handling.

## Inputs Required
- [ ] Tasks 01-08 approved
- [ ] Existing tool runtime adapter patterns
- [ ] `llms/tasks/0014_knowledge_source_files/plan.md`

## Expected Outputs
- [ ] `knowledge.search` source-file retrieval support.
- [ ] `knowledge.read` chunk-content retrieval support.
- [ ] Ready-only enforcement and bounded read defaults.

## Acceptance Criteria
- [ ] Tool outputs follow existing runtime success/error envelope.
- [ ] Tool responses exclude storage refs, raw paths, vectors, and provider responses.
- [ ] `knowledge.store` remains memory-only.

## Constraints
- No UI implementation in this task.

## Approval Gate
Human reviewer must approve this task before Task 10 begins.

## Human Review
*[Filled by human reviewer]*
