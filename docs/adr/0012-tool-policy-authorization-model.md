# ADR-0012 — Tool Policy and Authorization Model

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

LemmingsOS agents ("Lemmings") operate as supervised runtime processes that may
interact with external systems through controlled capabilities known as **Tools**.

Previous ADRs established several foundational constraints:

- Lemmings never execute arbitrary external actions.
- All external effects must pass through the Tool Runtime. (ADR-0005)
- Secrets are resolved through the Secret Bank subsystem. (ADR-0009)
- Runtime behavior follows hierarchical configuration inheritance. (ADR-0004)

Because Tools are the only mechanism through which a Lemming can interact with
external systems, uncontrolled access would introduce significant risks:

- unauthorized external API calls
- data exfiltration through unrestricted integrations
- misuse of credentials
- accidental or malicious side effects

Therefore the runtime must enforce a clear **Tool Authorization and Policy Model**
that determines:

- which tools exist in the platform
- which scopes enable those tools
- which Lemmings may invoke them
- which secrets and connections they may access

The model must remain consistent with the LemmingsOS hierarchy:

```
World → City → Department → Lemming
```

This ADR defines the runtime policy model governing Tool availability,
authorization, and secret resolution.

---

# 2. Decision Drivers

1. **Least privilege by default** — No tool should be available to a Lemming unless
   explicitly permitted at every hierarchy level. Open-by-default models create
   accidental exposure. Deny is the default; allow is an explicit act.

2. **Deny dominance** — Higher-scope denials must not be overridable by lower scopes.
   A World-level disabled tool cannot be re-enabled at the Department or Lemming type
   level. This prevents privilege escalation through nested configuration.

3. **Secret isolation** — Tool credentials must never be visible to Lemmings. The
   policy model must define a binding layer that resolves secrets through the Secret
   Bank at execution time only.

4. **Hierarchy alignment** — Tool availability must follow the same
   World → City → Department → Lemming Type chain as all other runtime configuration
   inheritance.

5. **Auditability** — Every tool invocation must produce an audit event identifying
   the Lemming, the tool, the Department, and the outcome. The policy model must make
   the authorization path transparent in the audit record.

6. **Extensibility** — The policy model must accommodate future governance layers
   (risk classification in ADR-0013, approval workflows in ADR-0014, cost governance
   in ADR-0015) without requiring a redesign of the authorization structure.

---

# 3. Considered Options

## Option A — Flat allowlist per Lemming type

Each Lemming type declares the tools it is allowed to use. No hierarchical policy
resolution; each type configuration is self-contained.

**Pros:**

- simple per-type configuration
- no inheritance chain to reason about

**Cons:**

- World and City level administrators cannot enforce platform-wide restrictions;
  a rogue Lemming type could claim access to any installed tool
- credential binding is per-type, creating inconsistent secret management
- no mechanism for a City to restrict tools that World has enabled for its Departments
- deny dominance cannot be enforced; lower scopes can always declare tool access

Rejected. Administrators cannot enforce platform-wide restrictions. This model
inverts the governance structure that LemmingsOS requires.

---

## Option B — Capability tokens per invocation

The Lemming requests a capability token from a central authority before each tool
invocation. The authority evaluates whether to issue the token at runtime.

**Pros:**

- fine-grained per-invocation control
- capability can be revoked between invocations

**Cons:**

- introduces a central token authority as a runtime dependency and bottleneck
- adds a network round-trip to every tool invocation
- the complexity of token issuance, revocation, and expiry is disproportionate to v1
- per-invocation decisions are harder to reason about than a static policy snapshot

Rejected. The operational complexity and latency cost are not justified for v1. Static
policy evaluation at invocation time achieves the same access control without the
infrastructure burden.

---

## Option C — Hierarchical tool policy model (chosen)

Tool availability is controlled at each level of the hierarchy. Resolution follows the
World → City → Department → Lemming Type chain with deny dominance. Secret binding is
declared by the tool and resolved by the Secret Bank at execution time.

**Pros:**

- administrators control availability at each level; lower levels can only restrict
- deny at any level propagates downward unconditionally
- secret binding is centralized and never exposes values to Lemmings
- the model composes cleanly with risk classification and approval workflows

**Cons:**

- policy resolution spans multiple scopes, which increases the complexity of reasoning
  about what a specific Lemming instance can actually do
- misconfiguration at one scope can silently deny a tool that was expected to be
  available

Chosen. The governance requirements demand hierarchy-aligned, deny-dominant policy
resolution. The operational cost of the complexity is manageable through the control
plane UI and clear audit events.

---

# 4. Decision

LemmingsOS implements a **hierarchical tool policy model** aligned with the
system hierarchy.

Policy evaluation follows the configuration chain:

```
World → City → Department → Lemming Type → Lemming Instance
```

More specific configuration may further restrict permissions but may **never
expand capabilities beyond what is allowed by higher scopes**.

Tool usage therefore becomes the result of resolving several layers of policy:

1. Tool installed at platform level
2. Tool enabled for the relevant hierarchy scope
3. Tool permitted for the Department
4. Tool permitted for the Lemming Type
5. Optional instance-level restrictions

Only when all checks succeed may the Tool Runtime execute the request.

---

# 5. Tool Availability Levels

Tool availability is controlled through hierarchical enablement.

## Platform level

A Tool must first be **installed and registered** in the Tool Registry.

Example lifecycle:

```
Installed → Registered → Enabled → Policy Allowed
```

Installation alone does not make a tool available to agents.

## World level

Administrators may enable or disable tools for the entire World.

Example:

```
Tool: github_repo_reader
World: enabled
```

This makes the tool eligible for use within that World.

## City level

Cities may further restrict tool availability.

Example:

```
World
  github_repo_reader: enabled

City: salvador
  github_repo_reader: disabled
```

Departments inside that City cannot use the tool.

## Department level

Departments may restrict the tools available to their agents.

Example:

```
Department: finance
Allowed tools:
  - postgres_query
  - http_fetch
```

Tools not listed remain unavailable.

## Inheritance rules

Policy resolution follows nearest-scope precedence with deny dominance.

Rules:

- lower scopes may **restrict** permissions
- lower scopes may **not bypass higher-level denies**
- the effective policy is the intersection of all scopes

Example resolution order:

```
Department → City → World → Platform
```

---

# 6. Tool Permission Resolution

The runtime determines whether a Lemming instance may call a Tool using
hierarchical policy evaluation.

Conceptual pseudocode:

```
tool_allowed?(lemming, tool)
```

Example resolution flow:

```
def tool_allowed?(lemming, tool) do
  tool_installed?(tool) and
  tool_enabled_in_world?(tool, lemming.world) and
  tool_enabled_in_city?(tool, lemming.city) and
  tool_allowed_in_department?(tool, lemming.department) and
  tool_allowed_for_type?(tool, lemming.type)
end
```

Checks performed:

1. Tool exists and is registered.
2. Tool is enabled at the World scope.
3. Tool is enabled at the City scope.
4. Department policy allows the tool.
5. Lemming Type configuration allows the tool.

Optional additional checks may include:

- instance-specific overrides
- rate limits
- cost budgets

If any check fails, the Tool Runtime rejects the invocation.

---

# 6.1 Policy Evaluation Order

To guarantee deterministic behavior, the runtime evaluates tool authorization
in a strict order.

Evaluation pipeline:

```
1. tool_installed?
2. tool_enabled_world?
3. tool_enabled_city?
4. tool_allowed_department?
5. tool_allowed_lemming_type?
6. instance_overrides?
```

Rules:

- evaluation stops on the **first failing rule**
- lower levels may only **restrict**, never expand permissions
- deny rules dominate allow rules

This deterministic evaluation order ensures predictable runtime behavior
and simplifies auditing and debugging.

## Intentional asymmetry with secret resolution

Policy evaluation and secret resolution (ADR-0009) intentionally use **opposite precedence rules**. This is not an inconsistency — it reflects the different nature of each concern.

**Policy is deny-dominant (most restrictive wins):**
Authorization is *constraint enforcement*. A deny at World level means no entity below World — City, Department, or Lemming — can grant that capability. If a more specific level could override a deny, any Department admin could escape platform-level restrictions. The security model depends on upper-level denies being unbreakable.

**Secrets resolve to the most specific definition (most specific wins):**
Secret resolution is a *definition lookup*. The runtime walks from the most specific scope upward until it finds a binding for the requested key. A Department-level credential legitimately overrides a City-level credential — there is no security concern with a more specific scope providing a different credential for a tool it is already authorized to use.

The authorization question ("may this Lemming use this tool?") is answered by policy before secret resolution ever begins. Secrets are only resolved after the tool call has been authorized. This ordering means the override semantics of secret resolution never affect whether an action is permitted — only which credential is used to perform an already-authorized action.

---

# 7. Secret and Connection Binding

Some tools require credentials or connection configuration.

Tools do not access secrets directly.

Instead:

- tools declare **logical secret requirements**
- runtime policy binds those requirements to concrete secret keys
- secrets are resolved through the Secret Bank

Example tool declaration:

```
tool: github_issue_creator
required_secrets:
  - github.token
```

Policy binding example:

```
secret_bindings:
  github.token: secrets.github.company
```

Execution resolution flow:

```
Tool Runtime
   ↓
resolve secret binding
   ↓
Secret Bank lookup
   ↓
Department → City → World
   ↓
secret injected into Tool adapter
```

The secret value is injected only into the Tool Runtime execution context.

Lemmings never receive raw credentials.

---

# 8. Execution Flow

Tool invocation follows a controlled runtime pipeline.

```
Lemming Instance
   ↓
Tool Runtime
   ↓
Policy evaluation
   ↓
Secret resolution
   ↓
Tool adapter execution
   ↓
Result returned to Lemming
```

More detailed runtime flow:

```
Lemming
   ↓ Tool.call
Tool Runtime
   ↓
Policy Check
   ↓
Secret Binding Resolution
   ↓
Secret Bank Lookup
   ↓
Tool Adapter
   ↓
External System
   ↓
Result
   ↓
Audit Event
```

All external side effects therefore occur through a single controlled runtime
boundary.

---

# 9. Security Properties

The model provides several key security guarantees.

## Least privilege

Each scope restricts the capabilities available to its agents.

Departments and Lemming types receive only the tools required for their role.

## Secret isolation

Lemmings never receive secret values directly.

Secrets are resolved only during tool execution and injected into the tool
adapter.

## Controlled external effects

All external actions occur through the Tool Runtime.

No direct system calls or arbitrary command execution are allowed.

## Auditable behavior

Every tool invocation produces an audit event containing:

- tool identifier
- world / city / department
- lemming instance
- timestamp

Secret values are never logged.

---

# 10. Examples

## Example 1 — Tool enabled only for one City

```
Tool installed globally

World
  http_fetch: enabled

City: salvador
  http_fetch: enabled

City: rio
  http_fetch: disabled
```

Result:

Lemmings in salvador may use the tool.

Lemmings in rio cannot.

---

## Example 2 — Department tool restrictions

```
Department: research
Allowed tools:
  - web_search
  - http_fetch

Department: finance
Allowed tools:
  - postgres_query
```

Finance agents cannot perform web search.

Research agents cannot access the database.

---

## Example 3 — Different credentials per Department

```
Tool: github_issue_creator

Department: open_source
  github.token → github.oss_token

Department: enterprise
  github.token → github.enterprise_token
```

The same tool uses different credentials depending on Department.

---

# 11. Consequences

## Positive

- The hierarchical model ensures that World and City administrators retain
  unconditional veto power over tool availability. No lower-scope configuration
  can override a deny at a higher level.
- Secret isolation is structural: Lemmings have no path to raw credentials. Even a
  compromised Lemming process cannot extract the API keys used to execute its tools.
- The policy evaluation chain is deterministic and auditable. For any denial, the
  audit event can identify exactly which layer in the hierarchy caused the rejection.

## Negative / Trade-offs

- Reasoning about effective tool access for a specific Lemming instance requires
  mentally tracing five levels of policy (platform, world, city, department, type).
  Operators must understand the full chain to diagnose unexpected denials.
- A misconfiguration at any level silently denies a tool that was expected to be
  available. The error is visible in the audit log but not necessarily in the
  Lemming's failure message.
- Secret binding configuration must be maintained at each scope that introduces a
  different credential. As the number of tools and Departments grows, this can
  become an operational maintenance burden.

## Mitigations

- The control plane UI should provide a resolved policy view showing the effective
  tool access for a given Lemming type, making the five-level chain inspectable
  without manual tracing.
- Audit events for denied tool invocations include the failing policy level, allowing
  operators to diagnose misconfiguration without reading through five layers of
  configuration manually.
- Secret binding follows the same hierarchical inheritance, so a binding set at World
  scope applies to all lower scopes unless overridden. Teams with uniform credentials
  need only one binding entry.

---

# 12. Non-Goals

The following capabilities are explicitly out of scope for version 1.

- dynamic policy engines
- per-user tool permissions
- marketplace trust scoring
- tool sandboxing

These features may be introduced later once the core runtime stabilizes.

---

# 13. Future Extensions

The following items from earlier drafts of this ADR have since been addressed by dedicated ADRs and are no longer future work:

- **tool risk classification** → ADR-0013
- **cost budgets per tool** → ADR-0015
- **sandboxed tool execution environments** → ADR-0016

Remaining potential improvements:

- external policy engines for dynamic rule evaluation
- signed tool packages and trust verification
- per-user tool permissions (below the Lemming-type granularity)
- marketplace trust scoring for community packages

These would extend the current policy model without changing its hierarchical foundations.

---

# 14. Rationale

Tools are the only mechanism by which a Lemming interacts with the external world.
Making tool access unrestricted or weakly governed would undermine the safety model
of the entire runtime.

The hierarchical policy model follows directly from the system's core design principle:
each level of the hierarchy owns its resources and can further constrain what is
available below it. Tool policy is an application of that principle, not an exception.

Secret binding at the policy layer rather than in Lemming definitions ensures that
credentials are an operational concern, not a code concern. Different Departments can
use the same tool with different credentials without modifying the tool or the Lemming.
