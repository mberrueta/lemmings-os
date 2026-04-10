# ADR-0004 — Lemming Execution Model

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

LemmingsOS is an Elixir/OTP-based runtime for autonomous agents organized as:

- World
- City
- Department
- Lemming

A core design principle is that a Lemming is **not** a general-purpose super-agent. Each Lemming is intentionally narrow, specialized, and focused on doing one thing well.

This creates a runtime requirement different from prompt-first agent frameworks:

- Lemmings may run for extended periods.
- Lemmings may wait on tools, messages, or external events.
- Lemmings must be restartable after crashes.
- Lemmings must operate under inherited constraints such as model policy, tool permissions, runtime limits, and cost budgets.
- Runtime state must remain inspectable and resumable.

We also want to avoid treating each agent as a permanently live process with unbounded in-memory state. Instead, execution should start on demand and remain supervised by OTP.

---

# 2. Decision Drivers

1. **Long-lived execution with blocking waits** — Lemmings spend significant time waiting on model responses, tool calls, peer agents, or external events. The execution model must support resident processes that yield during waits without blocking the scheduler.

2. **OTP supervision must own lifecycle** — On-demand spawning and crash recovery via supervision are first-class requirements. The execution model must be a native OTP citizen, not a wrapper around it.

3. **Inspectable and resumable state** — Instance existence, lifecycle transitions, and execution progress must be observable from outside the process. Crash recovery must be deterministic, not reliant on in-memory reconstruction.

4. **Execution under inherited constraints** — Model policy, tool permissions, cost budgets, and retry limits are resolved from the configuration hierarchy. These constraints must be structurally enforced, not enforced by trust in agent code.

5. **Lightweight process state** — The GenServer must not accumulate heavy concerns such as context storage, model inference, cost accounting, or audit. These must be delegated to dedicated runtime services to keep the instance process simple and restartable.

6. **Configuration snapshot isolation** — Instances must run against a frozen configuration snapshot resolved at spawn time. Mutable live configuration must not affect a running instance mid-execution.

---

# 3. Considered Options

## Option A — Permanently live agent processes

Each Lemming type runs as a permanently alive OTP process. Instances are long-lived singletons.

**Pros:**
- simple lifecycle; no on-demand spawn logic required
- always ready to receive work without startup latency

**Cons:**
- keeps unbounded idle state in memory indefinitely
- lifecycle management, upgrades, and recovery become harder to reason about
- does not map naturally to multiple concurrent instances of the same type
- idle agents consume resources even when no work is scheduled

Rejected. Permanently live processes do not align with the on-demand, multi-instance execution model required.

---

## Option B — Free-form actor loop with mostly in-memory state

Each Lemming runs as a standard GenServer with an unconstrained `handle_info` loop. All execution state lives in the process dictionary or GenServer state with no explicit lifecycle transitions.

**Pros:**
- straightforward to implement; minimal runtime infrastructure
- familiar Elixir pattern

**Cons:**
- in-memory state is lost on crash with no structured recovery path
- auditability is weakened because no lifecycle transitions are recorded
- budget and constraint enforcement require external hooks that are easy to bypass
- large state accumulation in the GenServer makes the process heavyweight and slow to restart

Rejected. In-memory-first execution weakens auditability, restartability, and budget enforcement.

---

## Option C — Workflow engine as the primary runtime abstraction

Lemming execution is modeled as a declarative workflow using a dedicated workflow engine as the core execution substrate.

**Pros:**
- workflow engines naturally support state persistence, retries, and timeouts
- visual composition and auditability are built-in

**Cons:**
- introduces a non-OTP dependency as the core execution substrate
- LemmingsOS is centered on agent execution and LLM reasoning loops, not on static graph traversal
- the constraint set (dynamic tool calls, model responses, peer messages) does not fit naturally into rigid workflow steps
- adds operational complexity for self-hosted deployments

Rejected for the core runtime. Workflow composition may exist as a higher-level abstraction later.

---

## Option D — On-demand supervised OTP process (chosen)

Each Lemming instance runs as a GenServer started under a DynamicSupervisor. Instances are created on demand, persist resumable state externally, and transition through an explicit state machine.

**Pros:**
- native OTP supervision: restart, crash isolation, and lifecycle are handled by the platform
- on-demand creation avoids idle resource waste
- explicit state machine makes execution observable and auditable
- external persistence enables deterministic crash recovery
- lightweight GenServer state keeps processes simple and restartable

**Cons:**
- recovery depends on checkpoint quality and freshness
- event-driven execution is more complex than a naïve blocking loop
- requires dedicated external services for context, accounting, and audit

Chosen. The model provides strong alignment with OTP, enforces inspectability, and enables deterministic recovery.

---

# 4. Decision

A runtime execution of a Lemming SHALL be modeled as an **on-demand supervised instance** implemented as an **OTP process**, with the initial implementation using a **GenServer** started under a **DynamicSupervisor**.

Each execution instance:

- is created on demand when work is assigned,
- owns only the **minimal runtime state** needed to coordinate execution,
- persists resumable execution state outside the process,
- can be restarted by supervision and rehydrated from persisted state,
- operates as a **stateful, event-driven workflow**, rather than as a free-form in-memory loop.

The Lemming definition shown in the control plane represents a **Lemming type** or template. Runtime work is performed by **Lemming instances** spawned from that type.

## 4.1 Phase 1 Runtime Slice

This ADR defines the long-term execution model and remains the source of truth for the intended architecture. The Phase 1 runtime slice uses a narrower operational subset rather than the full long-term execution taxonomy.

Phase 1 focuses on:

- on-demand `LemmingInstance` creation from a durable `Lemming`
- supervised per-instance executor processes
- explicit queueing, processing, retry, idle, failure, and expiry lifecycle
- model execution through `ModelRuntime`
- no peer delegation, join semantics, or generalized pause/resume workflow

The richer execution model in this ADR remains the intended long-term architecture unless intentionally revised by a later ADR. The Phase 1 runtime slice does not replace that model; it defines an intentionally smaller contract for the first runtime slice.

---

# 5. Runtime Model

## 5.1 Lemming type vs Lemming instance

A **Lemming type** defines the reusable agent template, such as:

- role and purpose
- system instructions
- model/provider policy
- allowed tools
- allowed communication targets
- runtime limits
- retry policy

A **Lemming instance** is a concrete execution of that type for a specific task or request.

The instance is the runtime unit supervised by OTP.

## 5.2 Process model

Each Lemming instance runs as a dedicated GenServer started under a DynamicSupervisor.

The GenServer is responsible for:

- coordinating the current execution step,
- receiving and reacting to events,
- delegating specialized concerns to runtime services,
- checkpointing resumable state,
- transitioning between execution states.

The GenServer is **not** the source of truth for all execution data.

## 5.3 State model

Each Lemming instance behaves as an explicit stateful execution with states such as:

- created
- queued
- running
- waiting_model
- waiting_tool
- waiting_message
- retry_backoff
- paused
- completed
- failed
- cancelled

The exact set of states may evolve, but the execution model is explicitly state-based and resumable.

### Phase 1 status subset

The Phase 1 runtime slice uses the following operational statuses:

- `created`
- `queued`
- `processing`
- `retrying`
- `idle`
- `failed`
- `expired`

These statuses are a constrained Phase 1 subset of the richer execution model above, not a replacement for it. They collapse several long-term states into operationally simpler buckets:

| Phase 1 status | Long-term interpretation |
|---|---|
| `created` | persisted instance exists before scheduler admission; the long-term model keeps this as the pre-execution lifecycle boundary |
| `queued` | ready-to-run work exists and is awaiting admission; later phases may split queue residency from more specialized waiting states |
| `processing` | coarse operational bucket covering active `running` work and `waiting_model` provider execution |
| `retrying` | operational form of `retry_backoff`; the instance is retrying the same work item under the configured retry policy |
| `idle` | reusable waiting bucket used after successful work completion when no queued work remains; later phases may refine this into `waiting_message`, `paused`, or other quiescent states |
| `failed` | terminal failure state aligned with the long-term `failed` outcome |
| `expired` | Phase 1 terminal idle-timeout outcome; a specialized operational terminal state that future phases may model with richer terminal-reason semantics |

The main mapping constraints are therefore:

- `running` and `waiting_model` map to `processing`
- `retry_backoff` maps to `retrying`
- `idle` is the deliberate Phase 1 stand-in for reusable waiting states that are not yet split into finer-grained categories
- `waiting_tool`, `waiting_message`, `paused`, `completed`, and `cancelled` are deferred beyond Phase 1

Deferred states remain part of the intended long-term model and should be introduced explicitly in later phases rather than inferred from temporary implementation shortcuts.

## 5.4 Minimal in-process state

The GenServer should keep only lightweight runtime coordination state, such as:

- instance identifier
- type identifier
- current status
- current step
- waiting reason
- timestamps and heartbeat data
- references to config snapshot, context snapshot, and usage/accounting records

Large or durable concerns must remain outside the process.

## 5.5 Persisted execution state

A Lemming instance must create an initial persisted record at startup so its existence and lifecycle can be traced externally from the beginning of execution.

A Lemming instance must persist the state required for recovery and resumption outside the process.

This persisted state may include:

- instance creation and lifecycle metadata
- current lifecycle state
- current step and pending action
- context references
- partial outputs
- retry metadata
- checkpoint history
- external wait conditions

If the process crashes and is restarted by supervision, the runtime should be able to rehydrate the instance and continue from the latest valid checkpoint.

## 5.6 Event-driven execution

A Lemming instance does not run as a blocking `while true` loop.

Instead, it progresses by:

- receiving a start signal,
- executing a step,
- delegating work to tools or other runtime services,
- persisting a checkpoint,
- waiting for the next event, timer, or callback,
- resuming when conditions are satisfied.

This keeps the execution model OTP-native, observable, and restart-friendly.

## 5.7 Phase 1 runtime control components

Phase 1 formalizes a small runtime control layer around each `LemmingInstance`.

### Executor

The per-instance executor remains the orchestration process for a single runtime session.

Responsibilities:

- own the in-memory queue and current work item
- drive status transitions for a single `LemmingInstance`
- publish runtime updates for UI and observability
- delegate provider work to `ModelRuntime`
- never own provider-specific HTTP logic

### DepartmentScheduler

Phase 1 introduces a formal **DepartmentScheduler** runtime component. There is one scheduler per active Department.

Responsibilities:

- own scheduling truth for the Department's queued instances
- react to runtime signals that work is available or capacity was released
- select the oldest eligible queued instance first in Phase 1
- request scarce execution capacity before an executor begins processing
- remain focused on scheduling responsibility, not Department lifecycle management

**Namespace clarification:** the implementation module lives under `LemmingsOs.LemmingInstances.DepartmentScheduler` because it is part of the instance runtime engine. Its **organizational scope** is the Department, but its **implementation namespace** is `LemmingInstances`. This is intentionally distinct from `Department.Manager`, which owns Department lifecycle and control-plane concerns rather than runtime admission control.

### ResourcePool

Scarce execution capacity is mediated by a runtime resource pool.

Responsibilities:

- gate concurrent model execution
- key capacity by the scarce resource, not by organizational scope
- allow many Departments to contend for the same model endpoint safely

In Phase 1 the pool key is the **resource key**, for example `ollama:llama3.2`. This is intentionally not keyed by Department or City. The bottleneck is the model endpoint itself.

That resource key must come from the same normalized active-model selection
contract consumed by `ModelRuntime`. The scheduler does not define its own
profile-selection heuristic; it consumes the resolved runtime snapshot.

### ModelRuntime

`ModelRuntime` is the dedicated model execution boundary for runtime orchestration.

Responsibilities:

- assemble prompts from structured runtime context
- resolve the configured provider implementation
- validate structured output
- capture normalized token and usage data
- keep provider-specific HTTP details outside the executor

`Providers.Ollama` is the first provider implementation for Phase 1. Additional providers extend this boundary; they do not change the executor's orchestration role.

## 5.8 Phase 1 boot recovery semantics

Phase 1 recovery after application restart is intentionally narrow and must be read as an explicit contract, not as a vague promise of general rehydration.

### Automatic boot reconciliation

At boot, the runtime may call `recover_created_sessions/1` to sweep persisted instances in these statuses:

- `created`
- `queued`
- `processing`
- `retrying`
- `idle`

This sweep is bounded and best-effort. It is intended to reattach sessions that were persisted already but lost their in-memory executor due to process or node restart.

### Automatic reattach vs recoverable-at-best

The boot-time contract is:

- if the latest persisted transcript row is a pending `user` message, the session is reattached and resumed as work to be processed again; the runtime normalizes the durable status back to `created` before re-entering the queue
- if there is no pending trailing `user` message, the session is reattached as `idle` so it can accept follow-up input again
- `queued`, `processing`, and `retrying` do not resume from an in-flight provider call; they are treated as recoverable-at-best and collapse either to "resume pending user work" or "reattach idle" depending on transcript state

In other words, Phase 1 automatically recovers **session attachment**, not exact in-flight execution position.

### States requiring explicit caller or operator action

- `failed` is **not** auto-recovered at boot; it requires an explicit `retry_session/2` call
- `retry_session/2` only succeeds when there is a pending trailing `user` message to replay; otherwise the failure remains terminal
- `expired` is terminal for the session lifecycle and is not reattached automatically; callers must spawn a new session

This is consistent with the broader Phase 1 design: durable session identity and transcript survive restart, while in-flight execution remains recoverable-at-best until richer rehydration semantics are introduced.

---

# 6. Configuration Inheritance

**ADR-0003** establishes World as a hard isolation boundary. That boundary has a direct consequence for execution: a Lemming instance is permanently scoped to the World it was spawned in and cannot address or observe anything outside it. Configuration inheritance follows the same boundary — a Lemming cannot inherit configuration from, or be governed by, a World it does not belong to.

Effective runtime configuration is resolved hierarchically from:

- World
- City
- Department
- Lemming type
- Instance overrides

More specific configuration takes precedence over less specific configuration.

However, inherited safety restrictions from higher levels must remain enforceable. In particular:

- lower levels must not exceed higher-level deny rules,
- lower levels must not escape upper budget constraints,
- effective permissions must remain bounded by platform policy.

The instance should run against a resolved configuration snapshot rather than continuously reading mutable live configuration during execution.

Waiting instances remain resident in memory while idle. They are not unloaded as part of normal waiting behavior. This is expected because Lemmings may spend significant time waiting on model responses, local machine calls, tools, other services, or peer agents. To support crash recovery, the runtime persists execution state at lifecycle boundaries (transition to idle, before termination) as defined in ADR-0008. Active running Lemmings do not checkpoint; their working state lives in ETS and is considered recoverable from the most recent idle snapshot.

---

# 7. Separation of Responsibilities

The Lemming GenServer is only the execution coordinator.

The following concerns are delegated to dedicated runtime services or modules:

- instance tracing and external runtime inspection

- context storage and compaction

- **model inference** — Lemmings never call providers directly. All inference requests
  are dispatched to the Model Runtime (ADR-0019), which handles provider routing,
  prompt assembly, retries, token accounting, structured output validation, and
  streaming. The Lemming transitions to `waiting_model` while inference is in
  progress. The minimal event set the execution model depends on:

  | event | family | consumed by |
  |---|---|---|
  | `model.request_started` | telemetry | observability |
  | `model.response_received` | telemetry | Lemming resumes execution |
  | `model.retry` | telemetry | observability |
  | `model.request_failed` | telemetry | Lemming transitions to failure/backoff |
  | `model.usage` | telemetry | cost governance (ADR-0015) |
  | `model.budget_denied` | audit | Lemming receives `{:error, :budget_exhausted}` |
  | `model.structured_output_invalid` | audit | Lemming receives structured error |

  Full event definitions and payload contracts are in ADR-0019 section 13 and the
  platform event catalog in ADR-0018.

- token and cost accounting
- audit/event logging
- checkpoint persistence
- large artifact storage
- tool execution

This prevents the instance process from becoming the single location for all runtime complexity.

---

# 8. Consequences

## Positive

- Waiting instances can resume immediately when external events arrive.
- External systems can observe that an instance exists and inspect its lifecycle from the beginning of execution.
- In-memory residency simplifies event delivery and coordination for long-running agents.
- Periodic idle checkpointing improves crash recovery without requiring full unload/reload semantics.
- Strong alignment with Elixir/OTP supervision patterns.
- On-demand execution avoids keeping idle agents permanently alive.
- Restart and recovery behavior becomes explicit and testable.
- Runtime state can be inspected, audited, and resumed.
- The process remains lightweight because heavy concerns are externalized.
- Specialized Lemming types remain easy to reason about.

## Negative

- Idle instances continue consuming memory while resident; the runtime must tune idle TTL and checkpoint frequency carefully.
- Recovery requires careful checkpoint design — stale checkpoints mean more repeated work on restart.
- Persisted state and in-memory state must stay consistent; a divergence between the two produces incorrect rehydration.
- Event-driven execution is more complex than a naïve in-memory loop.
- The runtime requires additional services for context, accounting, and audit concerns.

## Mitigations

- Idle memory pressure is mitigated by configurable `idle_ttl` eviction: instances that have been idle beyond the threshold are terminated and their context is compacted into a snapshot (ADR-0008).
- Checkpoint semantics are defined in ADR-0008: snapshots are written at lifecycle boundaries (idle transition, pre-termination), not continuously. The recovery gap for a running Lemming is bounded by how recently it last transitioned through idle.
- State consistency is maintained by treating persisted state as the source of truth: on rehydration, the GenServer state is rebuilt entirely from the persisted record rather than patched.

---

# 9. Non-Goals

This ADR intentionally does not define:

- the exact persistence backend (ADR-0008)
- the context compaction algorithm (ADR-0008)
- whether future implementations should use `:gen_statem` instead of `GenServer`
- model inference implementation (ADR-0019)
- tool execution implementation (ADR-0005 and ADR-0016)
- routing and addressing details (ADR-0007)

---

# 10. Future Extensions

- Migrating high-complexity instance types from `GenServer` to `:gen_statem` for richer state machine semantics.
- Streaming checkpoint writes to reduce the latency of idle checkpoints.
- Structured execution traces that capture every state transition for full replay auditing.

---

# 11. Rationale

Elixir/OTP provides exactly the supervision, lifecycle, and fault-tolerance primitives that a multi-agent runtime requires. Modeling each Lemming instance as a supervised GenServer is the idiomatic choice and provides restartability, crash isolation, and process introspection for free.

The explicit state machine prevents the instance from silently accumulating undefined behavior. Named states like `waiting_model` and `retry_backoff` are observable from outside the process, which makes debugging and monitoring concrete rather than speculative.

The separation of the execution coordinator (GenServer) from its supporting services (context, model, accounting, audit) is a deliberate boundary: each service can evolve, be replaced, or be optimized independently without changing the Lemming's execution contract.
