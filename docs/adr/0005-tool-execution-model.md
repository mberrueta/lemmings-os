# ADR-0005 — Tool Execution Model

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

LemmingsOS agents ("Lemmings") must interact with external systems such as:

- local machine capabilities
- HTTP APIs
- LLM providers
- databases
- other services
- other external platforms

Allowing agents to execute arbitrary code or unrestricted commands would introduce severe security, reliability, and governance risks.

Therefore, LemmingsOS introduces a **Tool model** as the controlled boundary between agents and external effects.

All interactions with systems outside the Lemming process must go through registered tools managed by the runtime.

The tool system must support:

- security and permission enforcement
- auditability of external actions
- runtime policy enforcement
- rate limits and timeouts
- cost and token accounting
- extensibility by third-party developers

The system must also support two main user profiles:

1. **Non-technical users**, who install and enable tools via a simple CLI or UI.
2. **Technical users**, who may install tools manually or develop custom tools locally.

---

# 2. Decision Drivers

1. **Agents must not execute arbitrary effects** — Unrestricted system calls, shell commands, or direct API access from agent code would make security enforcement impossible and audit trails meaningless. All external effects must be mediated by the runtime.

2. **Tool permissions must be hierarchically governable** — The same tool may have different allowed connections and usage limits in different Departments or Cities. Permission changes must be configuration changes, not code changes.

3. **The extension model must be validated from day one** — First-party tools must ship as separate packages using the same plugin mechanism as community tools. If the core runtime requires modification to add official capabilities, the extension model is broken.

4. **Tool execution must produce an audit trail** — Every external interaction, including failures and policy denials, must produce a traceable event. This is a governance requirement, not an optional observability feature.

5. **Non-technical operators must install tools without touching code** — The CLI-based installation workflow (`lemmings tool install <package>`) is a first-class user experience target, not a convenience.

6. **MCP is an execution backend, not the security boundary** — The Model Context Protocol is a useful adapter for LLM-native tool integrations, but it provides no authorization, audit, or cost governance. LemmingsOS must own those concerns independently of whatever adapter executes the tool.

---

# 3. Considered Options

## Option A — Agents execute external effects directly

Agents call external systems through Elixir function calls, HTTP clients, or shell commands without any runtime intermediary.

**Pros:**
- simplest implementation; no Tool abstraction layer required
- no registration or discovery machinery

**Cons:**
- no mechanism to enforce per-tool or per-department permission policies
- no audit trail for external interactions
- a faulty agent can consume unbounded API quota or make destructive external calls
- tool capabilities cannot be governed without changing agent code

Rejected. Direct execution from agent code makes governance structurally impossible.

---

## Option B — Simple module dispatch without registry or lifecycle

Tools are implemented as plain Elixir modules. The agent calls them directly using a known module name. No registry, no dynamic discovery, no lifecycle state.

**Pros:**
- low implementation overhead
- straightforward to test in isolation

**Cons:**
- no mechanism for runtime enable/disable without a code change
- policy enforcement requires wrapping every tool call with custom logic, which is error-prone
- tool inventory is only visible by reading source code, not through a queryable registry
- third-party tools require changes to the core application

Rejected. The lack of a registry and lifecycle makes operational governance unworkable.

---

## Option C — MCP as the primary tool boundary

All tools are implemented as MCP servers. The Lemming communicates with them through the MCP protocol directly, without a LemmingsOS Tool abstraction.

**Pros:**
- aligns with emerging LLM ecosystem standards
- MCP defines a structured schema format for tool inputs and outputs

**Cons:**
- MCP provides no authorization, policy hierarchy, or cost accounting; those concerns would fall to the agent itself
- MCP server lifecycle and availability are outside LemmingsOS supervision
- auditability requires intercepting every MCP call with a governance layer that effectively recreates the Tool Runtime
- MCP-native tool definitions cannot carry LemmingsOS-specific metadata such as risk level or connection declarations

Rejected. MCP is a useful adapter protocol but cannot serve as the governance boundary.

---

## Option D — Native first-class Tool abstraction with registry, adapter model, and policy enforcement (chosen)

Tools are first-class runtime entities distributed as Hex packages, registered in a Tool Registry, and executed exclusively through the Tool Runtime. The Tool Runtime enforces policy, auditing, and resource limits regardless of the underlying adapter (native Elixir, MCP, HTTP).

**Pros:**
- all external effects pass through a single governable boundary
- tools can be enabled, disabled, and governed without agent code changes
- the extension model is validated by shipping first-party tools as separate packages
- audit events are produced by the runtime, not by individual tool authors
- MCP and other adapters work as execution backends under the same governance layer

**Cons:**
- tool authors must implement the `LemmingsOs.Tool` behaviour contract
- the adapter layer adds one extra hop per tool invocation
- dynamic discovery via Hex package scanning requires application restart to register new tools in v1

Chosen. The governance, auditability, and extensibility requirements cannot be satisfied without a managed runtime boundary.

---

# 4. Decision

LemmingsOS defines a **native Tool abstraction** representing controlled capabilities that agents may invoke.

Tools are **first-class runtime entities** registered in the system and governed by runtime policy.

Agents are **not allowed to execute arbitrary code** or perform external actions directly. All external effects must pass through tools.

Tools are:

- distributed as **Hex packages**
- discovered and registered dynamically by the runtime
- enabled or disabled through the Tool Registry
- governed by hierarchical runtime policy

The runtime includes a **Tool Registry** responsible for tracking installed, registered, and enabled tools.

## 4.1 v1 Implementation Constraints

The v1 implementation establishes the Tool Runtime boundary, durable tool history, and operator-visible execution lifecycle while deferring the broader registry, policy, package, MCP, and sandbox-governance layers.

The v1 implementation has the following constraints:

- the executable catalog is fixed in code to these four tools:
  - `fs.read_text_file`
  - `fs.write_text_file`
  - `web.search`
  - `web.fetch`
- the `Executor` invokes `LemmingsOs.Tools.Runtime.execute/4` directly after `ModelRuntime` returns a structured `tool_call`
- tool execution is performed inline in the executor loop for the current runtime session
- each attempted invocation creates a durable `lemming_instance_tool_executions` row
- each row is scoped to the `World` and `LemmingInstance`
- each row stores the tool name, args, status, summary, preview, normalized result or normalized error, timestamps, and duration
- supported tool execution statuses are `running`, `ok`, and `error`
- PubSub and telemetry expose lifecycle visibility but do not own tool execution
- the tools page reads the same fixed catalog used by the runtime

Deferred beyond v1:

- Hex package discovery
- dynamic tool registration
- hierarchical tool policy enforcement
- approvals
- MCP adapters
- Docker or external-process sandboxing
- generic shell or command execution
- git/worktree tools

The fixed catalog is not the general registry model. It is the v1 catalog contract used to establish that model-selected tool calls cross the controlled execution boundary, produce durable history, and continue the reasoning loop.

---

# 5. Tool Model

A tool represents a structured capability exposed to agents.

Each tool must define:

- tool identifier
- human-readable name
- description
- input schema
- output schema
- execution adapter
- risk level classification
- supported connection types, if external credentials or connection metadata are required

Tool schemas allow validation of inputs and outputs and reduce ambiguity when used by agents.

---

# 6. Tool Execution Boundary

Agents never execute external effects directly.

Lemmings invoke tools through a runtime Tool API rather than talking to tool implementations directly. The Tool Runtime is the only supported path for tool execution.

The execution flow is:

```
Lemming Instance
   ↓
Tool Request
   ↓
Catalog and scope check
   ↓
Tool Adapter Execution
   ↓
Result
   ↓
Durable Tool Execution Row + Runtime Signals
```

This boundary ensures that:

- unsupported tools are rejected before adapter execution
- instance and World scope are checked before execution
- tool usage leaves durable runtime history
- normalized results and errors are returned to the executor
- failures can be isolated

Hierarchical policy, connection access, resource limits, approvals, and broader audit enforcement are deferred beyond v1. They extend this boundary; they do not replace it.

---

# 7. Runtime Interaction Overview

The following diagram illustrates how a Lemming interacts with tools and external systems through the runtime boundary:

```
                ┌───────────────────────┐
                │     Lemming Instance  │
                └───────────┬───────────┘
                            │
                            │ Tool Call (ToolRuntime.call)
                            ▼
                ┌───────────┴───────────┐
                │      Tool Runtime     │
                │  (policy + auditing)  │
                └───────────┬───────────┘
                            │
                ┌───────────┴───────────┐
                │  Policy / Permission  │
                │  Checks               │
                └───────────┬───────────┘
                            │
                            ▼
                  ┌─────────┴─────────┐
                  │    Tool Adapter   │
                  └─────────┬─────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
   Native Tool         MCP Service         HTTP / Worker
 (Elixir module)        Adapter              Adapter
        │                   │                   │
        └───────────────────┴───────────────────┘
                            │
                            ▼
                   External System / API
```

This architecture ensures that all side effects pass through a controlled runtime boundary where policy, auditing, and resource limits are enforced.

---

# 8. Tool Invocation Model

The Tool Runtime boundary is mandatory. The invocation transport may be direct or asynchronous depending on the tool class, execution duration, and isolation adapter.

Bounded trusted first-party tools may execute through a direct runtime call. Long-running tools, external runners, approval waits, and callback-driven integrations require an asynchronous invocation contract.

In both cases, the Lemming interacts with the Tool Runtime rather than with the tool implementation directly.

The asynchronous invocation contract supports:

- long-running tool calls
- external callbacks
- retries and supervision
- waiting states in agent execution
- audit and event tracing

The runtime may optimize specific tool adapters, but adapter optimization must not bypass the Tool Runtime boundary.

## 8.1 v1 Direct Invocation Contract

The v1 implementation uses a direct runtime-call contract. This is the supported v1 execution path and does not weaken the architectural requirement that all external effects pass through the Tool Runtime.

v1 flow:

```text
Executor
  -> ModelRuntime returns action = :tool_call
  -> Executor creates durable tool execution row with status = "running"
  -> Executor calls Tools.Runtime.execute/4 directly
  -> Tool Runtime validates fixed catalog membership and scope
  -> Tool adapter executes
  -> Executor updates the same durable row to "ok" or "error"
  -> Executor appends a normalized tool-result context message
  -> Executor calls ModelRuntime again until final reply or bounded failure
```

PubSub is used only to notify LiveViews that a persisted tool row changed. It is not the tool execution transport.

Asynchronous callbacks for long-running tools, approval waits, external runners, and richer supervision semantics are deferred beyond v1 and must preserve the same Tool Runtime boundary.

---

# 9. Execution Adapters

Tools may execute through different adapters depending on their implementation.

Examples include:

- native Elixir modules
- MCP-based integrations
- HTTP services
- worker processes

The tool abstraction is independent from the execution adapter.

This allows LemmingsOS to integrate with external ecosystems while maintaining runtime control.

**Isolation semantics by adapter**: not all adapters carry the same isolation
guarantees. Native Elixir module adapters may execute in-process when the tool
is classified as trusted first-party; all other adapters execute in external OS
processes. The trust gradient and process isolation model are defined in
ADR-0016 section 6. Tool authors must not assume that in-process execution is
available; it is a platform-side classification decision, not an author-side
choice.

---

# 10. MCP Integration

Model Context Protocol (MCP) may be used as an adapter for tools.

However, MCP is treated as an **execution backend**, not as the core security boundary.

The LemmingsOS Tool model remains the authoritative control layer for:

- permissions
- policy enforcement
- audit logging
- cost and runtime limits

---

# 11. Tool Registry

The runtime maintains a **Tool Registry** that tracks:

- installed tools
- discovered tool modules
- enabled or disabled status
- tool source (official, community, local)
- trust level
- configuration state

Tool lifecycle states include:

- Installed
- Registered
- Enabled
- Policy-allowed

Registration means the runtime has discovered a valid tool module, validated its metadata contract, and made it visible to the control plane and policy system.

Tools may be installed but remain disabled until explicitly enabled by an administrator.

---

# 12. Tool Distribution

Tools are distributed as **Hex packages**.

A package may contain one or more tool modules implemented using the runtime behaviour:

```elixir
use LemmingsOs.Tool
```

When installed, the runtime discovers modules that implement the Tool behaviour and registers them automatically.

This allows tools to be added without modifying the core application or its dependency manifest.

---

# 13. Plugin Model

The system supports extensibility through tool packages.

Tools may originate from:

- official packages
- community packages
- locally developed packages

Technical users may also install tools dynamically using mechanisms such as `Mix.install` during development.

---

# 14. Official Tools

First-party tools are distributed as **separate packages**, not embedded directly in the runtime core.

For example:

- lemmings_tools_official

This validates the extension model from the beginning and keeps the runtime core minimal.

Product distributions may bundle official tool packages by default for ease of installation.

---

# 15. Installation Flows

### Non-technical users

Tools may be installed through a simple CLI or UI workflow.

Example CLI:

```
lemmings tool install lemmings_tool_http
```

The runtime:

1. installs the package
2. discovers tool modules
3. registers tools in the registry
4. allows administrators to enable them

### Technical users

Developers may install tools locally during development.

Example:

```elixir
Mix.install([
  {:my_tool, path: "../my_tool"}
])
```

The runtime discovery mechanism will detect and register the tools.

---

# 16. Connections and Secret Access

Some tools require access to external systems such as Jira, GitHub, search APIs, databases, or other providers.

Tools do not read secrets directly and agents never receive raw credentials.

Instead:

- a tool declares the connection types it supports
- runtime policy binds a tool to specific allowed connections
- secret material is resolved by runtime services at execution time
- credentials are injected into the tool executor, not exposed to the agent

A tool may support one or more connection types, but it may only use concrete connections explicitly allowed by runtime policy.

The detailed connection, credential, and secret storage model is defined in ADR-0009.

---

# 17. Policy Enforcement

Tool usage is governed by hierarchical configuration:

```
World → City → Department → Lemming Type → Instance
```

More specific configuration takes precedence, but lower levels cannot exceed upper-level restrictions.

Policies may control:

- which tools are allowed
- which concrete connections each tool may use
- concurrency limits
- timeouts
- rate limits
- budget usage

The full tool policy authorization model is defined in ADR-0012.

---

# 18. Consequences

## Positive

- All external effects pass through a single runtime boundary, making authorization, auditing, and resource enforcement consistent and complete.
- Tool enable/disable and policy changes are operational decisions; they require no agent code changes.
- The Hex package distribution model allows community tools to follow exactly the same path as official tools, validating the extension model continuously.
- MCP and other emerging tool protocols are supported as adapters without ceding governance to those protocols.

## Negative

- Tool authors must implement the `LemmingsOs.Tool` behaviour contract precisely; malformed metadata schemas fail validation at registration time, not at invocation time.
- The adapter layer adds one serialization hop per tool invocation, which is measurable on high-frequency low-latency tool calls.
- Dynamic discovery via Hex package scanning requires a controlled application restart to register newly installed tools in v1; hot-loading is not supported.

## Mitigations

- The behaviour contract validation error identifies which field failed and why, giving tool authors actionable feedback during development rather than cryptic runtime failures.
- High-frequency tool calls that are performance-sensitive can use native Elixir adapter implementations, which avoid external process overhead entirely.
- The restart requirement for new tool registration is mitigated by the CLI install workflow, which can initiate a controlled restart as its final step.

---

# 19. Non-Goals

This ADR defines the conceptual Tool model and execution boundary. The following concerns are covered by dedicated ADRs:

- tool risk classification (ADR-0013)
- tool approval workflow (ADR-0014)
- tool execution isolation and sandboxing (ADR-0016)
- tool policy authorization model (ADR-0012)
- secret and connection injection details (ADR-0009)

---

# 20. Future Extensions

- Hot-loading of newly installed tools without full application restart.
- Signed tool packages with a trust registry for supply chain integrity.
- Tool marketplace/catalog with community rating and review.
- Per-tool usage analytics and quota dashboards.

---

# 21. Rationale

The Tool abstraction solves a fundamental tension in agent runtimes: agents must be capable of interacting with the world, but that capability must be governable, auditable, and bounded. Solving this by making Tools first-class runtime entities — rather than library calls or LLM-native primitives — means governance is structural. A tool that is not registered cannot be invoked, regardless of what the model decides. A tool that is not enabled for a Department cannot be invoked by a Lemming in that Department, regardless of what policy inheritance would otherwise allow.

The decision to ship first-party tools as separate Hex packages from day one is a discipline commitment: it prevents the tool system from accumulating a privileged class of "always available" capabilities that bypass the registry and governance mechanisms that community tools must use.
