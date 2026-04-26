# Lemming Instance Executor Runtime

## Purpose

`LemmingsOs.LemmingInstances.Executor` is the per-instance runtime coordinator for a `LemmingInstance`.

It is the GenServer boundary for one running instance and is one of the core runtime components of LemmingsOS. It owns the execution lifecycle, work queue, runtime state, timers, model monitors, and status transitions for an active instance.

The Executor is intentionally kept as the orchestration boundary. The helper modules under `LemmingsOs.LemmingInstances.Executor.*` exist to make the runtime easier to understand, test, and evolve, but they do not become independent runtimes.

## Runtime boundary

The Executor owns:

- process lifecycle
- in-memory work queue
- current runtime state
- queue admission and progression
- model task monitors and timeout references
- idle expiration timers
- retry progression
- status transitions such as `queued`, `processing`, `retrying`, `idle`, `failed`, and `expired`
- coordination between model output, tool calls, finalization, and multi-lemming communication

The Executor delegates focused concerns to helper modules, but the GenServer remains the single owner of process state and lifecycle decisions.

## Public API

External callers should treat `Executor` as the runtime API.

Common entry points include:

- `enqueue_work/2`
- `resume_pending/2`
- `resume_after_lemming_call/2`
- `retry/1`
- `status/1`
- `snapshot/1`
- `queue_depth/1`
- `admit/1`

Helper modules are internal implementation details. Control-plane, UI, scheduler, or other runtime callers should not call `Executor.*` helper modules directly.

## Design rule

The refactor splits responsibilities without splitting ownership.

```text
Executor owns runtime coordination.
Executor.* helpers make narrow decisions, build payloads, or execute isolated steps.
```

This keeps the runtime debuggable while avoiding a large GenServer full of unrelated branches.

## Runtime flow map

This map describes the stable execution flow. It is not intended to be a private function call graph.

```text
External caller
  ├─ enqueue_work/2
  ├─ resume_pending/2
  ├─ resume_after_lemming_call/2
  ├─ retry/1
  └─ admit/1
      ↓
Executor GenServer
  ├─ owns lifecycle, queue, timers, monitors, and runtime state
  ├─ emits diagnostic events
  └─ coordinates the next runtime step
      ↓
Queue admission
  └─ QueueData builds queue items and queue snapshots
      ↓
Executor state transition
  └─ TransitionsData builds transition attributes and status metadata
      ↓
Model step
  ├─ ContextMessages builds provider-facing context messages
  ├─ ModelStepPayload builds model request payloads
  └─ ModelStepRuntime converts model output into executor actions
      ↓
Executor applies the selected action
```

## Model-step branches

Model output is normalized into explicit executor actions. The Executor then applies the selected branch.

```text
ModelStepRuntime action
  ├─ assistant reply
  │   └─ Executor persists the visible response and transitions to idle or queued
  │
  ├─ tool call
  │   ├─ ToolLifecycle normalizes tool call/result status
  │   └─ ToolStepRuntime executes the tool-step handling path
  │
  ├─ lemming call
  │   ├─ Communication builds call attrs and resume decisions
  │   └─ CommunicationRuntime executes delegated call handling
  │
  ├─ finalization required
  │   ├─ FinalizationDecision decides the next action
  │   ├─ FinalizationPayload builds repair/finalization payloads
  │   └─ FinalizationRuntime applies repair or failure side effects
  │
  └─ retry/failure
      └─ RetryRuntime applies retry or exhaustion handling
```

## Helper ownership summary

| Helper family | Responsibility |
|---|---|
| `*Data` | Build plain runtime data structures. |
| `*Payload` | Build request payloads for model/finalization steps. |
| `*Decision` | Return explicit decisions without side effects. |
| `*Runtime` | Execute narrow runtime steps through explicit dependencies. |
| `Events` | Build and publish diagnostic runtime events. |
| `Communication*` | Isolate multi-lemming request and resume handling. |
| `RuntimeStore` | Isolate runtime-store access helpers. |

## Runtime store boundary

`RuntimeStore` exists to keep ETS/DETS/runtime-store access out of the main Executor flow.

The Executor decides when runtime state should be read, written, snapshotted, or cleaned up. `RuntimeStore` provides focused helpers for those operations.

This preserves a clear rule:

```text
Executor decides persistence timing.
RuntimeStore performs the narrow store operation.
```

## Event boundary

`Events` centralizes diagnostic event emission.

Runtime events should help explain what happened without becoming business logic. They should be safe for debugging and should not contain raw secrets, credentials, or unnecessary provider/tool payloads.

The Executor should emit events at important runtime boundaries, such as:

- work enqueued
- queue admitted
- model step started/completed/failed
- tool step started/completed/failed
- multi-lemming call requested/resumed
- retry scheduled or exhausted
- instance transitioned to idle, failed, or expired

## Communication boundary

Multi-lemming communication is intentionally isolated from the main execution loop.

`Communication` and `CommunicationRuntime` handle request shaping, delegated-call handling, and resume decisions. The Executor remains responsible for when to enter or resume that path.

This avoids mixing peer-call orchestration with queue, model, tool, and retry logic.

## Finalization boundary

Finalization is split into three concerns:

- `FinalizationDecision` decides what should happen next.
- `FinalizationPayload` builds model payloads for repair/finalization work.
- `FinalizationRuntime` applies repair or failure side effects through explicit callbacks/dependencies.

This keeps finalization behavior testable without making the Executor responsible for every repair/failure branch inline.

## Retry boundary

`RetryRuntime` owns retry-specific runtime handling, including retry progression and exhaustion behavior.

The Executor still owns the lifecycle state. Retry helpers should return explicit outcomes or apply narrow injected operations rather than hiding broad process transitions.

## Extension rules

When adding new Executor behavior:

1. Keep process lifecycle and state ownership in `Executor`.
2. Prefer pure `*Data`, `*Payload`, or `*Decision` helpers for data shaping and branching.
3. Use `*Runtime` helpers only for narrow runtime steps with explicit dependencies.
4. Do not let helper modules become alternate public APIs.
5. Do not let helpers own timers, monitors, or GenServer lifecycle.
6. Emit diagnostic events through `Events` instead of scattering event payloads across the runtime.
7. Keep secrets and raw sensitive provider/tool data out of runtime events, snapshots, and logs.

## Testing guidance

The Executor should be tested at two levels:

- integration-style tests for the GenServer runtime flow
- focused unit tests for helper modules that make decisions, build payloads, or normalize runtime data

Pure helpers should remain easy to test without a running GenServer.

Runtime helpers should use explicit dependencies/callbacks where practical so tests can verify behavior without relying on global process state.

## Non-goals

This document does not define a new architecture decision.

It documents the current implementation boundary of the Lemming instance runtime after the Executor refactor. Architectural decisions remain in ADRs. This document should evolve when the implementation structure changes, but it should not replace ADRs for new runtime contracts.

