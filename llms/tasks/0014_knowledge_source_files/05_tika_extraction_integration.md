# Task 05: Tika Extraction Integration

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior Elixir/Phoenix backend engineer.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Integrate private Tika extraction for source files.

## Objective
Implement extraction pipeline stages and Tika client integration using `Req`, with timeout/size limits and safe failure handling.

## Inputs Required
- [ ] Tasks 01-04 approved
- [ ] `llms/tasks/0014_knowledge_source_files/plan.md`
- [ ] Docker Compose and runtime config patterns

## Expected Outputs
- [ ] Private Tika service wiring (no public port by default).
- [ ] Extraction client + bounded timeout default `30s`.
- [ ] Max extracted characters enforcement default `500,000`.
- [ ] Lifecycle updates + safe failure reason tokens.

## Acceptance Criteria
- [ ] Extraction success/failure transitions are visible to downstream indexing flow.
- [ ] Unsupported or empty extraction output is handled safely.
- [ ] No full extracted content is logged or emitted in durable events.

## Constraints
- No chunking or embedding implementation in this task.

## Approval Gate
Human reviewer must approve this task before Task 06 begins.

## Human Review
*[Filled by human reviewer]*
