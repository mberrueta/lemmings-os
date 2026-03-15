# ADR-0013 — Tool Risk Classification and Runtime Governance

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

LemmingsOS agents ("Lemmings") interact with the external world only through
controlled runtime capabilities known as **Tools**.

Previous ADRs already define important parts of this boundary:

- Tools are the only supported mechanism for external side effects. (ADR-0005)
- Tool authorization determines whether a Lemming may invoke a given tool. (ADR-0012)
- Secrets are resolved only inside the Tool Runtime. (ADR-0009)
- Runtime behavior is governed by hierarchical configuration. (ADR-0004)

However, authorization alone is not sufficient.

Two tools may both be authorized for a given Department or Lemming type while still
having very different operational risk.

Examples:

- a tool that performs a web search
- a tool that reads a Git repository
- a tool that sends emails
- a tool that modifies a production database
- a tool that executes infrastructure changes

These tools differ materially in:

- blast radius
- side-effect severity
- credential sensitivity
- financial or production impact
- recovery difficulty after misuse or failure

This creates an important distinction.

**Authorization** answers:

- is this tool allowed for this Lemming under hierarchical policy?

**Runtime risk controls** answer:

- even if the tool is allowed, what additional safeguards must be enforced before execution?

Examples of such safeguards include:

- rate limits
- cost budgets
- manual approval requirements
- domain restrictions
- concurrency limits
- network sandboxing

Therefore LemmingsOS needs runtime governance in addition to authorization.

Authorization prevents use of tools outside policy.

Runtime governance limits how authorized tools may execute so that higher-risk tools
operate under stronger controls.

---

# 2. Decision Drivers

1. **Authorization is not sufficient** — Two tools may both be authorized for a
   Department while differing dramatically in blast radius. Governance must be a
   separate, composable layer that applies after authorization succeeds.

2. **Uniformity of enforcement** — Risk controls must apply consistently to all tools
   through a single enforced runtime boundary. Tools must not self-govern; doing so
   would create inconsistent coverage and allow bypass.

3. **Incrementality** — Risk classification must enable progressively stronger controls
   without requiring changes to the authorization model or tool definitions. New
   governance hooks should attach to existing risk levels without modifying tool
   metadata.

4. **Auditability of governance decisions** — Runtime governance outcomes (rate limit
   applied, approval required, execution denied by budget) must appear in audit events,
   not just execution outcomes. Operators must be able to reconstruct the governance
   path for any tool invocation.

5. **Operational transparency** — Operators must be able to see, in the control plane,
   what risk class a tool carries and what runtime controls that implies for their
   configuration.

---

# 3. Considered Options

## Option A — No risk classification; all authorized tools execute uniformly

Tools are either authorized or not. All authorized tools execute under identical
runtime controls regardless of their operational characteristics.

**Pros:**

- simplest model — no tool metadata beyond authorization policy
- no classification decisions to make or maintain

**Cons:**

- a `web_search` tool and a `terraform_apply` tool execute under exactly the same
  governance, which is operationally incorrect
- there is no runtime hook point for adding manual approval to high-impact tools
  without building entirely separate infrastructure
- risk controls cannot be introduced incrementally as new tools are added
- operators have no signal in the control plane about the relative risk of available tools

Rejected. The model cannot express the safety requirements for high-impact tools without
a redesign. A runtime that treats infrastructure mutation identically to a read-only web
search is not suitable for production use.

---

## Option B — Binary safe/unsafe classification

Each tool is classified as either `safe` (unrestricted execution) or `unsafe` (requires
explicit operator approval before every invocation).

**Pros:**

- simple two-state model — no spectrum to reason about
- a single classification decision per tool

**Cons:**

- the binary does not capture the meaningful spectrum between a medium-risk external API
  call and a critical infrastructure change; both are `unsafe` but warrant very different
  governance
- `safe` tools with no rate limits are vulnerable to cost and volume abuse
- approval-for-every-unsafe-invocation creates operator fatigue for medium-risk tools
  that execute frequently and legitimately

Rejected. The binary cannot express the gradient of risk that real tool inventories
exhibit. Collapsing medium and critical risk into one category leads to either
over-approval overhead or under-governance of genuinely dangerous operations.

---

## Option C — Four-tier risk classification with escalating governance baseline (chosen)

Each tool declares a risk level (`low`, `medium`, `high`, `critical`). The risk level
informs the baseline governance controls applied by the Tool Runtime after authorization
succeeds.

**Pros:**

- captures the operational risk spectrum without requiring per-tool custom governance
  configuration
- governance hooks attach to risk tiers, so adding a new high-risk tool automatically
  inherits the correct control baseline
- critical-risk tools can require approval workflows without affecting medium-risk tools
  that should execute automatically
- the tier structure is easy to communicate to tool authors and administrators

**Cons:**

- tool authors must make a classification judgment that may be subjective for
  borderline cases
- the four tiers cannot capture all nuance; a `postgres_query` for read-only use and
  the same tool for production write operations technically share a classification

Chosen. The four-tier model captures the meaningful risk distinctions in real tool
inventories while remaining operationally simple to explain and configure.

---

# 4. Decision

LemmingsOS introduces a **Tool Risk Classification Model**.

Each Tool declares a **risk level** as part of its metadata.

The initial risk levels are:

- `low`
- `medium`
- `high`
- `critical`

Risk classification is part of the Tool contract and is registered in the Tool
Registry together with the rest of the tool metadata.

Example conceptual metadata:

```text
tool_id: web_search
risk_level: low
```

The declared risk level does not by itself grant or deny authorization.

Instead, the risk level informs how the Tool Runtime evaluates and enforces
runtime safeguards after authorization succeeds and before execution begins.

---

# 5. Risk Level Semantics

The risk levels represent the expected operational impact of a tool if it is used
incorrectly, excessively, or in the wrong context.

## Low

Low-risk tools are primarily read-only and have little or no external side-effect.

Typical properties:

- read-only behavior
- low blast radius
- limited credential sensitivity
- failures are easy to contain

Examples:

- web search
- public HTTP fetch with restricted scope
- local document parsing without external mutation

## Medium

Medium-risk tools interact with external systems but usually have limited impact
or constrained side effects.

Typical properties:

- external requests are performed
- actions may create bounded side effects
- misuse is undesirable but typically recoverable

Examples:

- creating a GitHub issue
- posting to a non-critical webhook
- writing to a non-production collaboration system

## High

High-risk tools perform state-changing actions or access sensitive systems where
mistakes may create material operational impact.

Typical properties:

- state mutation in important systems
- stronger credential sensitivity
- higher recovery cost
- increased risk of data corruption, user impact, or service disruption

Examples:

- database writes
- repository mutations
- email sending
- actions against internal systems with persistent effects

## Critical

Critical-risk tools may affect infrastructure, financial systems, production
systems, or other high-consequence environments.

Typical properties:

- very high blast radius
- difficult or costly recovery
- production or financial impact
- requires the strongest governance expectations

Examples:

- infrastructure change execution
- production database administration
- cloud resource mutation
- financial transaction execution

Risk classification is a runtime governance signal, not a moral judgment about a
Tool. A critical tool may be valid and necessary, but it must operate under stricter
controls than a low-risk one.

---

# 6. Runtime Governance Hooks

Risk classification influences the safeguards the Tool Runtime may attach during
execution.

The baseline expectation in v1 is:

## Low

Low-risk tools typically execute with minimal additional restrictions beyond normal
authorization, validation, and standard runtime limits.

## Medium

Medium-risk tools may execute under additional controls such as:

- rate limits
- concurrency limits
- domain or endpoint restrictions

## High

High-risk tools may execute under stronger governance such as:

- rate limits
- budget tracking
- stricter timeout enforcement
- stronger connection restrictions

## Critical

Critical-risk tools may require the strongest controls, including optional approval
workflows where configured.

Examples:

- budget tracking
- strict rate limits
- manual approval before execution
- restricted runtime environments
- hardened network policies

The Tool Runtime may attach policies based on risk level before dispatching the tool
adapter.

This means that risk level becomes an input into runtime enforcement, not just a
label shown in the control plane.

---

# 7. Example Runtime Controls

The following runtime controls may be applied based on risk level and effective
policy:

- rate limits
- concurrency limits
- cost budgets
- manual approval requirements
- domain allowlists
- network sandboxing
- execution timeouts

These controls are enforced by the **Tool Runtime**.

Tools do not self-enforce platform governance.

This preserves a single authoritative execution boundary where LemmingsOS can:

- apply controls consistently
- audit decisions centrally
- evolve governance without changing every tool implementation

---

# 8. Execution Pipeline Integration

Risk classification is integrated into the runtime tool execution pipeline.

Conceptual flow:

```text
Lemming
   ↓
Tool Runtime
   ↓
Authorization check (ADR-0012)
   ↓
Risk policy evaluation
   ↓
Secret resolution
   ↓
Tool execution
   ↓
Audit event
```

Risk evaluation happens **after authorization but before execution**.

This ordering is intentional.

1. The runtime first verifies that the Lemming is allowed to use the tool at all.
2. If authorization succeeds, the runtime evaluates the controls required for that
   tool's risk level.
3. Only then does the runtime resolve secrets and execute the tool.

This preserves a clean separation of concerns:

- **authorization** decides whether execution is permitted in principle
- **risk governance** decides how permitted execution must be constrained

The runtime should emit audit information sufficient to explain not only tool usage,
but also governance decisions such as approval requirements, denied execution due to
budget exhaustion, or sandbox restrictions applied at execution time.

---

# 9. Examples

## Example 1 — `web_search`

```text
risk: low
```

Typical governance:

- standard validation
- normal timeout
- minimal additional runtime restrictions

This tool is read-oriented and has low direct side-effect risk.

## Example 2 — `github_issue_creator`

```text
risk: medium
```

Typical governance:

- rate limits
- domain allowlist for approved GitHub endpoints
- bounded concurrency

This tool creates an external side effect, but the blast radius is usually limited.

## Example 3 — `postgres_query`

```text
risk: high
```

Typical governance:

- rate limits
- budget tracking
- stricter connection restrictions
- tighter timeout policies

If configured for writes or production-adjacent systems, misuse may have material
impact.

## Example 4 — `terraform_apply`

```text
risk: critical
```

Typical governance:

- strict rate limits
- hardened runtime environment
- optional manual approval workflow
- strong network and credential restrictions

This tool can modify infrastructure directly and may have production-wide impact.

---

# 10. Consequences

## Positive

- Risk classification makes the governance expectations for each tool explicit and
  inspectable in the control plane. Operators can evaluate a tool's risk level before
  enabling it, rather than discovering it through an incident.
- Governance hooks attach to risk tiers, so new tools automatically inherit the
  correct control baseline without additional configuration.
- The separation of authorization and governance creates a clean extension point:
  approval workflows (ADR-0014), cost controls (ADR-0015), and isolation (ADR-0016)
  all plug in after risk evaluation without changing the authorization model.

## Negative / Trade-offs

- Risk classification is a judgment call made by tool authors. Borderline cases (a
  `postgres_query` that only reads versus one that writes) require per-tool context
  that the classification label cannot fully capture.
- The four-tier classification does not prevent operators from enabling critical-risk
  tools without approval workflows configured. Classification informs governance; it
  does not enforce a specific governance baseline automatically.
- Tool authors who underclassify (setting `low` for a tool that deserves `high`)
  reduce the governance signal without any system-level detection.

## Mitigations

- The control plane should display the effective governance controls for each enabled
  tool so operators can verify that risk-appropriate controls are configured.
- Tool package review processes and signing (a future extension) can provide a second
  check on classification accuracy before a tool is available to agents.
- Audit events for tool executions include the risk level, enabling retrospective
  detection of tools that consistently operate near governance thresholds and may
  warrant reclassification.

---

# 11. Non-Goals

The following capabilities are explicitly out of scope for v1:

- automatic risk scoring
- dynamic runtime ML policies
- full sandbox virtualization
- external compliance engines

Version 1 requires explicit tool classification and runtime enforcement hooks, not
fully automated governance.

---

# 12. Future Extensions

The following items have since been addressed by dedicated ADRs and are no longer future work:

- **human-in-the-loop approvals** → ADR-0014
- **cost governance** → ADR-0015

Remaining potential future work:

- per-Department risk policies and environment-aware risk profiles
- dynamic risk escalation based on repeated failures or suspicious behavior
- external policy engines for rule evaluation
- stronger sandbox isolation for critical-risk tools (beyond the OS-level model in ADR-0016)
- policy templates by Department type

These extensions can build on the classification model defined here without changing the core execution order:

authorization first, risk governance second, execution last.

---

# 13. Rationale

LemmingsOS already treats Tools as the controlled boundary for all external effects.
That boundary becomes significantly stronger when authorization and runtime governance
are separated but composed.

This ADR therefore establishes three layers of control:

1. **Tool existence and registration**
2. **Tool authorization through hierarchical policy**
3. **Runtime governance based on declared risk**

This keeps the system:

- predictable
- auditable
- extensible
- safer for high-impact tool execution

It also creates a foundation for future work such as approvals, cost controls,
and stronger sandboxing without requiring a redesign of the Tool model itself.
