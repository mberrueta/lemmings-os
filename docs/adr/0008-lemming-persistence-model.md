# ADR-0008 — Lemming Persistence Model

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

In LemmingsOS, every Lemming instance runs as an OTP process. Instances maintain a structured working context while executing tasks, coordinating with other agents, invoking tools, and interacting with users.

However, not all runtime state should be persisted the same way. The system must balance:

- resilience and crash recovery
- security (especially around secrets)
- resource efficiency
- operational simplicity for self-hosted deployments

Additionally, LemmingsOS assumes many deployments will run on simple self-hosted environments (single VPS, Docker, etc.), so persistence and secret management must remain lightweight while still providing reasonable safety guarantees.

This ADR defines how Lemming runtime state is stored, when persistence occurs, and how ephemeral versus durable data is handled.
It is contract-first: it defines the intended persistence architecture and, where needed, the explicit target-phase contract. It is not an implementation status report.

---

# 2. Decision Drivers

1. **OTP crash must not lose meaningful execution progress** — Lemming instances may run for extended periods accumulating task context, tool results, and partial outputs. A crash must allow the runtime to resume from the last valid checkpoint, not restart the task entirely.

2. **Secrets must never appear in any persistence layer** — The attack surface from a storage breach must be bounded. Secret material resolved during tool execution must not leak into checkpoints, context snapshots, audit logs, or any persistence store.

3. **Self-hosted deployments must not require distributed databases** — The persistence model must work correctly on a single-node VPS without Mnesia clustering, distributed ETS replication, or external storage services. Operational simplicity is a first-class constraint.

4. **Durable conversational state and ephemeral working state have different lifetimes** — Human-visible conversation history must survive restarts and be queryable from the control plane. Internal agent working state (tool outputs, partial reasoning, draft summaries) is short-lived and crash-recoverable with lower durability guarantees.

5. **Context compaction must be decoupled from the Lemming instance** — The instance must not pause its own execution to compact its context. Compaction is infrastructure work that should run on dedicated workers at the City level.

6. **The context structure is the integration contract with the Model Runtime** — The `context` sub-map field semantics must be stable because they drive prompt assembly in ADR-0019. Changes to field names or semantics require coordinated updates across the persistence model and the Model Runtime.

---

# 3. Considered Options

## Option A — File-based disk storage for runtime state

Lemming working context, instance snapshots, and checkpoints are written to local files on the host filesystem, optionally encrypted.

**Pros:**
- survives process crashes and node restarts without a separate in-memory store
- no external database dependency; suitable for minimal single-node setups

**Cons:**
- a self-hosted VPS with weak filesystem permissions exposes runtime state to any process or user with host access; operators running LemmingsOS without deep security hardening would be unaware of the exposure
- file I/O serialization adds latency to every context update during active execution
- TTL enforcement requires a separate cleanup process; stale files accumulate silently if cleanup fails
- file locking and concurrent access from multiple instances is error-prone

Rejected. Disk-based storage for runtime state creates unacceptable exposure on self-hosted deployments where filesystem security cannot be assumed. Active Lemming state does not need disk at all; ETS is sufficient.

---

## Option B — ETS-only for all ephemeral state (no disk persistence)

All working context for both active and idle Lemmings lives exclusively in ETS. No DETS, no disk writes for any runtime state.

**Pros:**
- no disk exposure; runtime state is never written to the filesystem
- ETS reads and writes are fast with no I/O overhead
- maximum simplicity for the ephemeral state layer

**Cons:**
- a node restart evicts all ETS tables, including the working context of idle Lemmings; follow-up work arriving after a restart cannot find the instance
- idle Lemmings that have not yet been explicitly dismissed lose all working context on restart
- the restartability guarantee in ADR-0004 cannot be fulfilled for idle instances without some form of crash-surviving storage

ETS-only is the correct model for **active, running** Lemmings — they do not need disk. However, it is insufficient for **idle/sleeping** Lemmings that must survive a node restart and be rehydrated to accept follow-up work. A lightweight disk-backed store is needed exclusively for that case.

Partially accepted for active state; rejected as the complete solution.

---

## Option C — Mnesia for distributed in-memory persistence

Use Mnesia as the in-memory store with optional disk persistence. Mnesia provides BEAM-native distributed tables with replication across nodes.

**Pros:**
- BEAM-native; no external dependency
- supports both in-memory and disk-backed tables
- provides distributed replication across City nodes without additional infrastructure

**Cons:**
- Mnesia clustering is operationally complex to configure correctly, particularly on self-hosted single-node deployments
- Mnesia split-brain scenarios require careful handling; the complexity is disproportionate to the v1 deployment target
- schema migrations require careful coordination across clustered nodes

Rejected. Mnesia's operational complexity is disproportionate to the self-hosted deployment target in v1. Other databases were also evaluated and do not add meaningful benefit over the chosen model — the same reasoning that led to rejecting a time-series database for audit events (ADR-0018) applies here: adding a specialized store for a concern that fits an existing tier is not justified.

---

## Option D — World-level Postgres + ETS (active state) + DETS (idle snapshots only) (chosen)

A single Postgres instance scoped to the World stores durable conversational state. ETS handles all working context for active running Lemmings (no disk). DETS is used exclusively for idle/sleeping Lemming snapshots to enable rehydration after a node restart. Secrets are never persisted in any tier.

**Pros:**
- active Lemming state never touches disk; no filesystem exposure during execution
- idle instance rehydration is supported with minimal disk writes (snapshot only at idle transition)
- a single World-level Postgres instance is operationally simple for self-hosted deployments
- write amplification is bounded: frequent context updates during active execution stay in ETS; Postgres absorbs only lifecycle-boundary writes

**Cons:**
- DETS requires TTL enforcement to prevent unbounded disk growth from orphaned idle snapshots
- rehydration is City-local; if the City node is unavailable, idle snapshots on that node cannot be accessed
- the ETS/DETS distinction adds implementation surface that must be maintained correctly

Chosen. ETS provides the right semantics for active state (fast, no disk exposure). DETS is the minimum necessary addition to support idle rehydration without introducing the security concerns of general file-based storage.

---

# 4. Decision

The persistence model separates **durable state**, **ephemeral runtime state**, and **secret material** into distinct tiers with different durability guarantees, access patterns, and security properties.

Active Lemming state never requires disk. ETS is sufficient for all in-execution working context. DETS is reserved exclusively for idle instance snapshots. A single World-level Postgres instance stores durable conversational state accessible across Cities.

## 4.1 Phase 1 Runtime Slice

The Phase 1 runtime slice uses this persistence contract in a constrained form:

- Postgres stores durable `LemmingInstance` and transcript message records
- ETS stores active per-instance runtime coordination state and queued work
- DETS stores best-effort idle snapshots only
- rehydration from DETS is deferred beyond Phase 1

Any later expansion of checkpointing or recovery must preserve the tier boundaries defined here unless this ADR is intentionally changed.

---

# 5. Durable State (Postgres)

LemmingsOS uses a **single Postgres instance scoped to the World**. There is one database per World, shared across all Cities in that World. Cities do not maintain separate Postgres instances.

Postgres stores only **durable conversational and case state**, similar to a chat history window.

Durable state includes:

- human messages
- system responses visible to the user
- promoted or accepted results
- references to artifacts
- case status
- metadata required to resume the conversation

Durable state **must respect the effective token budget** derived from:

- model context window
- world policy
- city policy
- department policy
- lemming type policy

The runtime enforces these limits before persisting or sending prompts.

Postgres **must never store**:

- internal agent thoughts
- discarded branches
- raw tool outputs not promoted to the main thread
- secrets

---

# 6. Ephemeral Runtime State (ETS / DETS)

Ephemeral state is split into two distinct tiers with different scopes and disk exposure.

## Active State — ETS

All working context for a **running Lemming** lives exclusively in ETS.

- no disk writes during active execution
- fast concurrent reads and writes
- evicted automatically when the process terminates

Active state includes:

- working context
- recent messages
- in-progress tool results
- partial outputs
- instance coordination metadata

Active state must **not contain secret material**.

## Idle Snapshot — DETS

When a Lemming transitions to **idle or sleeping**, the runtime writes a compact snapshot to DETS. This snapshot is the only point at which runtime state touches disk.

Purpose: enable rehydration if the node restarts before the Lemming is explicitly dismissed.

DETS snapshots:

- are written once at idle transition
- are governed by TTL with activity renewal
- are deleted on explicit dismissal or TTL expiry
- must **not contain secret material**

Active running Lemmings do not use DETS. DETS is exclusively the idle-rehydration store.

**Container deployment constraint:** Because OCI containers destroy their filesystem on restart by default, the DETS data directory must be backed by a **persistent volume mount** in all container deployments. Without a persistent volume, idle snapshots are lost on container restart and the rehydration guarantee cannot be fulfilled. This is a mandatory deployment requirement defined in ADR-0022.

---

# 7. Checkpoints

The runtime writes DETS snapshots at lifecycle boundaries, not continuously.

Checkpoint triggers:

1. when an instance transitions to `idle` or `paused`
2. before instance termination (if instance was idle)

Active running Lemmings do not checkpoint to DETS. Their working state lives in ETS and is considered recoverable-at-best. The long-term architecture allows rehydration from the most recent valid checkpoint. In Phase 1, rehydration is explicitly deferred; the runtime preserves durable records and idle snapshots without promising full automatic recovery.

---

# 8. Context Structure

The runtime context is a structured map.

Example structure:

```
%{
  instance_id: ...,
  status: ...,
  updated_at: ...,
  expires_at: ...,
  context: %{
    system_prompt: ...,
    task_goal: ...,
    instructions: ...,
    constraints: ...,
    working_summary: ...,
    tool_results: ...,
    artifacts: ...,
    recent_messages: ...,
    last_output: ...
  }
}
```

Parent/child execution lineage may be added as a future extension when delegation workflows are introduced. It is not part of the Phase 1 runtime contract.

The `context` sub-map is the **contract between the Lemming and the Model Runtime**
(ADR-0019). The Lemming never constructs raw prompt strings. The Model Runtime's
prompt assembler reads this structure and serializes it into a provider-compatible
message sequence at inference time. The field semantics are:

- `system_prompt` / `instructions` / `constraints` → system message
- `task_goal` → injected into the first user turn
- `recent_messages` → prior conversation turns
- `working_summary` → condensed context after compaction
- `tool_results` → tool result turns in provider format
- `last_output` → assistant continuation turn if applicable

Compaction (section 9) rewrites this structure in-place when token limits approach.
After compaction, the assembled prompt remains within the effective token budget
derived from the model policy resolved by the Model Runtime.

The **registry stores only stable runtime identifiers** used for routing and presence.

Runtime state lives exclusively in the ephemeral store.

---

# 9. Context Compaction

When context approaches token limits, the runtime triggers compaction.

Compaction is performed by **city-level infrastructure workers**, not by the Lemming itself.

Typical compaction order:

1. recent_messages
2. tool_results
3. working_summary rewritten
4. artifacts referenced rather than embedded

If compaction fails, a **fallback pool of compaction workers** is tried in priority order.

If all workers fail, the operation returns an error.

---

# 10. Rehydration

Long-term, instances may be rehydrated from ephemeral checkpoints. This section describes the intended architecture after rehydration is introduced.

Rules:

- rehydration occurs **only in the original City and Department**
- no migration between cities or departments

If the original environment is unavailable, rehydration fails.

Phase 1 explicitly defers this capability. Until rehydration is introduced, DETS snapshots exist as a persistence boundary and future extension point rather than an operator-facing recovery guarantee.

Sub-lemmings are **not automatically revived** when the parent instance rehydrates.

They may rehydrate independently if their state exists.

---

# 11. Worker Failure Semantics

Sub-lemming failure affects only the branch of work where it was created.

The coordinating instance decides whether to:

- retry
- create a new worker
- continue with partial results
- request human input

---

# 12. Ephemeral State Lifecycle

Ephemeral runtime state uses TTL with activity renewal.

Behavior:

- each context update refreshes TTL
- runtime attempts best-effort cleanup on case completion
- TTL guarantees eventual expiration even if cleanup fails

---

# 13. Secret Management

Secrets must **never appear in Lemming context or persistence layers**.

This includes:

- Postgres
- ETS
- DETS
- checkpoints
- audit logs

Instead, secrets are resolved at tool execution time.

The system provides a **City Secret Bank** abstraction.

### Secret Bank Properties

- exists per City
- stores sensitive credentials
- accessed only by tools
- governed by policy inheritance

Hierarchy:

```
World
  → City
    → Department
      → Tool policy
```

Lemmings only reference connection identifiers such as:

```
connection_ref = "github_prod"
```

The runtime resolves the actual secret when the tool executes.

---

# 14. Secret Storage (v1)

Secret storage details are intentionally minimal in this ADR and are defined in ADR-0009.

Version 1 supports environment variables as the primary self-hosted secret provider. File-based secret storage is not supported in v1; writing credentials to disk on a self-hosted VPS without strong filesystem security would undermine the protection that the secret isolation model provides.

Full secret storage implementation is defined in ADR-0009.

---

# 15. Consequences

## Positive

- Active Lemming execution never touches disk; no filesystem exposure during normal operation.
- DETS disk writes are minimal and bounded: one snapshot per idle transition, deleted on dismissal or TTL expiry.
- A single World-level Postgres instance is operationally simple for self-hosted deployments; there is no per-City database to provision or maintain.
- Secrets are structurally excluded from every persistence tier, making the storage breach attack surface significantly smaller regardless of which tier is compromised.
- The `context` sub-map contract is stable and explicit, making the integration boundary with the Model Runtime (ADR-0019) auditable and testable independently.

## Negative

- DETS requires TTL enforcement to prevent orphaned idle snapshots from accumulating on disk indefinitely.
- Rehydration is City-local; idle snapshots live on the City node's filesystem, so a node failure means those snapshots are inaccessible until the node recovers.
- Running Lemmings that crash mid-execution can only be recovered to the last idle snapshot, not to the exact point of failure; work accumulated since the last idle transition may be lost.
- Container deployments require a persistent volume mount for the DETS data directory. Operators who fail to configure this volume will silently lose idle snapshots on container restart; there is no error at startup.

## Mitigations

- DETS snapshots carry a hard `expires_at` field. Even if the dismissal cleanup fails, the TTL guarantees eventual expiration and disk reclaim.
- The crash-recovery gap for running Lemmings is bounded by how frequently they transition through `idle`. The runtime surfacing `{:error, :recovery_required}` gives coordinator logic a deterministic signal to spawn a fresh instance or request operator input.
- The City-local rehydration constraint is a documented v1 scope decision, not an oversight. The rehydration failure path is a structured error, not a silent loss.

---

# 16. Non-Goals

This ADR intentionally does not define:

- exact secret storage implementation (ADR-0009)
- context compaction algorithm details
- external secret manager integration (future extension)
- encrypted DETS snapshots
- distributed checkpoint storage across City nodes
- vector / RAG database for semantic search or embedding storage (future ADR)

---

# 17. Future Extensions

- External secret manager integration (Infisical, HashiCorp Vault, cloud provider secret managers).
- Encrypted ephemeral storage for DETS snapshots, reducing the impact of host filesystem compromise.
- Distributed checkpoint storage across multiple City nodes to enable cross-City rehydration.
- Automated compaction policies triggered by configurable token budget thresholds.

---

# 18. Rationale

The ETS/DETS distinction is not an arbitrary split — it reflects a precise security boundary. Active Lemming state never needs to touch disk. It changes too frequently, contains too much intermediate data, and exists only for the duration of a running task. ETS provides the right semantics: fast, in-memory, evicted automatically when the process ends. Writing active state to disk on a self-hosted VPS with weak filesystem permissions would expose intermediate reasoning, tool outputs, and partial results to any process or user with host access, most of whom would have no awareness that the files exist.

DETS is the minimum necessary exception: an idle Lemming needs exactly one thing to survive a node restart — a compact snapshot of its context so it can be rehydrated when follow-up work arrives. That is a bounded, infrequent write at a well-defined lifecycle boundary, not a continuous stream.

The single World-level Postgres follows from operational reality. Self-hosted operators running LemmingsOS on a VPS are not running multiple database instances. One Postgres per World is the right default — it is simple to provision, simple to back up, and contains only the state that needs durability: conversation history that a user can see.

Secrets must be structurally excluded from persistence, not just excluded by convention. By defining the rule at the persistence model level — no tier stores secrets, full stop — the attack surface is bounded regardless of which tier is breached. A tool that accidentally logs a secret is a bug in the tool; a secret that legitimately appears in Lemming context or a DETS snapshot is a design violation.

The decision to delegate compaction to City-level workers rather than the Lemming itself follows the same separation-of-concerns principle as the execution model (ADR-0004): the GenServer is the execution coordinator, not the infrastructure. Keeping the Lemming's process state minimal and its responsibilities narrowly scoped makes each component independently testable and independently replaceable.
