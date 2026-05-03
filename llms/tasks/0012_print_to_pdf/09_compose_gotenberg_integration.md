# Task 09: Compose Gotenberg Integration

## Status
- **Status**: COMPLETED
- **Approved**: [ ]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix configuration, deployment file changes, and focused validation.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Integrate Gotenberg into the default Docker Compose topology without publishing it to the host.

## Objective
Make Gotenberg available to app services on a private Compose network using `gotenberg/gotenberg:8`, while preserving local demo usability and documenting how developers can point `LEMMINGS_GOTENBERG_URL` at an external local Gotenberg when needed.

## Inputs Required
- [x] `llms/tasks/0012_print_to_pdf/plan.md`
- [x] Completed Tasks 01 through 08
- [x] `docker-compose.yml`
- [x] `.env.example`
- [x] `config/runtime.exs`

## Expected Outputs
- [x] Compose includes a `gotenberg` service using `gotenberg/gotenberg:8`.
- [x] Gotenberg exposes port `3000` internally only and has no default host-published `ports`.
- [x] App services that execute tools can reach `http://gotenberg:3000`.
- [x] Compose does not use `network_mode: host` for services that need private service-name resolution, or documents/adjusts the topology so service resolution works safely.
- [x] `LEMMINGS_GOTENBERG_URL` defaults appropriately for Compose/release use.
- [x] `.env.example` or comments document external local Gotenberg override for dev-only workflows.
- [x] Notes are recorded for later release-manager validation in Task 16.

## Acceptance Criteria
- [x] Default Compose does not publish Gotenberg to the host.
- [x] Default Compose does not require public network access to Gotenberg.
- [x] Existing Postgres/profile behavior and Phoenix startup remain understandable.
- [x] No application code changes beyond deployment/config support are made unless needed for Compose reachability.

## Technical Notes
- The current `docker-compose.yml` uses `network_mode: host` for app services. This conflicts with service-name access to `gotenberg`. Resolve this explicitly and document the tradeoff.
- Be careful not to introduce new required secrets.
- Release validation, rollback notes, and operator readiness review remain owned by Task 16.

## Execution Instructions
1. Review the current Compose topology and runtime config.
2. Make the smallest deployment change that satisfies private Gotenberg reachability.
3. Update `.env.example` comments if needed.
4. Validate Compose syntax with a non-destructive command if available.
5. Record commands and results in this task file.

## Execution Summary

### Work Performed
- [x] Added a `gotenberg` service (`gotenberg/gotenberg:8`) with internal-only `expose: ["3000"]` and no host `ports`.
- [x] Removed `network_mode: host` from `world`, `city_a`, and `city_b`, and moved app services to an explicit private Compose network (`lemmings_internal`) for service-name resolution.
- [x] Kept world UI host access by adding an explicit `world` port mapping `${PHX_PORT:-4000}:${PHX_PORT:-4000}`.
- [x] Wired `LEMMINGS_GOTENBERG_URL` env defaults in Compose to `http://gotenberg:3000` for all app services.
- [x] Added Compose comments and `.env.example` guidance for a dev-only host-local Gotenberg override via `http://host.docker.internal:3000`.
- [x] Added `extra_hosts: host.docker.internal:host-gateway` on app services to support host-local override connectivity.

### Outputs Created
- [x] Updated `docker-compose.yml`.
- [x] Updated `.env.example`.
- [x] Updated this task record with validation notes and command results.

### Assumptions Made
- [x] Compose bridge networking is acceptable for the demo topology as long as `world` explicitly publishes its UI port.
- [x] Using `host.docker.internal` as the documented dev override target is acceptable when paired with `extra_hosts` for Linux host-gateway support.

### Decisions Made
- [x] Chose a dedicated named network (`lemmings_internal`) to make private service-name routing explicit instead of relying on implicit default network wiring.
- [x] Kept `config/runtime.exs` unchanged because it already defaults `LEMMINGS_GOTENBERG_URL` to `http://gotenberg:3000`.
- [x] Updated Compose defaults for `DATABASE_URL` to service-name based `db` host to align with non-host-network operation.

### Blockers
- [x] `mix precommit` is not fully green due existing Credo findings in `lib/lemmings_os/tools/adapters/documents.ex` (readability/refactor complexity), unrelated to this Compose-only task.

### Questions for Human
- [x] Should we schedule a focused cleanup task for the existing `documents.ex` Credo issues so `mix precommit` can pass cleanly across all subsequent tasks?

### Ready for Next Task
- [x] Yes
- [ ] No

### Commands Run
- `docker compose config` ✅ (validates updated Compose topology and private Gotenberg exposure)
- `mix precommit` ⚠️ Dialyzer passed; Credo reported existing issues in `lib/lemmings_os/tools/adapters/documents.ex`

## Human Review
Human reviewer confirms Compose topology and private Gotenberg exposure before Task 10 begins.
