# Task 10: Docker Compose Multi-City Demo

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 04, Task 06
- **Blocks**: Task 11

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to add the local multi-city compose demo artifacts and runtime contract.

## Objective

Make the system runnable as one world/control-plane node plus two or three city nodes over shared Postgres, with honest stale-city behavior when one node stops heartbeating.

This task demonstrates the City foundation. It does not introduce remote observation, cross-city coordination, or active control-plane health management.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] `llms/tasks/0002_implement_city_management/04_first_city_bootstrap_and_startup_integration.md`
- [ ] `llms/tasks/0002_implement_city_management/06_heartbeat_worker_and_presence_model.md`
- [ ] `mix.exs`
- [ ] `config/runtime.exs`

## Expected Outputs

- [ ] root `docker-compose` artifacts
- [ ] root `Dockerfile` or equivalent image/release artifact
- [ ] explicit runtime env contract for full BEAM `node_name`
- [ ] multi-container demo notes for later docs

## Acceptance Criteria

- [ ] the demo starts one world/control-plane app and two or three city runtimes
- [ ] all cities are visible in the UI against a shared Postgres instance
- [ ] each runtime persists a distinct full BEAM `node_name` in `name@host` form
- [ ] stopping one city container makes it become stale within the documented threshold
- [ ] the stale transition results only from missing local heartbeats, not from remote detection logic
- [ ] the demo does not require clustering, remote attachment security, or city-to-city dispatch

## Technical Notes

### Relevant Code Locations

- `mix.exs`
- `config/runtime.exs`
- repo root

### Constraints

- Keep the demo self-hosted and low-complexity
- Use env vars for runtime configuration
- Do not hardcode secrets
- Do not turn the compose stack into a full production packaging effort
- Reuse the runtime identity contract already established in Task 04
- Do not introduce compose-only fallback identity semantics
- Do not redefine `node_name` rules in this task
- Each city runtime is only responsible for persisting its own presence
- The demo must not introduce cross-city health checks, polling, or coordination
- The stale transition must come only from missing local heartbeats, not remote observation
- Prefer local demo reproducibility over production-packaging completeness

## Execution Instructions

### For the Agent

1. Introduce the narrowest viable container/demo artifacts for this issue.
2. Reuse the runtime identity contract from Task 04 exactly as established there.
3. Keep `node_name` explicit and reviewable in compose/runtime config without redefining the rules.
4. Optimize for local reproducibility, not final production deployment shape.
5. Document any assumption the runbook task must explain later.

### For the Human Reviewer

1. Confirm the demo proves multi-city visibility and stale behavior only.
2. Confirm the runtime identity contract is explicit and env-driven.
3. Confirm no secret material is embedded in source-controlled compose artifacts.
4. Approve before Task 11 begins.
