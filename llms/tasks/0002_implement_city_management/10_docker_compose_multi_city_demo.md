# Task 10: Docker Compose Multi-City Demo

## Status

- **Status**: COMPLETE
- **Approved**: [X]
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

## Execution Summary

### Date: 2026-03-19

### Files Created

- `/Dockerfile` -- Multi-stage build (build on `hexpm/elixir:1.18.4-erlang-28.0.2-debian-bookworm-20250428-slim`, runtime on `debian:bookworm-slim`). Same image used for world and city nodes.
- `/docker-compose.yml` -- Four services: `db` (postgres:16-alpine), `world` (control-plane + web UI), `city_a`, `city_b`. All share one Postgres instance.
- `/.env.example` -- Documents `SECRET_KEY_BASE`, optional Postgres and Phoenix host/port overrides.
- `/.dockerignore` -- Excludes deps, _build, .git, .env, and other non-essential files from Docker context.
- `/lib/lemmings_os/release.ex` -- `LemmingsOs.Release` module with `migrate/0` and `rollback/2` for release eval tasks.

### Files Modified

- `/mix.exs` -- Added `releases: releases()` to project config and a `releases/0` private function defining the `:lemmings_os` release with unix executables and runtime_tools.
- `/.gitignore` -- Added `.env` to prevent secrets from being committed.

### Architecture Decisions

1. **Single image, env-driven identity**: All containers use the same release image. Node identity is controlled entirely by `LEMMINGS_CITY_NODE_NAME`, `LEMMINGS_CITY_SLUG`, `LEMMINGS_CITY_NAME`, and `LEMMINGS_CITY_HOST` environment variables, matching the contract established in Task 04 and `config/runtime.exs`.

2. **World node runs migrations**: The `world` service uses a shell entrypoint that runs `LemmingsOs.Release.migrate()` via release eval before starting the server. City nodes start directly without migrating.

3. **No BEAM distribution**: All containers set `RELEASE_DISTRIBUTION=none`. Nodes connect only via shared Postgres. Stale detection relies solely on missing heartbeat writes.

4. **World node is also a city**: The world container registers itself as a city (`world@world`) with its own heartbeat. This matches the plan's recommendation that the control-plane container be treated as a city too.

5. **No secrets in source control**: `docker-compose.yml` references `${SECRET_KEY_BASE}` from the `.env` file. The `DATABASE_URL` uses the same credentials as the `db` service definition (both default to `postgres:postgres`). `.env` is gitignored.

6. **City nodes do not serve HTTP**: Only the `world` service sets `PHX_SERVER=true` and exposes port 4000. City nodes run the full app (including heartbeat worker) but do not start the web server.

### Demo Usage Contract (for runbook task)

```sh
# 1. Generate a secret and create .env
mix phx.gen.secret  # copy output
cp .env.example .env
# edit .env, paste SECRET_KEY_BASE value

# 2. Build and start
docker compose up --build

# 3. Visit the world UI
open http://localhost:4000

# 4. Observe three cities (world, city-a, city-b) all alive

# 5. Stop one city to see stale behavior
docker compose stop city_a
# Wait ~90 seconds (freshness_threshold_seconds default)
# city-a should show as stale in the UI

# 6. Restart to see recovery
docker compose start city_a
```

### Assumptions for Later Tasks

- The runbook (Task 15) should document the full demo flow including the `.env` setup step.
- The Dockerfile uses `hexpm/elixir` base image pinned to the project's current Elixir/Erlang versions. If those versions change, the Dockerfile `FROM` line must be updated.
- The `priv/default.world.yaml` bootstrap file is included in the release via `COPY priv priv` during the build stage. No separate bootstrap copy step is needed.
- City nodes depend on `world` via `service_started` (not `service_healthy`) since there is no HTTP healthcheck on the world container. The world runs migrations before starting, so cities may retry DB connections briefly during startup. This is acceptable for a local demo.
