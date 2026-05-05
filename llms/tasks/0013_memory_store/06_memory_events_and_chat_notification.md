# Task 06: Memory Events And Chat Notification

## Status
- **Status**: COMPLETED
- **Approved**: [x] Human sign-off

## Assigned Agent
`dev-logging-daily-guardian` - Logging/event quality guardian for safe observability behavior.

## Agent Invocation
Act as `dev-logging-daily-guardian`. Implement and review memory lifecycle event emission and best-effort chat notification behavior for LLM-created memories.

## Objective
Wire lightweight memory lifecycle observability events and implement non-transactional user-visible chat notification after successful `knowledge.store`.

## Inputs Required
- [ ] `llms/tasks/0013_memory_store/plan.md`
- [ ] Task 05 output
- [ ] Existing event, PubSub, logging, telemetry, and transcript/message patterns
- [ ] `lib/lemmings_os/lemming_instances/*` (message/publish flow)

## Expected Outputs
- [ ] Event emission for memory created (user/llm), updated, and deleted.
- [ ] Safe event payload contract with scope + creator metadata and no sensitive content leakage.
- [ ] Best-effort chat notification for LLM-created memory with deep-link path when supported.
- [ ] Failure handling path that preserves stored memory when notification publish fails.

## Acceptance Criteria
- [ ] Events exist for `knowledge.memory.created`, `.updated`, `.deleted`, and `.created_by_llm` (or approved equivalent taxonomy).
- [ ] Event payloads exclude secrets, unrelated runtime snapshots, and raw filesystem paths.
- [ ] Notification failure does not roll back memory persistence.
- [ ] Successful notification is visible in active instance chat/transcript flow.

## Technical Notes
### Constraints
- Reuse existing PubSub/transcript patterns and lightweight logging/telemetry/event conventions already present in the repo.
- Keep metadata-focused events; avoid full content dumps in logs/events.

### Scope Boundaries
- No UI layout or component work in this task.

## Execution Instructions
### For the Agent
1. Add/adjust event helpers and payload shaping.
2. Implement resilient notification publish flow with safe logging on failures.
3. Verify logging fields stay stable and minimal.

### For the Human Reviewer
1. Validate leak-prevention requirements against emitted payloads/logs.
2. Confirm memory persistence remains authoritative even when notifications fail.

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
