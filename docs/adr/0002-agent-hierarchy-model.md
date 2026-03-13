# ADR 0002: Agent Hierarchy Model — World / City / Department / Lemming

- Status: Accepted
- Date: 2026-03-13
- Decision Makers: Maintainer(s)

## Context

LemmingsOS needs a clear, stable structural model for organizing and isolating
autonomous AI agents. The model must:

* support multiple levels of isolation (between deployments, between nodes, between agent groups)
* map naturally to Elixir/OTP supervision concepts
* be extensible without requiring schema redesign as the system grows
* communicate intent clearly to both operators and contributors

The naming/identity of each level is part of the product identity (pixel-inspired,
playful but structurally rigorous).

## Decision Drivers

1. Clear, non-overlapping isolation semantics at each level
2. Natural alignment with OTP process/supervision concepts
3. Extensible without requiring hierarchy changes for common use cases
4. Names that are memorable, distinctive, and map to real deployment concepts

## Considered Options

### Option A — World / City / Department / Lemming (Chosen)

Four levels: global boundary → node → logical group → individual agent.

* **World**: the global isolation boundary — no cross-World communication without an
  explicit gateway. Maps to a deployment or tenant.
* **City**: a running Elixir/OTP node. Cities join and leave Worlds dynamically.
  Maps directly to a `Node` in Elixir distributed computing.
* **Department**: a logical group of Lemmings within a City. Defines shared purpose,
  capabilities, and constraints. Maps to a named supervisor subtree.
* **Lemming**: a single supervised agent process. Has a stable identity, lifecycle,
  and mailbox. Maps to a `GenServer` or similar OTP process.

### Option B — Cluster / Node / Group / Agent

Generic naming aligned with distributed systems terminology.

* Familiar to DevOps engineers but lacks distinctive identity.
* "Agent" as the leaf-level conflicts with the broader "agent" concept in AI discourse.

### Option C — Environment / Server / Team / Bot

More casual naming.

* Less precise — "Environment" conflates deployment environment with isolation boundary.
* "Bot" carries connotations inconsistent with the serious engineering positioning.

### Option D — Two-level model (Node / Agent)

Simpler hierarchy with only two levels.

* Insufficient isolation for multi-tenant or multi-node deployments.
* Does not naturally support logical grouping within a node without ad-hoc conventions.

## Decision

We adopt the **World / City / Department / Lemming** four-level hierarchy.

## Rationale

The four-level model provides the right amount of structure:

* **World** provides hard isolation at the deployment/tenant level, which is necessary
  for staging vs. production separation and multi-tenant use cases.
* **City** has a direct 1:1 mapping to an Elixir node, making it concrete and
  operationally intuitive.
* **Department** allows logical grouping within a node without requiring separate nodes,
  which is the right granularity for agent purpose-partitioning.
* **Lemming** is the leaf-level process, directly mapping to an OTP process with
  a supervision strategy.

The pixel-inspired naming is memorable and builds product identity while remaining
structurally rigorous. The hierarchy does not preclude future extension (e.g., adding
a sub-Department grouping) without redesigning the top-level model.

## Consequences

### Positive

* Clear, non-overlapping isolation semantics at each level
* Direct alignment with Elixir/OTP: World → cluster config, City → Node,
  Department → supervisor subtree, Lemming → supervised process
* Memorable, distinctive identity
* Extensible at each level without hierarchy redesign

### Negative / Trade-offs

* Non-standard naming may require explanation for engineers unfamiliar with the project
* Four levels may be more than simple deployments need (single-City, single-Department
  use cases still work but carry some overhead of the model)

### Mitigations / Follow-ups

* Document the hierarchy with clear diagrams in `docs/architecture.md`
* Ensure `README.md` explains the hierarchy before anything else
* Provide a "quick start" that defaults to a sensible single-City, single-Department
  configuration to lower the onboarding barrier

## Implementation Notes

* OTP module naming: `LemmingsOs.World`, `LemmingsOs.City`, `LemmingsOs.Department`,
  `LemmingsOs.Lemming`
* Database tables: `worlds`, `cities`, `departments`, `lemmings`
* The hierarchy levels are schema-backed; runtime process names are derived from their DB identities
* Cross-World communication will require an explicit `LemmingsOs.Gateway` boundary (separate ADR)
