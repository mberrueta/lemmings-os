# Task 06: Heartbeat Worker and Presence Model

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: Task 04
- **Blocks**: Task 07, Task 08, Task 10, Task 12

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to add the city heartbeat worker and derived liveness model.

## Objective

Track city freshness by updating `last_seen_at` on a fixed interval and derive `alive`, `stale`, and `unknown` without ever treating admin `status` as liveness truth.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] `llms/tasks/0002_implement_city_management/04_first_city_bootstrap_and_startup_integration.md`
- [ ] `lib/lemmings_os/application.ex`
- [ ] `llms/constitution.md`

## Expected Outputs

- [ ] heartbeat worker/process
- [ ] supervision integration
- [ ] liveness derivation helper(s)
- [ ] deterministic OTP/process tests
- [ ] logging with `world_id` / `city_id` metadata where appropriate

## Acceptance Criteria

- [ ] heartbeat updates only `last_seen_at`
- [ ] admin `status` is never mutated by heartbeat logic
- [ ] a city with no heartbeat can be rendered as `unknown`
- [ ] a stopped city becomes `stale` after the documented threshold
- [ ] tests use `start_supervised/1` and are deterministic

## Technical Notes

### Relevant Code Locations

- `lib/lemmings_os/application.ex`
- `lib/lemmings_os/`
- `test/lemmings_os/`

### Constraints

- Use stable identities for any named processes
- Do not use runtime-generated atoms from external input
- Avoid timing-flaky tests
- Keep this worker local-city only

## Execution Instructions

### For the Agent

1. Implement the smallest heartbeat path that satisfies the plan.
2. Keep liveness derivation easy to test independently from the scheduler interval.
3. Name supervised processes safely.
4. Record the exact freshness-threshold assumption used by the implementation.

### For the Human Reviewer

1. Confirm liveness is derived from `last_seen_at`, not `status`.
2. Confirm the supervision design is safe and deterministic.
3. Confirm logging includes the right hierarchy metadata without leaking secrets.
4. Approve before Task 07, Task 08, Task 10, and Task 12 continue.

