# LemmingsOS — Architecture Overview

## Purpose

LemmingsOS is a self-hosted runtime for autonomous AI agent hierarchies. It provides
structured lifecycle management, supervision, isolation, and observability for
autonomous agents organized in a four-level hierarchy.

Five pillars guide all architecture decisions:

| Pillar | Constraint |
|---|---|
| Micro-agent architecture | Lemmings do one thing; no super-agents |
| Runtime, not prompts | Lifecycle and supervision, not workflow DAGs |
| Safety by design | All external actions go through typed Tools — no arbitrary code execution |
| True autonomy | Lemmings run for hours/days, retry, and resume after crashes |
| Local-first AI | Ollama and self-hosted models are first-class; cloud APIs are optional |

---

## Hierarchy

```
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

- **World** — Hard isolation boundary. No cross-World communication without explicit Gateway. One per deployment or tenant.
- **City** — One Elixir/OTP node. Multiple Cities can form a World cluster. City joins/leaves a World dynamically.
- **Department** — Named logical group of agents within a City. Defines shared purpose, capabilities, and constraints.
- **Lemming** — Supervised autonomous agent process. Has stable identity, lifecycle, and mailbox.

See ADR 0002 for the rationale behind this model.

---

## Component Overview

### World Registry (`LemmingsOs.World.Registry`)

* Tracks all active Worlds on the local node.
* Enforces World-scoping: no queries or events cross World boundaries without a Gateway.
* Provides the authoritative list of Cities in each World.

### City Supervisor (`LemmingsOs.City.Supervisor`)

* An OTP `Supervisor` (or `DynamicSupervisor`) managing all Departments within a City.
* Responsible for Department startup, restart, and shutdown.
* Reports health to the World Registry.

### Department Manager (`LemmingsOs.Department.Manager`)

* A `GenServer` managing the Lemming pool within a Department.
* Handles Lemming spawn requests, restarts on crash, and graceful shutdown.
* Enforces Department-level constraints (capacity limits, capability filters).

### Lemming Executor (`LemmingsOs.Lemming.Executor`)

* The leaf-level supervised process that runs agent logic.
* Has a stable identity (UUID) that persists across restarts within a lifecycle.
* Exposes a standard message interface: `dispatch/2`, `status/1`, `stop/1`.
* Agent logic is pluggable via a behaviour: `LemmingsOs.Lemming.Behaviour`.

### Event Bus (`LemmingsOs.Events`)

* Internal pub/sub scoped to a City (not cross-City by default).
* Used for intra-Department coordination and Department-to-Department signalling within
  the same City.
* Topic naming convention: `[world_id, city_id, department_id, event_type]`.

### Telemetry Layer (`LemmingsOs.Telemetry`)

* All hierarchy levels emit `:telemetry` events.
* Standard metadata: `world_id`, `city_id`, `department_id`, `lemming_id`.
* Phoenix.LiveDashboard integration for real-time process monitoring.

---

## Message Flow

### Inbound: dispatching work to a Lemming

```
User / LiveView
      │
      │  Department.dispatch(dept, task)
      ▼
Department Manager          ← validates task against Department constraints
      │
      │  Lemming.Executor.dispatch(pid, task)
      ▼
Lemming Executor            ← runs agent logic loop
      │
      │  Tool.call(tool_name, args)
      ▼
Tool Module                 ← controlled Elixir module; only permitted actions
      │
      ▼
External system / LLM / DB
```

All external side effects go through Tool modules. A Lemming cannot touch the outside
world except through its declared toolset. This is the primary safety boundary.

### Outbound: Lemming reporting results and events

```
Lemming Executor
      │
      ├─── Lemming.report_result(result)
      │         │
      │         ▼
      │    DB (lemmings table updated, status → :completed)
      │
      └─── EventBus.publish(topic, event)
                │
                ▼
           Department Manager   ← subscribed to Lemming events
                │
                ├── notify other Lemmings in the Department (if needed)
                └── emit telemetry event upward
```

The Event Bus is scoped to the City. Events do not cross City or World boundaries
without explicit routing through a Gateway (not yet implemented).

---

## Failure Model

LemmingsOS treats failure as a normal operating condition, not an exception.
This is the core value proposition of building on Elixir/OTP.

### Lemming crash

```
Lemming Executor crashes (runtime error, timeout, bad LLM response)
      │
      ▼
Department Manager (DynamicSupervisor)
      │  detects :DOWN signal from monitored Lemming
      │
      ├── increments restart count for this Lemming
      ├── checks restart policy (max_restarts, backoff strategy)
      │
      ├── [within policy] restart Lemming with same identity (UUID preserved)
      │         │
      │         └── Lemming.Executor resumes from last persisted checkpoint (if any)
      │
      └── [policy exceeded] mark Lemming status → :failed in DB
                │
                └── emit [:lemmings_os, :lemming, :failed] telemetry event
```

### Department crash

```
Department Manager crashes (unrecoverable state corruption)
      │
      ▼
City Supervisor (Supervisor, :one_for_one)
      │  restarts Department Manager
      │
      ├── Department Manager reinitializes from DB state
      │         (active Lemmings are re-supervised from persisted records)
      │
      └── emit [:lemmings_os, :department, :restarted] telemetry event
```

### City node failure

```
City node goes down (network partition, OS crash, deploy)
      │
      ▼
World Registry (on surviving nodes)
      │  detects node :DOWN via distributed Erlang monitoring
      │
      ├── marks City status → :unreachable in DB
      ├── does NOT automatically migrate Lemmings (operator decision)
      │
      └── emit [:lemmings_os, :city, :unreachable] telemetry event
               │
               └── LiveView dashboard reflects updated City status in real time
```

### Telemetry contract

Every failure path emits a structured telemetry event. All events include hierarchy
metadata so operators can pinpoint exactly where a failure occurred:

```elixir
:telemetry.execute(
  [:lemmings_os, :lemming, :failed],
  %{restart_count: n},
  %{world_id: w, city_id: c, department_id: d, lemming_id: l, reason: reason}
)
```

This makes LemmingsOS observable by default — not just when things go wrong, but
at every state transition across the lifecycle.

---

## Data Model (High Level)

### World Persistence And Bootstrap Model

The `World` row is the durable system-of-record identity. Bootstrap YAML is
ingestion input, not the long-term persisted source of truth, and runtime checks
remain ephemeral read-model data.

Current `worlds` shape:

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

This is an intentional departure from the older single-column `config_jsonb`
concept. The architecture keeps:

- persisted World identity and operational linkage metadata on normal columns
- world-level declarative config split across scoped JSONB columns
- bootstrap file contents as ingestion input, not persisted wholesale
- runtime-derived status in read models such as `WorldPageSnapshot`,
  `SettingsPageSnapshot`, `ToolsPageSnapshot`, and `HomeDashboardSnapshot`

### Target relational hierarchy

```
worlds
  id, name, slug, status, inserted_at

cities
  id, world_id, node_name, status, inserted_at

departments
  id, city_id, world_id, name, inserted_at

lemmings
  id, department_id, city_id, world_id,
  status, agent_module,
  started_at, stopped_at, inserted_at
```

All tables are scoped by `world_id`. Context APIs require explicit World scope.
See ADR 0003 for isolation semantics.

---

## Key Design Decisions

| Decision | ADR |
|---|---|
| License (Apache 2.0) | ADR 0001 |
| Four-level hierarchy model | ADR 0002 |
| World as hard isolation boundary | ADR 0003 |

---

## Operational Model

* `mix setup` bootstraps the database and dependencies.
* `mix phx.server` runs the full runtime locally on `localhost:4000` by default, or the port from `PORT` / `MIX_PORT`.
* The Phoenix LiveView UI provides a real-time dashboard of the hierarchy.
* All agent lifecycle events are logged with structured metadata.

---

## Future Work (not yet designed)

* `LemmingsOs.Gateway` — explicit cross-World communication bridge
* Multi-City clustering and City membership protocol
* Agent capability declarations and Department-level enforcement
* Lemming hot-reload and live config updates
