# ADR-0017 — Runtime Topology and City Execution Model

- Status: Accepted (narrowed 2026-03-19)
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

LemmingsOS defines a hierarchical logical model for organizing autonomous agents:

```
World → City → Department → Lemming
```

**ADR-0002** established the foundational definition of City: *"a running Elixir/OTP node — Cities join and leave Worlds dynamically, mapping directly to a `Node` in Elixir distributed computing."*

This ADR expands that definition. Where ADR-0002 names the concept, this ADR specifies the full runtime topology: what services run inside a City node, how isolation boundaries are enforced at the node level, how credentials are kept local, and how multi-City deployments are structured.

Other ADRs define execution behavior (ADR-0004), tool governance (ADR-0005, ADR-0012, ADR-0016), and security boundaries (ADR-0003, ADR-0009). However, the **physical runtime topology** of the system has not yet been explicitly defined.

Specifically, the system requires a clear definition of:

- how Cities map to runtime infrastructure
- where BEAM nodes execute
- where the Tool Runtime operates
- where the Secret Bank resides
- how isolation boundaries are enforced
- how routing works between runtime nodes

LemmingsOS is designed to run across a wide range of operational environments:

- single VPS self‑hosted deployments
- small clusters
- distributed infrastructures

Therefore the runtime topology must satisfy several design goals:

- remain simple for small installations
- support horizontal scaling
- provide strong isolation boundaries
- maintain predictable runtime behavior

The logical hierarchy therefore must map to infrastructure in a deterministic and operationally understandable way.

To achieve this, LemmingsOS treats **Cities as runtime execution units and isolation boundaries**.

This approach provides several benefits:

- **fault isolation** — failures in one City do not impact others
- **operational boundaries** — Cities can be deployed, upgraded, or restarted independently
- **deployment flexibility** — Cities may run on separate infrastructure
- **scaling capability** — additional Cities can be added horizontally

---

# 2. Decision Drivers

1. **Operational simplicity at minimal scale** — A single VPS deployment must be
   straightforward to install and operate. The topology must not require a cluster by
   default. A developer should be able to run a fully functional World with one City
   on one host.

2. **Horizontal scaling** — Adding more agent execution capacity must not require
   redesigning the architecture. The topology must scale by adding City nodes, not by
   vertically growing a monolith or centralizing all execution in one process.

3. **Fault isolation** — A failure in one City (a crash, a resource exhaustion, a
   misconfigured tool) must not cascade to other Cities. Isolation boundaries must be
   structural, not reliant on graceful error handling.

4. **Alignment with the logical hierarchy** — The physical deployment model must
   mirror the logical World → City → Department structure. An operational topology
   that diverges from the logical model creates a dual mental model burden.

5. **Secret and credential locality** — Each City must own and isolate its runtime
   credentials. Secrets must not transit between City runtime boundaries, even within
   the same World.

---

# 3. Considered Options

## Option A — Single monolithic BEAM node for all Cities

All Departments and Lemmings across all Cities run in one BEAM node. Cities are
logical namespaces in the application code, not runtime boundaries.

**Pros:**

- simplest deployment: one Elixir application, one node to operate
- no inter-node communication required
- shared memory simplifies state access across Departments

**Cons:**

- a failure or resource exhaustion in one Department can destabilize the entire node,
  affecting all Cities and Departments simultaneously
- Cities cannot be deployed, upgraded, or scaled independently
- secrets for all Cities reside in the same process tree, reducing the isolation
  guarantee even if the Secret Bank is logically partitioned
- there is no physical boundary enforcing the isolation that the logical model implies

Rejected. The monolith provides no fault isolation and makes independent City
operations impossible. For a system where Cities may run different workloads with
different risk profiles, shared execution is a structural liability.

---

## Option B — World-scoped runtime with City process groups

One BEAM node per World. Cities are isolated as OTP application boundaries or process
groups within the node, but the underlying BEAM instance is shared.

**Pros:**

- finer granularity than a single monolith
- OTP supervision can restart a City's process group without affecting others

**Cons:**

- shared BEAM node means a BEAM-level crash (hardware failure, OOM kill) still affects
  all Cities simultaneously
- the isolation guarantee is weaker: a runaway Elixir process inside one City can
  consume VM memory or scheduler capacity affecting other Cities
- independent deployment and upgrade of individual Cities is not possible

Rejected. The shared BEAM node does not provide the fault and operational isolation
that City-as-a-boundary requires. The model is a partial improvement over the monolith
but does not reach the isolation standard.

---

## Option C — City as an independent BEAM runtime node (chosen)

Each City runs as an independent BEAM node with its own supervised process tree. The
World provides shared durable persistence (PostgreSQL) but does not act as a shared
execution environment.

**Pros:**

- complete fault isolation: a City crash affects only that City's Lemmings
- Cities can be deployed, upgraded, and scaled independently
- secret isolation is structural: each City's Secret Bank runs in a separate process
  tree with no shared memory
- the deployment model is naturally simple at small scale (one City = one node on one
  host) and scales horizontally without architecture changes

**Cons:**

- the World layer requires coordination between City nodes for governance data (audit
  events, approval records, cost counters); this must flow through the shared
  persistence layer, not directly between nodes
- cross-City communication requires explicit routing if needed (disabled by default)
- operating a multi-City World requires managing multiple BEAM nodes

Chosen. The isolation, scalability, and operational clarity benefits justify the
multi-node coordination cost. The shared persistence layer (PostgreSQL) handles the
cross-City governance data with well-understood operational characteristics.

---

# 4. Decision

In LemmingsOS, a **City represents a runtime execution node**.

Each City runs a complete runtime environment that includes all services required to execute agents within that City.

Each City runs:

- a BEAM node
- the Lemmings runtime
- the Tool Runtime
- the Secret Bank
- supporting runtime services

Departments and Lemmings exist **inside a City** and execute exclusively within that City's runtime environment.

Cities do not share runtime state with one another.

The **World** represents the logical grouping of Cities but does not act as a shared runtime execution environment.

This model keeps runtime boundaries simple and explicit.

---

# 5. Runtime Topology

The conceptual runtime structure is as follows:

```
World
  ├─ City (runtime node)
  │     ├─ Tool Runtime
  │     ├─ Secret Bank
  │     ├─ Departments
  │     │     └─ Lemmings
  │
  └─ City (another runtime node)
```

Each City may be deployed on different types of infrastructure.

Possible deployment targets include:

- a single host
- a virtual machine
- a container
- a BEAM cluster node

A minimal deployment may run a single World with a single City on a single host.

Larger installations may deploy multiple Cities across different machines or regions.

This model allows operators to scale the system by **adding additional City nodes** without changing the core architecture.

---

# 5.1 Shipped City Runtime Model

The initial City implementation ships the following runtime model. Prior
wording in this ADR implied capabilities (distributed Erlang clustering,
automatic discovery, remote health polling) that are not yet implemented. This
section narrows the ADR to match what is actually shipped.

## Startup self-registration

Each runtime node registers itself as a City during application startup:

1. The World bootstrap import runs first, ensuring a persisted default World.
2. `LemmingsOs.Cities.Runtime.sync_runtime_city/1` upserts a `cities` row for
   the local node, keyed by `node_name`.
3. `node_name` is the full BEAM node identity in `name@host` form, resolved
   from application configuration (`LEMMINGS_CITY_NODE_NAME` env var).

There is no automatic discovery of remote nodes. Each runtime registers only
itself.

## Heartbeat-backed liveness

`LemmingsOs.Cities.Heartbeat` is a GenServer that updates `last_seen_at` on
the local City row at a fixed 30-second interval. Derived liveness is computed
purely from `last_seen_at` freshness:

- **alive** -- `last_seen_at` is within the freshness threshold (default 90s)
- **stale** -- `last_seen_at` is older than the threshold
- **unknown** -- no heartbeat has ever been observed (`last_seen_at` is nil)

The heartbeat worker never mutates the administrative `status` field.

## Runtime identity contract

`node_name` is frozen as the canonical persisted runtime identity. It stores
the full BEAM node name in `name@host` form, not a logical label or short
name. `host`, `distribution_port`, and `epmd_port` are optional connectivity
hints and are not authoritative for liveness.

## What is explicitly deferred

The following capabilities are referenced or implied elsewhere in this ADR but
are **not shipped** and require future ADRs before implementation:

- **Distributed Erlang clustering** -- Cities do not form an Erlang cluster.
  `RELEASE_DISTRIBUTION=none` is the default. No `:net_kernel` connectivity
  exists between City nodes.
- **Automatic discovery** -- There is no mechanism for a City to discover
  peers. Each node self-registers only.
- **Remote health polling** -- Liveness is derived from each node's own
  heartbeat writes. No node polls another node's health.
- **Failover and migration** -- Lemmings are not migrated between Cities on
  failure. There is no rescheduling mechanism.
- **Department runtime supervision** -- persisted `departments` rows now exist,
  but the City-level supervisor / Department-manager runtime described
  elsewhere in this ADR is still deferred. Current shipped work is control-
  plane persistence and operator UI, not Department-hosted Lemming execution.
- **Secure remote city attachment** -- There is no secure onboarding protocol
  for remote Cities. The compose demo uses shared database credentials and
  `RELEASE_DISTRIBUTION=none`. Secure remote attachment and encrypted secret
  distribution are deferred to a later ADR and security design. Future
  attachment may require persisted encrypted secret material, but that
  mechanism is not decided.
- **Erlang cookie management** -- No Erlang cookie is stored in the `cities`
  table or managed by the runtime.

---

# 6. Isolation Boundary

A **City is the primary runtime isolation boundary** within a World.

Cities isolate several critical aspects of the runtime environment.

Isolation applies to:

- runtime processes
- secret storage
- tool execution
- network access
- agent execution context

Cities must not share:

- secrets
- internal runtime state
- agent memory or context
- local runtime services

Each City maintains its own Secret Bank instance and Tool Runtime.

This ensures that:

- credentials remain local to the City
- governance policies apply locally
- operational failures remain contained

Isolation at the City level also simplifies operational reasoning.

If a City experiences failure, misconfiguration, or overload, the impact remains limited to that City's agents.

---

# 7. Cross‑City Communication

Cities are isolated by default.

Cross‑City communication is **disabled unless explicitly configured**.

If communication between Cities is required, it must occur through an explicit routing mechanism such as a gateway or external integration layer.

Implicit sharing of runtime state is not permitted.

Typical default behavior:

```
cross_city_communication = disabled
```

Optional deployments may enable controlled communication using explicit routing components.

Benefits of this approach include:

- stronger security guarantees
- predictable multi‑tenant isolation
- prevention of accidental coupling between runtime nodes

This design mirrors the strong isolation guarantees already defined at the World level.

---

# 8. Execution Locality

Agent execution is always **local to the City in which the agent resides**.

Execution locality rules:

- Lemmings execute only within their City
- Tool Runtime executes within the same City
- Secrets are resolved by the City's Secret Bank
- Tool adapters execute locally within the City environment

This locality model ensures:

- policy enforcement occurs locally
- secrets never cross runtime boundaries
- predictable cost governance
- deterministic runtime behavior

Tool execution therefore follows a local pipeline.

---

# 9. Example Execution Flow

Example tool invocation inside a City:

```
Lemming
   ↓
Tool Runtime
   ↓
Sandbox
   ↓
External System
```

Expanded conceptual flow:

```
Lemming Instance
      ↓
Tool Runtime
      ↓
Policy / Risk / Approval / Budget checks
      ↓
Secret resolution (Secret Bank)
      ↓
Sandboxed Tool Execution
      ↓
External System
      ↓
Result returned to Lemming
```

Because all runtime components reside inside the City boundary, the runtime can enforce governance policies consistently.

---

# 10. Runtime Topology Overview

Example distributed deployment:

```
World
   │
   ├─ City A (host/node)
   │      ├─ Lemmings
   │      ├─ Tool Runtime
   │      └─ Secret Bank
   │
   └─ City B (host/node)
          ├─ Lemmings
          ├─ Tool Runtime
          └─ Secret Bank
```

Each City operates independently while belonging to the same logical World.

Operational actions such as:

- scaling
- upgrades
- maintenance
- restarts

may occur independently for each City.

---

# 11. Consequences

## Positive

- Fault isolation is structural: a City that crashes, runs out of memory, or executes
  a runaway tool does not affect Lemmings in other Cities. The blast radius of any
  single failure is bounded by the City boundary.
- Cities can be independently deployed, upgraded, and scaled. An operator upgrading
  one City's runtime version does not need to coordinate with or restart other Cities.
- Secret isolation is enforced at the process boundary. A Secret Bank in City A has no
  memory or process access to secrets in City B, regardless of application-level code.

## Negative / Trade-offs

- Operating a multi-City World requires managing multiple BEAM nodes. Operators must
  understand how to deploy, monitor, and restart independent nodes rather than a single
  application process.
- Cross-City coordination (governance data, audit events, cost counters) flows through
  the shared PostgreSQL layer. This layer becomes a shared dependency; a database
  outage affects all Cities' ability to write governance records.
- A minimal single-City deployment carries the same topology model as a large
  multi-City deployment. There is no simplified single-process mode for local
  development or evaluation.

## Mitigations

- The minimal deployment (one World, one City, one host) runs a single BEAM node.
  Multi-node complexity only materializes when operators choose to add Cities.
- PostgreSQL is already required by the platform for all persistent storage. The
  shared persistence layer does not introduce a new operational dependency.
- City runtime failures are independent; a City that cannot reach the database for
  governance writes continues executing locally and retries writes when connectivity
  restores. Execution is not blocked by governance persistence failures.

---

# 12. Non‑Goals

The following features are explicitly out of scope for the shipped City
implementation:

- complex multi‑cluster orchestration
- cross‑City state replication
- distributed actor migration
- global secret storage
- automatic runtime load balancing between Cities
- distributed Erlang clustering between City nodes
- automatic City discovery or membership protocols
- secure remote City onboarding and secret distribution
- storing Erlang cookies in the `cities` table

These features introduce significant complexity and are unnecessary for the
initial City persistence and visibility foundation.

The current goal is a **simple, predictable, and observable runtime topology**
based on self-registration and heartbeat-backed liveness.

---

# 13. Future Extensions

Possible future improvements include:

- BEAM clustering between Cities (requires a future ADR)
- City auto‑scaling
- remote tool runners
- multi‑region World deployments
- distributed telemetry aggregation
- secure remote City attachment protocol (requires a dedicated ADR and
  security design; may involve persisted encrypted secret material)
- remote health polling and active liveness checks

These extensions may build on the City execution model defined in this ADR without changing the core isolation principle.

Cities remain the fundamental runtime boundary of LemmingsOS.

---

# Persistence and Shared Services

The **World** provides the durable storage layer used by all Cities.

Cities are independent runtime nodes but rely on shared World‑scoped infrastructure for persistence and governance data.

Typical World‑level shared services include:

- PostgreSQL database
- control plane APIs and UI
- audit log storage
- approval workflow persistence
- cost governance counters

Cities do **not** route persistence operations through other Cities.

Instead, each City runtime communicates directly with the World persistence layer.

Conceptual flow:

```text
Lemming (City B)
      ↓
City Runtime Services
      ↓
World Persistence Layer (PostgreSQL)
```

This design ensures:

- Cities remain operationally independent
- failure of one City does not block persistence for others
- audit and governance data remain globally visible

Direct City‑to‑City routing for persistence is intentionally avoided.

The City boundary therefore isolates **execution**, while the World layer provides **durable governance storage**.

## Local vs Shared Responsibilities

World‑scoped components:

- PostgreSQL storage
- control plane
- audit events
- approval records
- cost accounting

City‑scoped components:

- BEAM runtime node
- Lemming execution processes
- Tool Runtime
- Secret Bank
- sandbox execution environments

This separation preserves runtime isolation while allowing consistent governance across the system hierarchy.

---

# 14. Rationale

The City-as-runtime-node model follows directly from the system's core design principle:
the logical hierarchy must map predictably to operational boundaries. A topology that
diverges from the logical model forces operators to maintain two separate mental models
simultaneously.

Making Cities the unit of operational isolation means that capacity, failure, and
upgrade decisions all operate at the City granularity. This is the right level for a
system organized around organizational units: a team managing a City can operate it
independently without coordinating with other City operators.

The shared PostgreSQL persistence layer is a deliberate trade-off. Distributed consensus
or event streaming infrastructure would provide stronger isolation but at significant
operational cost. PostgreSQL is already required, well-understood, and sufficient for
the governance data volume that v1 will generate.
