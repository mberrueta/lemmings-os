# Project Context

This file captures project-specific context used by AI agents working on LemmingsOS.

## Precedence

- `llms/constitution.md` is the baseline for all LLM agents (Claude, Codex, Gemini, and others).
- This file extends that baseline with project-specific context and must not conflict with it.

## App identity

- App name: `lemmings_os`
- Web module: `LemmingsOsWeb`
- Framework: Phoenix 1.8 + LiveView 1.1

## Domain focus

LemmingsOS is a self-hosted runtime for autonomous AI agent hierarchies. The domain is:

- **agent lifecycle management** — spawn, supervise, restart, and terminate Lemmings
- **hierarchy enforcement** — World / City / Department / Lemming, with hard isolation at the World boundary
- **observability** — structured telemetry, logging, and real-time dashboards at every layer
- **extensibility** — pluggable agent behaviours via `LemmingsOs.Lemming.Behaviour`
- **self-hosted first** — no cloud dependency, operator controls infrastructure

## Core pillars (product invariants at the vision level)

These five pillars define what LemmingsOS is. Agents must not propose designs or features that contradict them.

1. **Micro-agent architecture** — Lemmings do one thing well. The platform encourages many specialized agents composing together, not one super-agent trying to do everything. Do not design generic "do anything" agents.

2. **Runtime, not prompts** — LemmingsOS focuses on lifecycle management, supervision, crash recovery, resource governance, and observability. Prompt engineering and workflow DAGs are the concern of the Lemmings, not the runtime. Do not add orchestration logic to the runtime layer.

3. **Safety by design** — Agents never execute arbitrary code. All external actions go through Tools — controlled, typed Elixir modules with explicit permission boundaries. Do not add shell execution or arbitrary eval capabilities.

4. **True autonomy** — Lemmings are designed to run for hours or days, not single prompt executions. They retry automatically, resume after crashes, and report results asynchronously. Do not design Lemmings as stateless one-shot processes.

5. **Local-first AI** — Designed to work with Ollama and self-hosted inference servers. Cloud APIs are supported but never required. Do not introduce hard dependencies on hosted AI services.

## Domain invariants (planning baseline)

- **World scoping is mandatory**: all context API functions for World-scoped resources MUST receive
  an explicit `world_id` or `%World{}` struct. There are no implicit global queries.
- **Cross-World communication is forbidden** without a named `Gateway` (see ADR 0003).
  Agents must never query across World boundaries directly.
- **Lemming identity is durable within a lifecycle**: a Lemming's UUID is stable across process
  restarts until the Lemming is explicitly stopped or its lifecycle ends.
- **Process names MUST be derived from stable DB IDs**, never from runtime-generated atoms.
  This prevents atom table exhaustion in long-running deployments.
- **Supervision strategy is intentional**: every Lemming, Department, and City must have a
  documented restart strategy (`:one_for_one`, `:one_for_all`, `:rest_for_one`, transient, temporary).
  Restart strategy decisions should be ADR'd when non-obvious.
- **Telemetry metadata includes hierarchy context**: all `:telemetry.execute/3` calls MUST include
  `world_id`, `city_id`, `department_id`, and (where applicable) `lemming_id` in the metadata map.

## Engineering conventions

- Follow `AGENTS.md` as the primary instruction source.
- Use `Req` for all HTTP integrations (including LLM API calls from Lemmings).
- Run `mix precommit` before finishing any task.
- Use `start_supervised/1` in all ExUnit tests that start OTP processes.
- Public context APIs for the domain hierarchy must be explicitly scoped; no convenience functions
  that bypass World scoping.
- Changeset modules live under their context: `LemmingsOs.World`, `LemmingsOs.City`, etc.
- The web layer calls contexts; contexts own all DB and OTP side effects.
- All new database columns that belong to a World-scoped entity MUST include `world_id`.
- Use `Ecto.Multi` for any operation that touches more than one table.
- Logging MUST include hierarchy metadata at the relevant level:
  `Logger.info("lemming started", world_id: w.id, city_id: c.id, department_id: d.id, lemming_id: l.id)`
- Avoid logging agent payloads (they may contain sensitive data from external LLM calls).

## Module naming conventions

| Layer | Module prefix |
|---|---|
| World | `LemmingsOs.World` |
| City | `LemmingsOs.City` |
| Department | `LemmingsOs.Department` |
| Lemming | `LemmingsOs.Lemming` |
| Event bus | `LemmingsOs.Events` |
| Telemetry | `LemmingsOs.Telemetry` |
| Web | `LemmingsOsWeb.*` |

## Key ADRs

- ADR 0001: Apache 2.0 license
- ADR 0002: World / City / Department / Lemming hierarchy model
- ADR 0003: World as hard isolation boundary
