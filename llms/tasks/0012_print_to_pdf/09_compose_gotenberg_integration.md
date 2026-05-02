# Task 09: Compose Gotenberg Integration

## Status
- **Status**: PENDING
- **Approved**: [ ]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix configuration, deployment file changes, and focused validation.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Integrate Gotenberg into the default Docker Compose topology without publishing it to the host.

## Objective
Make Gotenberg available to app services on a private Compose network using `gotenberg/gotenberg:8`, while preserving local demo usability and documenting how developers can point `LEMMINGS_GOTENBERG_URL` at an external local Gotenberg when needed.

## Inputs Required
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] Completed Tasks 01 through 08
- [ ] `docker-compose.yml`
- [ ] `.env.example`
- [ ] `config/runtime.exs`

## Expected Outputs
- [ ] Compose includes a `gotenberg` service using `gotenberg/gotenberg:8`.
- [ ] Gotenberg exposes port `3000` internally only and has no default host-published `ports`.
- [ ] App services that execute tools can reach `http://gotenberg:3000`.
- [ ] Compose does not use `network_mode: host` for services that need private service-name resolution, or documents/adjusts the topology so service resolution works safely.
- [ ] `LEMMINGS_GOTENBERG_URL` defaults appropriately for Compose/release use.
- [ ] `.env.example` or comments document external local Gotenberg override for dev-only workflows.
- [ ] Notes are recorded for later release-manager validation in Task 16.

## Acceptance Criteria
- [ ] Default Compose does not publish Gotenberg to the host.
- [ ] Default Compose does not require public network access to Gotenberg.
- [ ] Existing Postgres/profile behavior and Phoenix startup remain understandable.
- [ ] No application code changes beyond deployment/config support are made unless needed for Compose reachability.

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
- [ ] To be completed by the executing agent.

### Outputs Created
- [ ] To be completed by the executing agent.

### Assumptions Made
- [ ] To be completed by the executing agent.

### Decisions Made
- [ ] To be completed by the executing agent.

### Blockers
- [ ] To be completed by the executing agent.

### Questions for Human
- [ ] To be completed by the executing agent.

### Ready for Next Task
- [ ] Yes
- [ ] No

## Human Review
Human reviewer confirms Compose topology and private Gotenberg exposure before Task 10 begins.
