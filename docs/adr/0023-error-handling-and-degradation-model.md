# ADR-0023 — Error Handling and Graceful Degradation Model

- **Status:** Accepted
- **Date:** 2026-03-14
- **Decision Makers:** LemmingsOS maintainers

---

# 1. Decision Drivers

LemmingsOS needs a single cross-cutting failure philosophy because failure is not exceptional in an agent runtime; it is a normal operating condition.

Agents may run for minutes or hours. During that time, model providers may rate limit or become unavailable, tool executions may crash or time out, nodes may restart, and runtime dependencies may temporarily fail. Without an explicit architecture-level model, local retry logic tends to become inconsistent, failures become difficult to contain, and independent subsystems can amplify each other into cascading failure.

The runtime must therefore provide a consistent model for:

- containing failures within the smallest possible scope
- preventing retry storms and feedback loops
- preserving system stability under partial outage
- avoiding unbounded queue growth and resource exhaustion
- remaining operationally simple for self-hosted deployments

This is especially important for LemmingsOS because the project is intentionally designed to be:

- self-hosted
- accessible to small teams
- inexpensive to run
- operable without complex distributed infrastructure

The system must remain usable during partial failures, but it must not attempt to hide hard dependency failures with expensive coordination layers or complicated control planes.

---

# 2. Context

Previous ADRs already define local aspects of failure handling:

- the Lemming execution lifecycle and state transitions
- the Tool Runtime execution model
- the Model Runtime abstraction and provider routing
- runtime cost governance and hard budget stops
- runtime topology and deployment assumptions

Those ADRs establish where failures can happen, but they do not yet define a global philosophy for how failures should be contained, retried, surfaced, or degraded across the runtime as a whole.

The system must handle, at minimum, the following classes of failure:

- model API outages, timeouts, and rate limits
- tool crashes, timeouts, and sandbox failures
- temporary database failures
- overloaded nodes or saturated runtimes
- runaway agents repeatedly consuming compute without making progress
- node restart or process crash during active work

LemmingsOS must address these cases without introducing heavy resilience infrastructure such as service meshes, distributed breaker clusters, or centralized failure orchestration planes.

---

# 3. Decision

LemmingsOS adopts a simple OTP-native failure and degradation model based on:

- supervision trees for containment and restart
- bounded retries with exponential backoff
- explicit backpressure and concurrency limits
- fail-fast handling for non-recoverable errors
- local circuit breakers for repeatedly failing dependencies
- hierarchical model-provider fallback from day 0

The runtime prioritizes:

- stability over throughput
- predictable behavior over aggressive retries
- local containment over global coordination
- simple operational semantics over infrastructure-heavy resilience patterns

Failure handling is intentionally local-first. The runtime should recover common transient failures automatically when safe to do so, degrade in a visible and bounded way when necessary, and stop work explicitly when a dependency is hard-required and unavailable.

---

# 4. Failure Containment Model

Failures must remain contained within the lowest practical boundary of the hierarchy.

```text
World
  └─ City
       └─ Department
            └─ Lemming
```

The containment model is:

- a tool execution failure affects the current Lemming execution path, not the Department
- a Lemming crash does not terminate the Department supervisor tree
- a Department overload or crash does not terminate the City
- a City-level failure does not corrupt World-level configuration or control-plane state

This behavior is implemented with OTP supervision trees, restart intensity limits, and explicit ownership boundaries between runtime processes.

The architecture does not attempt to make every failure invisible. Instead, it ensures that failures are isolated, observable, and recoverable at the correct scope.

---

# 5. Failure Classification

For runtime behavior, failures are classified into three broad categories:

## 1. Transient failures

Examples:

- provider timeout
- HTTP 429 rate limit
- short-lived network interruption
- temporary database connectivity issue
- temporary node overload

These failures may be retried using bounded retry rules.

## 2. Persistent or semi-persistent failures

Examples:

- provider outage lasting several minutes
- a tool consistently crashing because of environment issues
- local sandbox misconfiguration
- database unavailable until operator intervention

These failures should trigger local degradation behavior such as breaker open state, queue slowdown, or explicit pause of new work.

## 3. Permanent or non-recoverable failures

Examples:

- invalid tool input
- policy denial
- authorization failure
- budget exhaustion
- missing required configuration
- unsupported model or tool capability

These failures must fail fast and must not be retried automatically.

---

# 6. Retry Strategy

Retries must always be bounded.

Unbounded retries are forbidden.

The default retry philosophy is:

- retry only for clearly transient failures
- use exponential backoff
- optionally add jitter to avoid synchronized retry spikes
- stop retrying once the retry budget is exhausted
- surface the failure explicitly to the owning process

Illustrative policy:

```text
attempt 1  -> immediate failure handling
attempt 2  -> backoff 1s
attempt 3  -> backoff 5s
attempt 4  -> backoff 30s
then fail
```

Subsystem guidance:

- **Model Runtime:** bounded retries for timeouts, 429s, and selected 5xx failures
- **Tool Runtime:** bounded retries only when the tool contract declares the action retry-safe
- **Persistence / database operations:** bounded retries for transient connectivity or lock-related failures
- **Policy, auth, approval, and budget failures:** no automatic retry

Retry policy remains local to the subsystem, but all subsystem policies must follow the same architectural rule: bounded, explicit, and classified.

---

# 7. Backpressure Philosophy

LemmingsOS must protect the host and runtime before it protects throughput.

Backpressure is mandatory and is implemented with local limits such as:

- maximum active Lemmings per Department
- maximum queued work per Department
- maximum concurrent tool executions
- maximum concurrent model requests per provider
- maximum retries in flight for a given failure domain
- cost and budget hard stops as defined in ADR-0015

When limits are reached, the runtime may:

- queue work for later execution
- reject new work explicitly
- transition work into a waiting state
- slow or pause scheduling within the local scope

The architecture does not require distributed queue coordination. Local concurrency limits and bounded queues are sufficient for v1 and consistent with the deployment model.

---

# 8. Circuit Breakers (Minimal and Local)

Circuit breakers are allowed, but only as simple local runtime mechanisms.

Examples:

- the Tool Runtime temporarily disables a repeatedly failing tool within the local node scope
- the Model Runtime opens a breaker for a failing provider or model route

Illustrative behavior:

```text
provider fails repeatedly
-> breaker opens for 60 seconds
-> no new requests sent during cooldown
-> one probe request allowed after cooldown
-> success closes breaker, failure reopens it
```

The architecture explicitly rejects:

- globally coordinated breaker state
- distributed resilience clusters
- service-mesh-based breaker behavior

Breaker state is intentionally local because LemmingsOS is designed for simple self-hosted deployments and because local containment is sufficient to prevent retry storms in the intended operating model.

---

# 9. Model Provider Fallback

Hierarchical model-provider fallback is a required capability from v1.

LemmingsOS supports a primary model route and a fallback model route. Fallback can be configured hierarchically:

- World may define a default fallback provider/model
- City may override the World fallback
- Department may override the City fallback
- Lemming type or instance policy may select from the allowed effective configuration

Fallback is used only when failure classification indicates that the primary model route is temporarily unavailable or unhealthy, such as:

- timeout
- provider outage
- rate-limit saturation
- repeated transient transport failure

Fallback is not used to bypass policy denial, budget exhaustion, or authorization failure.

The runtime must preserve the same policy and budget checks when switching to fallback. A fallback provider is not an escape hatch around governance.

If both primary and fallback routes are unavailable, the Lemming transitions into a waiting or failed state according to its execution policy.

---

# 10. Database Failure Semantics

PostgreSQL is a required system dependency.

If PostgreSQL becomes temporarily unavailable, the runtime should not panic, crash-loop uncontrollably, or amplify the failure through aggressive retry behavior. Instead:

- database-dependent operations may retry with bounded backoff
- supervisors remain alive where possible
- new work may be slowed, queued, or rejected
- affected processes move into safe waiting or failed states
- operators should receive explicit degraded-state signals through logs and audit events where applicable

However, LemmingsOS does **not** define an offline operating mode.

If PostgreSQL is unavailable for longer than the local retry window, the system should be treated as degraded or unavailable, not as partially offline-capable. The architecture prefers honest dependency failure over hidden split-brain behavior, local shadow persistence, or ad hoc offline execution semantics.

In short:

- temporary DB loss -> bounded retry and controlled degradation
- prolonged DB loss -> system unavailable for normal operation
- no offline mode

---

# 11. Graceful Degradation Model

Graceful degradation means the runtime continues operating in a reduced but controlled manner when some capabilities are unavailable.

It does **not** mean pretending that hard dependencies are optional.

| Failure | Runtime behavior |
| --- | --- |
| Primary model provider unavailable | Retry with backoff, then route to configured fallback provider if allowed |
| Primary and fallback model unavailable | Lemming waits or fails according to execution policy |
| Tool execution crash | Current execution path fails, retry only if tool contract allows |
| Tool repeatedly failing | Local breaker opens and new calls are paused during cooldown |
| Node restart | Supervisors restore runtime processes according to restart strategy and persisted state |
| Temporary PostgreSQL failure | Operations retry with backoff and runtime enters controlled degraded mode |
| Prolonged PostgreSQL failure | System becomes unavailable for normal operation; no offline fallback mode |
| Budget exhausted | Hard stop; no degradation path that continues spending |
| Department overload | Scheduling slows, queues fill up to limit, then new work is rejected or deferred |

---

# 12. Operational Characteristics

This decision deliberately favors:

- low infrastructure complexity
- low operational cost
- single-node and small-cluster operability
- straightforward operator mental models
- OTP-native recovery mechanisms

The runtime should remain reliable on:

- a laptop
- a single server
- a small cluster of nodes

without requiring:

- service meshes
- distributed queue coordinators
- centralized resilience control planes
- expensive observability or traffic-management systems

The architecture assumes that many LemmingsOS deployments will be run by small teams with limited infrastructure budgets. Simplicity is therefore an explicit resilience feature, not merely a convenience.

---

# 13. Implementation Notes

Failure handling should be implemented with standard OTP patterns and small local runtime components.

Illustrative modules include:

```elixir
LemmingsOs.Lemming.Executor
LemmingsOs.Lemming.Supervisor
LemmingsOs.Tool.Runtime
LemmingsOs.Tool.Breaker
LemmingsOs.Model.Runtime
LemmingsOs.Model.Breaker
LemmingsOs.Department.Manager
LemmingsOs.Runtime.Scheduler
```

Implementation guidance:

- supervisors define restart boundaries and intensity limits
- retry metadata should be explicit in runtime state, not hidden in recursive loops
- breaker state should remain local and lightweight
- queue sizes and concurrency limits should be configurable by scope where appropriate
- fallback model routing should reuse the same policy, budget, and audit hooks as primary routing
- degraded-state transitions should be visible in logs and audit events

---

# 14. Considered Options

## Full distributed circuit breaker systems

Rejected.

This adds coordination overhead and operational complexity that do not fit the project's self-hosted and low-cost philosophy.

## Service-mesh-based resilience

Rejected.

This shifts core runtime behavior into infrastructure that many intended deployments will not have and should not need.

## Complex centralized failure orchestration layers

Rejected.

This conflicts with the OTP-first design of the runtime and creates an unnecessary control-plane dependency for common failure handling.

## Offline execution mode for database loss

Rejected.

This would require shadow persistence, reconciliation semantics, and significantly more complexity. For v1, PostgreSQL remains a required dependency.

---

# 15. Consequences

## Positive

- failure behavior becomes consistent across runtime subsystems
- cascading failures are less likely
- retry storms and resource blowups are reduced
- the system remains simple to operate for small teams
- the deployment model stays compatible with self-hosted, low-cost environments
- model fallback provides practical resilience from day 0 without adding heavy infrastructure

## Negative

- prolonged database failure makes the system unavailable rather than partially offline-capable
- local breakers do not coordinate globally across nodes
- throughput may be reduced under load because stability is preferred over aggressive scheduling
- some failures remain visible to users and operators instead of being hidden behind heavy recovery machinery

---

# 16. Future Extensions

Future ADRs may refine:

- exact retry classification tables per subsystem
- breaker thresholds and cooldown defaults
- operator-facing degraded-state visibility and health reporting
- persistence recovery semantics after node restart
- optional larger-scale deployment patterns

Those future refinements must remain compatible with this ADR's central principle: simple, OTP-native, bounded, and operationally accessible resilience.

---

# 17. Rationale

The core design tension in an agent runtime's failure model is between recovery
ambition and operational simplicity. Distributed systems literature offers many
heavy patterns — globally coordinated circuit breakers, service meshes, offline
execution modes, saga orchestration — that are technically sophisticated but
operationally demanding. LemmingsOS is explicitly designed for small teams,
self-hosted VPS deployments, and operators who are not running a site reliability
engineering function. Importing heavy resilience infrastructure for that context
would make the system harder to operate without making it meaningfully more
reliable for its intended scale.

OTP is the right foundation because Elixir supervision trees already implement
the containment model the architecture needs. A Lemming crash is contained by its
supervisor. A Department overload does not propagate upward to the City because
OTP restart intensity limits and process isolation provide the boundary. The
framework's failure model aligns directly with the runtime hierarchy; there is no
need to recreate it with application-level coordination layers.

Bounded retries with exponential backoff are the correct default because transient
failures — rate limits, short provider outages, brief network interruptions — are
the common case in autonomous agent workloads. But unbounded retries are the
common path to retry storms and resource exhaustion in the same context. The
distinction between retryable and non-retryable failures must be made explicit at
the classification level, not left to individual subsystems to discover
inconsistently.

Honesty about hard dependencies is a deliberate choice. Defining an offline
execution mode for PostgreSQL loss would require shadow persistence, reconciliation
semantics, and the kind of split-brain complexity that is disproportionate to both
v1 scope and the intended deployment target. A system that fails visibly and
honestly when its required dependency is unavailable is easier to operate and
debug than one that appears to continue while silently accumulating divergent
state. The architecture prefers explicit degraded-state signals over hidden partial
operation.

Local circuit breakers rather than globally coordinated ones follows the same
principle. A breaker that opens for a failing tool on a single City node is
sufficient to prevent retry storms locally. A globally synchronized breaker adds
coordination overhead and a new failure mode (the coordination channel itself) for
a benefit that does not materialize at the intended deployment scale.
