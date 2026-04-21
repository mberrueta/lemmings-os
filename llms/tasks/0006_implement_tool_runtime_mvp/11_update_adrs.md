# Task 11: Update ADRs

## Status
- **Status**: ✅ COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`docs-feature-documentation-author`

## Agent Invocation
Act as `docs-feature-documentation-author` following `llms/constitution.md` and update ADRs/architecture docs for the Tool Runtime MVP.

## Objective
Document the Tool Runtime MVP slice as implemented, without expanding into out-of-scope future governance features.

## Inputs Required

- [ ] `llms/tasks/0006_implement_tool_runtime_mvp/plan.md`
- [ ] Tasks 01 through 10 outputs
- [ ] Relevant ADRs and architecture docs under `docs/`

## Expected Outputs

- [ ] ADR/documentation updates aligned with the implemented MVP slice

## Acceptance Criteria

- [ ] Docs reflect the fixed four-tool MVP only
- [ ] Docs reflect direct runtime-call execution
- [ ] Docs reflect work area, transcript visibility, and observability behavior at the implemented level
- [ ] Docs do not reopen approvals, permissions hierarchy, MCP, Docker sandboxing, or worktree scope

## Execution Instructions

### For the Agent
1. Read the implemented outputs.
2. Update only the relevant ADR/docs.
3. Keep the documentation precise and scope-bounded.

### For the Human Reviewer
1. Verify docs match implementation.
2. Verify out-of-scope topics were not reintroduced.

---

## Execution Summary
Updated ADRs and architecture docs to match the implemented Tool Runtime MVP slice:

- `docs/adr/0005-tool-execution-model.md` now documents the fixed four-tool catalog, direct executor-to-runtime call path, durable tool execution rows, and explicit out-of-scope governance layers.
- `docs/adr/0016-tool-execution-isolation-model.md` now documents the MVP work-area/filesystem boundary and clarifies that the four first-party tools run in-process.
- `docs/adr/0018-audit-log-event-model.md` now documents implemented tool lifecycle logs, telemetry, PubSub notification, activity-log entries, and the distinction between MVP runtime history and future audit-event storage.
- `docs/adr/0021-core-domain-schema.md` now includes `lemming_instance_tool_executions` as a Phase 1 runtime-history table.
- `docs/adr/0024-observability-and-monitoring-model.md` now lists the implemented tool execution telemetry metrics.
- `docs/architecture.md` now includes the Tool Runtime layer, direct tool-call flow, persistence table, and live-only interaction trace behavior.

Scope kept to the implemented MVP. Did not reintroduce approvals, MCP, Docker sandboxing, generic command execution, broader policy hierarchy, or worktree/git scope as implemented behavior.

## Human Review
*[Filled by human reviewer]*
