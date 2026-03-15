# ADR-0016 — Tool Execution Isolation Model

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

In LemmingsOS, agents ("Lemmings") never interact with the external world directly. All external interactions occur through **Tools**, which are executed by the **Tool Runtime**.

Tools may perform operations such as:

- accessing external networks
- calling third‑party APIs
- executing local processes
- reading or writing files
- running compute workloads
- interacting with external services

Because tools are distributed as third‑party packages and may execute arbitrary logic, they represent a **major security boundary** in the architecture.

Without proper isolation, a malicious or buggy tool could compromise the runtime environment. Potential risks include:

### Filesystem Access

A tool with unrestricted filesystem access could:

- read sensitive host files
- access runtime configuration
- read secret storage locations
- modify system files

### Unrestricted Network Access

Tools with unrestricted network access could:

- exfiltrate sensitive data
- communicate with unauthorized external services
- scan internal networks
- access cloud metadata endpoints

### Arbitrary Process Execution

Tools capable of launching unrestricted processes could:

- execute shell commands
- run malicious binaries
- escape runtime supervision

### Resource Exhaustion

A faulty tool could consume unlimited resources such as:

- CPU
- memory
- disk space
- execution time

This could degrade or crash the runtime host.

### Data Exfiltration

Tools may attempt to extract sensitive information through:

- network requests
- logs
- external integrations

### Privilege Escalation

A tool running without isolation could attempt to:

- escalate system privileges
- access runtime internals
- interfere with the BEAM VM

Because tools may originate from **third‑party packages**, the runtime must assume that tool code cannot be fully trusted.

Therefore the **Tool Runtime must enforce strong isolation guarantees** so that tools cannot compromise the host environment.

At the same time, the system must remain simple enough to operate in **self‑hosted deployments**, such as:

- single VPS installations
- Docker environments
- small on‑premise setups

The isolation model must therefore balance **security and operational simplicity**.

---

# 2. Decision Drivers

1. **Third-party tool packages cannot be fully trusted** — Tools originate from
   external packages. The runtime must assume that tool code may be malicious or
   buggy. Security must not depend on tool authors being trustworthy.

2. **BEAM VM must be protected** — A tool crash or exploit must not affect the
   runtime host's BEAM VM or other running Lemmings. Process isolation between the
   VM and tool execution is a hard requirement.

3. **Self-hosted constraint** — The isolation mechanism must work on a single VPS
   without requiring container orchestration, a Kubernetes cluster, or cloud-specific
   infrastructure. Operational complexity must remain proportional to deployment scale.

4. **Defense in depth** — No single isolation mechanism is sufficient. The model must
   compose multiple lightweight layers (process isolation, filesystem sandbox, network
   restrictions, resource limits) rather than relying on any one mechanism.

5. **Operational manageability** — Administrators must be able to configure isolation
   policies (allowed commands, network allowlists, resource limits) without deep
   systems expertise or infrastructure changes.

---

# 3. Considered Options

## Option A — In-process execution inside the BEAM VM

Tools run as Elixir processes within the BEAM VM, managed by the supervisor tree.

**Pros:**

- simplest implementation; no external process management
- tools benefit from BEAM process isolation and supervision
- straightforward error handling via OTP patterns

**Cons:**

- a tool that crashes with a segfault or similar native error can destabilize the BEAM
  VM and affect all running Lemmings
- tools running inside the VM have access to VM internals through Erlang's reflection
  and introspection capabilities
- filesystem and network access cannot be sandboxed at the process level inside the VM
- a tool consuming unlimited memory inside the VM causes the entire node to fail

Rejected. In-process execution cannot provide the process isolation and filesystem/
network sandboxing required for untrusted third-party tool code.

---

## Option B — Full container isolation per invocation

Each tool execution creates an ephemeral container. The container is destroyed after
the tool completes.

**Pros:**

- strong isolation: container namespaces provide process, filesystem, and network
  isolation by default
- widely understood operational model

**Cons:**

- container lifecycle overhead (image pull, container start, teardown) adds latency to
  every tool invocation; unsuitable for low-latency tools
- requires a container runtime (Docker, containerd) as an operational dependency on
  every deployment host, significantly increasing the self-hosted operational burden
- image management for tool containers adds complexity to the tool packaging model
- impractical for single VPS deployments without Docker infrastructure configured

Rejected. The operational dependency on a container runtime is disproportionate to the
target self-hosted deployment scale. The latency overhead per invocation is also
unacceptable for frequently-invoked low-risk tools.

---

## Option C — Layered OS-level isolation (chosen)

Tools execute in separate OS processes with filesystem sandboxing, network restrictions,
and resource limits applied by the Tool Runtime. Each layer is independently
configurable and can be strengthened as requirements evolve.

**Pros:**

- process isolation between tools and the BEAM VM without requiring a container runtime
- filesystem and network restrictions are enforceable at the OS process level
- resource limits (CPU, memory, execution time) prevent runaway tool processes
- composable: each isolation layer can be configured independently; adding stronger
  isolation in one dimension does not require redesigning others
- works on a bare VPS without any container infrastructure

**Cons:**

- OS-level filesystem and network sandboxing is less hermetic than container namespaces
- implementation must handle platform differences (Linux vs macOS for development)
- command allowlist management requires ongoing maintenance as tool inventories grow

Chosen. The model provides sufficient isolation for the self-hosted deployment target
without requiring container infrastructure. The defense-in-depth composition of layers
addresses the limitations of any single mechanism.

---

# 4. Decision

LemmingsOS introduces a **Tool Execution Isolation Model** enforced by the Tool Runtime.

All tool executions occur inside **controlled execution environments** managed by the runtime.

Tools are never executed directly inside the BEAM VM or with unrestricted host access.

Instead, the runtime creates a sandboxed execution context that applies several layers of isolation.

Primary isolation mechanisms include:

- process isolation
- filesystem sandboxing
- network sandboxing
- resource limits

These protections ensure that tools cannot access host resources beyond what is explicitly permitted.

---

# 5. Isolation Layers

The Tool Runtime enforces multiple isolation layers. Each layer restricts a different class of potential attacks.

The model intentionally composes several lightweight protections rather than relying on a single heavy isolation mechanism.

```
Tool Runtime
      │
      ▼
Sandbox Environment
      │
      ├─ Process Isolation
      ├─ Filesystem Sandbox
      ├─ Network Sandbox
      └─ Resource Limits
```

Each layer is described below.

---

# 6. Process Isolation and Trust Gradient

The isolation requirement for a tool depends on its **trust classification**.
LemmingsOS defines two tiers.

## 6.1 Trusted first-party tools (in-process)

Tools shipped as part of the LemmingsOS platform and reviewed by maintainers may
execute as **native Elixir modules inside the BEAM VM**. These tools implement
the `LemmingsOs.Tool` behaviour contract directly and run in a supervised Elixir
process within the Tool Runtime.

This tier is appropriate for:

- low-risk, high-frequency operations where external process overhead is
  unacceptable (e.g., text parsing, schema validation, local arithmetic)
- tools that have no external side-effects or network access
- tools whose complete source is audited and co-versioned with the platform

In-process tools are still subject to all policy, authorization, audit, and cost
governance enforcement by the Tool Runtime. In-process execution does **not** bypass
governance; it only relaxes the process isolation layer.

## 6.2 Third-party and community tools (external process)

All tools originating from external Hex packages — including community tools and
operator-supplied integrations — must execute in **separate operating system
processes** managed by the Tool Runtime.

This prevents untrusted tool code from:

- crashing the BEAM VM
- corrupting runtime memory
- accessing internal runtime state or secrets

The runtime may implement external-process isolation using one of several
mechanisms:

- supervised OS processes via `Port` or `MuonTrap`
- containerized execution (future extension)
- external tool runner processes

Example execution path for external-process tools:

```
BEAM Runtime
   │
   ▼
Tool Runtime (governance boundary)
   │
   ▼
External Tool Runner Process
   │
   ▼
Tool Adapter
```

If an external tool crashes or misbehaves, the BEAM runtime remains protected.

## 6.3 Classification is explicit

The trust tier of a tool is a field in its Tool Registry entry, not an implicit
property of its package origin. The Tool Runtime reads this field at execution
time to determine which isolation path to use. Misclassifying a third-party tool
as first-party is a configuration error that will be flagged during tool
installation review.

---

# 7. Filesystem Sandbox

Tools must not have unrestricted access to the host filesystem.

The Tool Runtime provides a **restricted working directory** for each tool execution.

Allowed access typically includes:

- temporary execution workspace
- explicitly mounted directories
- tool-specific working files

Access is **denied by default** for:

- host filesystem root
- runtime configuration directories
- secret storage locations
- system directories

Conceptual sandbox structure:

```
/sandbox
   ├─ workspace/
   ├─ input/
   └─ output/
```

Tools may read and write only within the sandbox unless explicit mounts are configured.

This prevents tools from reading sensitive host files or modifying system configuration.

---

# 8. Network Sandbox

Tools must not be able to open unrestricted network connections.

The runtime may enforce network restrictions such as:

- outbound allowlists
- DNS filtering
- blocked internal networks
- blocked metadata endpoints

Example policy:

```
allowed_hosts:
  - api.openai.com
  - api.github.com
```

Connections to other destinations are denied by default.

The runtime should also block access to common internal network targets such as:

- localhost services
- container metadata endpoints
- cloud instance metadata APIs

This significantly reduces the risk of data exfiltration and lateral movement.

---

# 9. Resource Limits

Tools must not be able to consume unlimited system resources.

The Tool Runtime may enforce resource limits including:

- CPU usage
- memory consumption
- execution duration
- concurrent tool executions

Example runtime limits:

```
max_execution_time: 30s
max_memory: 512MB
max_cpu: 1 core
```

If a tool exceeds its limits, the runtime terminates execution and reports a failure.

This protects the runtime host from resource exhaustion attacks or runaway workloads.

---

# 10. Controlled Command Execution

Some tools may need to execute local binaries available on the host system. Examples include utilities such as `git`, `ffmpeg`, `jq`, or `rg`.

To prevent arbitrary shell access, LemmingsOS introduces a **controlled command execution model**.

Tools must not execute unrestricted shell commands (for example `bash -c`). Instead, process execution occurs through a runtime‑controlled command adapter.

The adapter enforces an **allowlisted command catalog**.

Example configuration:

```
allowed_commands:
  git
  gh
  rg
  jq
```

Each command entry defines runtime enforcement rules.

Example conceptual definition:

```
commands:
  git:
    binary: /usr/bin/git
    risk: medium
    allowed_args:
      - clone
      - status
      - diff
      - log
      - show
    allowed_workdirs:
      - /sandbox/workspace

  gh:
    binary: /usr/bin/gh
    risk: high
    allowed_args:
      - issue
      - pr
      - repo
    allow_network: true
    allowed_hosts:
      - api.github.com
```

The runtime validates command invocations before execution.

Invocation format should use structured arguments rather than raw shell strings.

Example invocation:

```
{
  "command": "gh",
  "args": ["issue", "list", "--limit", "20"]
}
```

This allows the runtime to validate:

- the binary being executed
- permitted subcommands
- argument structure
- working directory constraints
- network policy

Tools may optionally include **LLM usage guidance** to reduce command guesswork.

Example guidance:

```
llm_usage:
  summary: GitHub CLI for repository operations
  examples:
    - gh issue list --limit 20
    - gh pr view <number>
```

Runtime enforcement always takes precedence over LLM guidance.

Unrestricted shell tools are considered **critical‑risk capabilities** and should be disabled by default or require explicit approval.

---

## Command Adapter Runtime

The command execution path inside the Tool Runtime follows a structured validation and enforcement pipeline.

```
Tool Runtime
     │
     ▼
Command Adapter
     │
     ├─ command allowlist check
     ├─ argument validation
     ├─ working directory policy
     ├─ filesystem sandbox
     ├─ network policy enforcement
     └─ resource limits applied
     │
     ▼
OS Process Execution
```

This adapter acts as a security boundary between tool logic and the host operating system.

The adapter is responsible for rejecting any invocation that violates the command catalog rules before the process is spawned.

---

# 11. Model Runtime to Tool Runtime Integration

Lemmings do not construct tool call requests directly. The model produces a structured
output (ADR-0019) that the **Model Runtime** validates and returns to the Lemming as a
`ModelResponse` with `stop_reason: :tool_use`. The Lemming extracts the tool decision
from the response and dispatches it to the Tool Runtime.

Conceptual decision handoff:

```
Model Runtime
   ↓
ModelResponse{stop_reason: :tool_use, content: [%ToolUseBlock{...}]}
   ↓
Lemming (extracts tool name + args)
   ↓
Tool Runtime
   ↓
Authorization → Risk → Approval → Budget → Sandbox → Execute
```

The Lemming is the boundary between the reasoning layer (Model Runtime) and the effect
layer (Tool Runtime). Neither runtime calls the other directly. This keeps the two
subsystems independently testable and independently governable.

If the model produces an invalid or unparseable tool call, the Model Runtime's
structured output validation (ADR-0019, section 9) handles retry before the response
reaches the Lemming, preventing malformed inputs from entering the Tool Runtime pipeline.

---

# 12. Execution Flow

The sandbox model integrates directly into the Tool Runtime pipeline.

Conceptual execution flow:

```
Lemming
   ↓
Tool Runtime
   ↓
Policy authorization
   ↓
Risk classification
   ↓
Approval workflow
   ↓
Cost governance
   ↓
Sandbox environment created
   ↓
Tool executed inside isolation
   ↓
Result returned
```

Expanded view:

```
Lemming Instance
       │
       ▼
Tool Runtime
       │
       ├─ Authorization Check
       ├─ Risk Governance
       ├─ Approval Workflow
       ├─ Budget Evaluation
       │
       ▼
Sandbox Creation
       │
       ├─ Process isolation
       ├─ Filesystem sandbox
       ├─ Network sandbox
       └─ Resource limits
       │
       ▼
Tool Execution
       │
       ▼
Result Returned to Lemming
```

Sandbox creation occurs **immediately before tool execution**.

This ensures that all runtime governance decisions are evaluated before the tool receives any execution privileges.

---

# 13. Security Guarantees

The isolation model provides several critical protections.

Tools cannot:

- access arbitrary host filesystem paths
- read runtime configuration files
- retrieve secrets directly
- open unrestricted network connections
- consume unlimited CPU or memory
- execute inside the BEAM runtime

As a result:

- the runtime host remains protected
- secret exposure risk is reduced
- resource exhaustion attacks are limited

The BEAM runtime remains isolated from tool execution failures.

---

# 14. Consequences

## Positive

- The BEAM VM is protected from tool crashes, memory corruption, and native-level
  failures. A tool process that segfaults or is killed by resource limits does not
  affect other Lemmings or the supervisor tree.
- Secret values are never accessible to tool processes. The sandbox boundary ensures
  that even a compromised tool cannot read credentials from the host filesystem or
  environment.
- Defense in depth means that bypassing one isolation layer (e.g., the filesystem
  sandbox) does not automatically compromise other layers (e.g., network restrictions
  or resource limits).

## Negative / Trade-offs

- OS-level sandboxing is less hermetic than container namespaces. A sufficiently
  sophisticated exploit against the OS process isolation primitives could escape the
  sandbox. Container-based isolation would provide stronger guarantees.
- The command allowlist requires ongoing maintenance. As tool inventories grow,
  administrators must keep the catalog up-to-date; a tool that needs a binary not in
  the catalog will fail silently at the policy check.
- Network allowlists must be configured per deployment. Tools that call external APIs
  require their endpoints to be explicitly permitted, which creates operational overhead
  for every new integration.

## Mitigations

- Container-based isolation is explicitly listed as a future extension. The layered
  isolation model is designed so that containers can be added as an optional stronger
  layer without changing the Tool Runtime contract.
- The command adapter rejects unlisted commands with a clear policy error, not a
  cryptic failure. Operators can diagnose allowlist gaps from audit events.
- The control plane should provide a tool configuration review surface so administrators
  can verify sandbox policies before enabling new tools for agent use.

---

# 15. Non‑Goals

Version 1 intentionally avoids complex infrastructure requirements.

The following capabilities are **out of scope for v1**:

- full container orchestration
- kernel-level virtualization
- complex policy engines
- remote sandbox clusters

The initial implementation focuses on **practical local isolation** suitable for self‑hosted deployments.

---

# 16. Future Extensions

Possible future improvements include:

- container-based sandboxing
- microVM execution environments (e.g., Firecracker)
- remote tool execution clusters
- signed tool packages
- capability-based sandbox policies

These extensions could further strengthen isolation without changing the core Tool Runtime architecture.

---

# 17. Rationale

Tools are untrusted third-party code that executes in response to LLM-driven agent
decisions. This combination — external code, AI-directed invocation — demands a defense
posture that does not assume good faith from tool authors.

The layered isolation model follows from this assumption: no single protection is
sufficient, but composing process isolation, filesystem restrictions, network allowlists,
and resource limits creates a meaningful security boundary without requiring container
infrastructure on every deployment host.

The self-hosted constraint is a real design driver. Requiring Docker or Kubernetes to run
LemmingsOS on a VPS would exclude a significant part of the target audience. The OS-level
isolation model provides adequate protection at the right operational cost for v1.
