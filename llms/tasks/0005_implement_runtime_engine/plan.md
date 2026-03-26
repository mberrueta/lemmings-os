# LemmingsOS -- 0005 Implement Runtime Engine (First Vertical Slice)

## Execution Metadata

- Spec / Plan: `llms/tasks/0005_implement_runtime_engine/plan.md`
- Created: `2026-03-26`
- Status: `PLANNING`
- Related Issue: TBD
- Upstream Dependency: Lemming Management merged in `PR #14`

## Goal

Deliver the first real **runtime vertical slice** for LemmingsOS so that a durable `Lemming` definition can spawn one or more supervised `LemmingInstance` processes, accept a first request, process work through a resource-aware Department scheduler, execute against a local Ollama model, and expose live runtime state in the UI.

The branch should end with:

- a persisted `lemming_instances` table scoped by `world_id`, `city_id`, `department_id`, and `lemming_id`
- a persisted `lemming_instance_messages` table for durable conversation transcripts
- a `LemmingsOs.LemmingInstances.LemmingInstance` schema and `LemmingsOs.LemmingInstances` context
- a `LemmingsOs.LemmingInstances.Message` schema for durable transcript messages
- a `LemmingInstance` executor GenServer with per-instance FIFO queue, state machine, retry logic, and idle timeout
- a `DepartmentScheduler` GenServer per Department for resource-aware dispatch
- a resource pool controlling Ollama model concurrency
- Ollama-backed model execution via `Req` with structured output contract and retry
- ETS-backed ephemeral runtime state (queue, retries, internal context) with best-effort DETS snapshot on idle
- a Spawn flow from the Lemming detail page (modal with first request input)
- an Instance session page with live status updates via PubSub
- visible runtime states: `created`, `queued`, `processing`, `retrying`, `idle`, `failed`, `expired`
- telemetry events on all key lifecycle transitions
- controllable scheduler/pool gates for deterministic testing
- the product feeling like a real runtime system, not only a management UI

---

## Project Context

### Related Entities

- `LemmingsOs.Lemmings.Lemming` -- Durable agent definition; parent for runtime instances
  - Location: `lib/lemmings_os/lemmings/lemming.ex`
  - Key fields: `slug`, `name`, `instructions`, `status` (`draft`/`active`/`archived`), 5 config buckets
  - Only `active` lemmings should be spawnable
- `LemmingsOs.Lemmings` -- Context owning Lemming CRUD, lifecycle, topology summary
  - Location: `lib/lemmings_os/lemmings.ex`
  - Key functions: `list_lemmings/2`, `get_lemming/2`, `set_lemming_status/2`
- `LemmingsOs.Departments.Department` -- Structural parent; scheduler scope
  - Location: `lib/lemmings_os/departments/department.ex`
  - Key fields: `slug`, `name`, `status`, `world_id`, `city_id`
- `LemmingsOs.Cities.City` -- Runtime node identity
  - Location: `lib/lemmings_os/cities/city.ex`
  - Key fields: `node_name`, `status`, `last_seen_at`
- `LemmingsOs.Worlds.World` -- Hard isolation boundary
  - Location: `lib/lemmings_os/worlds/world.ex`
- `LemmingsOs.Config.Resolver` -- Hierarchical config resolution (World -> City -> Department -> Lemming)
  - Location: `lib/lemmings_os/config/resolver.ex`
  - Already resolves Lemming scope including `tools_config`; runtime must snapshot resolved config at spawn time
- `LemmingsOs.Config.RuntimeConfig` -- Contains `idle_ttl_seconds` used for instance idle timeout
  - Location: `lib/lemmings_os/config/runtime_config.ex`
- `LemmingsOs.Cities.Heartbeat` -- OTP GenServer pattern to follow for runtime processes
  - Location: `lib/lemmings_os/cities/heartbeat.ex`
  - Pattern: injectable deps, `:manual` interval for tests, `start_supervised/1` friendly
- `LemmingsOs.Cities.Runtime` -- Runtime identity resolution pattern
  - Location: `lib/lemmings_os/cities/runtime.ex`
- `LemmingsOs.PubSub` -- Phoenix.PubSub configured in Application; acceptable for runtime signals
  - Location: configured in `lib/lemmings_os/application.ex`

### Related Features

- **Lemming Detail** (`lib/lemmings_os_web/live/lemmings_live.ex`)
  - Currently shows definition with overview/settings tabs
  - Must be extended with: Spawn CTA, active instances list, instance navigation
  - Template: `lib/lemmings_os_web/live/lemmings_live.html.heex`
- **Lemming Components** (`lib/lemmings_os_web/components/lemming_components.ex`)
  - Reusable UI components for Lemming rendering
- **Home Dashboard** (`lib/lemmings_os_web/page_data/home_dashboard_snapshot.ex`)
  - Topology card may later gain instance counts; out of scope for this issue

### Naming Conventions Observed

- **Context modules**: `LemmingsOs.Worlds`, `LemmingsOs.Cities`, `LemmingsOs.Departments`, `LemmingsOs.Lemmings` (plural noun)
- **Schema modules**: nested under context, singular -- `LemmingsOs.Lemmings.Lemming`
- **New context**: `LemmingsOs.LemmingInstances` (plural noun, following convention)
- **New schemas**: `LemmingsOs.LemmingInstances.LemmingInstance`, `LemmingsOs.LemmingInstances.Message`
- **Tables**: `lemming_instances`, `lemming_instance_messages` (plural snake_case)
- **Primary keys**: UUID via `@primary_key {:id, :binary_id, autogenerate: true}`
- **Timestamps**: `timestamps(type: :utc_datetime)`
- **Context functions**: `list_*`, `get_*`, `create_*`, `update_*`, `topology_summary`
- **Filter pattern**: private multi-clause `filter_query/2` with pattern matching on keyword list
- **OTP processes**: GenServer with injectable deps, configurable intervals, `start_link/1` + `child_spec/1`
- **Process names**: derived from stable DB IDs (UUIDs), never from runtime-generated atoms
- **Factories**: `LemmingsOs.Factory` in `test/support/factory.ex`
- **Gettext domain**: `dgettext("default", ".some_key")` for status translations

### ADRs That Constrain This Work

- **ADR-0002**: `World -> City -> Department -> Lemming` hierarchy is canonical
- **ADR-0003**: World is the hard isolation boundary; all instance APIs must be World-scoped
- **ADR-0004**: Lemming execution model -- on-demand spawn, OTP supervision, configuration snapshot isolation, lightweight process state with delegated concerns
- **ADR-0008**: Lemming persistence model -- ETS for active state, DETS for idle snapshots, Postgres for durable records; secrets never in persistence; context compaction decoupled from instance
- **ADR-0019**: Model provider execution model -- provider contract, prompt assembly, structured output, token tracking, Ollama as primary
- **ADR-0020**: Hierarchical configuration model; resolved config must be snapshotted at spawn time per ADR-0004
- **ADR-0021**: Core domain schema; describes `lemming_instances` table shape -- this issue implements it

---

## Terminology Alignment

### `LemmingInstance` -- Validated

ADR-0021 defines `lemming_instances` as runtime execution records bound to a `Lemming`. This issue implements that entity exactly as described. The Elixir schema will be `LemmingsOs.LemmingInstances.LemmingInstance` following the project's `Context.Schema` naming pattern.

### `Message` -- New Term, Formally Established

The draft describes "durable transcript messages" as separate persisted records per instance. This plan formalizes the schema as `LemmingsOs.LemmingInstances.Message` with table `lemming_instance_messages`. This entity is not described in ADR-0021 (which predates the message-level persistence decision) and must be documented in the ADR update.

### `work item` -- In-Memory Only

A "work item" is the ephemeral in-memory representation of a processable request. Work items live in the instance's ETS-backed queue and are **never persisted to Postgres**. They must be clearly distinguished from `Message` records, which are the durable transcript output. One work item may produce zero or more durable `Message` records.

### `DepartmentScheduler` -- New OTP Process, Formally Established

A novel runtime process type. One `DepartmentScheduler` exists per active Department. It owns scheduling truth for all instances within that Department. The module will be `LemmingsOs.LemmingInstances.DepartmentScheduler`.

### `ModelRuntime` -- Dedicated Runtime Boundary, Formally Established

Model inference is not a `LemmingInstances` concern. It must sit behind a dedicated runtime boundary parallel to future Tool Runtime concerns. In this issue, the executor delegates model execution to `LemmingsOs.ModelRuntime`, which in turn dispatches to a provider behaviour implementation such as `LemmingsOs.ModelRuntime.Providers.Ollama`.

### `session` -- Maps to `LemmingInstance` Lifetime

The draft uses "session" loosely. In this plan, a session is the lifetime of a single `LemmingInstance` -- from `created` to `expired` or `failed`. The instance page is the session page.

### `Spawn` -- Canonical Action Name

"Spawn" is the user-facing CTA and the domain verb for creating a new `LemmingInstance` from a durable `Lemming` definition. Persistence lives in `LemmingsOs.LemmingInstances`, while the web layer should call a single runtime/application entrypoint such as `LemmingsOs.Runtime.spawn_session/3` to perform the full spawn lifecycle.

### First Input Persistence -- Modal Input Becomes First Message

The spawn modal requires a non-empty text input from the user. This input is **not** stored on `LemmingInstance`. It is persisted exclusively as the first `Message` with `role = "user"` on that instance. The `LemmingInstance` row itself carries no copy of this text. The `Message` table is the single source of truth for transcript content.

### Instance Status Taxonomy vs Lemming Definition Statuses

The `LemmingInstance` status field uses a **completely separate** set of values from the `Lemming` definition statuses:

| Lemming (definition) | LemmingInstance (runtime) |
|---|---|
| `draft` | `created` |
| `active` | `queued` |
| `archived` | `processing` |
| | `retrying` |
| | `idle` |
| | `failed` |
| | `expired` |

These two status taxonomies must never be confused. Definition statuses govern operator-facing lifecycle. Instance statuses govern runtime execution state.

### Mock Status Field Mapping

The existing mock data in `LemmingsOs.MockData` uses runtime-oriented statuses (`:running`, `:thinking`, `:idle`, `:error`). These are replaced by the formal instance status taxonomy above. The mapping is:

| Mock status | Instance status | Notes |
|---|---|---|
| `:running` | `processing` | Active model execution |
| `:thinking` | `processing` | No separate thinking state in v1 |
| `:idle` | `idle` | Queue empty, awaiting work or timeout |
| `:error` | `failed` | Terminal error after retry exhaustion |

---

## Frozen Contracts / Resolved Decisions

### 1. Runtime model separation

- `Lemming` is the durable definition/configuration (already implemented in PR #14).
- `LemmingInstance` is the runtime execution/session.
- A `Lemming` may have many `LemmingInstances`.
- This issue is **single-lemming execution only**. No tools. No lemming-to-lemming execution. No dependency graph.
- Model execution crosses a dedicated `ModelRuntime` boundary. `LemmingInstances` owns orchestration and lifecycle; `ModelRuntime` owns provider selection, prompt assembly, structured output validation, and provider-specific HTTP details.
- Spawn lifecycle also crosses a dedicated runtime/application boundary. `LemmingInstances` owns durable persistence APIs; `LemmingsOs.Runtime` owns the end-to-end spawn workflow that persists state, starts the executor, wakes the scheduler if needed, and returns the new `instance_id`.

### 2. LemmingInstance table shape

```text
lemming_instances
  id                  UUID PK
  lemming_id          FK -> lemmings.id, NOT NULL
  world_id            FK -> worlds.id, NOT NULL
  city_id             FK -> cities.id, NOT NULL
  department_id       FK -> departments.id, NOT NULL
  status              string, NOT NULL, default "created"
  config_snapshot     jsonb, NOT NULL
  started_at          utc_datetime, nullable
  stopped_at          utc_datetime, nullable
  last_activity_at    utc_datetime, nullable
  inserted_at         utc_datetime
  updated_at          utc_datetime
```

**Divergence from ADR-0021**: The ADR describes `instance_ref`, `parent_instance_id`, and `last_checkpoint_at`. These are deferred:
- `instance_ref` -- not needed in v1; the UUID `id` serves as the stable process identity
- `parent_instance_id` -- required for lemming-to-lemming execution, which is out of scope
- `last_checkpoint_at` -- deferred until rehydration is implemented

**Additions over ADR-0021**:
- `config_snapshot` -- the frozen resolved configuration at spawn time (per ADR-0004 requirement for configuration snapshot isolation)
- `started_at` -- when the OTP executor process was born (set once at spawn, not at first work item); `inserted_at` is record creation, `started_at` is process birth
- `last_activity_at` -- updated on every real runtime move (status transition, work item completed, retry, idle entry)
- `stopped_at` -- set only on terminal outcomes (`failed`, `expired`); never set on intermediate states

### 3. Message table shape

```text
lemming_instance_messages
  id                  UUID PK
  lemming_instance_id FK -> lemming_instances.id, NOT NULL
  world_id            FK -> worlds.id, NOT NULL
  role                string, NOT NULL (values: "user", "assistant")
  content             text, NOT NULL
  provider            string, nullable
  model               string, nullable
  input_tokens        integer, nullable
  output_tokens       integer, nullable
  total_tokens        integer, nullable
  usage               jsonb, nullable
  inserted_at         utc_datetime
```

**Design rationale**: Messages are the durable transcript. Only final visible responses are persisted -- not raw provider payloads, not technical failure messages, not retry attempts. The `role` field uses `"user"` and `"assistant"` (matching LLM API conventions). Future `origin` enrichment (user vs lemming vs system) can be added as a separate column without breaking this shape.

`total_tokens` is stored as a convenience aggregate alongside `input_tokens` / `output_tokens`, since some providers report only the total. `usage` is a nullable JSONB cushion for provider-specific fields that do not map cleanly to the normalized columns (e.g., Anthropic cache token breakdowns, OpenAI reasoning tokens, Ollama eval/prompt duration). It must never be required by application logic -- if the field is absent the message is still valid. This prevents a premature schema migration when the next provider introduces a novel usage shape.

### 4. Instance status taxonomy (v1 operational subset)

> **Scope note**: ADR-0004 defines a richer execution state model including `waiting_model`, `waiting_tool`, `retry_backoff`, `completed`, and others intended for the full autonomy runtime. The statuses below are a **v1 operational subset** — coarser-grained states sufficient for the first runtime slice. They do not contradict ADR-0004; they are a deliberate simplification that the ADR update for this issue must document explicitly. The full ADR taxonomy remains the target for future milestones.

Allowed v1 runtime statuses:

- `created` -- instance record exists, not yet scheduled
- `queued` -- instance has work, waiting for scheduler admission
- `processing` -- actively executing a work item against the model
- `retrying` -- current work item failed structured validation, retrying (n/max_attempts)
- `idle` -- queue is empty, instance is alive and reusable
- `failed` -- terminal error after retry exhaustion or unrecoverable runtime error
- `expired` -- idle timeout elapsed, instance has been terminated

**Transitions**:
```text
created -> queued (scheduler notified)
queued -> processing (scheduler admits, pool grants capacity)
processing -> idle (work item completed, queue empty)
processing -> queued (work item completed, more items in queue)
processing -> retrying (structured output validation failed)
retrying -> processing (retry attempt begins)
retrying -> failed (max retries exhausted)
idle -> queued (new work item arrives)
idle -> expired (idle timeout elapses)
```

### 5. ETS key schema

Ephemeral runtime state is stored in a named ETS table per City (or a single global table in v1):

```text
Table: :lemming_instance_runtime
Key: {instance_id :: binary()}
Value: %{
  queue: :queue.queue(),       # FIFO work items
  current_item: work_item | nil,
  retry_count: non_neg_integer(),
  max_retries: 3,
  context_messages: [map()],   # accumulated conversation context for prompt assembly
  status: atom(),
  started_at: DateTime.t(),      # process birth, set once at spawn
  last_activity_at: DateTime.t() # updated on every real runtime move
}
```

Work items are maps with at minimum: `id`, `content`, `origin` (`:user` | `:lemming` | `:system`), `inserted_at`.

### 6. Retry behavior

- Automatic retry per work item on structured output validation failure.
- Maximum attempts: `3` (configurable via resolved `runtime_config`).
- Retry is visible in the UI as `retrying (n/3)`.
- Queue does not advance while the current item is retrying.
- Non-structured-output failures (network errors, provider errors) also trigger retry.
- After max retries exhausted, the instance transitions to `failed`.

### 7. DepartmentScheduler ownership

- Scheduling truth belongs to the **DepartmentScheduler**.
- One scheduler per active Department.
- Scheduler is event-driven / push-based via PubSub.
- Global selection policy in v1: **oldest eligible first** (by `inserted_at` of the queued work item).
- Scheduler does not execute work directly -- it grants admission tokens to instance executors.
- Future dependency-aware scheduling must be left explicit in the interface but not implemented.

**Namespace clarification**: The module lives at `LemmingsOs.LemmingInstances.DepartmentScheduler` because it is fully coupled to the instance runtime in this slice. Its **organizational scope** is the Department (one scheduler governs all instances within a Department); its **implementation namespace** is `LemmingInstances` (it is a runtime concern, not a Department management concern). The ADR update for this issue must document this distinction explicitly to avoid confusion with `Department.Manager`, which architecture.md already designates as responsible for Department lifecycle management.

### 8. Resource pool

- Execution capacity is controlled by a resource pool keyed by **resource key**, not by Department or City.
- The resource key identifies the scarce resource, not the organizational boundary. The bottleneck is the model endpoint, not the Department. Example key: `ollama:llama3.2`.
- **v1 implementation**: a single global pool per resource key. One `ResourcePool` process per active resource key, managed globally (not per-Department, not per-City).
- Pool is implemented as a simple counter-based semaphore (GenServer or ETS counter).
- Many instances across many Departments may contend for the same pool; only `pool_size` tokens may be held simultaneously.
- Pool capacity is configured via resolved `runtime_config` or application config.
- The resource key design means future per-City or per-Department pool scoping can be added by changing the key namespace (`city:<id>:ollama:llama3.2`) without changing the pool API contract.

### 9. Persistence split

**Postgres (durable)**:
- `LemmingInstance` record (identity, status, config snapshot, temporal markers)
- `Message` records (visible conversation transcript)

**ETS (ephemeral, active runtime)**:
- Work item queue
- Current item + retry state
- Accumulated conversation context for prompt assembly
- Runtime status (canonical; DB status is synced on transitions)

**DETS (best-effort snapshot)**:
- On transition to `idle`, attempt a best-effort DETS snapshot of the ETS entry
- Snapshot failure must not fail the instance
- Log the failure and emit telemetry
- Snapshot is used for future rehydration (out of scope for this issue)

### 10. DETS snapshot semantics

- Triggered on `processing -> idle` and `retrying -> idle` transitions.
- The snapshot captures the full ETS value for the instance.
- File location: configurable, defaults to `priv/runtime/dets/` (created at startup).
- One DETS file per Department (keyed by Department ID) or one global file -- implementation choice for the tech lead.
- On instance expiry, the DETS entry is deleted (best-effort).

### 11. Idle lifecycle

- When queue becomes empty after successful processing, instance transitions to `idle`.
- `idle` instances remain alive and reusable -- they can accept new work items.
- After `idle_ttl_seconds` (from resolved `runtime_config`, defaulting to 300 seconds), the instance auto-expires.
- Expiry terminates the executor process, sets DB status to `expired`, sets `stopped_at`, and cleans up ETS/DETS entries.
- Rehydration after restart/expiry is out of scope for this issue.

### 12. Spawn UX contract

- Main CTA is **Spawn** on the Lemming detail page (only for `active` lemmings).
- Spawn opens a modal/popup.
- Modal requires a non-empty text input (the first user message).
- If the user cancels, nothing is created.
- On confirm:
  1. Create `LemmingInstance` record in Postgres (status: `created`)
  2. Start executor GenServer process
  3. Enqueue the first work item in ETS
  4. Notify DepartmentScheduler via PubSub
  5. Navigate to the instance session page

### 13. Structured output contract

- LLM output must be JSON-parseable, not free text.
- Minimal v1 contract:
  ```json
  {
    "action": "reply",
    "reply": "The visible user-facing response text"
  }
  ```
- `reply` is the durable message content persisted to `lemming_instance_messages`.
- `action` is extensible (future: `"tool_call"`, `"delegate"`, etc.) but v1 only implements `"reply"`.
- Invalid structured output (parse failure or missing required fields) triggers retry.

### 14. Prompt assembly

The prompt sent to the model provider is assembled inside `ModelRuntime` at execution time from:
- **System message**: Lemming `instructions` + structured output contract definition + runtime rules
- **Conversation history**: accumulated user/assistant messages from ETS context
- **Current request**: the work item being processed

The prompt is **not** stored in its assembled form. Only the components are stored (instructions in `Lemming`, messages in ETS/Postgres, contract in code).

### 15. ModelRuntime and Ollama provider integration

- `LemmingsOs.ModelRuntime` is the orchestration boundary for model execution.
- A provider behaviour defines the execution contract used by `ModelRuntime`.
- The first provider implementation is `LemmingsOs.ModelRuntime.Providers.Ollama`.
- HTTP calls via `Req` (constitution mandates `Req` for all HTTP).
- `Req` dependency must be added to `mix.exs`: `{:req, "~> 0.5"}`.
- Endpoint: configurable via application config, defaults to `http://localhost:11434`.
- API: Ollama `/api/chat` endpoint with `format: "json"` for structured output.
- Model selection: from resolved `models_config` at spawn time (config snapshot).
- Timeout: configurable, default 120 seconds per request.
- Response parsing: extract `message.content`, parse as JSON, validate against structured output contract.
- `LemmingInstances.Executor` must not embed provider-specific details or call Ollama directly; it delegates to `ModelRuntime`.

### 16. PubSub topics

Runtime signals use `LemmingsOs.PubSub` with these topic patterns:

- `"department:#{department_id}:scheduler"` -- work available, instance state changes
- `"instance:#{instance_id}:status"` -- instance status transitions (for LiveView subscriptions)

### 17. Testability gate

- The DepartmentScheduler and resource pool must expose a controllable gate for tests.
- Gate allows tests to: pause admission, hold work in stable states, release execution deterministically.
- Pattern: injectable `:admission_mode` option (`:auto` for production, `:manual` for tests) following the `Heartbeat` pattern of `:manual` interval.

---

## User Stories

### US-1: Spawn a LemmingInstance from a Lemming definition

As an **operator**, I want to spawn a new runtime instance from an active Lemming definition by providing an initial request, so that I can see the agent execute real work against a model.

### US-2: View instance session with live status

As an **operator**, I want to view the session page of a running LemmingInstance, so that I can see its current status, conversation transcript, and runtime state updating live without page refresh.

### US-3: Send additional requests to an idle instance

As an **operator**, I want to send additional requests to an idle instance, so that I can continue a conversation within the same session context.

### US-4: See retry behavior on invalid output

As an **operator**, I want to see that an instance retries when the model returns invalid structured output, so that I can understand the system is self-healing and know when retries are exhausted.

### US-5: Instance expires after idle timeout

As an **operator**, I want idle instances to automatically expire after the configured timeout, so that resources are reclaimed and the system does not accumulate stale processes.

### US-6: Resource-aware scheduling constrains concurrency

As an **operator**, I want the system to respect model concurrency limits, so that multiple spawned instances queue for capacity rather than overwhelming the local Ollama server.

### US-7: View active instances from the Lemming detail page

As an **operator**, I want to see a list of active instances on the Lemming detail page, so that I can navigate to any running session or understand how many instances are alive.

### US-8: Instance failure is visible and terminal

As an **operator**, I want to see a clear failure state when an instance exhausts retries or hits a terminal error, so that I can diagnose issues and understand that the instance is no longer processing.

---

## Acceptance Criteria

### US-1: Spawn a LemmingInstance

**Scenario: Happy path spawn**
- **Given** an active Lemming with instructions and a reachable Ollama model
- **When** the operator clicks "Spawn" on the Lemming detail page, enters "Summarize the project roadmap" as the initial request, and confirms
- **Then** a `LemmingInstance` record is created in Postgres with status `created`
- **And** an executor GenServer process starts
- **And** the initial request is enqueued as the first work item
- **And** the operator is navigated to the instance session page

**Scenario: Spawn denied for non-active lemming**
- **Given** a Lemming in `draft` status
- **When** the operator views the Lemming detail page
- **Then** the "Spawn" button is disabled or hidden with an explanatory tooltip

**Scenario: Spawn denied with empty initial request**
- **Given** the Spawn modal is open
- **When** the operator leaves the initial request field empty and tries to confirm
- **Then** the confirm button is disabled or validation prevents submission

**Criteria Checklist:**
- [ ] `LemmingsOs.Runtime.spawn_session/3` (or equivalent runtime service) is the single spawn entrypoint used by the web layer
- [ ] The runtime service persists the instance record and first message via `LemmingsOs.LemmingInstances`
- [ ] The runtime service starts the executor and wakes the DepartmentScheduler if needed
- [ ] Config is snapshotted from `Config.Resolver.resolve/1` at spawn time
- [ ] `world_id`, `city_id`, `department_id` are set from the Lemming's hierarchy, not from user input
- [ ] The executor process is registered with a name derived from the instance UUID (not an atom from user input)
- [ ] LiveView does not directly start executors or notify schedulers
- [ ] On success: navigate to `/lemmings/instances/:id` (or equivalent route)
- [ ] `started_at` is set when the executor process starts (at spawn, not at first work item)

### US-2: View instance session with live status

**Scenario: Instance is processing**
- **Given** a LemmingInstance in `processing` status
- **When** the operator views the session page
- **Then** the status badge shows "Processing" with an elapsed time indicator
- **And** the conversation transcript shows the initial request

**Scenario: Instance completes and goes idle**
- **Given** a LemmingInstance that just completed processing its work item
- **When** the model returns a valid structured response
- **Then** the status badge updates to "Idle" without page refresh
- **And** the assistant's reply appears in the transcript

**Criteria Checklist:**
- [ ] Session page subscribes to `"instance:#{instance_id}:status"` PubSub topic
- [ ] Status changes are broadcast and reflected in the UI without full page reload
- [ ] Transcript shows user messages and assistant replies in chronological order
- [ ] Provider and model name are displayed per assistant message
- [ ] Token usage (input/output) is displayed per assistant message when available

### US-3: Send additional requests to an idle instance

**Scenario: Continue conversation**
- **Given** an idle LemmingInstance
- **When** the operator types a new request and submits
- **Then** the request is enqueued on the instance
- **And** the instance transitions from `idle` to `queued`
- **And** the new request appears in the transcript

**Criteria Checklist:**
- [ ] New requests are queued via the same work item mechanism as the initial request
- [ ] The DepartmentScheduler is notified of new work
- [ ] Context from previous messages is included in prompt assembly
- [ ] Queue is FIFO within the instance

### US-4: Retry behavior on invalid output

**Scenario: Model returns non-JSON response**
- **Given** a LemmingInstance processing a work item
- **When** the model returns plain text instead of the structured JSON contract
- **Then** the instance status changes to `retrying (1/3)`
- **And** the model is called again with the same prompt
- **And** the UI reflects the retrying state

**Scenario: Max retries exhausted**
- **Given** a LemmingInstance in `retrying` state at attempt 3/3
- **When** the third retry also returns invalid structured output
- **Then** the instance transitions to `failed`
- **And** the failure is logged with structured metadata

**Criteria Checklist:**
- [ ] Retry count is visible in the UI as `retrying (n/3)`
- [ ] Queue does not advance while current item is retrying
- [ ] Failed status is terminal for this issue (no manual retry/restart in v1)
- [ ] Each retry includes the full conversation context (not just the last message)

### US-5: Instance expires after idle timeout

**Scenario: Idle timeout**
- **Given** a LemmingInstance in `idle` status with `idle_ttl_seconds: 300`
- **When** 300 seconds elapse with no new work
- **Then** the executor process is terminated
- **And** the DB status is set to `expired` with `stopped_at` timestamp
- **And** ETS and DETS entries are cleaned up
- **And** the session page shows "Expired" status

**Criteria Checklist:**
- [ ] Idle timeout uses `idle_ttl_seconds` from the config snapshot (not live config)
- [ ] The timer is reset when new work arrives (idle -> queued transition)
- [ ] DETS snapshot is attempted before expiry cleanup
- [ ] Expired instances cannot accept new work

### US-6: Resource-aware scheduling

**Scenario: Pool at capacity**
- **Given** pool capacity is 1 and one instance is already processing
- **When** a second instance has work queued
- **Then** the second instance remains in `queued` status until the first completes

**Scenario: Pool releases capacity**
- **Given** one instance completes processing and releases its pool slot
- **When** another instance is waiting in `queued` status
- **Then** the scheduler admits the waiting instance and it transitions to `processing`

**Criteria Checklist:**
- [ ] Pool capacity is configurable (default: 1 for local Ollama)
- [ ] Scheduler uses oldest-eligible-first selection policy
- [ ] Multiple instances can be `queued` simultaneously
- [ ] Pool slots are released on completion, failure, and expiry

### US-7: View active instances on Lemming detail

**Scenario: Lemming has active instances**
- **Given** a Lemming with 2 active instances (1 processing, 1 idle)
- **When** the operator views the Lemming detail page
- **Then** both instances are listed with their current status, first user message preview, and creation time
- **And** the first user message preview is fetched by joining the earliest `Message` with `role = "user"` for each instance (no denormalized column on `lemming_instances`)

**Scenario: Lemming has no instances**
- **Given** a Lemming with no active instances
- **When** the operator views the Lemming detail page
- **Then** an empty state message is shown (e.g., "No active instances")

**Criteria Checklist:**
- [ ] Instance list is loaded from `LemmingsOs.LemmingInstances.list_instances/2`
- [ ] Only non-expired, non-failed instances are shown in the active list (or all with status badges)
- [ ] Each instance links to its session page
- [ ] The first user message preview is sourced from the earliest `Message` with `role = "user"` (via join or preload in `list_instances/2`); **no denormalized preview column on `lemming_instances`**

### US-8: Instance failure is visible

**Scenario: Terminal failure**
- **Given** a LemmingInstance that has exhausted all retries
- **When** the instance transitions to `failed`
- **Then** the session page shows a clear "Failed" status badge
- **And** the last attempted work item's context is preserved in the transcript
- **And** the operator can review what went wrong

**Criteria Checklist:**
- [ ] Failed status is rendered with error/danger styling
- [ ] The failure reason is logged with structured metadata (world_id, city_id, department_id, lemming_id, instance_id)
- [ ] Failed instances do not accept new work
- [ ] No raw provider error payloads are exposed to the operator

---

## Edge Cases

### Spawn Edge Cases

- [ ] Lemming has been archived between page load and spawn attempt -> Spawn fails with a clear error
- [ ] Ollama is unreachable at spawn time -> Instance is created but first processing attempt fails and triggers retry; if Ollama never responds, instance eventually `failed`
- [ ] Two operators spawn from the same Lemming simultaneously -> Both succeed; each gets an independent instance

### Scheduling Edge Cases

- [ ] Department has no DepartmentScheduler running -> Scheduler must start on demand (lazy initialization) or be pre-started for active Departments
- [ ] All pool capacity is consumed and 10 instances are queued -> All remain queued; oldest-first dispatch when capacity frees
- [ ] Instance is admitted by scheduler but executor process has crashed -> Scheduler must detect and release the pool slot

### Retry Edge Cases

- [ ] Model returns valid JSON but missing `action` field -> Treated as invalid structured output; triggers retry
- [ ] Model returns valid JSON with `action: "unknown_action"` -> Treated as invalid in v1; triggers retry
- [ ] Model returns empty string -> Treated as invalid; triggers retry
- [ ] Network timeout during model call -> Treated as retriable error; triggers retry

### Idle / Expiry Edge Cases

- [ ] New work arrives exactly as idle timeout fires -> Race condition; the idle timer should be cancelled when new work is enqueued; if the timer has already fired, the instance must be treated as expired (new work rejected)
- [ ] DETS snapshot fails (disk full, permissions) -> Instance still transitions to idle; failure is logged + telemetry emitted
- [ ] Node restarts while instances are idle -> All ETS state is lost; instances remain in DB with their last persisted status; rehydration is out of scope

### Message Persistence Edge Cases

- [ ] Model returns extremely long response -> Persisted as-is; no truncation in v1 (text column has no DB-level limit)
- [ ] Token counts not available from provider -> `input_tokens` and `output_tokens` are nullable; persisted as nil

### Process Safety Edge Cases

- [ ] Executor process crashes -> Supervisor restarts it; ETS state for that instance may be lost; instance DB status reflects last persisted state; recovery/rehydration is out of scope
- [ ] DepartmentScheduler crashes -> Supervisor restarts it; in-flight admissions may be lost; instances should re-announce via PubSub on scheduler restart

### Permission / Scope Errors

- [ ] Attempt to spawn from a Lemming in a different World -> Context function validates World scope
- [ ] Attempt to view an instance belonging to a different World -> 404 (not 403)

---

## UX States

### Lemming Detail Page -- Instances Section

| State | Behavior |
|-------|----------|
| **Loading** | Show skeleton while instance list loads |
| **Empty** | Show "No active instances" with Spawn CTA |
| **Populated** | Show instance list with status badges, first user message preview (joined from `Messages`), creation time |
| **Spawn Modal Open** | Modal overlay with initial request text input and Confirm/Cancel buttons |

### Instance Session Page

| State | Behavior |
|-------|----------|
| **Created** | Show "Starting..." with spinner |
| **Queued** | Show "Waiting for capacity..." status |
| **Processing** | Show "Processing" with elapsed time indicator; disable new request input |
| **Retrying** | Show "Retrying (n/3)" with warning styling |
| **Idle** | Show "Idle" with active request input for follow-up; show idle timeout countdown or indicator |
| **Failed** | Show "Failed" with error styling; request input disabled; show failure context |
| **Expired** | Show "Expired" with muted styling; request input disabled |
| **Not Found** | Show "Instance not found" if ID is invalid |

### Spawn Modal

| State | Behavior |
|-------|----------|
| **Initial** | Empty text input, Confirm button disabled until text is entered |
| **Valid Input** | Confirm button enabled |
| **Submitting** | Confirm button disabled with loading indicator |
| **Error** | Error message shown (e.g., "Failed to create instance"), form preserved |

---

## Explicitly Out of Scope

1. **Tool execution** -- Lemmings cannot invoke tools in this issue; `action: "reply"` is the only supported action
2. **Lemming-to-lemming execution** -- No `origin: :lemming` work items are processed
3. **Dependency graphs or blocked/unblocked resolution** -- Scheduler is simple oldest-first
4. **Cancellation/edit/reordering of queued items** -- Queue is append-only FIFO
5. **Rehydration/replay after restart** -- Idle DETS snapshots are written but not read back
6. **Prompt compaction/summarization** -- Context accumulates without compaction
7. **Provider-agnostic multimodal support** -- Text-only, Ollama-only in v1
8. **Complex fairness / priority / starvation policies** -- Oldest-first only
9. **Distributed scheduling across Cities/nodes** -- Single-City scheduling only
10. **Durable relational queue storage** -- Queue lives in ETS only
11. **Streaming responses** -- Full response only in v1; streaming deferred
12. **Instance topology counts on Home dashboard** -- Only Lemming definition counts exist today
13. **Manual retry/restart of failed instances** -- Failed is terminal in v1
14. **Authentication/authorization for spawn actions** -- No auth model exists yet (ADR-0010/0011)

---

## Future-Proofing Seams

The implementation must leave clean extension points for later addition of:

- **Tool execution**: the `action` field in the structured output contract is the seam; future actions like `"tool_call"` are parsed from the same contract
- **Lemming-to-lemming requests**: the `origin` field on work items (`:user` | `:lemming` | `:system`) is the seam; only `:user` is implemented in v1
- **Dependency-aware scheduling**: the `DepartmentScheduler` interface must accept a pluggable selection policy; v1 hardcodes oldest-first
- **Additional providers**: the model execution path must be behind a provider behaviour/module boundary, not hardcoded to Ollama's HTTP API shape
- **Tool Runtime parity**: `ModelRuntime` is the dedicated boundary for model inference and must remain parallel to future Tool Runtime concerns rather than being absorbed into `LemmingInstances`
- **Richer prompt/version tracing**: the `config_snapshot` on `LemmingInstance` preserves the full resolved config; future prompt versioning hooks into this
- **Durable/rehydratable queue**: DETS snapshots are the seam; future issues read them back on startup
- **Context compaction/summarization**: the ETS `context_messages` list is the seam; a future compaction service operates on this list
- **Higher-level runtime dashboards**: the `topology_summary` pattern on `LemmingInstances` context provides aggregate counts; future dashboard pages consume this
- **Streaming**: the model execution module must return results through a response struct, not raw HTTP; streaming can be added by changing the response delivery mechanism

---

## Task Breakdown

| Task | Agent | Description |
|---|---|---|
| 01 | `dev-db-performance-architect` | `lemming_instances` and `lemming_instance_messages` migrations, FKs, indexes, constraint review |
| 02 | `dev-backend-elixir-engineer` | `LemmingInstance` and `Message` schemas plus `LemmingInstances` context -- CRUD, status transitions, durable spawn persistence, list/query APIs |
| 03 | `dev-backend-elixir-engineer` | Instance executor GenServer -- state machine, queue, retry, idle timeout |
| 04 | `dev-backend-elixir-engineer` | DepartmentScheduler GenServer -- event-driven dispatch, pool admission, PubSub integration |
| 05 | `dev-backend-elixir-engineer` | Resource pool -- counter-based concurrency control |
| 06 | `dev-backend-elixir-engineer` | ETS runtime state management -- table setup, read/write, cleanup |
| 07 | `dev-backend-elixir-engineer` | DETS snapshot -- write on idle, delete on expiry, failure tolerance |
| 08 | `dev-backend-elixir-engineer` | ModelRuntime boundary, provider behaviour, and Ollama provider -- `Req`-based HTTP client, prompt assembly, structured output parsing |
| 09 | `dev-backend-elixir-engineer` | PubSub topic setup and broadcast helpers |
| 10 | `dev-frontend-ui-engineer` | Lemming detail page -- Spawn CTA, spawn modal, active instances list |
| 11 | `dev-frontend-ui-engineer` | Instance session page -- route, status display, conversation transcript, live updates |
| 12 | `dev-frontend-ui-engineer` | Instance session page -- follow-up request input for idle instances |
| 13 | `dev-backend-elixir-engineer` | Add `Req` dependency to `mix.exs` |
| 14 | `dev-backend-elixir-engineer` | Runtime service and application supervisor updates -- `Runtime.spawn_session`, DynamicSupervisor for executors, scheduler startup |
| 15 | `dev-backend-elixir-engineer` | Testability gates -- admission mode, pool gate, injectable deps for executor and scheduler |
| 16 | `dev-logging-daily-guardian` | Structured logging and telemetry events for all lifecycle transitions |
| 17 | `qa-test-scenarios` | Test scenario and coverage plan |
| 18 | `qa-elixir-test-author` | ExUnit tests -- schema, context, executor, scheduler, pool, FIFO, retry, idle expiry |
| 19 | `qa-elixir-test-author` | LiveView tests -- spawn flow, session page, live status updates |
| 20 | `dev-backend-elixir-engineer` | Factory additions -- `:lemming_instance`, `:lemming_instance_message` |
| 21 | `dev-backend-elixir-engineer` | Branch validation, `mix test`, `mix precommit` |
| 22 | `tl-architect` | ADR updates -- ADR-0021 (add `lemming_instance_messages`, update `lemming_instances` shape), new ADRs for runtime state split, DepartmentScheduler, instance lifecycle |
| 23 | `audit-pr-elixir` | Security and performance review |
| 24 | `audit-pr-elixir` | Final PR audit |

## Task Sequence

| # | Task | Status | Approved |
|---|---|---|---|
| 13 | Add Req Dependency | PENDING | [ ] |
| 01 | Runtime Table Migrations and Indexes | PENDING | [ ] |
| 02 | Runtime Schemas and Context | PENDING | [ ] |
| 20 | Factory Additions | PENDING | [ ] |
| 09 | PubSub Topic Setup and Broadcast Helpers | PENDING | [ ] |
| 06 | ETS Runtime State Management | PENDING | [ ] |
| 05 | Resource Pool | PENDING | [ ] |
| 07 | DETS Snapshot | PENDING | [ ] |
| 08 | ModelRuntime and Ollama Provider | PENDING | [ ] |
| 03 | Instance Executor GenServer | PENDING | [ ] |
| 04 | DepartmentScheduler GenServer | PENDING | [ ] |
| 15 | Testability Gates | PENDING | [ ] |
| 14 | Application Supervisor Updates | PENDING | [ ] |
| 16 | Structured Logging and Telemetry | PENDING | [ ] |
| 10 | Lemming Detail Page -- Spawn and Instances | PENDING | [ ] |
| 11 | Instance Session Page -- Core | PENDING | [ ] |
| 12 | Instance Session Page -- Follow-up Input | PENDING | [ ] |
| 22 | ADR and Architecture Updates | PENDING | [ ] |
| 17 | Test Scenarios and Coverage Plan | PENDING | [ ] |
| 18 | ExUnit Tests -- Backend | PENDING | [ ] |
| 19 | LiveView Tests -- Frontend | PENDING | [ ] |
| 21 | Branch Validation and Precommit | PENDING | [ ] |
| 23 | Security and Performance Review | PENDING | [ ] |
| 24 | Final PR Audit | PENDING | [ ] |

---

## Acceptance Criteria (Branch-Level)

The branch is reviewable only when all of the following are true:

- a persisted `lemming_instances` table exists with `lemming_id`, `world_id`, `city_id`, `department_id`, `status`, `config_snapshot`, temporal markers
- a persisted `lemming_instance_messages` table exists with `lemming_instance_id`, `world_id`, `role`, `content`, provider/model/token fields
- `LemmingsOs.LemmingInstances.LemmingInstance` and `LemmingsOs.LemmingInstances.Message` schemas exist
- `LemmingsOs.LemmingInstances` context exposes a small explicit API including `spawn_instance/3`, `get_instance/2`, `list_instances/2`, `update_status/3`, `enqueue_work/3`, `list_messages/2`, and `topology_summary/1`
- `LemmingsOs.Runtime.spawn_session/3` (or equivalent runtime service) owns the end-to-end spawn lifecycle used by the web layer
- Instance executor GenServer manages per-instance FIFO queue, state machine, retry, and idle timeout
- DepartmentScheduler dispatches work using oldest-eligible-first with pool-bounded concurrency
- Resource pool limits concurrent model execution (default: 1 for Ollama)
- Ollama model execution works via `Req` with structured output contract and retry on invalid output
- ETS stores ephemeral runtime state; DETS snapshots are attempted on idle
- Spawn flow works from the Lemming detail page (modal with initial request)
- Instance session page shows live status updates, conversation transcript, and follow-up input
- All 7 runtime statuses are rendered correctly in the UI
- PubSub is used for runtime signals between scheduler, executor, and LiveView
- Testability gates allow deterministic testing of scheduler admission and pool capacity
- Telemetry events are emitted on all key lifecycle transitions with full hierarchy metadata
- `Req` is added to `mix.exs` dependencies
- No `MockData` calls are introduced for runtime state
- Tests cover: schema/changeset, context CRUD, executor state machine, scheduler dispatch, pool capacity, FIFO ordering, retry logic, idle expiry, spawn flow, session page LiveView
- `mix test` passes
- `mix precommit` passes
- coverage report is generated
- ADR updates document: `lemming_instance_messages` as a new entity, updated `lemming_instances` shape divergence from ADR-0021, runtime state split (ETS/DETS/Postgres), DepartmentScheduler as a formal runtime component

---

## Assumptions

1. `Req ~> 0.5` is available and compatible with the current dependency set.
2. Ollama is running locally at `http://localhost:11434` during development and can serve at least one model (e.g., `llama3.2`).
3. The existing `Config.Resolver` already handles Lemming scope (confirmed in codebase) and `runtime_config.idle_ttl_seconds` provides the idle timeout value.
4. The `LemmingsOs.PubSub` configured in `Application` is sufficient for local runtime signals in v1 (no distributed PubSub needed).
5. Process names for executors and schedulers will use `{:via, Registry, {RegistryName, uuid}}` pattern or equivalent, not atom-based names.
6. This issue does not introduce authentication or authorization for spawn/view actions (no auth model exists yet per ADR-0010/0011 status).
7. The branch builds on top of PR #14 (Lemming Management) which has been merged to main.

---

## Risks / Open Questions

1. **Ollama availability in CI**: Tests that hit Ollama need either a running instance in CI or a mock/bypass strategy. The `Bypass` library is already in `mix.exs` and should be used for HTTP-level mocking of the Ollama API in tests.

2. **ETS table ownership and lifecycle**: If the executor process owns the ETS entry and crashes, the entry survives only if the ETS table is owned by a longer-lived process (e.g., the DynamicSupervisor or a dedicated ETS owner process). This ownership model needs careful design.

3. **Race between idle timeout and new work**: The idle timeout timer and incoming work PubSub messages can race. The executor must handle this atomically -- either cancel the timer or reject the work if expiry has already been initiated.

4. **DepartmentScheduler discovery**: When a new instance spawns in a Department, the scheduler for that Department must exist. Options: (a) lazy-start schedulers on first spawn, (b) pre-start for all active Departments at boot. The tech lead should decide.

5. **Pool scope**: Is the resource pool per-Department, per-City, or global? The draft implies a global Ollama concurrency limit. In v1, a single global pool is simplest and correct for a single-City deployment. The interface should allow future scoping.

6. **Config snapshot size**: The `config_snapshot` JSONB column stores the full resolved config at spawn time. For v1 this is small, but should be bounded or at least monitored.

7. **DETS reliability**: DETS has known limitations (corruption risk on crash, 2GB file size limit). For v1 best-effort snapshots this is acceptable, but the ADR should document these limitations and the expected migration path to a more durable store.

---

## ADR / Doc Update Requirements

> **This is a required task, not optional.**

This issue must update the relevant ADRs and architecture docs in the same branch.

Those updates must:

- **ADR-0021**: Add `lemming_instance_messages` as a new entity in the core domain schema; update the `lemming_instances` table shape to reflect the actual implementation (divergence from original: `config_snapshot` instead of `config_jsonb`, addition of `last_activity_at`, deferral of `instance_ref` and `parent_instance_id`; no `initial_request` column -- first input persisted only as the first Message)
- **New ADR or ADR-0008 amendment**: Document the runtime state split -- ETS for active state, DETS for idle snapshots, Postgres for durable records; the specific data that lives in each layer; the DETS limitations and expected migration path
- **New ADR or ADR-0004 amendment**: Document the DepartmentScheduler as a formal runtime component with defined responsibilities, lifecycle, and interface contract
- **ADR-0019 relevance note**: Document that the first provider integration (Ollama) is implemented in this issue; note the structured output contract and the provider module boundary for future expansion

---

## Change Log

| Date | Task | Change | Reason |
|---|---|---|---|
| 2026-03-26 | Plan | Created implementation-ready plan from draft spec | PO review: validated against codebase, aligned terminology, formalized frozen contracts, created acceptance criteria and task sequence |
