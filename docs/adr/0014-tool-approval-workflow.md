# ADR-0014 — Tool Approval Workflow

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

LemmingsOS agents ("Lemmings") interact with external systems exclusively through **Tools**. Tool usage is governed by multiple runtime safeguards defined in earlier ADRs:

- Tool execution boundary (ADR-0005)
- Hierarchical tool authorization (ADR-0012)
- Risk classification and runtime governance (ADR-0013)

Tool authorization determines **whether a Lemming is permitted to use a specific Tool** according to hierarchical policy.

However, authorization alone is insufficient for certain high‑impact operations.

Some tool invocations may be technically authorized yet still represent actions that require explicit human review before execution.

Examples include:

- modifying production infrastructure
- executing Terraform or cloud configuration changes
- performing financial operations
- destructive database mutations
- high‑cost external API operations

In these situations the system must support **human‑in‑the‑loop decision points** to ensure that sensitive actions are executed intentionally and with operator awareness.

It is therefore necessary to distinguish two separate concepts:

Authorization
: Determines whether a tool *may be used at all* by a Lemming according to runtime policy.

Approval
: Determines whether a **specific invocation** of a tool should be allowed to proceed at a particular moment.

Authorization is a static policy evaluation.
Approval is a dynamic runtime decision applied to an individual execution request.

Human approval gates are a widely used safeguard in systems that allow automation to affect critical infrastructure or financial resources. Introducing an approval workflow allows LemmingsOS to safely support high‑risk automation without removing human oversight.

---

# 2. Decision Drivers

1. **Human oversight for high-impact actions** — Autonomous agents executing
   infrastructure mutations, financial operations, or destructive database changes
   without human review is unacceptable for most organizations. The runtime must
   support mandatory human gates as a first-class feature.

2. **Separation from authorization** — Approval is a per-invocation runtime decision,
   not a static policy evaluation. The implementation must be architecturally separate
   from ADR-0012 tool authorization. Conflating the two would make the authorization
   model dynamic and unpredictable.

3. **Durability** — Pending approval requests must survive BEAM process restarts. A
   Lemming crash must not silently lose the waiting state or resume without the
   required approval having been granted.

4. **Hierarchy alignment** — Approval authority must follow the same scope rules as
   the rest of the system. An operator may approve only requests within their assigned
   hierarchy scope.

5. **Simplicity of initial implementation** — v1 must be operable without complex
   configuration. Multi-step approval chains and quorum requirements are future work.
   A single human gate that any qualified operator can resolve is sufficient.

---

# 3. Considered Options

## Option A — No approval workflow; rely on post-hoc audit

All authorized tool executions proceed immediately. Operators review the audit log
after the fact and terminate agents or roll back changes if problems are detected.

**Pros:**

- no additional runtime infrastructure required
- no execution latency introduced by waiting for approval

**Cons:**

- production infrastructure changes and financial operations execute before any human
  can review them; by the time the audit log is reviewed, the blast radius has already
  materialized
- audit records satisfy compliance requirements but do not prevent damage
- operators cannot express "this specific tool must never run autonomously"

Rejected. For critical-risk tools, post-hoc detection is not an acceptable substitute
for pre-execution review. The blast radius of an autonomous infrastructure change cannot
be unwound by reading a log.

---

## Option B — LLM self-approval; the Lemming's own reasoning evaluates whether to proceed

Before executing a high-risk tool, the Lemming uses its model to reason about whether
the action is appropriate and decides whether to proceed.

**Pros:**

- no additional infrastructure required
- the Lemming's context about the task informs the approval decision

**Cons:**

- LLM reasoning cannot substitute for human accountability; operators cannot delegate
  production infrastructure decisions to a language model
- the approval decision is non-deterministic and cannot be audited as a human act
- prompt injection or model hallucination could cause unintended approval of dangerous
  operations
- the Lemming's self-assessment is not visible to operators until after execution

Rejected. Human accountability for high-impact actions cannot be delegated to an LLM.
The governance requirements are not satisfiable by model-based self-evaluation.

---

## Option C — Single-step human approval gate via ApprovalManager (chosen)

A dedicated ApprovalManager runtime component pauses execution when an invocation
meets approval criteria. The request enters a pending state visible in the control
plane. A qualified operator approves or rejects it. The decision is durable and
auditable.

**Pros:**

- provides a genuine human accountability gate for high-impact operations
- approval requests are durable: a Lemming restart does not lose the pending decision
- approval authority follows the existing hierarchy scope rules from ADR-0011
- the ApprovalManager is a discrete runtime component that can be tested and evolved
  independently of individual Lemming implementations
- every approval decision produces an audit record satisfying forensic and compliance
  requirements

**Cons:**

- introduces a new durable runtime component (ApprovalManager) that must be
  supervised, persisted, and maintained
- execution latency for approval-gated tools depends on how quickly an operator
  responds; an unattended system with critical-risk tools in the execution path
  will block indefinitely
- operators must actively monitor the approval queue for time-sensitive operations

Chosen. The durability, auditability, and genuine human accountability justify the
operational overhead for the class of operations that approval is designed to protect.

---

# 4. Decision

LemmingsOS introduces a **Tool Approval Workflow** mechanism.

The Tool Runtime may require explicit human approval before executing a tool invocation.

Approval requirements are evaluated dynamically during tool execution and may depend on runtime policy conditions such as:

- tool risk classification
- specific tool identity
- execution scope (World / City / Department)
- execution environment (for example staging vs production)
- operation type or parameters

If an invocation requires approval, execution is paused and the request enters a pending state until a qualified operator reviews the request.

The approval workflow acts as a runtime control layer that sits **after authorization and risk evaluation but before tool execution**.

Approval requirement detection is performed by the **Tool Runtime through deterministic policy evaluation**. It is not delegated to the LLM and is not implemented independently inside each Lemming.

Pending approval state and lifecycle management are owned by a dedicated runtime subsystem, referred to in this ADR as the **ApprovalManager**.

---

# 5. Approval Triggers

Approval may be required for certain tool invocations depending on administrator-defined policy.

Typical triggers include:

- tools classified as **critical risk**
- destructive operations (delete, drop, terminate)
- operations that mutate infrastructure
- operations with significant financial impact
- operations exceeding configured cost thresholds
- actions outside normal operational policies

Approval requirements are configured by administrators through runtime policy.

Different scopes may apply different approval rules.

Example:

```
World
  terraform_apply → approval required

City: staging
  terraform_apply → approval optional

City: production
  terraform_apply → approval mandatory
```

The runtime determines whether approval is required based on the **effective policy after hierarchical resolution**.

For v1, approval policy is intended to remain simple to operate.

The primary administrator experience is:

- a simple per-tool approval setting in the control plane
- an optional advanced YAML configuration for more specific approval rules

Tools provide structured metadata that helps the runtime evaluate approval requirements, for example:

- risk level
- supported actions
- mutating or destructive action hints

Tools do **not** define approval policy themselves.

Instead:

- tool packages provide metadata
- administrators configure approval behavior
- the Tool Runtime evaluates the effective policy deterministically

This keeps governance centralized and operationally manageable.

---

# 6. Approval Workflow Model

When approval is required, tool execution follows a structured lifecycle.

```
Tool invocation requested
        ↓
Runtime detects approval requirement
        ↓
Invocation enters pending state
        ↓
Approval request created
        ↓
Authorized operator reviews request
        ↓
Approve or reject
        ↓
Runtime continues or aborts execution
```

If the request is approved, execution resumes normally.

If the request is rejected, the invocation terminates and the Lemming receives a failure result.

Pending approval requests must be:

- durable
- auditable
- visible to operators through the control plane

Approval requests therefore persist independently of the requesting Lemming process so that system restarts do not lose pending decisions.

The pending request lifecycle is managed by a dedicated **ApprovalManager** runtime component.

ApprovalManager responsibilities include:

- creating approval requests
- persisting pending approval state
- exposing approve and reject operations
- resuming or aborting blocked execution after a decision
- emitting audit events for approval lifecycle transitions

This keeps approval governance outside individual Lemming implementations and avoids duplicating approval logic across agents.

---

# 7. Approval Scope and Permissions

Only authorized human operators may approve tool executions.

Approval permissions follow the same hierarchical authorization model defined for the control plane.

Users may approve requests if:

1. their role allows approval actions
2. their assigned scope is an ancestor of the request scope

Example:

```
operator(city = salvador)
```

This operator may approve tool executions originating from:

- departments within the Salvador city
- lemmings within those departments

Role capabilities:

Admin
: may approve requests within their scope and all descendants.

Operator
: may approve requests within their operational scope.

Viewer
: cannot approve or reject requests.

This ensures that approval authority aligns with the same hierarchy used for runtime governance.

---

# 8. Execution Pipeline Integration

The approval mechanism integrates into the Tool Runtime execution pipeline.

Conceptual execution flow:

```
Lemming
   ↓
Tool Runtime
   ↓
Authorization check (ADR-0012)
   ↓
Risk policy evaluation (ADR-0013)
   ↓
Approval requirement check
   ↓
(optional) Approval Workflow
   ↓
Secret resolution
   ↓
Tool execution
   ↓
Audit event
```

More explicitly:

```
Lemming
   ↓
Tool Runtime
   ↓
Authorization check
   ↓
Risk evaluation
   ↓
Approval policy evaluation
   ↓
ApprovalManager
   ├─ no approval required → continue
   └─ approval required → create pending request
   ↓
Secret resolution
   ↓
Tool execution
   ↓
Audit event
```

If approval is required, execution pauses at the approval step.

The Lemming instance transitions to a **waiting_approval** state until the decision is made.

Once approval is granted, execution continues automatically without requiring additional intervention from the Lemming.

The Lemming does not decide whether approval is needed and does not own the approval workflow state.

---

# 9. Approval Record

Each approval decision must produce a persistent record stored in the system audit log.

The record must include:

- tool invocation identifier
- requesting lemming instance
- world / city / department scope
- tool name
- summarized parameters
- approval decision (approved / rejected)
- approving user
- decision timestamp

Example record:

```
approval_event
  invocation_id: inv-78421
  lemming_id: lem-23
  world: prod
  city: salvador
  department: infra
  tool: terraform_apply
  decision: approved
  approved_by: operator_17
  timestamp: 2026-03-14T18:21:03Z
```

Approval records must never contain secret values or sensitive credentials.

The audit trail ensures that every high-risk action executed by the system remains traceable.

In addition to final approve or reject decisions, the ApprovalManager should emit audit events for key approval lifecycle transitions, such as:

- approval requested
- approval granted
- approval rejected

This provides full traceability from pending request creation through final resolution.

---

# 10. Consequences

## Positive

- Human accountability is guaranteed for configured high-risk operations. An autonomous
  agent cannot execute a production infrastructure change or destructive mutation without
  an explicit human decision being recorded.
- Approval state is durable. A Lemming crash while waiting for approval does not lose
  the pending request; the system can resume execution once the operator decides.
- Approval authority follows the same hierarchy scope rules as the rest of the system.
  Operators approve only what they are already authorized to manage.
- The ApprovalManager is a discrete subsystem. Approval logic does not leak into
  individual Lemming implementations.

## Negative / Trade-offs

- A new durable runtime component (ApprovalManager) must be designed, supervised,
  persisted, and maintained. Bugs in the ApprovalManager affect every approval-gated
  tool execution across all Lemmings in the system.
- Execution latency for approval-gated tools is unbounded at runtime. If no operator
  is available to respond, the Lemming blocks indefinitely in `waiting_approval` state.
- Operators must actively monitor an approval queue for time-sensitive operations.
  There is no timeout or escalation in v1.
- Systems where many tools require approval may create operator fatigue, reducing the
  effectiveness of the approval gate over time.

## Mitigations

- The approval queue is visible in the control plane with enough context (tool, scope,
  parameters summary) for operators to make decisions without navigating to the Lemming
  detail view.
- Approval requirements are configurable per scope: a staging environment can have
  approval optional while production keeps it mandatory, reducing routine approval
  volume for non-production work.
- Future extensions (approval expiration, escalation, chat-based notifications) can
  address operator response latency without changing the core approval model.

---

# 11. Non‑Goals

The following capabilities are explicitly **out of scope for v1**:

- complex approval chains
- multi‑stage approvals
- external policy engines (for example OPA)
- automated risk scoring
- Slack or Telegram approval integrations
- approval delegation workflows

Version 1 focuses on a **simple single‑step approval gate** integrated directly into the Tool Runtime.

---

# 12. Future Extensions

Potential future improvements include:

- multi‑approver workflows
- quorum‑based approvals
- approval expiration and TTL
- escalation rules
- integration with external approval systems
- chat‑based approval flows
- programmable policy engines

These extensions would expand the approval system while preserving the fundamental separation between **authorization**, **risk governance**, and **human approval**.

---

# 13. Rationale

Authorization determines whether a tool may be used at all. Risk classification
determines the governance baseline that applies. Approval determines whether a specific
invocation should proceed at this specific moment.

These are three separate concerns and must remain architecturally separate. Merging
approval into authorization (making authorization dynamic) would make the policy model
unpredictable. Delegating approval to the LLM removes human accountability. Skipping
approval entirely for high-risk tools is not acceptable for production systems.

The ApprovalManager as a dedicated runtime component keeps approval state durable and
visible, and keeps approval logic out of individual Lemming implementations. This means
that adding approval requirements to a new tool is a configuration change, not a code
change.
