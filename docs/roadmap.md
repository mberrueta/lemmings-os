# LemmingsOS — Roadmap

## Phase 0 — Foundation (current)

Goal: establish the engineering operating model and structural scaffolding before writing domain code.

- [x] Phoenix 1.8 application scaffold
- [x] Repository structure: `docs/`, `llms/`, `docs/adr/`
- [x] Architecture Decision Records (ADR 0001–0003)
- [x] LLM governance: constitution, project context, agent catalog
- [x] Coding style guides and task execution conventions
- [ ] CI pipeline (GitHub Actions: format, test, credo)
- [ ] Docker / docker-compose setup
- [ ] ASDF version pinning (`.tool-versions`)

## Phase 1 — Core Domain Model (MVP: minimal working hierarchy)

Goal: implement the World / City / Department / Lemming data model and context APIs.

- [ ] Database schema: `worlds`, `cities`, `departments`, `lemmings` tables
- [ ] Context APIs with explicit World scoping
- [ ] ExMachina factories for all entities
- [ ] Unit and integration tests for context layer
- [ ] ADRs for any new schema decisions

## Phase 2 — Runtime: Lemming Lifecycle

Goal: Lemmings can be spawned, supervised, and terminated via OTP.

- [ ] `LemmingsOs.Lemming.Behaviour` — pluggable agent behaviour
- [ ] `LemmingsOs.Lemming.Executor` — supervised GenServer
- [ ] `LemmingsOs.Department.Manager` — dynamic supervisor for Lemming pool
- [ ] Lemming status tracking (running, stopped, crashed)
- [ ] Crash/restart telemetry

## Phase 2.5 — Messaging: The Nervous System

Goal: Lemmings can communicate with each other and report results asynchronously.
Without this layer, Lemmings are isolated processes with no coordination — useful but limited.

- [ ] `LemmingsOs.Events` — City-scoped pub/sub event bus (backed by `Phoenix.PubSub`)
- [ ] Topic naming convention enforced: `[world_id, city_id, department_id, event_type]`
- [ ] `LemmingsOs.Lemming.Executor` message API: `dispatch/2`, `report_result/2`, `subscribe/2`
- [ ] Inter-Lemming messaging within a Department (fan-out, point-to-point)
- [ ] Inter-Department messaging within a City (routed through Department Manager)
- [ ] Event bus scoping: events cannot cross World boundaries without explicit Gateway
- [ ] Telemetry events for all message routing paths
- [ ] Tests for back-pressure, dead subscribers, and ordering guarantees

## Phase 3 — Runtime: City and World

Goal: Cities join Worlds; World Registry is operational.

- [ ] `LemmingsOs.City.Supervisor` — OTP supervision tree for a City
- [ ] `LemmingsOs.World.Registry` — tracks Cities and enforces World scoping
- [ ] City node membership (join, leave, health reporting)
- [ ] World isolation enforcement at context and event bus levels

## Phase 4 — Observability Dashboard

Goal: LiveView dashboard gives real-time visibility into the hierarchy.

- [ ] World / City / Department / Lemming list views
- [ ] Lemming lifecycle events and status timeline
- [ ] Real-time telemetry integration (Phoenix LiveDashboard)
- [ ] Structured logging with hierarchy metadata

## Phase 5 — Agent Extensibility

Goal: external agent logic can be plugged in cleanly.

- [ ] `LemmingsOs.Lemming.Behaviour` documented with examples
- [ ] Built-in sample agents (no-op, echo, scheduled task)
- [ ] Agent capability declarations and Department-level enforcement
- [ ] Live configuration updates for Lemmings

## Phase 6 — Multi-City and Clustering

Goal: multiple Cities form a distributed World cluster.

- [ ] Multi-node City membership protocol
- [ ] Cross-City event routing (within World boundary)
- [ ] Cluster health and partition-tolerance documentation
- [ ] `LemmingsOs.Gateway` for cross-World communication (scoped ADR required)

## Non-goals (out of scope for all phases)

* Providing or hosting AI models
* Workflow DAG scheduling
* Hosted SaaS product
