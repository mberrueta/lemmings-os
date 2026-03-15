# ADR-0007 — Runtime Routing / Registry / Address Resolution

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

LemmingsOS models each Lemming instance as an OTP process supervised by the runtime. Instances may execute asynchronously, persist state periodically, and remain alive across multiple interactions before being dismissed or evicted after an idle timeout.

Previous ADRs established the boundaries this ADR builds on:

- **ADR-0004 — Lemming Execution Model**: each Lemming instance is a supervised OTP process with its own lifecycle.
- **ADR-0005 — Tool Execution Model**: all external side effects must happen through Tools and the Tool Runtime.
- **ADR-0006 — Agent Communication Model**: Lemmings communicate natively through runtime messaging using request/reply, notification, and delegation patterns.

This ADR defines how a caller resolves a destination, how the runtime addresses concrete instances, what metadata is tracked for routing, and how instance lifecycle interacts with addressing.

The design goal is to keep the mental model simple:

- a caller can create a new worker by asking for an **agent type**
- a caller can continue talking to the same worker through its **instance reference**
- the runtime owns liveness, placement, and delivery concerns
- callers do not pre-check whether an instance is still alive

This model must support multiple concurrent instances of the same agent type, iterative follow-up work on a delegated subtask, and safe routing boundaries aligned with World isolation.

---

# 2. Decision Drivers

1. **Callers must be isolated from OTP internals** — PIDs and node placement are unstable identifiers: a process restart produces a new PID, and a node migration changes the location. Callers must hold a stable logical handle that the runtime resolves to a live process without caller involvement.

2. **Multiple concurrent instances of the same type must be natural** — Agent types are not singletons. A coordinator may spawn two `web_researcher` instances focused on different sources simultaneously. The addressing model must support this without special-casing.

3. **Liveness and placement are runtime concerns, not caller concerns** — Callers must not pre-check process health or perform their own registry lookups. The runtime is responsible for delivery, failure signaling, and reconnection.

4. **World isolation must be a hard routing boundary** — Cross-World routing must be structurally prevented by the addressing model, not only by policy checks. A caller in World A must not be able to address a Lemming in World B through any routing path.

5. **The registry must remain lightweight** — Only routing metadata (instance ref, type, world, city, department, pid, status) belongs in the registry. Working context, model state, and business data must live in the ephemeral store (ADR-0008). Mixing them would bloat the registry and complicate crash recovery.

6. **Idle instances must remain addressable** — Instance references must stay valid through idle periods so a coordinator can send follow-up work to the same worker without respawning. The runtime owns idle TTL and cleanup; callers do not.

---

# 3. Considered Options

## Option A — Direct Elixir Registry with PID-based addressing

Use `{:via, Registry, {LemmingsOs.Registry, instance_ref}}` as the standard Elixir Registry. Callers obtain a PID from the registry and call it directly.

**Pros:**
- uses a built-in Elixir mechanism; minimal custom infrastructure
- Registry supervision and cleanup are provided by OTP

**Cons:**
- PIDs are unstable; callers must re-resolve after any restart, making `instance_ref` not truly stable from the caller's perspective
- the Registry provides no World-scoped routing boundary; a caller can look up any registered name regardless of World
- there is no standard way to record routing metadata (city, department, status, last activity) alongside the PID without a separate lookup table

Rejected. PID instability and the lack of World-scoped isolation require a custom routing layer regardless.

---

## Option B — ETS-based ad-hoc name-to-PID table

Maintain a global ETS table mapping `instance_ref` → `{pid, metadata}`. Callers look up the table directly.

**Pros:**
- fast in-memory lookup; ETS reads are concurrent and cheap
- flexible schema for storing routing metadata alongside the PID

**Cons:**
- ETS tables are node-local; no cross-node routing without custom replication
- the table is a shared global mutable structure; concurrent writes and deletions require careful coordination
- no supervision integration; stale entries must be cleaned up manually when processes die
- World isolation must be enforced by lookup logic, not by structural separation

Rejected. A global ETS table grows into a custom registry with the downsides of both approaches and the advantages of neither.

---

## Option C — External service registry (Consul, etcd)

Use an external service registry as the canonical instance directory.

**Pros:**
- battle-tested for distributed service discovery
- supports cross-node routing natively
- health-check integration is built in

**Cons:**
- requires an external operational dependency on every self-hosted deployment
- adds network latency to every routing lookup
- Consul/etcd availability becomes a hard dependency for all inter-agent communication
- operationally disproportionate for a single-node or small-cluster deployment target

Rejected. The operational dependency is disproportionate to the self-hosted deployment target.

---

## Option D — Two-tier addressing with node-local runtime registry (chosen)

Use two address forms: `agent_type` for spawning new instances and `instance_ref` for addressing existing ones. The runtime maintains a node-local registry with World-scoped lookup. Callers hold stable logical handles; the runtime resolves them to live processes.

**Pros:**
- simple mental model: create by type, continue by reference
- World-scoped lookup prevents cross-World routing structurally
- stable `instance_ref` abstracts PID instability from callers
- routing metadata (city, department, status, last activity) can be stored alongside routing entries without bloating the registry

**Cons:**
- requires a custom registry implementation beyond plain Elixir Registry
- callers must handle delivery failures explicitly when idle instances expire

Chosen. The simplicity of the two-tier model and the structural World isolation are the right design anchors for v1.

---

# 4. Decision

## 4.1 Address forms

Runtime addressing supports exactly two forms in v1:

1. **`agent_type`**
   - Used to create a new instance of a specific agent class.
   - Agent types are **not** singletons.
   - Multiple concurrent instances of the same type are first-class.
   - Addressing by type does **not** target an existing instance implicitly.

2. **`instance_ref`**
   - Used to address an existing concrete instance directly.
   - `instance_ref` is the canonical logical identity of a Lemming instance.
   - `instance_ref` is stable and opaque.
   - Runtime internals such as PID or node placement are not exposed as the addressing contract.

## 4.2 Default addressing semantics

The runtime applies the following default semantics:

- `agent_type` → **spawn new instance**
- `instance_ref` → **send to existing instance**

This keeps routing predictable and avoids hidden reuse decisions in v1.

Example:

- John delegates to `web_buyer_researcher`
- the runtime spawns two instances of the same type
- one instance focuses on Amazon
- one instance focuses on Mercado Livre
- subsequent follow-up work is sent to each concrete worker through its `instance_ref`

## 4.3 Instance lifecycle and idle behavior

Spawned instances remain alive after completing a task and transition to an **idle** state.

Idle instances:

- preserve their working context
- remain directly addressable by `instance_ref`
- may receive follow-up work later

Idle instances may be terminated in two ways:

- **explicit dismissal** by the caller
- **automatic eviction** by the runtime after `idle_ttl` expiration

The runtime owns idle expiration and cleanup.

## 4.4 Caller responsibilities and liveness

Callers treat `instance_ref` as a stable logical handle.

Callers do **not** pre-check whether an instance is alive before sending follow-up work. Instead:

- the caller sends work to the `instance_ref`
- the runtime attempts delivery
- if delivery fails because the instance is unavailable, the caller decides what to do next

Possible caller strategies include:

- spawn a replacement instance
- retry later
- ignore that branch
- mark the delegated subtask as failed

Liveness and placement are runtime concerns, not caller concerns.

## 4.5 Working context ownership

Each Lemming instance owns its own structured working context. The context lives
in process memory while the instance is active. Model input is reconstructed on
each LLM invocation from this structured state; the runtime does not rely on
implicit model memory across requests.

Context structure, field semantics, compaction triggers, and persistence
semantics are defined in ADR-0008. The registry has no visibility into context
content — it stores routing metadata only.

## 4.7 Registry responsibilities

The runtime uses an Elixir registry-style routing layer to track addressable instances.

The registry is responsible only for **presence, routing, and placement metadata**. It is **not** the source of truth for the instance working context.

The registry stores minimal routing metadata such as:

- `instance_ref`
- `agent_type`
- `world`
- `city`
- `department`
- `pid` or runtime location
- `status`
- `last_activity_at`

This keeps routing concerns separated from business or model state.

## 4.8 Routing scope

Routing is always scoped to a single **World** and, in v1, to a single **City**.

- **cross-world routing is never allowed**
- cross-department routing is allowed within the same City
- **cross-city routing is not supported in v1**; all routing is City-local

Cross-City routing requires a distributed registry capable of resolving instance
references across BEAM nodes. This infrastructure adds significant complexity
without a concrete v1 use case — within a single City, Departments already provide
the isolation and grouping needed for agent coordination. Cross-City routing is
deferred to a future extension (see section 8).

This preserves the strong isolation boundary of World while keeping the v1 routing
model simple, local, and testable without multi-node infrastructure.

## 4.9 Peer communication policy

Peer communication is denied by default.

A Lemming instance may only spawn or address peer agent types that are explicitly allowed by policy.

The runtime must enforce this before:

- spawning a new peer instance by `agent_type`
- sending work to an existing peer by `instance_ref`

Policy therefore acts as an allowlist for peer communication.

## 4.10 Routing and delivery outcomes

The runtime distinguishes routing and delivery failures explicitly.

Suggested return shapes:

- `{:ok, result}`
- `{:error, :instance_not_found}`
- `{:error, :instance_unavailable}`
- `{:error, :timeout}`
- `{:error, :not_allowed}`
- `{:error, :spawn_failed}`

These outcomes allow callers to distinguish between:

- resolution failure
- delivery failure
- policy failure
- spawn failure
- downstream execution failure

## 4.11 Lifecycle contract

The minimal conceptual lifecycle contract in v1 is:

- `spawn(agent_type, initial_task) -> instance_ref`
- `send(instance_ref, message) -> result | error`
- `dismiss(instance_ref) -> ok | error`

This is a conceptual runtime contract, not a final public API.

---

# 5. Diagrams

## Addressing model

```text
Caller (John)
   |
   | delegate by agent_type = web_buyer_researcher
   v
Runtime Router / Policy Check
   |
   | spawn new instance
   v
+------------------------------+
| instance_ref = lem_a         |
| type = web_buyer_researcher  |
| focus = Amazon               |
+------------------------------+

Caller (John)
   |
   | delegate by agent_type = web_buyer_researcher
   v
Runtime Router / Policy Check
   |
   | spawn new instance
   v
+------------------------------+
| instance_ref = lem_b         |
| type = web_buyer_researcher  |
| focus = Mercado Livre        |
+------------------------------+

Follow-up work:
John -> send(lem_a, "check page 2")
John -> send(lem_b, "apply price filter")
```

## Liveness and idle handling

```text
spawned --> running --> idle --> dismissed
                    \-> idle_ttl expired --> terminated

While idle:
- instance_ref stays valid
- working context remains in memory
- caller may send follow-up work

If follow-up arrives after termination:
- runtime returns delivery error
- caller decides whether to respawn or ignore
```

## Boundary and routing scope

```text
World A
├─ City 1
│  ├─ Department X
│  │  └─ John
│  └─ Department Y
│     └─ lem_a
└─ City 2
   └─ Department Z
      └─ lem_b

Allowed:
- John -> lem_a
- John -> lem_b

Not allowed:
- World A -> World B
```

---

# 6. Consequences

## Positive

- Simple mental model: create by type, continue by instance.
- Supports multiple concurrent workers of the same type naturally.
- Avoids hidden reuse behavior in v1.
- Keeps liveness and placement inside the runtime where they belong.
- Preserves iterative delegated workflows through idle instances.
- Aligns with OTP process lifecycle and supervision.
- Keeps World as the hard isolation boundary.
- Limits peer communication through explicit policy.

## Negative

- Callers must handle delivery failure when an idle instance expires before follow-up work arrives; this requires explicit failure handling in coordinator logic.
- Context reconstruction remains necessary on every LLM invocation because the runtime does not maintain implicit model state.
- Without automatic rehydration in v1, an expired instance cannot be transparently resumed; the caller must choose how to handle the gap.
- Default spawn-new semantics may increase instance count if coordinators do not dismiss workers after they are no longer needed.

## Mitigations

- Delivery failure return values (`{:error, :instance_not_found}`, `{:error, :instance_unavailable}`) are distinct and actionable, giving coordinator logic a clear signal to spawn a replacement.
- Idle TTL is configurable per Lemming type; long-running research tasks can use a longer TTL than short-lived classification tasks, reducing premature eviction.
- The minimal lifecycle contract (`spawn`, `send`, `dismiss`) makes explicit dismissal straightforward to add to coordinator logic; the intended pattern is spawn → use → dismiss, not spawn and forget.

---

# 7. Non-Goals

This ADR intentionally does not define:

- cross-City routing; v1 routing is City-local only (see section 4.8 and Future Extensions)
- snapshot storage backend and retention policy (ADR-0008)
- automatic instance rehydration after eviction
- scheduling, queueing, or mailbox prioritization
- load balancing heuristics across nodes

---

# 8. Future Extensions

- Distributed registry with cross-City routing for Worlds that span multiple City nodes.
- Automatic instance rehydration from a persisted snapshot when follow-up work arrives after eviction.
- Mailbox prioritization and work-stealing between idle instances.
- Load balancing heuristics for spawning instances on less-loaded City nodes.

---

# 9. Rationale

The two-tier addressing model reflects a fundamental distinction in agent workflows: the intent to create new work (spawn by type) versus the intent to continue existing work (address by instance). Conflating these into a single addressing form would either force callers to manage instance uniqueness manually or hide implicit reuse decisions in the runtime.

Keeping the registry lightweight — routing metadata only, no business state — is the boundary that prevents the registry from becoming a bottleneck. The working context belongs in the ephemeral store (ADR-0008), where it has its own TTL, compaction, and persistence semantics. A registry that stores context would couple routing availability to context persistence health, creating failure cascades where none are necessary.
