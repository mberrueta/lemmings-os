# LemmingsOS -- 0006 Implement Tool Runtime MVP

## Execution Metadata

- Spec / Plan: `llms/tasks/0006_implement_tool_runtime_mvp/plan.md`
- Created: `2026-04-18`
- Status: `PLANNING`
- Branch: `feat/0006_tool_runtime_mvp`
- Related upstream plan: `llms/tasks/0005_implement_runtime_engine/plan.md`

## Goal

Deliver the first end-to-end Tool Runtime slice so a spawned `LemmingInstance` can execute a small fixed catalog of tools, receive normalized tool results, surface tool activity live in the instance session UI, and leave useful file artifacts in a dedicated per-instance work area.

This PR validates the minimum product loop from runtime session to tool execution to visible transcript history to final artifact generation. It is intentionally a narrow MVP slice, not the general tool governance system.

---

## Execution Plan

## Overview

This execution plan breaks the Tool Runtime MVP into smaller sequential tasks grouped by backend, backend tests, frontend, frontend tests, ADR updates, and final PR review. Each task is intentionally scoped so it can be implemented and approved independently without introducing separate verification-only tasks.

## Technical Summary

### Codebase Impact

- **New files**: expected across runtime persistence, tool adapters/catalog, UI components, tests, and ADR updates
- **Modified files**: expected in runtime, model integration, LiveView transcript rendering, telemetry, and tools registry surfaces
- **Database migrations**: Yes
- **External dependencies**: None expected beyond existing `Req`

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Tool call loop expands beyond the agreed four-tool MVP | Medium | High | Keep the task outputs explicitly limited to the fixed catalog and restate out-of-scope items in backend/frontend tasks |
| Transcript history becomes split between messages and tool events in inconsistent ways | Medium | High | Make backend persistence and frontend rendering tasks share the same chronological transcript requirement |
| World scoping or workspace path boundaries are implemented inconsistently | Medium | High | Keep world-scoped APIs and workspace-relative path handling as explicit acceptance criteria in backend and test tasks |
| Observability becomes partial and only covers happy paths | Medium | Medium | Require lifecycle logging, telemetry, and historical inspection in backend implementation and PR review |

## Roles

### Human Reviewer

- Approves each task before the next begins
- Executes all git operations
- Confirms task outputs satisfy the acceptance criteria
- Decides whether follow-up work is needed after ADR review or PR review

### Executing Agents

| Task | Agent | Description |
|------|-------|-------------|
| 01 | `dev-backend-elixir-engineer` | Implement persistence and spawn-time work area support |
| 02 | `dev-backend-elixir-engineer` | Implement fixed tool catalog and MVP tool adapters |
| 03 | `dev-backend-elixir-engineer` | Implement executor/model integration for the tool-call loop |
| 04 | `dev-logging-daily-guardian` | Implement tool execution observability and runtime-facing backend visibility |
| 05 | `qa-elixir-test-author` | Implement backend tests for persistence, work area, and tool adapters |
| 06 | `qa-elixir-test-author` | Implement backend tests for executor loop and observability |
| 07 | `dev-frontend-ui-engineer` | Implement transcript tool cards and historical session rendering |
| 08 | `dev-frontend-ui-engineer` | Implement tools page runtime catalog wiring |
| 09 | `qa-elixir-test-author` | Implement LiveView tests for the instance transcript tool UX |
| 10 | `qa-elixir-test-author` | Implement LiveView tests for the tools page runtime catalog |
| 11 | `docs-feature-documentation-author` | Update ADRs and architecture notes to reflect the delivered MVP slice |
| 12 | `audit-pr-elixir` | Perform the final branch-level PR review |

## Task Sequence

| # | Task | Status | Approved |
|---|------|--------|----------|
| 01 | Backend: Persistence And Work Area | ⏳ PENDING | [ ] |
| 02 | Backend: Tool Catalog And Adapters | ⏳ PENDING | [ ] |
| 03 | Backend: Executor Tool Loop | ⏳ PENDING | [ ] |
| 04 | Backend: Observability And Runtime Visibility | ⏳ PENDING | [ ] |
| 05 | Backend Tests: Persistence And Adapters | ⏳ PENDING | [ ] |
| 06 | Backend Tests: Executor And Observability | ⏳ PENDING | [ ] |
| 07 | Frontend: Transcript Tool Cards | ⏳ PENDING | [ ] |
| 08 | Frontend: Tools Registry Runtime Catalog | ⏳ PENDING | [ ] |
| 09 | Frontend Tests: Instance Transcript Tool UX | ⏳ PENDING | [ ] |
| 10 | Frontend Tests: Tools Registry Runtime Catalog | ⏳ PENDING | [ ] |
| 11 | Update ADRs | ⏳ PENDING | [ ] |
| 12 | PR Review | ⏳ PENDING | [ ] |

## Assumptions

1. The current `plan.md` is the approved source of truth for scope and is ready for tech-lead task decomposition.
2. No additional product slicing is needed beyond the four approved tools.
3. The existing runtime executor remains the correct implementation seam for tool invocation.
4. The instance session page remains the primary UX surface for tool execution visibility in this PR.
5. ADR updates should document implemented behavior only and should not reopen out-of-scope governance topics.

## Open Questions

1. None currently blocking Task 01.

## Change Log

| Date | Task | Change | Reason |
|------|------|--------|--------|
| 2026-04-18 | Plan | Initial functional plan created | PO analysis |
| 2026-04-18 | Plan | Added execution task breakdown and approval sequence | TL architecture planning |

---

## Project Context

### Related Entities

- `LemmingsOs.LemmingInstances.LemmingInstance`
  - Location: `lib/lemmings_os/lemming_instances/lemming_instance.ex`
  - Existing role: durable runtime session record
  - Relevant fields today: `status`, `config_snapshot`, `started_at`, `stopped_at`, `last_activity_at`
  - Required change for this issue: ensure spawn-time work area creation uses the runtime workspace root layout
- `LemmingsOs.LemmingInstances.Message`
  - Location: `lib/lemmings_os/lemming_instances/message.ex`
  - Existing role: immutable transcript entries for `user` and `assistant`
  - Constraint: current message role taxonomy should not be overloaded to represent tool lifecycle records
- `LemmingsOs.LemmingInstances`
  - Location: `lib/lemmings_os/lemming_instances.ex`
  - Existing role: durable session persistence boundary and transcript access
  - Relevant seam: `spawn_instance/3`, `list_messages/2`, `enqueue_work/3`, world-scoped query patterns
- `LemmingsOs.LemmingInstances.Executor`
  - Location: `lib/lemmings_os/lemming_instances/executor.ex`
  - Existing role: per-instance work queue, status transitions, model execution, PubSub updates
  - Relevant seam: this is where model output currently converges back into runtime behavior
- `LemmingsOs.ModelRuntime`
  - Location: `lib/lemmings_os/model_runtime.ex`
  - Existing role: provider boundary for structured assistant output
  - Constraint discovered in tests: current contract accepts `reply` and explicitly rejects `tool_call`
- `LemmingsOs.LemmingInstances.PubSub`
  - Location: `lib/lemmings_os/lemming_instances/pubsub.ex`
  - Existing role: live status/message updates for the session page
  - Constraint: appropriate for live UI fanout only; not appropriate as the primary tool execution mechanism
- `LemmingsOs.Runtime.ActivityLog`
  - Location: `lib/lemmings_os/runtime/activity_log.ex`
  - Existing role: in-memory operator feed for recent runtime events
  - Constraint: useful for live/operator visibility, but not sufficient for durable tool execution history
- `LemmingsOs.LemmingInstances.Telemetry`
  - Location: `lib/lemmings_os/lemming_instances/telemetry.ex`
  - Existing role: safe telemetry helper with full hierarchy metadata
  - Relevant seam: correct place to extend event emission for tool execution lifecycle

### Related Features

- **Instance Session Page**
  - Locations: `lib/lemmings_os_web/live/instance_live.ex`, `lib/lemmings_os_web/live/instance_live.html.heex`
  - Existing behavior: compact streamed transcript with status banner, follow-up composer, and PubSub-driven updates
  - Pattern to follow: add compact timeline entries/cards instead of a separate raw log screen
- **Tools Registry Page**
  - Locations: `lib/lemmings_os_web/live/tools_live.ex`, `lib/lemmings_os_web/page_data/tools_page_snapshot.ex`
  - Existing behavior: page already expects a runtime-backed tool registry but still uses placeholder fetchers
  - Pattern to follow: replace the placeholder runtime fetcher with the actual fixed catalog for this PR
- **Runtime Dashboard / Logs**
  - Locations: `lib/lemmings_os/runtime/status.ex`, `lib/lemmings_os_web/telemetry.ex`, `lib/lemmings_os_web/live/runtime_dashboard_live.ex`
  - Existing behavior: runtime counts, telemetry polling, in-memory activity feed
  - Pattern to follow: add metrics and activity log events rather than introducing a second observability stack

### Naming Conventions Observed

- Context / boundary modules use `LemmingsOs.<PluralOrRuntimeName>`
- Durable runtime schemas live under their context namespace
- Instance session features use `LemmingsOs.LemmingInstances.*` and `LemmingsOsWeb.InstanceLive`
- Fixed runtime registry data is already conceptually represented under `LemmingsOs.Tools.*`
- Telemetry event naming follows `[:lemmings_os, :domain, :transition]`
- World-scoped context APIs require explicit `world_id` or `%World{}`

### Permissions / Actor Model

- No application-level authenticated role system is implemented in the current codebase
- The functional actor in this issue is the platform operator using the runtime UI
- Tool permissions, approvals, and hierarchy filtering are explicitly out of scope for this PR

---

## Terminology Alignment

### `Tool Runtime`

Use `Tool Runtime` for the direct execution boundary that validates args, resolves workspace-relative paths, executes the tool adapter, persists a tool execution record, and returns a normalized result to the executor.

This is distinct from:

- `LemmingsOs.Tools.*` as catalog/read-model concerns
- PubSub as a live-update mechanism
- `ModelRuntime`, which chooses when a tool call should happen but must not execute tools itself

### `tool execution`

Use `tool execution` for the durable record of one attempted tool invocation.

This record must include:

- tool identity
- normalized args
- status
- short preview / summary
- normalized result or normalized error
- timestamps / duration

This record is required because the existing in-memory `ActivityLog` is not durable enough to satisfy the history requirement.

### `work area`

Use `work area` for the writable directory created at spawn time under the runtime workspace root.

The work area is:

- dedicated to one `LemmingInstance`
- created before the instance begins useful work
- derived from the lemming hierarchy at runtime
- the default target for artifacts written during the session

### `transcript tool card`

Use `transcript tool card` for the compact session UI representation of a tool execution.

This card is not a raw stdout dump. It should show:

- tool name
- running / ok / error status
- short summary
- optional preview

### `catalog`

For this PR, `catalog` means the fixed global list of four supported tools only:

- `fs.read_text_file`
- `fs.write_text_file`
- `web.search`
- `web.fetch`

No permission filtering, policy reconciliation, or effective-per-lemming catalog work belongs in this issue.

Any broader tool catalog discussion from earlier exploration should be treated as background context only, not as part of the implementation brief for this PR.

---

## Scope Boundaries

### In Scope

- fixed global Tool Runtime catalog for the four approved tools only
- direct runtime execution from the existing executor path
- spawn-time work area creation under the configured runtime workspace root
- durable tool execution history with compact session transcript visibility
- live updates plus operational visibility through logs, telemetry, and metrics

### Out of Scope

- hierarchical tool permissions, allowlists, denylists, or limit enforcement
- approval workflows
- MCP configuration
- Docker sandboxing
- any command-execution surface such as `exec.run`
- any broader filesystem catalog beyond `fs.read_text_file` and `fs.write_text_file`
- git branches, worktrees, or cleanup jobs
- generated `LEMMINGS.md`, `task_context.md`, or similar per-task artifacts
- durable persistence of every intermediate LLM/tool loop turn; the raw interaction trace for this MVP stays live-only in the executor

---

## Runtime Loop Notes

### Live interaction trace

The MVP now includes a live-only executor trace for the LLM/tool loop.

- Owner: `LemmingsOs.LemmingInstances.Executor`
- Surface: raw context LiveView timeline
- Persistence: none beyond the lifetime of the running executor

This trace exists to debug token use, repeated tool calls, and prompt/tool handoff behavior without changing the durable transcript model.

### ADR follow-up

Task 11 should update `ADR-0004` with:

- a simplified execution-flow diagram for the Phase 1 model/tool loop
- explicit ownership boundaries for `Executor`, `ModelRuntime`, and `Tool Runtime`
- clarification that the live interaction trace is ephemeral executor state, not a durable audit log
- separate operator pages for tool audit beyond what is needed on the instance page and existing runtime surfaces

---

## Validation Findings Against Current Codebase

1. The current runtime already has the correct execution owner: `LemmingsOs.LemmingInstances.Executor`.
   Tool execution should extend that path instead of introducing a second async execution pipeline.

2. The current session page already has the right UI shell: a streamed transcript with compact cards and PubSub updates.
   Tool visibility should be added into this transcript rather than building a separate tool console first.

3. The current `Message` schema is intentionally scoped to `user` and `assistant`.
   Tool executions should be persisted in a dedicated schema instead of overloading transcript messages with another pseudo-role.

4. The current `ActivityLog` is useful but ephemeral.
   A durable `tool executions` store is required to meet the brief’s history requirement.

5. The current telemetry helper and runtime dashboard patterns are already in place.
   This PR should extend those patterns rather than invent a second observability model.

6. The current tools page is already prepared for a runtime-backed catalog.
   This PR should replace the placeholder runtime fetcher with the fixed Tool Runtime catalog.

7. The current `ModelRuntime` test suite explicitly rejects `tool_call`.
   The implementation plan must include the minimum structured-output extension required for tool invocation and final reply completion.

---

## Confirmed Constraints For This PR

- Direct runtime call boundary from the existing executor path; PubSub is for live updates only.
- Dedicated durable tool execution history is required so operators can inspect results after reload.
- The runtime session must create its work area under the configured runtime workspace root; absolute host paths must not leak into persisted tool records or tool-visible outputs.
- The fixed catalog for this PR is only `fs.read_text_file`, `fs.write_text_file`, `web.search`, and `web.fetch`.
- Tool results and errors must be normalized consistently for both model/runtime use and transcript inspection.
- The instance session page remains the primary operator surface; tool cards stay compact and support inspection of persisted details without defaulting to raw output dumps.

---

## User Stories

### US-1: Execute fixed catalog tools from a runtime session

As an operator running a lemming session, I want the session to execute the approved MVP tools, so that the instance can read/write files and gather web context during a task.

### US-2: Produce artifacts inside a dedicated work area

As an operator, I want each spawned instance to have its own writable work area, so that generated artifacts are isolated, predictable, and inspectable after the run.

### US-3: See tool activity live in the session transcript

As an operator watching a runtime session, I want compact tool execution cards to appear in the transcript in real time, so that I can understand what the instance is doing without reading raw output dumps.

### US-4: Inspect historical tool executions after the live event

As an operator returning to a session later, I want tool execution history to remain visible and inspectable, so that I can audit what happened even after the live updates are gone.

### US-5: Observe success, failure, and runtime health operationally

As an operator maintaining the runtime, I want logs, metrics, and status records for every tool execution, so that failures and latency trends are diagnosable from day 0.

---

## Acceptance Criteria

### US-1: Execute fixed catalog tools from a runtime session

**Scenario: tool call succeeds**

- **Given** an active `LemmingInstance` with a valid config snapshot
- **When** the model returns a structured `tool_call` action for one of the four approved tools
- **Then** the executor invokes Tool Runtime directly
- **And** Tool Runtime validates args against the tool schema
- **And** a durable tool execution record is created
- **And** the normalized tool result is returned to the executor for continued reasoning

**Scenario: unsupported tool requested**

- **Given** the model returns a tool name outside the fixed catalog
- **When** the executor resolves the requested tool
- **Then** the tool execution is recorded as `error`
- **And** the error is normalized with a stable `code`
- **And** the session remains alive unless broader retry logic decides otherwise

**Criteria Checklist**

- [ ] Only `fs.read_text_file`, `fs.write_text_file`, `web.search`, and `web.fetch` can execute
- [ ] Tool args are validated before adapter execution
- [ ] Tool Runtime is called directly from runtime code, not through PubSub
- [ ] Tool results and errors use one normalized public shape
- [ ] `ModelRuntime` contract supports the minimum `tool_call` action needed for this PR

### US-2: Produce artifacts inside a dedicated work area

**Scenario: work area created at spawn**

- **Given** a new runtime session is spawned successfully
- **When** the spawn workflow completes
- **Then** the instance has a dedicated work area created under the runtime workspace root
- **And** the work area path resolves to `<workspace_root>/<department_id>/<lemming_id>`

**Scenario: filesystem write respects workspace boundaries**

- **Given** the instance calls `fs.write_text_file`
- **When** the target path resolves outside `/workspace`
- **Then** the write is rejected with a normalized error
- **And** no file is written

**Criteria Checklist**

- [ ] Work area is created during spawn, not lazily on first write
- [ ] Work area is created at `<workspace_root>/<department_id>/<lemming_id>`
- [ ] Filesystem tools only accept workspace-relative paths
- [ ] Absolute paths and upward traversal are rejected
- [ ] The final assistant response can reference the produced artifact path using the relative workspace path

### US-3: See tool activity live in the session transcript

**Scenario: running card appears**

- **Given** a connected operator on the instance session page
- **When** a tool execution starts
- **Then** a compact tool card appears in the transcript with `running` status

**Scenario: completion updates the same card**

- **Given** a running tool card already shown in the transcript
- **When** the execution completes or fails
- **Then** the card updates to `ok` or `error`
- **And** the card shows a short summary and optional preview
- **And** full raw output is not rendered inline by default

**Criteria Checklist**

- [ ] Tool cards render inside the existing session transcript timeline
- [ ] Live updates use PubSub broadcasts from persisted lifecycle changes
- [ ] Cards remain visually compact
- [ ] Default rendering favors summary/preview over raw payload dumps

### US-4: Inspect historical tool executions after the live event

**Scenario: session page reload retains history**

- **Given** a session with completed tool executions
- **When** the operator reloads the instance page later
- **Then** prior tool cards reappear from persisted records in transcript order
- **And** each record remains inspectable

**Criteria Checklist**

- [ ] Tool executions are persisted durably, not only broadcast live
- [ ] Reloading the instance page reconstructs transcript history with tool cards included
- [ ] Success and failure records are both inspectable after reload

### US-5: Observe success, failure, and runtime health operationally

**Scenario: successful execution emits observability signals**

- **Given** a tool call completes successfully
- **When** the lifecycle transitions occur
- **Then** structured logs, telemetry events, and counters/duration metrics are emitted

**Scenario: failed execution emits observability signals**

- **Given** a tool call fails validation or adapter execution
- **When** the failure is persisted
- **Then** structured logs and telemetry still emit with normalized reason metadata

**Criteria Checklist**

- [ ] Lifecycle transitions are logged
- [ ] `started`, `completed`, and `failed` transitions emit telemetry
- [ ] Metrics cover volume, success/error rate, and duration
- [ ] All tool execution observability metadata includes full hierarchy context plus `tool_name`

---

## Implementation Plan

### Workstream 1: Data Model And Spawn-Time Work Area

Deliver the minimal persistence needed for durability and operator inspection.

Planned changes:

- add a dedicated durable store for tool execution records
- add world-scoped context APIs to create, update, and list tool executions per instance
- extend the runtime spawn workflow so work area creation happens before returning a spawned session

Expected alignment with current code:

- `LemmingsOs.Runtime.spawn_session/3` remains the end-to-end spawn entrypoint
- `LemmingsOs.LemmingInstances.spawn_instance/3` remains the durable instance persistence boundary
- work area creation belongs in the spawn flow, not in transient ETS state

### Workstream 2: Fixed Catalog And Tool Runtime Boundary

Create a minimal Tool Runtime layer with one direct call entrypoint and a fixed catalog definition.

Planned changes:

- introduce a dedicated tool-execution runtime boundary aligned with existing runtime naming and layering conventions
- define one fixed global catalog that both the runtime and tools UI can read
- define structured arg schemas and normalized result/error contracts
- implement four adapters only:
  - `fs.read_text_file`
  - `fs.write_text_file`
  - `web.search`
  - `web.fetch`

Implementation constraints:

- filesystem adapters must resolve relative paths against `/workspace`
- `fs.write_text_file` must support artifact creation in the instance work area
- web adapters should use `Req`
- no generic shell or command execution path belongs here

### Workstream 3: Executor / Model Integration

Extend the runtime loop so tool calls are first-class but still minimal.

Planned changes:

- extend the structured output contract so the model can request a `tool_call`
- keep `reply` as the assistant completion action
- update the executor to:
  - detect `tool_call`
  - persist and broadcast lifecycle transitions
  - invoke Tool Runtime directly
  - append normalized tool results into the model context for continued reasoning
  - continue until a final assistant reply is produced or a bounded runtime failure occurs

Important constraint:

- this PR should support one clean iterative loop for tool use and final answer generation, but it should not open multi-agent delegation, tool approvals, or general workflow orchestration

### Workstream 4: Session UI And Historical Inspection

Extend the existing instance transcript to include compact tool execution cards.

Planned changes:

- update `InstanceLive` transcript composition to interleave persisted messages and persisted tool execution records chronologically
- add PubSub-driven live updates for tool execution lifecycle changes
- add one compact tool card component consistent with the current transcript aesthetic
- support lightweight detail inspection for persisted normalized result/error data without defaulting to raw payload dumps

Important constraint:

- tool cards belong on the existing session page
- no new primary navigation area is needed for this PR

### Workstream 5: Observability And Registry Surfaces

Extend existing observability and registry patterns rather than creating new ones.

Planned changes:

- add `tool_call.started`, `tool_call.completed`, and `tool_call.failed` lifecycle events
- record structured log lines for each lifecycle transition
- add `ActivityLog.record/4` entries for operator-facing runtime awareness
- add metrics in `LemmingsOsWeb.Telemetry` for:
  - tool call volume
  - success/error counts
  - duration
- replace the placeholder tools runtime fetcher with the actual fixed catalog

---

## Non-Functional Requirements

### Safety / Boundary Rules

- Paths must remain relative to `/workspace`
- Tool adapters must reject boundary-escaping paths deterministically
- Tool Runtime must never expose host absolute paths in persisted records or model-visible outputs
- All web requests must use `Req`

### Durability

- Tool execution history must survive page reload and live update loss
- Successful and failed executions both remain inspectable

### Observability

- Logs exist for lifecycle transitions
- Metrics cover count, success/error, and duration
- Telemetry metadata includes `world_id`, `city_id`, `department_id`, `lemming_id`, `instance_id`, and `tool_name`

### UX

- Tool UI is compact by default
- Running, success, and error states are clearly distinguishable
- Raw payloads are not shown inline by default

### Performance / Operational Restraint

- This PR should remain lightweight and synchronous at the execution boundary
- It should not introduce additional queueing layers or distributed execution semantics
- It should not create a second long-lived process per tool invocation unless a later issue requires it

---

## Edge Cases

### Filesystem

- [ ] Read target does not exist
- [ ] Read target is outside `/workspace`
- [ ] Write target attempts `../` traversal
- [ ] Write target parent directory does not exist
- [ ] Write target overwrites an existing file

### Web

- [ ] Search returns no results
- [ ] Fetch receives a bad URL or unsupported URL form
- [ ] Fetch fails due to timeout or transport error
- [ ] Fetch succeeds but content is too noisy or too large for default preview

### Runtime / Model Loop

- [ ] Model requests an unknown tool
- [ ] Model sends invalid args for a known tool
- [ ] Tool call fails but the session remains recoverable
- [ ] Tool execution is persisted as `running` but completion fails to broadcast; reload must still show the final durable state

### UI

- [ ] Historical transcript contains messages and tool cards on the same day
- [ ] Tool cards preserve chronological order across reloads
- [ ] Transcript remains usable when a session has many tool executions

---

## UX States

### Instance Session Transcript Tool Card

| State | Behavior |
|---|---|
| `running` | Compact card with tool name, running status, brief in-progress summary |
| `ok` | Compact card with success status, summary, optional preview |
| `error` | Compact card with error status, summary, normalized error copy |
| `reloaded history` | Same compact card shape reconstructed from persisted records |

### Tools Registry Page

| State | Behavior |
|---|---|
| `catalog available` | Shows the four fixed tools from the real runtime fetcher |
| `catalog unavailable` | Existing degraded/unknown state remains valid |

---

## Testing Expectations

This issue changes executable runtime logic and must satisfy the constitution’s testing rules.

Required test coverage:

- context tests for work area creation and persistence
- Tool Runtime unit tests for arg validation and result normalization
- adapter tests for each of the four tools
- executor tests for the `tool_call` -> runtime -> final reply loop
- telemetry tests for lifecycle events and metrics metadata
- LiveView tests for transcript tool cards, live updates, and reload persistence
- tools page tests proving the fixed catalog is exposed through the runtime fetcher

Testing style should follow the existing runtime engine approach:

- deterministic tests
- `start_supervised/1` for runtime processes
- explicit world-scoped setup
- LiveView assertions via IDs and element presence rather than raw HTML snapshots

---

## Delivery Notes For The Implementing Engineer

1. Keep the PR slice narrow. Do not add adjacent tools or governance features.
2. Reuse existing runtime seams first:
   - `LemmingsOs.Runtime`
   - `LemmingsOs.LemmingInstances`
   - `LemmingsOs.LemmingInstances.Executor`
   - `LemmingsOs.LemmingInstances.PubSub`
   - `LemmingsOs.LemmingInstances.Telemetry`
3. Do not model tool execution as a fake transcript message role.
4. Do not use PubSub as the primary execution mechanism.
5. Do not leak absolute host paths into persisted rows, transcript cards, or model-visible tool results.
6. Do not reopen permissions, approvals, MCP, Docker sandboxing, or git worktree design in this PR.

---

## Out of Scope

Explicitly excluded from this feature:

1. Hierarchical tool permissions by World / City / Department / Lemming
2. Approval workflows for risky tools
3. MCP connectors and remote tool registration
4. Docker-based sandbox execution
5. `exec.run` and any shell-style tool surface
6. Broader filesystem mutation and management commands outside the four approved tools
7. Git branch/worktree lifecycle management
8. Cleanup jobs for work areas
9. Generated contextual docs such as `LEMMINGS.md` or `task_context.md`

These items must not be implemented as part of this PR.

---

## PO Review Summary

### Changes Made

- Replaced the brief-only file with an implementation-ready staff-level plan
- Validated the plan against the current runtime executor, session LiveView, tools registry placeholder, telemetry helper, and activity log patterns
- Added explicit durable tool execution requirements and spawn-time work area creation requirements
- Clarified how the executor, Tool Runtime, PubSub, and session transcript should interact without reopening broader architecture
- Added user stories, acceptance criteria, edge cases, UX states, testing expectations, and non-functional requirements

### Clarifications / Corrections

| Topic | Clarification |
|---|---|
| Branch name | Canonical branch for this task is `feat/0006_tool_runtime_mvp`. |
| History requirement | Existing `ActivityLog` is not durable enough; a persisted tool execution record is required |
| Transcript modeling | Tool executions should not be stored as `Message` rows with a synthetic role |
| UI direction | Existing instance transcript is the correct primary surface for tool cards |
| Runtime boundary | Executor must call Tool Runtime directly; PubSub is live-update infrastructure only |
| Catalog source | Tools page and executor should share one fixed catalog definition for this PR |

### Key Findings

- The current codebase already provides the correct runtime seams for this feature
- The major missing pieces are durable tool execution persistence, work area persistence, and the structured output extension for `tool_call`
- The tools page can be made real in this PR without reopening permissions or policy work

### Status

✅ **READY FOR TECH LEAD REVIEW**
