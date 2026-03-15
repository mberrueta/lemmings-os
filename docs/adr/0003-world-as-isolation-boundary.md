# ADR 0003: World as Hard Isolation Boundary

- Status: Accepted
- Date: 2026-03-13
- Decision Makers: Maintainer(s)

## Context

The World is the outermost level of the LemmingsOS hierarchy (see ADR 0002). We need
to define precisely what "isolation" means at the World level.

This decision affects:

* multi-tenant deployments
* staging vs. production separation
* air-gapped agent environments
* the security model for all agent execution within a deployment

## Decision Drivers

1. Security over convenience — the isolation boundary must be structural, not configurable away
2. No accidental data leakage between tenants or environments, ever
3. Compatibility with single-World deployments (the common case)
4. Clear failure semantics when boundary rules are violated

## Considered Options

### Option A — Hard Isolation: No Cross-World Communication (Chosen)

Worlds are fully and permanently isolated. No agent in World A can send a message to,
observe, or depend on an agent in World B. There is no mechanism — configured or
otherwise — for cross-World communication within the platform.

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

**Worlds are hard, permanent isolation boundaries.** There is no cross-World
communication. No agent, tool, or runtime service may address or observe anything
outside its own World. This is not a default that can be configured away — it is a
structural property of the platform.

The primary driver is security: a misconfigured or compromised agent in one World must
not be able to affect or observe any other World. This guarantee must hold without
depending on operator discipline or runtime policy configuration.

A typical deployment runs two or more Worlds on shared infrastructure — for example,
`world_production` and `world_staging`, or `world_argentina` and `world_brazil` for a
multi-region company. These Worlds share the same hardware but are completely opaque to
each other at the platform level.

Specifically, each World has its own:

* process namespace (no cross-World process discovery)
* database scope (no cross-World schema access)
* event bus scope (no cross-World event subscription)
* telemetry scope (metrics are tagged by World and do not aggregate cross-World by default)
* Secret Bank (credentials are never shared across Worlds)

The World identity is propagated as mandatory metadata on all logs, telemetry events, and DB rows.

## Rationale

Hard, permanent isolation:

* Makes security reasoning simple: there is no boundary to misconfigure, no flag to set
  incorrectly, no Gateway to forget to lock down. Isolation is structural.
* Enables true multi-tenancy without any possibility of accidental data leakage between
  tenants — a compromised agent in one World cannot reach another World by any path.
* Gives operators clear operational handles: a World can be suspended, terminated, or
  migrated without affecting other Worlds on the same infrastructure.
* Aligns with the principle of security over convenience: teams that need coordination
  across environments do so through external integrations, not through the platform runtime.

The cost — operators who want to share data between Worlds must do so outside the
platform — is acceptable and intentional. A platform that can be configured to leak
across tenant boundaries provides weaker guarantees than one that structurally cannot.

## Consequences

### Positive

* Strong multi-tenant isolation that does not depend on operator configuration to hold
* Clear security boundary: no agent action can leak outside its World by any path
* Enables independent lifecycle management per World (suspend, migrate, terminate)
* Security reasoning is simple — there is no cross-World communication model to audit

### Negative / Trade-offs

* Teams that need coordination across environments (e.g., syncing data between production and staging) must do so through external integrations outside the platform
* World identity must be propagated explicitly through all data models and telemetry

### Mitigations / Follow-ups

* Design the default single-World startup to require zero extra configuration
* Tag all database rows with `world_id`; enforce at the context API level, not just
  at the query level
* Document isolation semantics in `docs/architecture.md`

## Implementation Notes

* All top-level database tables that are World-scoped must include a `world_id` foreign key.
* Context API functions must require an explicit `world_id` (or a `%World{}` struct) as scope —
  no implicit global queries.
* The World Registry (`LemmingsOs.World.Registry`) is the authoritative source of
  active Worlds on a node.
* Telemetry metadata: all `telemetry.execute/3` calls must include `%{world_id: id}` in metadata.
* The runtime execution unit that operates within a World boundary is the Lemming instance (ADR-0004). Configuration inheritance, peer communication policy, and routing scope all start at the World level and flow down through City → Department → Lemming type → instance.
