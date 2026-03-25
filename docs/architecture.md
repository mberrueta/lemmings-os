# LemmingsOS - Architecture Overview

## Purpose

LemmingsOS is a self-hosted platform/runtime for hierarchical autonomous agents. It provides structured lifecycle management, supervision, isolation, and observability for autonomous agents organized in a four-level hierarchy.

Five pillars guide all architecture decisions:

| Pillar | Constraint |
|---|---|
| Micro-agent architecture | Lemmings do one thing; no super-agents |
| Runtime, not prompts | Lifecycle and supervision, not workflow DAGs |
| Safety by design | All external actions go through typed Tools - no arbitrary code execution |
| True autonomy | Lemmings run for hours/days, retry, and resume after crashes |
| Local-first AI | Ollama and self-hosted models are first-class; cloud APIs are optional |

---

## Hierarchy

```text
                        ┌─────────────────────────────────────┐
                        │               World                  │
                        │    (hard isolation boundary)         │
                        └──────────────┬──────────────────────┘
                                       │
                   ┌───────────────────┴───────────────────┐
                   │                                       │
          ┌────────┴────────┐                   ┌──────────┴──────────┐
          │     City A      │                   │      City B         │
          │  (OTP node)     │                   │   (OTP node)        │
          └────────┬────────┘                   └──────────┬──────────┘
                   │                                       │
         ┌─────────┴──────────┐                ┌──────────┴──────────┐
         │                    │                │                     │
  ┌──────┴──────┐    ┌────────┴──────┐  ┌─────┴───────┐    ┌────────┴──────┐
  │  Dept: QA   │    │  Dept: Infra  │  │  Dept: Docs │    │  Dept: Ops    │
  └──────┬──────┘    └────────┬──────┘  └──────┬──────┘    └───────┬───────┘
         │                    │                │                    │
    ┌────┴────┐          ┌────┴────┐      ┌────┴────┐         ┌────┴────┐
    │Lemming 1│          │Lemming 3│      │Lemming 5│         │Lemming 7│
    │Lemming 2│          │Lemming 4│      │Lemming 6│         │Lemming 8│
    └─────────┘          └─────────┘      └─────────┘         └─────────┘
```

Level descriptions:

- **World** - Hard isolation boundary. No cross-World communication without explicit Gateway. One per deployment or tenant.
- **City** - One Elixir/OTP node. Persisted with real identity, heartbeat-backed liveness, and split config buckets. Multiple Cities can exist within a World; clustering is architecturally intended.
- **Department** - Persisted logical group of agents within a City. Stores operator-facing metadata, lifecycle status, and local config overrides.
- **Lemming** - The durable agent entity. A Lemming is the canonical persisted agent record within a Department. It carries identity, long-lived configuration, capability metadata, and lifecycle policy.
- **LemmingInstance** - A runtime execution of a Lemming. Instances are supervised processes that run agent logic, own the message queue, and record checkpoints and status. One Lemming can have many instances over time.

Runtime execution hangs off each durable Lemming as one or more LemmingInstances.

---

## Component Overview

The labels below describe architectural runtime roles. Current module names are implementation references for the existing codebase, not the contract itself.

### World Context

* Current implementation module: `LemmingsOs.Worlds`.

* Manages persisted World rows and bootstrap import.
* Enforces World-scoping: no queries or events cross World boundaries without a Gateway.
* Provides the authoritative World identity used by City registration and config resolution.

### Config Resolver

* Current implementation module: `LemmingsOs.Config.Resolver`.

* Resolves effective configuration by merging World, City, Department, and Lemming config buckets.
* Merge order is hierarchical: child scopes override parent scopes, and deny-dominant keys follow ADR 0020 semantics.
* Pure in-memory: callers must preload the parent chain before calling.
* Child overrides parent; no DB access inside the resolver.

### City Runtime

* Current implementation module: `LemmingsOs.Cities.Runtime`.

* Resolves and upserts the local runtime City identity at application startup.
* Registers the local node as a City by upserting a `cities` row keyed by `node_name`.
* Does not perform discovery, clustering, or remote node management.

### City Heartbeat

* Current implementation module: `LemmingsOs.Cities.Heartbeat`.

* A GenServer that updates the local City's `last_seen_at` on a fixed 30-second interval.
* Derived liveness (`alive`, `stale`, `unknown`) is computed from `last_seen_at` freshness.
* Never mutates the administrative `status` field.

### City Supervisor

* Current implementation module: `LemmingsOs.City.Supervisor`.

* An OTP `Supervisor` (or `DynamicSupervisor`) managing all Departments within a City.
* Responsible for Department startup, restart, and shutdown.
* Coordinates city-level process lifecycles without crossing World boundaries.

### Department Manager

* Current implementation module: `LemmingsOs.Department.Manager`.

* A `GenServer` managing durable Lemmings and their runtime instances within a Department.
* Handles Lemming activation, restarts on crash, and graceful shutdown.
* Enforces Department-level constraints (capacity limits, capability filters).

### Lemming Runtime

* Current implementation module: `LemmingsOs.Lemming.Executor`.

* The leaf-level supervised runtime that executes a single LemmingInstance derived from a durable Lemming.
* The durable Lemming identity remains stable; instance records capture individual execution lifecycles, retries, and checkpoints.
* Exposes a standard message interface: `dispatch/2`, `status/1`, `stop/1`.
* Agent logic is pluggable via a behaviour: `LemmingsOs.Lemming.Behaviour`.

### Lemming Instance

* Current implementation module: `LemmingsOs.Lemming.Instance`.

* Runtime execution record for a durable Lemming.
* Tracks message queue ownership, checkpoints, retry bookkeeping, and execution status.
* May be created, stopped, or replaced without changing the durable Lemming identity.

### Event Bus

* Current implementation module: `LemmingsOs.Events`.

* Internal pub/sub scoped to a City (not cross-City by default).
* Used for intra-Department coordination and Department-to-Department signalling within the same City.
* Topic naming convention: `[world_id, city_id, department_id, event_type]`.

### Telemetry Layer

* Current implementation module: `LemmingsOs.Telemetry`.

* All hierarchy levels emit `:telemetry` events.
* Standard metadata: `world_id`, `city_id`, `department_id`, `lemming_id`, `lemming_instance_id`.
* Phoenix.LiveDashboard integration for real-time process monitoring.

---

## Message Flow

### Inbound: dispatching work to a LemmingInstance

```text
User / LiveView
      │
      │  Department.dispatch(dept, task)
      ▼
Department Manager          ← validates task against Department constraints
      │
      │  Lemming Runtime.dispatch(instance, task)
      ▼
Lemming Instance            ← runs agent logic for a durable Lemming
      │
      │  Tool.call(tool_name, args)
      ▼
Tool Module                 ← controlled Elixir module; only permitted actions
      │
      ▼
External system / LLM / DB
```

All external side effects go through Tool modules. A LemmingInstance cannot touch the outside world except through its declared toolset. This is the primary safety boundary.

### Outbound: LemmingInstance reporting results and events

```text
Lemming Instance
      │
      ├─── LemmingInstance.report_result(result)
      │         │
      │         ▼
      │    DB (lemming_instances row updated, status → :completed)
      │
      └─── EventBus.publish(topic, event)
                │
                ▼
           Department Manager   ← subscribed to LemmingInstance events
                │
                ├── notify other Lemmings in the Department (if needed)
                └── emit telemetry event upward
```

The Event Bus is scoped to the City. Events do not cross City or World boundaries without explicit routing through a Gateway.

---

## Failure Model

LemmingsOS treats failure as a normal operating condition, not an exception. This is the core value proposition of building on Elixir/OTP.

### LemmingInstance crash

```text
LemmingInstance crashes (runtime error, timeout, bad LLM response)
      │
      ▼
Department Manager (DynamicSupervisor)
      │  detects :DOWN signal from monitored instance
      │
      ├── increments restart count for this instance
      ├── checks restart policy (max_restarts, backoff strategy)
      │
      ├── [within policy] restart a new instance for the same durable Lemming identity
      │         │
      │         └── Lemming Runtime resumes from last persisted checkpoint (if any)
      │
      └── [policy exceeded] mark the instance status → :failed in DB and update the parent Lemming lifecycle state
                │
                └── emit [:lemmings_os, :lemming_instance, :failed] telemetry event
```

### Department crash

```text
Department Manager crashes (unrecoverable state corruption)
      │
      ▼
City Supervisor (Supervisor, :one_for_one)
      │  restarts Department Manager
      │
      ├── Department Manager reinitializes from DB state
      │         (active LemmingInstances are re-supervised from persisted Lemmings and instance records)
      │
      └── emit [:lemmings_os, :department, :restarted] telemetry event
```

### City node failure

```text
City node goes down (container stop, OS crash, deploy)
      │
      ▼
Heartbeat stops writing to last_seen_at
      │
      ▼
Other nodes / UI derive liveness from last_seen_at freshness
      │
      ├── last_seen_at becomes stale after threshold (default 90s)
      ├── derived liveness changes from "alive" to "stale"
      ├── admin status is NOT automatically changed
      │
      └── LiveView dashboard reflects stale liveness on next poll
```

### Telemetry contract

Every failure path emits a structured telemetry event. All events include hierarchy metadata so operators can pinpoint exactly where a failure occurred:

```elixir
:telemetry.execute(
  [:lemmings_os, :lemming_instance, :failed],
  %{restart_count: n},
  %{world_id: w, city_id: c, department_id: d, lemming_id: l, reason: reason}
)
```

This makes LemmingsOS observable by default - not just when things go wrong, but at every state transition across the lifecycle.

---

## Data Model (High Level)

### World Persistence And Bootstrap Model

The `World` row is the durable system-of-record identity. Bootstrap YAML is ingestion input, not the long-term persisted source of truth, and runtime checks remain ephemeral read-model data.

Worlds shape:

```text
worlds
  id
  slug
  name
  status
  bootstrap_source
  bootstrap_path
  last_bootstrap_hash
  last_import_status
  last_imported_at
  limits_config
  runtime_config
  costs_config
  models_config
  inserted_at
  updated_at
```

This is an intentional departure from the older single-column `config_jsonb` concept. The architecture keeps:

- persisted World identity and operational linkage metadata on normal columns
- world-level declarative config split across scoped JSONB columns
- bootstrap file contents as ingestion input, not persisted wholesale
- runtime-derived status in read models such as `WorldPageSnapshot`, `SettingsPageSnapshot`, `ToolsPageSnapshot`, and `HomeDashboardSnapshot`

### Core relational hierarchy

```text
worlds
  id, slug, name, status, bootstrap_source, bootstrap_path,
  last_bootstrap_hash, last_import_status, last_imported_at,
  limits_config, runtime_config, costs_config, models_config,
  inserted_at, updated_at

cities
  id, world_id, slug, name, node_name, host, distribution_port,
  epmd_port, status, last_seen_at,
  limits_config, runtime_config, costs_config, models_config,
  inserted_at, updated_at

departments
  id, world_id, city_id, slug, name, status, notes, tags,
  limits_config, runtime_config, costs_config, models_config,
  inserted_at, updated_at

lemmings
  id, world_id, city_id, department_id, slug, name, description,
  instructions, status, limits_config, runtime_config, costs_config,
  models_config, tools_config,
  inserted_at, updated_at

lemming_instances
  id, lemming_id, world_id, city_id, department_id, parent_instance_id,
  instance_ref, status, queue_ref, started_at, stopped_at, last_checkpoint_at
```

All tables are scoped by `world_id`. Context APIs require explicit World scope.
`LemmingType` remains available as an optional future template/reuse layer, but it is not the primary core model.
See ADR 0003 for isolation semantics.

---

## Key Design Decisions

| Decision | ADR |
|---|---|
| License (Apache 2.0) | ADR 0001 |
| Four-level hierarchy model | ADR 0002 |
| World as hard isolation boundary | ADR 0003 |
| City as runtime execution node | ADR 0017 |
| Hierarchical configuration with split JSONB | ADR 0020 |
| Core domain schema | ADR 0021 |
| Deployment and packaging model | ADR 0022 |

---

## Operational Model

* `mix setup` bootstraps the database and dependencies.
* `mix phx.server` runs the full runtime locally on `localhost:4000` by default, or the port from `PORT` / `MIX_PORT`.
* The Phoenix LiveView UI provides a real-time dashboard of the hierarchy.
* All agent lifecycle events are logged with structured metadata.

---

## Implementation Sequencing

Implementation can stage persistence, orchestration, and runtime execution separately. That sequencing does not change the architectural contract above.

---

## Future Work (not yet designed)

* `LemmingsOs.Gateway` - explicit cross-World communication bridge
* Distributed Erlang clustering between City nodes (requires future ADR)
* Secure remote City attachment and secret distribution (requires dedicated ADR and security design)
* City membership protocol and automatic discovery
* Department runtime supervisor / manager orchestration
* Agent capability declarations and Department-level enforcement
* Lemming hot-reload and live config updates
* ETS-backed config cache (`Config.Cache`)
* Implementation of deny-dominant merge enforcement in the resolver and validator
* Optional reusable template layer, if future reuse requirements justify it
