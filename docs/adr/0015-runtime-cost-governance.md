# ADR-0015 — Runtime Cost Governance

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

LemmingsOS allows autonomous agents ("Lemmings") to operate for extended periods of time. These agents may continuously invoke Tools, call external APIs, communicate with other agents, or interact with large language models.

Because many of these operations incur **monetary cost**, the runtime must include deterministic mechanisms to prevent uncontrolled spending.

Typical cost sources include:

- LLM token usage
- external API billing
- cloud compute usage
- third‑party service fees
- long‑running tool executions

Without runtime governance, autonomous systems may unintentionally generate excessive cost.

Examples include:

- a research agent executing thousands of web searches
- repeated LLM inference calls consuming large token volumes
- tools triggering expensive infrastructure operations
- recursive agent loops invoking tools repeatedly

Because LemmingsOS is designed for **long‑running autonomous execution**, cost governance must be enforced by the runtime rather than relying solely on operator supervision.

Cost controls must apply consistently across all runtime interactions that may generate external cost, including:

- LLM usage
- external API usage
- tool execution
- long‑running processes

The system must also align cost governance with the **hierarchical architecture** of LemmingsOS:

```
World → City → Department → Lemming
```

Budgets must be enforceable at higher scopes and restrict the execution capacity of lower scopes.

This allows operators to allocate cost budgets safely across organizational units.

---

# 2. Decision Drivers

1. **Autonomous systems can generate unbounded cost** — A recursive agent loop or
   runaway research agent can consume large token volumes or trigger expensive API
   calls without human intervention. Hard stops are a first-class safety requirement,
   not an optional monitoring feature.

2. **Hierarchy-aligned budgets** — Budget allocation must follow the
   World → City → Department structure so operators can delegate spending authority
   predictably. Lower scopes must not be able to exceed limits set by their parent.

3. **Integration with the existing execution pipeline** — Cost enforcement must plug
   into the same Tool Runtime execution pipeline as authorization, risk evaluation,
   and approval. A bolt-on post-hoc check would create bypass paths.

4. **Operational intent over billing precision** — v1 goal is deterministic runtime
   protection against runaway spending, not billing-grade financial reconciliation.
   The model must avoid over-engineering for precision that is not required.

5. **Token tracking regardless of monetary cost** — Local providers (Ollama) and
   free-tier cloud providers carry zero or near-zero monetary cost but still consume
   context budget and operational capacity. Volume tracking is valuable even when the
   cost estimate is zero.

---

# 3. Considered Options

## Option A — No runtime cost governance; rely on operator supervision

Operators monitor dashboards and manually terminate agents that generate excessive cost.

**Pros:**

- no additional runtime infrastructure required
- no execution pipeline changes

**Cons:**

- autonomous agents run unattended; operators are not available 24/7 to intervene
- by the time an operator detects runaway spending, the cost has already materialized
- no mechanism to enforce organizational budget allocation across Cities and Departments
- LLM providers enforce their own spending limits at the account level, which is too
  coarse for per-Department governance

Rejected. Relying on operator supervision to prevent runaway spending in an autonomous
system is not viable. The system is explicitly designed for unattended operation.

---

## Option B — Provider-side limits only

Configure rate limits and spending caps directly at each API provider's account or
project level.

**Pros:**

- no changes to the LemmingsOS runtime
- provider-enforced limits are guaranteed to be respected

**Cons:**

- provider limits are account-scoped, not hierarchy-scoped; there is no mechanism to
  enforce per-Department budgets using provider controls alone
- local providers (Ollama) have no monetary billing; token volume cannot be governed
  at all with this approach
- budget exhaustion produces provider-level errors (HTTP 429) rather than a controlled
  runtime signal; agents receive opaque failures rather than a `budget_exhausted` result
- budget allocation across organizational units requires coordination with every
  provider independently

Rejected. Provider-side limits cannot model the hierarchical budget allocation that
LemmingsOS requires, and they provide no coverage for local or free-tier providers.

---

## Option C — Checkpoint-based runtime budget subsystem (chosen)

A dedicated cost governance subsystem tracks usage at runtime, evaluates budget
availability before cost-generating operations, and enforces hard stops when budgets
are exhausted. Budgets are hierarchical and aligned to the World → City → Department
structure.

**Pros:**

- hard stops prevent runaway spending before it occurs, not after
- budget allocation follows the hierarchy, enabling per-Department spending controls
- token volume is tracked for all providers including zero-cost local models
- cost governance integrates into the same execution pipeline as other runtime
  safeguards, with no bypass path

**Cons:**

- introduces a new runtime subsystem with its own persistence and failure modes
- checkpoint-based persistence means recent usage may be lost after a crash; the
  model is best-effort, not exact
- cost estimation for some tools is approximate; actual provider billing may differ
  from runtime estimates

Chosen. The operational protection benefit justifies the implementation cost. The
best-effort persistence model is an explicitly accepted trade-off for v1.

---

# 4. Decision

LemmingsOS introduces a **Runtime Cost Governance subsystem**.

The subsystem tracks and enforces runtime cost budgets across the system hierarchy:

```
World → City → Department
```

Each scope may define limits that restrict the execution capacity of agents below it.

Budget controls may include:

- total budget
- execution limits
- cost thresholds
- usage quotas

Costs accumulate as agents perform operations that may generate monetary expense.

The runtime evaluates budget availability before executing cost-generating operations.

If a limit is exceeded, the runtime prevents the operation from executing.

Budget enforcement therefore becomes a **first-class runtime safeguard**, similar to policy authorization, tool approval, and risk classification.

Version 1 uses **checkpoint-based, best-effort cost persistence** rather than full event-level billing storage.

Runtime usage is persisted at significant lifecycle boundaries such as:

- LLM call completion
- expensive tool completion
- transition to `idle`
- completion
- failure
- cancellation

At these checkpoints, the runtime attempts to update aggregated cost counters for the Lemming instance and its enclosing scopes.

If cost persistence fails, the failure does **not** block Lemming lifecycle progression, although the most recent usage update may be lost.

This model is intentionally operational rather than billing-grade. Its purpose is deterministic runtime governance, not precise financial reconciliation.

# 5. Budget Model

Budgets are hierarchical and align with the system architecture.

Example allocation structure:

```
World
  total monthly budget

City
  allocated portion of world budget

Department
  allocated portion of city budget
```

Higher levels constrain lower levels.

Lower scopes may define stricter limits but cannot exceed the limits of their parent scope.

Budgets may be defined using different units depending on the type of resource.

Supported budget units include:

- currency (e.g., USD)
- token counts
- API call counts
- execution quotas

Examples:

```
World
  monthly_budget_usd: 1000

City: salvador
  monthly_budget_usd: 300

Department: research
  llm_tokens_per_day: 2_000_000
```

Budgets may exist simultaneously across multiple resource categories.

The runtime evaluates the effective budget by combining constraints inherited from all parent scopes.

---

# 6. Cost Sources

The runtime tracks cost events generated by operations performed by agents.

Typical cost sources include the following categories.

## 6.1 LLM Usage

Operations involving model inference may generate cost.

Token usage data originates exclusively from the **Model Runtime** (ADR-0019). After
every provider response, the Model Runtime emits a usage event directly to this
subsystem before returning the result to the Lemming. The cost governance subsystem
never polls Lemmings for token counts — the Model Runtime is the authoritative and
sole source for all LLM usage events.

For zero-cost providers (Ollama) and free-tier providers (Gemini free tier), token
volume is still recorded. This enables context budget enforcement and capacity
planning even when the monetary cost estimate is zero.

Metadata tracked per inference call:

- model provider
- model identifier
- prompt tokens
- completion tokens
- cache read / cache write tokens (where provider supports it)
- estimated monetary cost

## 6.2 External API Usage

Many tools invoke external APIs that charge per request.

Examples:

- web search APIs
- SaaS integrations
- AI providers

Tracked metrics may include:

- request count
- provider identifier
- estimated cost per request

## 6.3 Tool Execution

Some tools trigger operations that incur infrastructure cost.

Examples:

- compute jobs
- database operations
- infrastructure automation

Tracked metrics may include:

- execution duration
- compute resource usage
- estimated infrastructure cost

## 6.4 Long‑Running Processes

Certain operations may accumulate cost over time.

Examples:

- continuous research agents
- streaming API usage
- batch processing tasks

The runtime may track elapsed time or usage volume as part of cost accounting.

---

# 7. Budget Enforcement

Budget enforcement occurs during the runtime execution pipeline.

Before executing any operation that may generate cost, the runtime verifies whether sufficient budget remains.

Possible enforcement strategies include:

- blocking tool invocation
- pausing agent execution
- requiring approval for high-cost operations
- throttling execution rate

When the effective budget is exhausted, the runtime applies a **hard stop**.

This means:

- the Lemming may no longer execute cost-generating operations
- the runtime blocks further spending immediately
- execution is stopped even if the task has not yet completed

Budget exhaustion therefore takes precedence over task completion.

If a budget is exhausted, the runtime must **prevent further cost-generating operations** until the budget is replenished, reset, or the execution is manually resumed under updated policy.

This ensures deterministic protection against runaway spending.

Operators may later adjust budgets or resume execution manually.

# 8. Runtime Integration

Cost governance integrates directly into the runtime execution pipeline.

Conceptual execution flow:

```
Lemming
   ↓
Tool Runtime
   ↓
Authorization Check
   ↓
Risk Evaluation
   ↓
Approval Check
   ↓
Cost Budget Evaluation
   ↓
Tool Execution
```

The cost budget evaluation step occurs immediately before execution.

If the runtime determines that the operation would exceed the effective budget, execution is rejected.

The Lemming receives a runtime error indicating that budget constraints prevent the operation.

This design ensures that cost governance operates consistently with other runtime safeguards.

---

# 9. Cost Tracking

The following diagram illustrates the checkpoint-based tracking and hard-stop enforcement model:

```text
Lemming Instance
      │
      │ executes LLM call / Tool / external API
      ▼
Cost-generating operation
      │
      │ usage produced
      ▼
Runtime checkpoint boundary
(idle / completion / failure / cancellation / expensive call finished)
      │
      ├── attempt aggregate cost update
      │      ▼
      │   Lemming cost counters
      │   (best-effort persistence)
      │
      └── emit governance / audit event when relevant
             ▼
         Audit / Telemetry

Before next cost-generating operation:

Lemming
   ▼
Tool Runtime
   ▼
Authorization
   ▼
Risk / Approval
   ▼
Budget Evaluation
   ├── budget available  ──► execute
   └── budget exhausted ──► HARD STOP
                              - no further spending
                              - task may remain unfinished
```

A second view of hierarchical budget enforcement:

```text
World Budget
   │
   ├── City A Budget
   │      │
   │      ├── Department X Budget
   │      │       └── Lemming instances consume from here,
   │      │          while remaining bounded by all ancestors
   │      │
   │      └── Department Y Budget
   │
   └── City B Budget
```


The runtime emits **cost events** whenever a cost‑generating operation occurs.

These events are recorded through the system's audit and telemetry infrastructure.

Each event may include:

- tool name
- cost category
- estimated or actual cost
- world identifier
- city identifier
- department identifier
- lemming instance identifier
- timestamp

Example conceptual event:

```
{:cost_event,
  tool: "web_search",
  cost_usd: 0.002,
  world: "world_main",
  city: "salvador",
  department: "research",
  lemming: "lem_123",
  timestamp: ...
}
```

These events support:

- budget tracking
- operational monitoring
- audit and traceability

The runtime uses these events to update cumulative usage counters associated with each budget scope.

---

# 10. Consequences

## Positive

- Hard stops guarantee that no Lemming can spend beyond its effective budget regardless
  of how long it runs or how many tool calls it makes. The protection is structural, not
  dependent on operator monitoring.
- Hierarchical budget allocation enables per-Department spending controls without
  requiring changes to individual Lemming definitions. Budget policy is an operational
  concern, not a code concern.
- Token volume is tracked for all providers including zero-cost local models. This
  supports context budget enforcement and capacity planning even when the monetary cost
  is zero.
- Cost governance uses the same audit event model as other runtime safeguards, keeping
  cost visibility consistent with the rest of the platform's observability.

## Negative / Trade-offs

- Checkpoint-based persistence means that usage accrued between the last checkpoint and
  a process crash may be lost. The effective budget enforcement may temporarily allow
  slightly more spending than the configured limit in crash recovery scenarios.
- Cost estimation for external tools is approximate. The runtime cannot know the exact
  provider billing in advance; post-hoc reconciliation may reveal discrepancies between
  runtime estimates and actual charges.
- Budget exhaustion stops execution even if the agent was performing valuable work close
  to completion. Operators must tune budgets carefully to avoid premature termination
  of legitimate long-running tasks.

## Mitigations

- The checkpoint-based model is explicitly documented as best-effort and operational
  rather than billing-grade. Operators requiring financial precision must use provider
  billing dashboards as the authoritative source.
- Budget exhaustion produces a structured `{:error, :budget_exhausted}` result, not an
  opaque failure. Lemmings can transition to a recoverable state rather than crashing.
- Operators can set budgets with headroom to account for estimation approximation and
  the checkpoint gap, treating the runtime budget as a conservative soft ceiling.

---

# 11. Non‑Goals

Version 1 intentionally excludes several advanced features.

Out of scope for v1:

- precise billing reconciliation with providers
- real‑time provider billing synchronization
- predictive cost estimation
- financial reporting systems
- automated budget rebalancing

The initial implementation focuses on **deterministic runtime enforcement** rather than full financial accounting.

---

# 12. Future Extensions

Possible improvements include:

- dynamic budget allocation between departments
- predictive cost estimation
- budget alerts and notifications
- cost monitoring dashboards
- integration with provider billing APIs
- automatic throttling policies

These extensions may build on the event model defined in this ADR without changing the core runtime enforcement architecture.

---

# 13. Rationale

Autonomous systems that operate unattended must have structural guardrails against
runaway resource consumption. Relying on operator supervision for cost control is not
viable when agents are designed to run continuously without human interaction.

The hierarchical budget model follows directly from the system's governance philosophy:
each level of the hierarchy allocates resources to lower levels, and lower levels cannot
exceed their allocation. This is the same principle applied to tool policy and
authorization.

The checkpoint-based persistence model is an explicit acceptance of the best-effort
trade-off. Billing-grade precision would require event-level persistence with
transactional guarantees on every operation, which is operationally expensive and
architecturally complex. For the v1 goal of preventing runaway spending, checkpoint-based
counters are sufficient.
