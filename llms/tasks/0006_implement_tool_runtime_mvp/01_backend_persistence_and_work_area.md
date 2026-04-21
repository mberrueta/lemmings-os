# Task 01: Backend Persistence And Work Area

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and implement the persistence changes for Tool Runtime MVP.

## Objective
Add the minimal durable backend support for tool execution history and per-instance work area creation at spawn time.

## Inputs Required

- [ ] `llms/tasks/0006_implement_tool_runtime_mvp/plan.md`
- [ ] `lib/lemmings_os/lemming_instances.ex`
- [ ] `lib/lemmings_os/lemming_instances/lemming_instance.ex`
- [ ] Current runtime spawn flow and migrations patterns

## Expected Outputs

- [ ] Migration(s) for durable tool execution history and any required work area schema cleanup
- [ ] Schema/context support for the new persistence needs
- [ ] Spawn-time work area creation wired into the runtime flow

## Acceptance Criteria

- [ ] Work area creation happens at spawn time
- [ ] Tool execution history is persisted durably and linked to the runtime session and world scope
- [ ] New public context APIs remain explicitly world-scoped

## Technical Notes

### Constraints
- Keep the persistence slice limited to this MVP
- Do not implement approvals, MCP, Docker sandboxing, or broader tool governance

## Execution Instructions

### For the Agent
1. Add the required persistence changes.
2. Wire spawn-time work area creation into the runtime/session flow.
3. Expose the minimum context support needed by later tasks.

### For the Human Reviewer
1. Verify durable tool execution history exists.
2. Verify work area creation uses the configured runtime workspace root.
3. Verify scope stays within the MVP slice.

---

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*
