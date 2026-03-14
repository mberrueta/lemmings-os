# ADR-0006 — Agent Communication Model

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

LemmingsOS is built around specialized, narrow agents rather than general-purpose super-agents.

A single user request may require multiple Lemmings to cooperate. For example:

- one agent searches recent news
- one agent searches a technical knowledge source
- one agent searches a human-oriented knowledge source
- one coordinating agent aggregates and synthesizes results

This means LemmingsOS must define a native communication model for cooperation between runtime instances.

Because Lemmings are runtime processes, direct process messaging is technically possible. However, raw process messaging alone is not enough as an architecture model. The runtime must also define:

- what communication patterns are supported
- who may talk to whom
- how communication is traced and governed
- how multi-agent cooperation remains predictable

Communication between Lemmings is an internal runtime concern and must not be modeled as a Tool. Tools are reserved for interaction with external systems.

---

# 2. Decision Drivers

1. **Specialized agents require structured cooperation** — Multi-step tasks decompose across multiple Lemmings. The runtime must define how they coordinate without falling back to super-agents or unstructured messaging.

2. **Direct OTP messaging is insufficient as a governance boundary** — Raw `GenServer.call` / `send` expose PIDs as the caller's concern, provide no policy enforcement, and produce no audit events. A runtime communication API is required.

3. **Communication must be policy-controlled** — Uncontrolled fan-out, cross-department messaging, or unexpected communication graphs must be preventable through configuration, not code changes. Default-deny is the correct starting posture.

4. **Communication must be auditable** — Agent-to-agent interactions are security-relevant and must produce traceable events. A coordinator spawning ten workers without any audit trail is indistinguishable from a runaway loop.

5. **Not every interaction requires a response** — Both fire-and-forget patterns (status notifications, lifecycle signals) and synchronous request/reply patterns are legitimate. The model must support both without forcing async wrappers everywhere.

6. **Communication is an internal runtime concern, not a Tool** — Reusing the Tool execution path for agent messaging would conflate two different governance domains. Communication and external effects have different authorization, audit, and resource accounting requirements.

---

# 3. Considered Options

## Option A — Direct OTP process messaging

Lemmings communicate by calling each other directly using PIDs obtained from the registry. No runtime communication API is involved.

**Pros:**
- zero additional infrastructure; standard Elixir pattern
- lowest possible latency

**Cons:**
- exposes PID-based addressing to callers; PIDs are unstable across restarts
- no policy enforcement point; any Lemming can message any other Lemming
- no audit events without wrapping every call site manually
- callers must handle process liveness themselves

Rejected. Direct OTP messaging does not provide a policy or audit boundary.

---

## Option B — Shared event bus as the primary communication model

Lemmings publish events to a shared bus (Phoenix.PubSub or Erlang `:pg`). Other Lemmings subscribe to topics of interest.

**Pros:**
- decouples producers from consumers
- supports broadcast and fan-out naturally

**Cons:**
- subscription management becomes a new source of complexity
- topic-based routing does not naturally model directed request/reply
- a shared bus makes it harder to enforce per-Lemming communication policy
- audit requires intercepting all publish/subscribe calls, which is more complex than a single API boundary

Rejected. A shared bus is a good fit for observability events but not for governed agent-to-agent work dispatch.

---

## Option C — External message queue (RabbitMQ, Redis Streams)

Agent communication uses an external MQ as the transport layer.

**Pros:**
- durable message delivery across node restarts
- standard messaging patterns (work queues, pub/sub) are well understood

**Cons:**
- requires an external operational dependency on every self-hosted deployment
- adds significant latency for inter-agent messages that would otherwise be in-process
- queue management, serialization, and consumer lifecycle are substantial operational surface
- does not solve the governance and policy enforcement requirement; those still require a runtime layer on top

Rejected. An external MQ is operationally disproportionate for in-runtime agent communication.

---

## Option D — Native runtime communication API with typed patterns and policy enforcement (chosen)

Agent communication goes through a native LemmingsOS communication API. The runtime enforces allowed peers, pattern types, and communication scope. All interactions produce audit events.

**Pros:**
- single governable boundary for all inter-agent communication
- policy enforcement is structural, not per-call-site
- audit events are produced by the runtime, not by individual agents
- aligns with OTP-style async callback semantics

**Cons:**
- the runtime must manage routing, tracing, and reply correlation
- introduces a communication layer between agents that adds a small per-message overhead
- policy design is important; overly restrictive policies create rigid communication graphs

Chosen. The governance and auditability requirements require a runtime-owned communication boundary.

---

# 4. Decision

LemmingsOS defines agent-to-agent communication as a **native runtime capability**.

Communication is:

- explicit
- directed
- policy-controlled
- auditable

The runtime supports three primary communication patterns:

- request / reply
- notification
- delegation with join

These patterns are available as runtime communication primitives. They are not rigid agent role types.

Lemmings are not configured with a single fixed communication type. Instead, runtime policy determines:

- which peer Lemmings a given Lemming may contact
- which communication patterns it may use
- whether delegation is allowed

The recommended cooperation model for multi-agent execution is **coordinator → worker(s) → join**, but this is a runtime pattern, not a mandatory topology for all communication.

---

# 5. Addressing Model

Agent communication supports two addressing modes.

## 5.1 Addressing by Lemming type

A Lemming may delegate work to a **Lemming type** rather than an existing instance.

Example:

```
delegate to: news_researcher
```

In this case the runtime:

1. resolves the target Lemming type
2. spawns a new Lemming instance
3. returns an instance reference to the caller

This allows agents to dynamically create specialized workers when decomposing tasks.

## 5.2 Addressing by Lemming instance

After delegation, subsequent communication targets the specific instance created by the runtime.

Example conceptual flow:

```
Lemming John
   ↓ delegate(news_researcher)
Runtime spawns
   ↓
Lemming Sara
   ↓ instance_ref(sara-123)

John → sara-123 → follow-up request
```

The caller stores the returned instance reference in its state and continues communicating with that instance rather than spawning a new worker for every follow-up interaction.

This preserves task context and avoids uncontrolled instance creation.

---

# 6. Communication Primitives

## 6.1 Request / reply

A Lemming sends a directed request to another Lemming and expects a response.

Examples:

- ask another agent to summarize a document
- ask another agent to research a topic
- ask another agent to classify or evaluate a result

This is the primary pattern for structured cooperation.

## 6.2 Notification

A Lemming sends a directed notification without expecting a reply.

Examples:

- report task completion
- report a failure
- signal that intermediate data is available

This pattern is useful for lightweight coordination and lifecycle signaling.

## 6.3 Delegation with join

A coordinating Lemming delegates work to one or more specialized Lemmings and later joins their results.

This enables controlled swarm behavior.

Examples:

- delegate research to several specialists
- wait for all or some results
- synthesize the responses into a final output

This is the preferred pattern for multi-agent decomposition.

---

# 7. Runtime Interaction Model

Communication events are traceable as part of runtime observability. The runtime records agent-to-agent interactions so that execution flows can be inspected, audited, and debugged.

Lemmings do not send arbitrary free-form messages to unknown peers.

Instead, communication flows through a native runtime communication boundary.

```
Lemming A
   ↓
Communication Runtime API
   ↓
Policy / Routing / Audit
   ↓
Lemming B
   ↓
Reply / Notification / Completion
   ↓
Lemming A
```

This allows the runtime to enforce:

- peer restrictions
- communication pattern restrictions
- tracing and observability
- resource governance

---

# 8. Coordinator-Worker Pattern

The recommended pattern for collaborative execution is:

```
                ┌──────────────────────┐
                │      Coordinator     │
                └──────────┬───────────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
          ▼                ▼                ▼
 ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
 │   Worker A     │ │   Worker B     │ │   Worker C     │
 │ news research  │ │ tech research  │ │ human research │
 └────────┬───────┘ └────────┬───────┘ └────────┬───────┘
          │                  │                  │
          └──────────────────┴──────────────────┘
                             │
                             ▼
                ┌────────────┴───────────┐
                │    Join / Synthesis    │
                └────────────────────────┘
```

This pattern is encouraged because it preserves specialization while keeping orchestration understandable and auditable.

---

# 9. Policy Model

Agent communication is governed by runtime policy.

Policy defines:

- allowed peer targets
- allowed communication patterns
- whether delegation is permitted
- limits on fan-out or concurrency
- limits on communication scope across runtime boundaries

A Lemming may only communicate with peers explicitly allowed by effective configuration.

This prevents uncontrolled swarm expansion and unpredictable communication graphs.

---

# 10. Configuration Model

Communication permissions are resolved through hierarchical configuration:

```
World → City → Department → Lemming Type → Instance
```

More specific configuration takes precedence, but lower levels may not exceed upper-level restrictions.

This allows, for example:

- a coordinator to contact specific worker types
- a worker to reply only to coordinators
- certain departments to block cross-department delegation

---

# 11. Communication Semantics

The communication model is asynchronous by default from the runtime perspective.

A Lemming submits a communication request and later receives:

- a reply
- a notification
- a completion event
- a timeout or failure event

This aligns with OTP-style runtime design and fits naturally with long-running, supervised agent execution.

---

# 12. What Is Intentionally Not Supported

LemmingsOS does not use unrestricted free-form conversation between arbitrary agents as the default communication model.

The runtime does not assume that any Lemming may spontaneously talk to any other Lemming without policy and routing constraints.

This avoids:

- communication loops
- runaway swarm expansion
- unclear ownership of results
- hard-to-debug emergent behavior

---

# 13. Consequences

## Positive

- Clear native runtime model for agent cooperation.
- Supports specialization without requiring super-agents.
- Enables controlled swarm execution with deterministic fan-out bounds.
- Keeps communication auditable and policy-bound; no interaction is invisible.
- Fits naturally with OTP runtime semantics and asynchronous execution.

## Negative

- The runtime must manage routing, tracing, and reply correlation for all inter-agent messages; this is non-trivial infrastructure.
- Free-form multi-agent conversation is deliberately constrained; agents that need looser communication patterns require explicit policy grants.
- Policy design becomes load-bearing: overly restrictive policies create rigid graphs; overly permissive ones recreate the uncontrolled swarm problem.

## Mitigations

- Routing and address resolution are scoped to ADR-0007, which defines the registry and delivery failure semantics separately from this policy model.
- Policy defaults use an explicit allowlist rather than a denylist; the common case of a coordinator talking to its own spawned workers is always permitted without operator intervention because the coordinator owns the `instance_ref`.
- Policy validation errors are surfaced as structured runtime errors (`{:error, :not_allowed}`), not silent message drops, so debugging policy misconfigurations is straightforward.

---

# 14. Non-Goals

This ADR defines the conceptual model for communication between Lemmings. The following concerns are intentionally out of scope:

- routing and address resolution implementation details (ADR-0007)
- event bus usage for observability or broadcasts
- cross-City communication behavior
- cross-World communication (structurally impossible — see ADR-0003)
- communication cost accounting and fan-out limits

---

# 15. Future Extensions

- Cross-City communication within the same World, subject to city-to-city routing capability and policy.
- Communication cost accounting to track and limit fan-out by budget scope.
- Broadcast patterns for coordination signals within a Department.
- Structured timeout policies for pending delegations.

---

# 16. Rationale

The core insight is that communication in a multi-agent system is a governance surface, not just an implementation detail. When an agent can spawn ten workers and each spawns ten more, the result is not emergent intelligence — it is an uncontrolled resource explosion. Making communication policy-controlled and audit-producing is the structural mechanism that keeps multi-agent execution understandable and bounded.

The decision to keep communication separate from the Tool system reflects a real architectural distinction: Tools are about external effects (side effects on the world), while communication is about internal coordination (collaboration within the runtime). Mixing them would either weaken Tool governance or over-burden the communication API with security concerns that are not relevant for in-runtime messaging.
