# Task 04: Runtime Tool Integration

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Wire Secret Bank resolution into the existing tool execution path while preserving all prompt, snapshot, logging, and runtime-event redaction guarantees.

## Objective
Make tool configs able to use `$secrets.*` references and receive resolved raw values only inside trusted execution, without exposing those values to Lemmings or LLMs.

## Expected Outputs
- Updates to tool runtime modules under `lib/lemmings_os/tools/**` and/or executor modules.
- Safe runtime event/error payloads for successful and failed secret resolution.

## Acceptance Criteria
- Tool execution detects `$secrets.github.token` style references only in trusted tool configuration or adapter configuration and resolves them through Secret Bank as `github.token`.
- Tool execution never resolves `$secrets.*` references from model-provided, Lemming-provided, user-provided, or runtime tool args.
- Raw values are injected only into the trusted adapter/runtime call path.
- Lemming prompts, context messages, finalization payloads, checkpoints, snapshots, PubSub runtime events, and activity entries do not contain raw secret values or derived previews.
- Missing secret failures produce safe tool errors and do not execute the adapter with partial credential state.
- Existing tools without secret requirements continue to work.
- World/city/department/lemming scope metadata is passed explicitly to resolution.

## Review Notes
Reject if raw values are added to structs or maps that are later serialized, persisted, broadcast, or sent to model runtime. Reject if `$secrets.*` references in model/tool args can trigger secret resolution.
