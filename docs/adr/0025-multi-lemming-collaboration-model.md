# ADR-0025 — Multi-Lemming Collaboration Model

- Status: Accepted
- Date: 2026-04-24
- Decision Makers: Maintainer(s)

---

# 1. Context

This branch introduces the first collaboration support where one runtime instance can delegate bounded work to another runtime instance while preserving explicit hierarchy boundaries.

This feature introduced several architecture questions that were not fully settled by ADR-0006, ADR-0017, ADR-0021, and ADR-0024:

- how a Department manager is identified in persisted data
- whether collaboration history is modeled on runtime instances or on separate durable records
- which hierarchy boundaries apply to delegation
- how continuation works when a delegated child instance has expired
- what observability data is emitted and what sensitive data is intentionally omitted
- how seeded demo topology and operator UI should surface the implemented behavior

This ADR defines the intended collaboration contract for bounded multi-lemming delegation. The first implementation slice may implement only part of this contract.

---

# 2. Decision Drivers

1. **Manager identity must be explicit** — the runtime cannot infer coordinator roles from prompt text alone.
2. **Delegated work must survive runtime churn** — collaboration state must outlive transient executor state and expired child instances.
3. **Hierarchy boundaries must stay hard** — collaboration must not bypass World or City isolation.
4. **Cross-department work needs one safe path** — workers must not create arbitrary department-to-department graphs.
5. **Operators need understandable UI state** — manager and child instance pages must explain delegation without exposing raw internals by default.
6. **Observability must remain useful without leaking payloads** — logs, telemetry, and PubSub need scope and status metadata, but should avoid full request/result bodies.

---

# 3. Considered Options

## Option A — Infer managers from prompts or naming conventions

Examples: treat `*_manager` slugs as authoritative, or rely on instructions that tell a lemming it is a coordinator.

**Pros**

- no schema change
- easy to prototype

**Cons**

- runtime authorization would depend on conventions instead of persisted data
- UI could not reliably show primary manager identity
- bootstrap validation could not enforce the role contract

Rejected. The implemented slice uses explicit persisted metadata.

## Option B — Store delegation only on runtime instances

Examples: parent instance tracks child ids in memory or in instance snapshots, without a first-class collaboration table.

**Pros**

- fewer tables
- simple for happy-path live sessions

**Cons**

- collaboration history disappears when child instance expires or manager executor restarts
- continuation chains cannot be represented cleanly
- observability and UI state become coupled to one executor's current memory

Rejected. The current collaboration model uses a dedicated durable call record.

## Option C — Durable collaboration records plus manager-only bounded delegation (chosen)

Use explicit manager designation, persist delegations in a durable collaboration record, limit targets to same-city manager-approved paths, and use successor links when expired child work continues.

**Pros**

- durable collaboration history independent from runtime instance status
- explicit authorization boundary for manager-only delegation
- continuation across expired child instances without reusing dead runtime instances
- UI and observability can read one canonical collaboration model

**Cons**

- more schema and state-mapping complexity
- operators must understand two related but distinct concepts: instance status and call status

Chosen. This matches the implemented code and tests in this branch.

---

# 4. Decision

LemmingsOS adopts this collaboration model for this collaboration slice:

1. **Manager designation is explicit.**
   `collaboration_role` is the authority for whether a lemming acts as a `manager` or `worker`. The default is `worker`.

2. **Collaboration is persisted separately from runtime sessions.**
   Each delegation is stored in a durable call record scoped to a World, with caller/callee city, department, lemming, and instance identity derived from the participating runtime instances.

3. **Delegation stays inside one World and one City.**
   Calls require explicit World scope and reject cross-city caller/callee pairs. Successor links must resolve inside the same World.

4. **Managers are the only callers.**
   Only manager instances may initiate delegated calls.

5. **Cross-department delegation is manager-only on both ends.**
   A manager may call:
   - active workers in its own department
   - active managers in other departments in the same World and City

   A worker cannot call other workers, cannot call managers, and cannot cross department boundaries directly.

6. **Continuation prefers the same live child instance, then a successor call.**
   When continuation targets a live child, the runtime enqueues more work on that child and keeps the same call record.
   When the child instance has expired, the runtime spawns a new child instance, creates a successor call, links it with `previous_call_id` and `root_call_id`, and emits recovery observability.

7. **Durable call status is distinct from runtime instance status.**
   Call records carry their own lifecycle state, including active, recovery-related, completed, and failed outcomes. The UI presents these states as operator-facing collaboration statuses such as queued, running, retrying, recovery pending, completed, failed, and dead.

---

# 5. Implemented Behavioral Contract

## 5.1 Durable call lifecycle

Each call stores:

- caller and callee instance identity
- caller and callee department identity
- caller and callee lemming identity
- request text
- lifecycle status and optional result/error summaries
- recovery metadata when continuation context matters
- successor-chain links when work moves to a replacement child session

This model preserves logical collaboration history even when the child runtime instance has expired or the manager executor is unavailable.

## 5.2 Continuation and recovery

Continuation rules:

- live child instance + non-terminal call -> enqueue more work on same child instance
- expired child instance -> spawn successor child instance and successor call

Recovery metadata is carried on the call record, not inferred from instance status alone.
The current collaboration model preserves enough recovery state to distinguish follow-up or continuation work from terminal completion and to explain whether a successor call is retrying expired child work.

## 5.3 Observability and privacy

The implemented collaboration observability intentionally prefers scope/status metadata over raw payload capture.

Logs, telemetry, activity log records, and PubSub payloads include hierarchy-safe identifiers such as:

- `world_id`
- `city_id`
- `caller_department_id`
- `callee_department_id`
- `caller_instance_id`
- `callee_instance_id`
- `lemming_call_id`
- status and recovery metadata

Current constraints in this slice:

- request text is not emitted in lemming-call logs, telemetry metadata, or PubSub payloads
- PubSub payloads broadcast status transitions and ids only
- activity log entries record summaries, not raw child transcript payloads
- structured logs may use shortened summaries instead of full payloads
- child transcript UI hides duplicated delegated request text from the visible child-session user stream and instead shows it as manager-request relationship context

This keeps operator visibility useful while reducing payload leakage in shared observability channels.

## 5.4 Seeded default world and demo setup

`priv/default.world.yaml` is the canonical bootstrap for this collaboration slice. It defines one default World and one bootstrap City with three collaboration-ready departments:

- `it`
- `marketing`
- `sales`

Each of those departments includes an explicit manager lemming and worker lemmings with `collaboration_role` values set in bootstrap data.

This default world is the collaboration showcase:

- managers have `lemming.call` in `allowed_tools`
- workers do not
- `runtime.cross_city_communication` is `false`

`priv/repo/seeds.exs` extends the database with additional demo cities and departments, but preserves the original bootstrap city and seeded counts for the default collaboration setup. The collaboration contract therefore anchors on `priv/default.world.yaml`, not on incidental seed-only additions.

## 5.5 Operator-facing UI behavior

The current UI surfaces collaboration in two places.

Department detail:

- identifies the primary manager from persisted `collaboration_role`
- prefers an active manager as primary manager, otherwise falls back to any manager in the department
- labels each lemming type as `Manager` or `Worker`
- exposes the primary manager as the recommended department entry point

Instance session:

- manager sessions show delegated work inline with transcript, available call targets, and active/historical counts
- delegated call rows expose child links and mapped UI state
- child sessions show manager relationship strip and link back to parent manager instance
- raw context view includes latest delegation state and whether callback context reached the manager executor

---

# 6. Rationale

This model best matches product intent and the implemented behavior in this branch because it keeps collaboration:

- explicit in schema
- durable across runtime churn
- bounded by World/City/Department rules
- visible in operator UI
- observable without broadcasting full payloads

It also preserves ADR-0003 World isolation and ADR-0017 City isolation without inventing a new cross-node messaging layer.

---

# 7. Consequences

Positive outcomes:

- collaboration permission is data-driven through `collaboration_role`
- manager-centered UX is backed by durable persistence, not prompt convention
- expired child continuation does not require unsafe runtime resurrection
- observability can correlate collaboration flows by ids and scope metadata

Trade-offs:

- operators and developers must reason about both instance status and call status
- successor chains add extra query/state-mapping logic
- recovery and continuation states introduce additional UI/state-mapping logic beyond basic call completion

Out of scope for this ADR:

- cross-city collaboration
- cross-world collaboration
- city-wide or company-wide super-manager roles
- arbitrary worker-to-worker delegation graphs

---

# 8. Implementation Notes

- The persistence layer adds explicit collaboration-role metadata on lemmings and a durable call record for delegated work.
- The web layer includes read models and UI surfaces that expose department manager identity, delegated work state, and child-to-manager relationship context.
- The runtime collaboration boundary enforces manager authorization, World/City scoping, continuation behavior, and observability hooks.
- The default bootstrap data provides the reference collaboration topology for this slice.
