# ADR 0003: World as Hard Isolation Boundary

- Status: Accepted
- Date: 2026-03-13
- Decision Makers: Maintainer(s)

## Context

The World is the outermost level of the LemmingsOS hierarchy (see ADR 0002). We need
to define precisely what "isolation" means at the World level and what constraints apply
to cross-World communication.

This decision affects:

* multi-tenant deployments
* staging vs. production separation
* air-gapped agent environments
* the design of any future inter-World bridge or gateway

## Decision Drivers

1. Strong isolation guarantees by default for security and correctness
2. Explicit, auditable cross-boundary communication
3. Compatibility with single-World deployments (the common case)
4. Clear failure semantics when boundary rules are violated

## Considered Options

### Option A — Hard Isolation: No Cross-World Communication Without Explicit Gateway (Chosen)

Worlds are fully isolated by default. No agent in World A can directly send a message
to, observe, or depend on an agent in World B. Cross-World communication requires an
explicit `Gateway` abstraction that is separately configured, audited, and monitored.

### Option B — Soft Isolation: Cross-World Communication Allowed With Permission Flags

Worlds share a process registry and can communicate if a permission flag is set.

* Simpler to implement initially.
* Creates implicit coupling that is hard to audit and reverse.
* Violates the principle of explicit over implicit.

### Option C — Single-World Model

No World concept; isolation is entirely the operator's responsibility at the
infrastructure level (separate deployments, separate databases).

* Loses the ability to run multiple isolated environments on a single infrastructure
  footprint.
* Does not scale to multi-tenant use cases without duplicating entire deployments.

## Decision

**Worlds are hard isolation boundaries.** No cross-World communication is permitted
without routing through a named, explicitly configured Gateway.

Specifically:

* A World has its own:
  * process namespace (no cross-World process discovery)
  * database scope (no cross-World schema access)
  * event bus scope (no cross-World event subscription)
  * telemetry scope (metrics are tagged by World and do not aggregate cross-World by default)
* The World identity is propagated as metadata on all logs, telemetry events, and DB rows.
* A future `LemmingsOs.Gateway` module will mediate cross-World communication with
  explicit configuration, rate limits, and audit logging.

## Rationale

Hard isolation by default:

* Makes security reasoning simple: the boundary is always enforced unless explicitly bridged.
* Enables true multi-tenancy without accidental data leakage between tenants.
* Aligns with the "explicit over implicit" design principle.
* Gives operators clear operational handles: a World can be suspended, terminated, or
  migrated independently.

The cost — slightly more configuration for single-World use cases — is acceptable.
A well-designed default configuration will make single-World deployments transparent.

## Consequences

### Positive

* Strong multi-tenant isolation guarantee
* Clear security boundary that is easy to audit
* Enables independent lifecycle management per World (suspend, migrate, terminate)
* All cross-boundary communication is explicit, logged, and auditable

### Negative / Trade-offs

* Adds indirection for use cases that genuinely need cross-World coordination
* World identity must be propagated explicitly through all data models and telemetry

### Mitigations / Follow-ups

* Design the default single-World startup to require zero extra configuration
* Tag all database rows with `world_id`; enforce at the context API level, not just
  at the query level
* Design the `Gateway` abstraction before exposing any multi-World feature in the UI
* Document isolation semantics in `docs/architecture.md`

## Implementation Notes

* All top-level database tables that are World-scoped must include a `world_id` foreign key.
* Context API functions must require an explicit `world_id` (or a `%World{}` struct) as scope —
  no implicit global queries.
* The World Registry (`LemmingsOs.World.Registry`) is the authoritative source of
  active Worlds on a node.
* Telemetry metadata: all `telemetry.execute/3` calls must include `%{world_id: id}` in metadata.
