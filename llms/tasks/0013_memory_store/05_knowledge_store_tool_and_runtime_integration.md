# Task 05: Knowledge Store Tool And Runtime Integration

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for runtime/tool integration.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Add `knowledge.store` as a memory-only tool in the existing fixed Tool Runtime catalog and execution path.

## Objective
Implement tool catalog/runtime dispatch and adapter/service integration for LLM-created memories with safe input/output and default Lemming scope behavior.

## Inputs Required
- [ ] `llms/tasks/0013_memory_store/plan.md`
- [ ] Tasks 03 and 04 outputs
- [ ] `lib/lemmings_os/tools/catalog.ex`
- [ ] `lib/lemmings_os/tools/runtime.ex`
- [ ] `lib/lemmings_os/lemming_instances/executor/*`

## Expected Outputs
- [ ] `knowledge.store` catalog entry with title guidance copy aligned to plan.
- [ ] Runtime dispatch path that validates args and invokes memory store service.
- [ ] Memory store path sets `source = llm` and captures creator lemming/instance metadata where available.
- [ ] Safe structured error mapping for invalid scope/input/unsupported fields.

## Acceptance Criteria
- [ ] Tool accepts only memory fields (`title`, `content`, optional `tags`, optional scope hint).
- [ ] Tool rejects unsupported file/category/type inputs safely.
- [ ] Default scope is the current Lemming when scope is omitted.
- [ ] Any explicit scope hint is validated against the current execution ancestry.
- [ ] Tool output is safe and minimal (`knowledge_item_id`, status, scope), no internal paths or unrelated runtime state.

## Technical Notes
### Constraints
- Reuse existing runtime normalization envelope (`{:ok, %{summary, preview, result}}` and structured errors).
- Do not expose database internals or broad inventory through tool output.

### Scope Boundaries
- Do not add `knowledge.search` or `knowledge.read` as Lemming tools in this task.

## Execution Instructions
### For the Agent
1. Add catalog entry and runtime dispatch with minimal surface change.
2. Implement adapter/service boundary with input normalization and safe errors.
3. Keep behavior deterministic for tests and auditability.

### For the Human Reviewer
1. Verify tool interface remains memory-only and LLM-friendly.
2. Verify cross-boundary scope escalation is blocked.

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
