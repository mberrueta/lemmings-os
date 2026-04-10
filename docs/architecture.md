# LemmingsOS - Architecture Overview

## Purpose

LemmingsOS is a self-hosted runtime for hierarchical autonomous agents. It provides structured lifecycle management, supervision, isolation, and observability for autonomous agents organized in a four-level hierarchy.

Five pillars guide all architecture decisions:

| Pillar | Constraint |
|---|---|
| Micro-agent architecture | Lemmings do one thing; no super-agents |
| Runtime, not prompts | Lifecycle and supervision, not workflow DAGs |
| Safety by design | All external actions go through typed Tools; no arbitrary code execution |
| True autonomy | Lemmings run for hours or days, retry, and resume after crashes |
| Local-first AI | Ollama and self-hosted models are first-class; cloud APIs are optional |

---

## Hierarchy

```text
World
  └── City
        └── Department
              └── Lemming
                    └── LemmingInstance
                          └── Message
```

- **World** is the hard isolation boundary.
- **City** is the runtime node identity inside a World.
- **Department** is the organizational and scheduling scope inside a City.
- **Lemming** is the durable agent definition.
- **LemmingInstance** is a runtime session spawned from a durable Lemming.
- **Message** is the durable transcript row for a runtime session.

The core relation is durable-definition to runtime-session:

```text
Lemming (definition) 1 ────< many LemmingInstances (runtime sessions)
LemmingInstance 1 ────< many Messages (durable transcript turns)
```

---

## Layered View

```text
LiveView / UI
  -> Contexts + Runtime entrypoint
       -> Runtime engine
            -> Postgres / ETS / DETS / PubSub / Telemetry / Model provider
```

### LiveView and UI

Current implementation references:

- `LemmingsOsWeb.Live.*`
- `LemmingsOsWeb.PageData.*`

Responsibilities:

- render hierarchy and runtime state to operators
- initiate spawn and follow-up input flows
- subscribe to per-instance PubSub topics for live status updates
- never start OTP runtime processes directly

### Contexts and runtime entrypoint

Current implementation references:

- `LemmingsOs.Worlds`
- `LemmingsOs.Cities`
- `LemmingsOs.Departments`
- `LemmingsOs.Lemmings`
- `LemmingsOs.LemmingInstances`
- `LemmingsOs.Runtime`
- `LemmingsOs.Config.Resolver`

Responsibilities:

- own World-scoped persistence APIs
- resolve effective configuration through the hierarchy
- snapshot resolved config at spawn time
- expose a single runtime orchestration boundary for spawn and session continuation

`LemmingsOs.LemmingInstances` owns durable runtime rows and transcript rows. `LemmingsOs.Runtime` owns end-to-end runtime orchestration such as spawning a session, starting the executor, ensuring scheduler and pool readiness, and wiring runtime signals.

### Runtime engine layer

The Phase 1 runtime engine is a formal architectural layer. It sits below contexts and above infrastructure.

#### Executor

Current implementation reference: `LemmingsOs.LemmingInstances.Executor`

Responsibilities:

- one supervised process per `LemmingInstance`
- own the in-memory FIFO work queue for a single session
- drive runtime status transitions
- publish runtime updates through PubSub and telemetry
- delegate model execution through `ModelRuntime`

The executor is an orchestration process. It is not the place for provider-specific HTTP logic.

#### DepartmentScheduler

Current implementation reference: `LemmingsOs.LemmingInstances.DepartmentScheduler`

Responsibilities:

- one scheduler per active Department
- own scheduling truth for queued instances in that Department
- select the oldest eligible instance first in Phase 1
- request scarce execution capacity before the executor begins processing

Namespace clarification:

- organizational scope: Department
- implementation namespace: `LemmingInstances`

This is intentional. The scheduler is part of the runtime engine, not a Department lifecycle manager. It is therefore distinct from Department management concerns such as a `Department.Manager`.

#### ResourcePool

Current implementation reference: `LemmingsOs.LemmingInstances.ResourcePool`

Responsibilities:

- gate concurrent execution against scarce model resources
- key capacity by resource key, not by Department or City
- allow many Departments to contend safely for the same model endpoint

Phase 1 resource keys look like `ollama:llama3.2`. The scarce thing is the model endpoint itself, so the pool is keyed by resource identity rather than organization.

The key detail is where that resource key comes from: scheduler admission and
model execution both read the same normalized active-model contract from the
runtime config snapshot. The scheduler does not independently choose a profile.

#### ModelRuntime

Current implementation references:

- `LemmingsOs.ModelRuntime`
- `LemmingsOs.ModelRuntime.Provider`
- `LemmingsOs.ModelRuntime.Providers.Ollama`

Responsibilities:

- assemble prompts from structured runtime context
- select and invoke the configured provider
- validate structured output
- normalize provider, model, token, and usage metadata

`ModelRuntime` is the dedicated model execution boundary. It is parallel to future Tool Runtime concerns, not a helper hidden inside `LemmingInstances`.

For Phase 1, `ModelRuntime` shares the same active-model selection contract used
by the scheduler: `config_snapshot.model_runtime.{profile, provider, model,
resource_key}`. This avoids drift between admission control and actual provider
execution.

#### Runtime state stores

Current implementation references:

- `LemmingsOs.LemmingInstances.EtsStore`
- `LemmingsOs.LemmingInstances.DetsStore`

Responsibilities:

- ETS stores active runtime coordination state
- DETS stores best-effort idle snapshots
- both stay behind the runtime engine boundary rather than leaking into the web layer

### Infrastructure and observability

Current implementation references:

- `LemmingsOs.PubSub`
- `LemmingsOs.Runtime.ActivityLog`
- `LemmingsOs.Runtime.Status`
- `:telemetry`

Responsibilities:

- broadcast scheduler and per-instance runtime signals
- expose runtime status for read models and diagnostics
- emit structured lifecycle and failure events with hierarchy metadata

---

## Runtime flow

### Spawn flow

```text
Operator on Lemming detail page
  -> submit Spawn form with first input
  -> LemmingsOs.Runtime.spawn_session/3
  -> LemmingsOs.LemmingInstances persists:
       - lemming_instances row
       - first lemming_instance_messages row with role = "user"
  -> Executor receives the same input as the first ephemeral work item in ETS
  -> Executor starts for the new instance
  -> DepartmentScheduler is notified that work is available
  -> session LiveView navigates to the instance page
```

Key contract points:

- only `active` Lemmings are spawnable
- the first user input is stored as a transcript message, not as a column on `lemming_instances`
- the first user input also exists as an ephemeral work item so the executor can process it without reading execution state directly from the transcript table
- `Message` is the durable transcript source of truth; the work item is the runtime execution unit
- `world_id`, `city_id`, and `department_id` are derived from the Lemming hierarchy, never from user input
- `started_at` records runtime process birth; `inserted_at` is only the durable row creation time
- there can be a brief `created` window where the row is already persisted but the executor has not initialized yet, so `started_at` is still `nil`

### Processing flow

```text
Executor
  -> queued
  -> DepartmentScheduler admits work
  -> ResourcePool grants capacity for resource key
  -> ModelRuntime invokes Providers.Ollama
  -> assistant reply persisted as lemming_instance_messages row
  -> status broadcast on "instance:<id>:status"
  -> queue empty => idle
```

The Phase 1 runtime status taxonomy is:

- `created`
- `queued`
- `processing`
- `retrying`
- `idle`
- `failed`
- `expired`

This is the deliberate Phase 1 subset of the richer execution taxonomy defined in ADR-0004.

---

## Persistence model

The runtime engine uses a three-tier persistence split.

### Postgres

Durable relational records:

- `worlds`
- `cities`
- `departments`
- `lemmings`
- `lemming_instances`
- `lemming_instance_messages`

Phase 1 runtime columns of note:

```text
lemming_instances
  id, lemming_id, world_id, city_id, department_id,
  status, config_snapshot, started_at, last_activity_at, stopped_at,
  inserted_at, updated_at

lemming_instance_messages
  id, lemming_instance_id, world_id, role, content,
  provider, model, input_tokens, output_tokens, total_tokens, usage,
  inserted_at
```

Deferred beyond Phase 1:

- `instance_ref`
- `parent_instance_id`
- `last_checkpoint_at`

### ETS

Active runtime state:

- per-instance FIFO queue
- current work item
- retry count and retry metadata
- prompt-assembly context
- active runtime status snapshot

The executor consumes work from this ephemeral queue. It does not treat the
`lemming_instance_messages` table as its execution queue.

### DETS

Best-effort idle snapshots:

- written when an instance becomes idle
- used as a future rehydration boundary
- deleted on expiry or other successful cleanup paths
- failure-tolerant; snapshot failure does not fail the runtime session

Automatic rehydration from DETS is explicitly out of scope for Phase 1.

---

## Failure and lifecycle model

### Executor failure

- the runtime session remains represented by its durable `lemming_instances` row
- supervision can restart the executor process
- runtime state recovery is bounded by the persisted row and any available idle snapshot
- Phase 1 does not promise full automatic rehydration from DETS

### Retry exhaustion

- invalid structured output or provider failure can move an instance into `retrying`
- retry exhaustion moves the instance into terminal `failed`
- terminal failures are visible in durable status and telemetry

### Idle expiry

- an idle instance remains reusable until `idle_ttl_seconds` elapses
- expiry moves the durable status to `expired`
- `stopped_at` is set only on terminal outcomes such as `failed` or `expired`
- ETS and DETS cleanup is best-effort

### City failure

- City liveness is derived from `last_seen_at` freshness
- the administrative City `status` is not rewritten automatically by heartbeat loss
- idle DETS snapshots remain a future extension point for recovery, not a Phase 1 operator guarantee

### Boot recovery contract

After application restart, Phase 1 recovery is intentionally limited.

- `recover_created_sessions/1` performs a bounded best-effort sweep of persisted instances in `created`, `queued`, `processing`, `retrying`, and `idle`
- if the latest transcript row is a pending `user` message, the runtime reattaches the session and replays that pending work by normalizing the durable state back to `created` and queueing it again
- if there is no pending trailing `user` message, the runtime reattaches the session as `idle`
- `queued`, `processing`, and `retrying` are therefore not resumed at exact in-flight position; they are only recoverable-at-best through transcript-driven replay or idle reattach
- `failed` is not auto-recovered at boot; it requires explicit `retry_session/2`
- `expired` is terminal and requires a new spawn rather than reattach

For a new reader, the practical rule is simple: Phase 1 preserves durable session identity and transcript across restart, but not exact in-flight provider execution state.

---

## ADR map

| Decision | ADR |
|---|---|
| Four-level hierarchy model | ADR 0002 |
| World as hard isolation boundary | ADR 0003 |
| Lemming execution model | ADR 0004 |
| Lemming persistence model | ADR 0008 |
| Model runtime provider boundary | ADR 0019 |
| Hierarchical configuration model | ADR 0020 |
| Core domain schema | ADR 0021 |
| Deployment and packaging model | ADR 0022 |

---

## Future work

- richer execution taxonomy beyond the Phase 1 subset
- explicit rehydration from DETS idle snapshots
- delegation and lineage tracking across runtime sessions
- broader model provider set beyond `Providers.Ollama`
- future Tool Runtime concerns layered beside `ModelRuntime`
- distributed runtime coordination across multiple Cities
