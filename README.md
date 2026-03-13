# LemmingsOS

> An open-source runtime for autonomous AI agent hierarchies.
> Pixel-inspired identity. Staff-engineer-level engineering standards.

[![CI](https://github.com/mberrueta/lemmings-os/actions/workflows/elixir.yml/badge.svg)](https://github.com/mberrueta/lemmings-os/actions/workflows/elixir.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Elixir](https://img.shields.io/badge/elixir-1.15%2B-purple.svg)](https://elixir-lang.org/)
[![Status](https://img.shields.io/badge/status-early--stage-orange.svg)]()

## What is LemmingsOS?

LemmingsOS is a **self-hosted runtime** for creating, supervising, and orchestrating autonomous AI agent hierarchies. It provides:

- **Structured agent hierarchy** — Worlds → Cities → Departments → Lemmings
- **Hard isolation boundaries** — each World is a complete isolation boundary; Cities map to running server nodes
- **OTP-native lifecycle management** — spawn, supervise, and terminate agents using Elixir's battle-tested fault tolerance
- **Observability by default** — structured logging and telemetry at every layer of the hierarchy
- **Extensible agent interfaces** — plug in your own agent logic through well-defined, typed contracts
- **Self-hosted** — your infrastructure, your agents, your data

LemmingsOS is not an AI model. It provides the **runtime scaffolding** that autonomous AI agents need to operate reliably: supervision, identity, messaging, and lifecycle management.

---

## Hierarchy

```
                        ┌─────────────────────────────────────┐
                        │               World                 │
                        │    (hard isolation boundary)        │
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

- **World** — The outermost isolation boundary. Cross-World communication is not permitted without an explicit gateway. Useful for staging vs. production, multi-tenant deployments, or air-gapped environments.
- **City** — A live Elixir/OTP node. Cities can join or leave a World dynamically. Each City runs a local agent supervision tree.
- **Department** — A named partition within a City. Departments define the purpose, capabilities, and constraints of the agents they contain.
- **Lemming** — The atom of execution. A Lemming is a supervised process running a specific agent task. It has a stable identity, a lifecycle, and a message queue.

---

## Design Principles

1. **Hierarchy is the unit of isolation** — no cross-boundary coupling without explicit contracts.
2. **Supervision is non-optional** — every Lemming runs under a supervisor; crashes are expected, handled, and observable.
3. **Observability by default** — every layer emits structured telemetry. No black-box agents.
4. **Explicit over implicit** — all agent creation goes through the hierarchy API. No magic spawning.
5. **Correctness before performance** — a correct, slow system is easier to optimize than a fast, broken one.
6. **Self-hosted first** — designed to run on your own infrastructure, not as a cloud service dependency.
7. **Agent identity is durable** — Lemmings have stable IDs across restarts within their lifecycle.
8. **Minimal surface area** — the runtime does one thing well; domain logic lives in Lemmings, not in the framework.

---

## Non-goals

- Not an AI model or LLM provider.
- Not a workflow DAG runner or task queue (it is a runtime, not an orchestration framework).
- Not a hosted SaaS product.
- Not designed for single-script hobbyist automation (use a simpler tool).

---

## Why LemmingsOS Exists

Most AI agent frameworks focus on building "super agents" — a single agent that attempts to reason about everything and perform many tasks.

LemmingsOS takes a different approach.

### Micro-agents, not super-agents

Each Lemming is intentionally simple.

A Lemming is designed to perform one narrow task extremely well, such as:

- reviewing UX decisions
- researching libraries
- validating framework usage
- generating tests
- optimizing layouts

Instead of one powerful agent, LemmingsOS encourages many specialized agents collaborating together.

This approach follows the same philosophy that made Unix successful:

> *Do one thing well. Compose many small processes.*

### Runtime infrastructure, not prompt engineering

Most frameworks focus on prompts, workflows, and tool calls.

LemmingsOS focuses on the runtime layer that autonomous agents require:

- lifecycle management
- crash recovery
- supervision
- resource governance
- identity and isolation
- observability

The goal is not to build smarter prompts — but to provide reliable infrastructure for long-running autonomous systems.

### Safety by design

Agents never execute arbitrary code.

All external actions go through **Tools** — controlled Elixir modules that:

- define exactly what can be executed
- enforce permission and rate limits
- provide auditable, traceable behavior

This design dramatically reduces the risks commonly found in agent frameworks that allow unrestricted shell execution.

### Built for long-running agents

A Lemming is not a single prompt execution.

Lemmings can:

- run for hours or days
- retry tasks automatically
- resume after crashes
- report results asynchronously

This model aligns naturally with Elixir/OTP supervision trees, where process failure and recovery are first-class concerns.

### Local-first AI

LemmingsOS is designed to work without expensive hosted models.

It integrates naturally with:

- [Ollama](https://ollama.com/)
- local inference servers
- self-hosted LLM stacks

Cloud APIs can still be used, but they are not required.

---

## Architecture

High-level components:

| Component | Responsibility |
|---|---|
| World Registry | Tracks Cities, Departments, and Lemmings; enforces boundary rules |
| City Supervisor | OTP supervision tree managing a City's Departments |
| Department Manager | Controls Lemming lifecycle within a Department |
| Lemming Executor | The process that runs a Lemming's agent logic loop |
| Event Bus | Internal pub/sub for intra-City events |
| Telemetry Layer | Structured metrics and traces across all hierarchy layers |

See [docs/architecture.md](docs/architecture.md) for details.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Elixir 1.15+ / OTP 26+ |
| Web / UI | Phoenix 1.8 + LiveView 1.1 |
| Database | PostgreSQL 14+ |
| Asset pipeline | Tailwind v4, esbuild, daisyUI |
| HTTP server | Bandit |
| Container | Docker + docker-compose |

---

## Quick Start

**Prerequisites:** Elixir/Erlang (via [ASDF](https://asdf-vm.com/)), PostgreSQL, Node.js.

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

Open: [http://localhost:4000](http://localhost:4000)

---

## CI / Quality Gates

```bash
mix format               # code formatting check
mix test                 # full test suite
mix credo --strict       # style and lint
mix precommit            # full gate (format + test + credo)
```

All PRs must pass `mix precommit` before merge. See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Roadmap

See [docs/roadmap.md](docs/roadmap.md).

---

## Documentation Layout

```
docs/
  architecture.md        system architecture overview
  roadmap.md             development roadmap and phase plan
  adr/                   architecture decision records
    README.md
    0001-*.md, ...

llms/
  constitution.md        non-negotiable LLM/agent governance rules
  project_context.md     project-specific context for AI agents
  agents/                specialized agent prompt files and catalog
  coding_styles/         Elixir, Phoenix, and testing conventions
  tasks/                 LLM issue execution plans
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

All AI-assisted contributions must comply with `llms/constitution.md` and `AGENTS.md`.

---

## Security

Do not report vulnerabilities via public issues. See `SECURITY.md` (coming soon).

---

## License

Apache License 2.0 — see [LICENSE](LICENSE).
