# ADR-0024 — Observability and Monitoring Model

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

LemmingsOS operates as a runtime for long‑running autonomous agents organized in a hierarchical topology:

World → City → Department → Lemming

Previous ADRs define multiple runtime subsystems that generate operational signals:

- ADR‑0004 — Lemming Execution Model
- ADR‑0015 — Runtime Cost Governance
- ADR‑0018 — Audit Event Model
- ADR‑0023 — Error Handling and Degradation Model

ADR‑0018 introduces an **append‑only audit event system** that records significant runtime actions. However, audit events alone are not sufficient for operators to determine the **current operational state of the runtime**.

Operators must be able to answer practical operational questions such as:

- Is the runtime currently running?
- Which City nodes are healthy?
- Are Lemmings executing tasks normally?
- Are tool executions failing?
- Are model calls succeeding?
- Are queues backing up or stalled?

Because LemmingsOS targets **self‑hosted deployments for small teams**, the observability model must avoid operational complexity typically associated with enterprise monitoring stacks.

The system must remain observable in environments such as:

- a single VPS
- a local workstation
- small on‑premise servers

Therefore the observability model must prioritize:

- simplicity
- low operational overhead
- minimal infrastructure dependencies

---

# 2. Decision Drivers

Several constraints shape the observability approach.

1. **Operators must understand runtime health** — If agents execute for long periods, operators need clear signals that the runtime remains healthy.

2. **Distributed nodes require visibility** — Multiple City nodes may exist in a single World. Operators must quickly determine which nodes are reachable and operational.

3. **Failures must be diagnosable** — Runtime failures, tool crashes, or model errors must produce sufficient logs and signals for investigation.

4. **Stuck systems must be detectable** — Long‑running tasks or queue backlogs must be visible so operators can intervene.

5. **Self‑hosted constraint** — Observability must not require large external systems such as SaaS monitoring platforms or distributed tracing clusters.

6. **Cost sensitivity** — The observability model must remain inexpensive and compatible with minimal infrastructure.

---

# 3. Considered Options

## Option A — Full distributed observability stack

Adopt a full enterprise monitoring stack including distributed tracing, metrics aggregation, and centralized log ingestion.

Examples:

- OpenTelemetry tracing pipelines
- distributed trace collectors
- centralized logging clusters

**Pros**

- deep visibility across distributed systems
- advanced diagnostics

**Cons**

- operational complexity
- high infrastructure requirements
- unsuitable for small self‑hosted deployments

Rejected. This model conflicts with the goal of simple self‑hosted installations.

---

## Option B — Logs only

Expose runtime state purely through application logs.

**Pros**

- extremely simple
- no infrastructure dependencies

**Cons**

- difficult to determine real‑time system health
- operators must manually interpret log streams
- no standardized liveness signal

Rejected. Logs alone are insufficient to quickly determine runtime health.

---

## Option C — Layered observability model (chosen)

Adopt a **three‑layer observability model** combining:

- health checks
- structured event logging
- optional metrics

Each layer provides a different class of operational insight while keeping the system simple to operate.

Chosen. This approach balances operational visibility with minimal infrastructure requirements.

---

# 4. Decision

LemmingsOS adopts a **three‑layer observability architecture**.

```
1. Health checks
2. Structured event logging
3. Optional metrics
```

The runtime prioritizes **logs and health endpoints** as the primary operational signals.

Metrics export and external monitoring integrations are **optional extensions**, not mandatory infrastructure.

This ensures that a minimal installation remains observable without requiring external monitoring systems.

---

# 5. Health Checks

Every City runtime exposes a **health endpoint**.

Example endpoint:

```
/health
```

The endpoint returns basic runtime status information.

Example response:

```json
{
  "status": "ok",
  "node": "city_a@host",
  "database": "connected",
  "runtime": "healthy"
}
```

Health checks provide a **fast liveness signal** that operators and orchestration tools can use to determine whether the runtime is operational.

---

# 6. Node Health Model

Each City node exposes a small set of runtime health indicators.

Typical values include:

- node name
- uptime
- number of active Lemmings
- number of active tool executions
- queue depth

These values may be retrieved via the administrative API or a runtime dashboard.

The goal is not to provide deep system introspection but to expose **clear operational signals** for operators.

---

# 7. Event Logging

The primary observability mechanism in LemmingsOS is **structured event logging**.

All important runtime actions emit events defined by **ADR‑0018 (Audit Event Model)**.

Event type names must match the canonical catalog in ADR-0018 exactly. Examples
of catalog-compliant event types relevant to observability:

- `lemming.started`
- `lemming.failed`
- `tool.invocation_requested`
- `tool.invocation_denied`
- `tool.invocation_failed`
- `model.request_started`
- `model.request_failed`
- `model.usage`
- `config.updated`

Example structured log event:

```json
{
  "event": "model.request_failed",
  "model": "qwen3",
  "lemming_id": "abc123",
  "error": "timeout",
  "attempt": 3
}
```

Structured logs allow operators to reconstruct runtime behavior and diagnose failures.

---

# 8. Error Reporting

The runtime may optionally forward errors to external reporting systems.

Examples include:

- Sentry
- OpenTelemetry exporters
- centralized log collectors

These integrations are **optional** and disabled by default.

The runtime must remain fully functional without them.

---

# 9. Metrics (Optional)

LemmingsOS may expose runtime metrics using **Elixir Telemetry**.

Possible metrics include:

- active Lemming count
- tool execution latency
- model request latency
- queue depth
- failure rates

Operators may export these metrics to systems such as:

- Prometheus
- Grafana

Metrics are optional and not required for normal operation.

---

# 10. Observability Architecture

Conceptual signal flow:

```
Runtime Event
     │
     ▼
Structured Log
     │
     ├─ Operator log inspection
     ├─ Optional metrics export
     └─ Optional error reporting
```

Health endpoints provide the **runtime liveness signal**.

Logs provide **diagnostic visibility**.

Metrics provide **optional operational insight**.

---

# 11. Operational Characteristics

The observability design prioritizes:

- simplicity
- low operational overhead
- compatibility with single‑node installations
- compatibility with distributed deployments

A minimal deployment should remain fully observable using only:

- application logs
- health endpoints

This keeps operational requirements aligned with the project's self‑hosted philosophy.

---

# 12. Implementation Notes

Possible runtime modules include:

```
LemmingsOs.Observability
LemmingsOs.Health.Endpoint
LemmingsOs.Event.Logger
```

Telemetry hooks may emit metrics and integrate with Phoenix LiveDashboard when available.

---

# 13. Consequences

## Positive

- Operators gain immediate visibility into runtime health.
- Failures can be reconstructed from structured event logs.
- Observability remains compatible with very small deployments.

## Negative / Trade‑offs

- Without external monitoring systems, long‑term metrics analysis may be limited.
- Operators relying solely on logs must interpret system behavior manually.

## Mitigations

Optional telemetry exporters and log collectors can be integrated when deeper observability is required without modifying the core runtime architecture.

