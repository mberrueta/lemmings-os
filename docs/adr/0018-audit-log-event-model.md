# ADR-0018 — Audit Log / Event Model

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

Multiple LemmingsOS ADRs already depend on a shared audit and event model, but that model has not yet been defined centrally.

Today the architecture already references concepts such as:

- append-only audit log
- audit events for secret access and secret changes
- authentication and authorization audit events
- tool approval lifecycle events
- tool execution events
- cost governance events
- structured telemetry and runtime observability

However, without a single ADR defining the platform event model, several important questions remain ambiguous:

- what fields every event must contain
- how actors, scope, and resources are represented
- how traceability works across multi-step flows
- how audit events differ from telemetry events
- what immutability guarantees apply
- how events are queried, retained, and indexed

Because LemmingsOS is designed as a self-hosted runtime for autonomous systems, auditability is not optional.

Operators must be able to answer questions such as:

- who changed this policy?
- which user approved this tool execution?
- which Lemming accessed this credential-bound capability?
- why was a tool execution denied?
- which sequence of events led to a failure or cost spike?

The event model must therefore support both:

1. **forensic auditability** for security and governance
2. **operational observability** for debugging and monitoring

The model must also align with the system hierarchy:

```text
World → City → Department → Lemming
```

and remain practical for version 1 self-hosted deployments using PostgreSQL as the default durable system database.

---

# 2. Decision Drivers

1. **Multiple subsystems already depend on audit events** — ADRs 0009 through 0015 all
   reference audit events without a shared contract. A central definition is required
   to resolve field naming ambiguity, prevent per-subsystem schema drift, and ensure
   cross-subsystem correlation works.

2. **Forensic traceability is a first-class requirement** — The system manages
   autonomous agents that may affect production systems, infrastructure, and financial
   resources. Operators must be able to reconstruct any multi-step event chain post-hoc,
   including who approved what and which agent caused which side effect.

3. **Self-hosted constraint** — The event model must work with PostgreSQL as the only
   required storage dependency. Kafka, NATS, or dedicated event infrastructure must not
   be required. Self-hosted operators should not need to operate a message broker to
   have governance coverage.

4. **Distinct semantics for audit vs telemetry** — Security and governance records
   require strong immutability and long retention. Operational metrics may have shorter
   retention and different querying patterns. Both must share infrastructure but must
   remain semantically distinct.

5. **Cross-subsystem correlation** — A single operator action may produce events across
   auth, tool authorization, approval, secret resolution, and cost governance. The model
   must provide a `correlation_id` and `causation_id` mechanism to reconstruct these
   chains without requiring a separate tracing infrastructure.

6. **Prevent per-subsystem schema drift** — Without a central ADR, each subsystem
   invents slightly different field names, actor representations, and scope encodings.
   A unified canonical envelope eliminates this class of consistency problem.

---

# 3. Considered Options

## Option A — Per-subsystem event schemas, each subsystem defines its own format

Each subsystem (auth, tool runtime, approval manager, cost governance) defines its own
event table or log format independently.

**Pros:**

- each subsystem can optimize its schema for its specific query patterns
- no cross-subsystem coordination required during development

**Cons:**

- forensic reconstruction across subsystems requires joining inconsistently structured
  records with different field names for the same concepts (actor, scope, resource)
- `correlation_id` semantics must be agreed on informally; without a central definition,
  implementations will diverge
- adding a new observability dashboard requires understanding multiple incompatible schemas
- the audit guarantee (append-only, immutable) must be implemented and verified
  independently in every subsystem

Rejected. The forensic traceability requirement cannot be satisfied by a collection of
independently designed schemas. Cross-subsystem event reconstruction is the primary
governance use case and must be a first-class design goal.

---

## Option B — Separate audit log and telemetry infrastructure with distinct tables and schemas

Audit events go to a dedicated `audit_events` table (or service). Telemetry events go
to a separate `telemetry_events` table with different fields. Each family is managed
independently.

**Pros:**

- strict separation of retention and immutability policies
- each table can be optimized independently

**Cons:**

- shared query patterns (filtering by correlation_id, by actor, by City) must be
  implemented against two separate tables
- the canonical envelope fields (event_id, occurred_at, world_id, correlation_id) would
  be duplicated between schemas, creating maintenance overhead
- the conceptual overhead of routing each new event type to the correct table adds
  friction for contributors

Rejected. The overhead of maintaining two separate schemas for what are structurally
similar records does not justify the separation. Retention and semantic differences can
be expressed through an `event_family` field in a shared table.

---

## Option C — Unified canonical event envelope with explicit event_family distinction (chosen)

All durable platform events share the same base envelope schema stored in a single
PostgreSQL table. Events are distinguished by `event_family` (audit vs telemetry) and
`event_type`. Retention policy and immutability guarantees are enforced at the
`event_family` level.

**Pros:**

- single schema to implement, document, and query across all subsystems
- cross-subsystem forensic reconstruction works with a single query by `correlation_id`
- adding a new event type requires only naming the event and defining its payload;
  the envelope and infrastructure are already in place
- immutability guarantees apply uniformly to the entire store
- PostgreSQL is already required; no new operational dependency

**Cons:**

- all event producers must adopt the shared envelope, which requires up-front
  coordination during development
- a single table may grow large in active systems; retention and indexing require
  deliberate maintenance
- telemetry and audit sharing storage means a misconfigured deletion policy could
  accidentally affect audit records

Chosen. The forensic traceability and operational simplicity requirements favor a single
unified model. The risks are manageable through explicit retention policy separation
and careful index design.

---

# 4. Decision

LemmingsOS adopts a **unified platform event model** with a shared canonical envelope and two explicit event families:

- `audit`
- `telemetry`

All durable platform events use the same base envelope.

Each event:

- is immutable once written
- is append-only
- is tagged with hierarchy scope
- records actor and resource context when applicable
- supports correlation across multi-step workflows
- stores event-specific details in a structured payload

Version 1 stores durable events in a **single PostgreSQL-backed event store**.

The platform distinguishes clearly between:

- **audit events**: security, governance, control-plane, approval, and important runtime decision records
- **telemetry events**: operational lifecycle, counters, timings, and other observability-oriented records

Both families may share the same storage table and base schema in v1, but they must remain semantically distinct through explicit fields and retention policy.

---

# 5. Event Families

## 5.1 Audit Events

Audit events record actions or decisions that matter for governance, accountability, security, or forensic reconstruction.

Typical audit events include:

- user login
- user logout
- password change
- user created
- assignment changed
- secret created
- secret replaced
- secret resolved by Secret Bank
- secret used by a tool
- tool invocation requested
- tool invocation denied
- approval requested
- approval granted
- approval rejected
- budget exhausted hard stop
- model request blocked by budget (`model.budget_denied`)
- policy changed
- tool enabled or disabled
- Department or Lemming created, updated, paused, resumed, or terminated

Audit events are intended to answer:

- who did what
- to which resource
- in which scope
- when
- as part of which workflow
- with what outcome

## 5.2 Telemetry Events

Telemetry events record operational behavior for debugging, monitoring, capacity management, and performance analysis.

Typical telemetry events include:

- Lemming started
- Lemming completed
- Lemming failed
- Department restarted
- City unreachable
- tool execution duration
- retry count incremented
- queue depth sampled
- compaction executed
- sandbox resource limit hit
- checkpoint written
- model request dispatched (`model.request_started`)
- model response received (`model.response_received`)
- model retry attempt (`model.retry`)
- model request failed after retries (`model.request_failed`)
- model token usage recorded (`model.usage`) — primary input for ADR-0015
- model structured output validation failed (`model.structured_output_invalid`)

Model Runtime events (ADR-0019, section 13) follow the same canonical envelope as
all other platform events, using `world_id`, `city_id`, `department_id`,
`lemming_id`, and `correlation_id` to provide full hierarchy context. `model.usage`
carries the token breakdown in `payload` and is the sole source for token accounting
in the cost governance subsystem (ADR-0015).

Telemetry events are intended to answer:

- what is the system doing
- how often it is happening
- how long it took
- where performance or reliability problems exist

## 5.3 Tool Runtime v1 Events

The v1 Tool Runtime implementation emits operational signals through the existing structured logger, in-memory activity log, PubSub, and Elixir Telemetry. Durable canonical audit events for tool execution are not supported yet.

Implemented v1 signals:

- structured log event `instance.executor.tool_execution.started`
- structured log event `instance.executor.tool_execution.completed`
- structured log event `instance.executor.tool_execution.failed`
- telemetry event `[:lemmings_os, :runtime, :tool_execution, :started]`
- telemetry event `[:lemmings_os, :runtime, :tool_execution, :completed]`
- telemetry event `[:lemmings_os, :runtime, :tool_execution, :failed]`
- PubSub notification `:tool_execution_upserted` for instance transcript refresh
- in-memory activity-log entries in the `tool_execution` category

Telemetry metadata includes the hierarchy and tool identity needed for runtime diagnostics:

- `world_id`
- `city_id`
- `department_id`
- `lemming_id`
- `instance_id`
- `tool_execution_id`
- `tool_name`
- `tool_status`
- `duration_ms`
- `reason` on failure

The durable v1 history is the `lemming_instance_tool_executions` table, not the platform audit-event table. That table is runtime history scoped to one instance; it supports transcript reconstruction and operator inspection but does not replace the canonical append-only audit envelope.

## 5.3.1 Secret Bank MVP Durable Events

The Secret Bank MVP uses the canonical `events` table for durable audit events.
Implemented event types are:

- `secret.created`
- `secret.replaced`
- `secret.deleted`
- `secret.resolved`
- `secret.resolve_failed`
- `secret.used_by_tool`

The shipped implementation does not emit the older planning names
`secret.accessed` or `secret.access_failed`.

Secret event payloads may contain safe metadata such as bank key, secret
reference, requested hierarchy scope, resolved source, reason, tool name,
adapter name, and lemming instance ID. They must never contain raw secret
values, old values, new values, env values, masked previews, hashes, or
fingerprints.

## 5.4 Shared Envelope, Distinct Semantics

Audit and telemetry use the same base envelope so that infrastructure remains simple and query patterns remain consistent.

However:

- `audit` is governance-oriented and must preserve strong immutability expectations
- `telemetry` is observability-oriented and may have shorter retention or aggregation rules

This distinction must be explicit in the schema through `event_family`.

---

# 6. Canonical Event Envelope

Every durable event must contain the following canonical fields.

## 6.1 Required Fields

- `event_id`
- `event_family`
- `event_type`
- `occurred_at`
- `inserted_at`
- `world_id`
- `correlation_id`
- `payload`

## 6.2 Standard Optional Fields

The following fields are optional in the general schema, but should be populated whenever applicable.

### Hierarchy Scope

- `city_id`
- `department_id`
- `lemming_id`

### Actor

- `actor_type`
- `actor_id`
- `actor_role`

### Resource

- `resource_type`
- `resource_id`

### Workflow / Execution Context

- `causation_id`
- `tool_invocation_id`
- `approval_request_id`
- `request_id`

### Outcome / Description

- `action`
- `status`
- `message`

## 6.3 Field Semantics

### `event_id`

Globally unique identifier for the event.

### `event_family`

One of:

- `audit`
- `telemetry`

### `event_type`

Stable machine-readable event name.

Examples:

- `auth.login_succeeded`
- `auth.login_failed`
- `secret.resolved`
- `secret.resolve_failed`
- `secret.used_by_tool`
- `tool.invocation_requested`
- `tool.invocation_denied`
- `approval.requested`
- `approval.approved`
- `approval.rejected`
- `budget.exhausted`
- `model.request_started`
- `model.response_received`
- `model.retry`
- `model.request_failed`
- `model.usage`
- `model.budget_denied`
- `model.structured_output_invalid`
- `lemming.failed`
- `city.unreachable`

### `occurred_at`

Timestamp representing when the underlying action or observation happened.

### `inserted_at`

Timestamp representing when the event was persisted in the durable event store.

These may differ if the system buffers or retries insertion.

### `world_id`, `city_id`, `department_id`, `lemming_id`

Hierarchy scope for the event.

At minimum, every event must include `world_id`.

More specific scope fields are included when the event belongs to that part of the hierarchy.

### `actor_type`

Originator category.

Typical values:

- `user`
- `lemming`
- `system`
- `tool_runtime`
- `approval_manager`
- `control_plane`

### `actor_id`

Identifier of the actor within its category.

Examples:

- user id
- lemming instance id
- system component name

### `actor_role`

Relevant for human control-plane actions, where the acting role matters.

Examples:

- `admin`
- `operator`
- `viewer`

### `resource_type` and `resource_id`

Describe the target object affected by the action.

Examples:

- `user`
- `secret`
- `tool`
- `tool_invocation`
- `approval_request`
- `department`
- `lemming`
- `policy`

### `correlation_id`

A stable identifier tying together all events belonging to the same end-to-end workflow, request, or runtime execution path.

### `causation_id`

Points to the immediately preceding event that caused the current event.

Used to reconstruct chains such as:

```text
user action
  → tool invocation requested
  → approval requested
  → approval approved
  → tool executed
  → cost recorded
```

### `payload`

Structured JSON object containing event-specific details.

Payload must remain machine-readable and bounded in size.

### `message`

Short human-readable summary for operators and dashboards.

### `action`

Normalized action name when useful.

Examples:

- `create`
- `update`
- `delete`
- `approve`
- `reject`
- `execute`
- `deny`

### `status`

Normalized outcome status when useful.

Examples:

- `requested`
- `allowed`
- `denied`
- `approved`
- `rejected`
- `succeeded`
- `failed`

---

# 7. Actor, Scope, and Resource Model

The event model separates three concepts that must not be conflated.

## 7.1 Actor

The **actor** is who or what initiated the action.

Examples:

- a human operator
- a Lemming instance
- the Tool Runtime
- the ApprovalManager
- an internal recovery process

## 7.2 Scope

The **scope** is where in the hierarchy the event occurred.

Examples:

- world `prod`
- city `salvador`
- department `infra`
- lemming `lem_123`

## 7.3 Resource

The **resource** is the object affected by the action.

Examples:

- secret `github.token`
- approval request `apr_998`
- tool invocation `inv_78421`
- department `support`

These may differ.

Example:

```text
actor     = user:operator_17
scope     = world=prod, city=salvador, department=infra
resource  = tool_invocation:inv_78421
```

This distinction is mandatory because many important governance events involve one actor operating on a different resource within a larger scope.

---

# 8. Correlation and Traceability

LemmingsOS must support reconstruction of multi-step flows across runtime subsystems.

Therefore:

- every durable event must include a `correlation_id`
- events should include `causation_id` whenever the triggering event is known

## 8.1 Correlation ID

The `correlation_id` ties together all events belonging to the same logical execution flow.

Examples:

- one user request through the control plane
- one lemming execution instance
- one tool invocation workflow
- one approval-gated execution path

## 8.2 Causation ID

The `causation_id` links an event to the immediately prior event that caused it.

This enables causality reconstruction rather than only loose grouping.

## 8.3 Example Flow

```text
event-1  auth.login_succeeded
event-2  lemming.created                causation_id=event-1
event-3  tool.invocation_requested      causation_id=event-2
event-4  approval.requested             causation_id=event-3
event-5  approval.approved              causation_id=event-4
event-6  tool.invocation_succeeded      causation_id=event-5
event-7  cost.recorded                  causation_id=event-6
```

All of the above share the same `correlation_id` when they belong to the same operational flow.

---

# 9. Append-Only and Immutability Invariants

The durable event store is **append-only**.

## 9.1 Core Invariants

1. Events are never updated in place.
2. Events are never rewritten to change historical meaning.
3. Corrections must be represented as new compensating events.
4. `occurred_at` and `inserted_at` are immutable once written.
5. Event identity is permanent.

## 9.2 Correction Model

If a prior event is incorrect, the system must not mutate it.

Instead, write a new event such as:

- `policy.change_reverted`
- `approval.corrected`
- `secret.rotation_superseded`
- `audit.annotation_added`

This preserves history and forensic trust.

## 9.3 Deletion Semantics

In v1:

- audit events must not be physically deleted during normal operation
- telemetry events may be subject to retention or archival policy, but never mutated

---

# 10. Payload Rules and Sensitive Data

The payload is intentionally flexible, but not unbounded.

## 10.1 Allowed Payload Content

Payload may include:

- parameter summaries
- identifiers
- counters
- durations
- model names
- cost estimates
- sandbox decisions
- validation errors
- structured reason codes

## 10.2 Forbidden Content

Events must never store:

- raw secret values
- API tokens
- passwords
- session secrets
- full credential blobs
- private keys
- encryption master keys

Events should also avoid storing:

- oversized raw tool outputs
- full prompt transcripts unless explicitly promoted by design
- arbitrary internal chain-of-thought style reasoning

## 10.3 Large Data Handling

If event-related data is too large, the event should store:

- a bounded summary in `payload`
- an artifact reference or external storage reference if needed

Example:

```json
{
  "artifact_ref": "artifact://tool-results/abc123",
  "summary": "terraform plan produced 14 changes"
}
```

---

# 11. Storage Model for v1

Version 1 uses a **single PostgreSQL-backed durable event store**.

The recommended initial schema is a single `events` table with a JSONB payload and explicit indexed columns for common query dimensions.

## 11.1 Recommended Table Shape

Conceptual schema:

```text
events
  event_id               uuid / ulid primary key
  event_family           text not null
  event_type             text not null
  occurred_at            timestamptz not null
  inserted_at            timestamptz not null

  world_id               text not null
  city_id                text null
  department_id          text null
  lemming_id             text null

  actor_type             text null
  actor_id               text null
  actor_role             text null

  resource_type          text null
  resource_id            text null

  correlation_id         text not null
  causation_id           text null
  request_id             text null
  tool_invocation_id     text null
  approval_request_id    text null

  action                 text null
  status                 text null
  message                text null

  payload                jsonb not null
```

## 11.2 Why a Single Table in v1

This choice is preferred because it:

- keeps self-hosted deployments simple
- works well with PostgreSQL already required by the platform
- supports both audit and telemetry with minimal extra infrastructure
- avoids premature complexity such as separate event pipelines or dedicated event databases

This is an operational event store, not a full event-sourcing architecture.

---

# 12. Queryability and Indexing

The event model must support both fast operational lookup and forensic reconstruction.

## 12.1 Required Query Dimensions

At minimum, the system must support querying by:

- time range
- `event_family`
- `event_type`
- `world_id`
- `city_id`
- `department_id`
- `lemming_id`
- `actor_type`
- `actor_id`
- `resource_type`
- `resource_id`
- `correlation_id`
- `tool_invocation_id`
- `approval_request_id`
- `status`

## 12.2 Recommended Indexes

Version 1 should create indexes optimized for the most common operational and forensic queries.

Recommended initial indexes:

- `(occurred_at desc)`
- `(event_family, occurred_at desc)`
- `(event_type, occurred_at desc)`
- `(world_id, occurred_at desc)`
- `(world_id, city_id, department_id, occurred_at desc)`
- `(lemming_id, occurred_at desc)`
- `(actor_type, actor_id, occurred_at desc)`
- `(resource_type, resource_id, occurred_at desc)`
- `(correlation_id)`
- `(tool_invocation_id)`
- `(approval_request_id)`

A JSONB GIN index on `payload` may be added selectively if query needs justify it.

## 12.3 Query Use Cases

Typical queries include:

- show all approval events in department `infra`
- show all events for correlation id `corr_123`
- show all tool denials in city `salvador` in the last 24 hours
- show all secret accesses by tool `github_issue_creator`
- show all budget exhaustion events in world `prod`

---

# 13. Retention Model

Retention must distinguish between audit and telemetry.

## 13.1 Audit Retention

Audit events should be retained for a long period and, by default, indefinitely in v1 unless operators configure archival procedures.

Reason:

- audit events support compliance, forensics, and accountability
- deleting them too aggressively weakens trust in the system history

## 13.2 Telemetry Retention

Telemetry events may have shorter retention or be aggregated over time.

Possible policies include:

- retain raw telemetry for N days
- archive or summarize older telemetry
- keep only high-value telemetry beyond the short horizon

## 13.3 Retention Principle

Retention may remove old telemetry rows, but it must never alter the meaning of rows that remain.

---

# 14. Event Production Rules

To keep event quality consistent, event producers must follow shared rules.

## 14.1 Stable Event Names

Event types must use stable, namespaced identifiers.

Recommended style:

```text
auth.login_succeeded
secret.created
secret.resolved
secret.resolve_failed
secret.used_by_tool
tool.invocation_requested
tool.invocation_denied
approval.requested
approval.approved
approval.rejected
budget.exhausted
lemming.failed
city.unreachable
```

## 14.2 Prefer Structured Fields Over Free Text

Event details should be stored in structured form whenever possible.

Bad:

```text
"something failed in tool runtime"
```

Better:

```json
{
  "reason_code": "budget_exhausted",
  "tool": "web_search",
  "remaining_budget_usd": 0.0
}
```

## 14.3 Message Is Supplemental

`message` is for operator readability only.

System behavior must not depend on parsing `message`.

---

# 15. Examples

## 15.1 Secret Tool Usage Audit Event

```json
{
  "event_id": "evt_001",
  "event_family": "audit",
  "event_type": "secret.used_by_tool",
  "occurred_at": "2026-03-14T18:20:00Z",
  "inserted_at": "2026-03-14T18:20:00Z",
  "world_id": "prod",
  "city_id": "salvador",
  "department_id": "infra",
  "resource_type": "secret",
  "resource_id": "GITHUB_TOKEN",
  "correlation_id": "corr_78421",
  "tool_invocation_id": "inv_78421",
  "action": "use",
  "status": "succeeded",
  "message": "GITHUB_TOKEN used by web.fetch",
  "payload": {
    "key": "GITHUB_TOKEN",
    "tool_name": "web.fetch",
    "adapter_name": "LemmingsOs.Tools.Adapters.Web",
    "lemming_instance_id": "inst_78421",
    "resolved_source": "department"
  }
}
```

## 15.2 Approval Audit Event

```json
{
  "event_id": "evt_002",
  "event_family": "audit",
  "event_type": "approval.approved",
  "occurred_at": "2026-03-14T18:21:03Z",
  "inserted_at": "2026-03-14T18:21:03Z",
  "world_id": "prod",
  "city_id": "salvador",
  "department_id": "infra",
  "actor_type": "user",
  "actor_id": "operator_17",
  "actor_role": "operator",
  "resource_type": "approval_request",
  "resource_id": "apr_998",
  "correlation_id": "corr_78421",
  "causation_id": "evt_approval_requested",
  "tool_invocation_id": "inv_78421",
  "approval_request_id": "apr_998",
  "action": "approve",
  "status": "approved",
  "message": "Operator approved terraform apply",
  "payload": {
    "tool": "terraform_apply",
    "risk_level": "critical"
  }
}
```

## 15.3 Telemetry Event

```json
{
  "event_id": "evt_003",
  "event_family": "telemetry",
  "event_type": "lemming.failed",
  "occurred_at": "2026-03-14T18:22:10Z",
  "inserted_at": "2026-03-14T18:22:10Z",
  "world_id": "prod",
  "city_id": "salvador",
  "department_id": "research",
  "lemming_id": "lem_123",
  "actor_type": "system",
  "actor_id": "department_manager",
  "resource_type": "lemming",
  "resource_id": "lem_123",
  "correlation_id": "corr_123",
  "action": "fail",
  "status": "failed",
  "message": "Lemming exceeded retry policy",
  "payload": {
    "restart_count": 5,
    "reason_code": "retry_limit_exceeded"
  }
}
```

---

# 16. Consequences

## Positive

- establishes one canonical event contract across the platform
- removes ambiguity between audit, approval, cost, auth, and runtime events
- provides strong forensic traceability through actor, scope, resource, and correlation fields
- keeps v1 operationally simple by using PostgreSQL
- supports future dashboards, search, and analytics without redesigning event production

## Negative / Trade-offs

- a shared event schema requires discipline across all producers
- one central event table may grow quickly in active systems
- telemetry and audit sharing storage requires careful retention policy and indexing
- some producers may need adaptation work to emit structured events consistently

## Mitigations

- keep envelope fields explicit and stable
- enforce event emission through shared runtime helpers
- define naming conventions for event types early
- introduce archival and partitioning later if growth requires it

---

# 17. Non-Goals

The following are explicitly out of scope for v1:

- full event sourcing of all runtime state
- Kafka, NATS, or dedicated stream infrastructure as a requirement
- billing-grade financial reconciliation
- arbitrary user-defined event schemas in the control plane
- long-term analytics warehouse design
- distributed tracing protocol integration standards

The goal of this ADR is to define a durable, pragmatic, self-hosted event model suitable for governance and observability in version 1.

---

# 18. Future Extensions

Potential future work includes:

- PostgreSQL table partitioning by time or event family
- archival of old telemetry events
- dedicated search views or materialized views
- dashboards and audit explorers in the control plane
- event annotations for incident review
- export pipelines to external observability systems
- stronger schema validation per event type
- OpenTelemetry bridge or external tracing integration

These extensions can build on the canonical envelope defined here without changing the core model.

---

# 19. Rationale

LemmingsOS already assumes that governance-critical actions are auditable and that runtime behavior is observable.

Without a central event model, every subsystem risks inventing a slightly different schema and weakening the architecture.

This ADR creates a shared contract that is:

- explicit
- append-only
- traceable
- hierarchy-aware
- practical for v1

It therefore becomes the common foundation for secrets, auth, approvals, cost governance, tool execution tracing, and runtime observability.
