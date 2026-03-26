# Task 16: Structured Logging and Telemetry Events

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-logging-daily-guardian` - logging quality guardian for structured events, hierarchy metadata, and telemetry consistency.

## Agent Invocation
Act as `dev-logging-daily-guardian` following `llms/constitution.md` and add structured logging and telemetry events for all runtime lifecycle transitions in the executor, scheduler, and resource pool.

## Objective
Instrument the runtime engine with structured `Logger` calls and `:telemetry.execute/3` events on every key lifecycle transition. Every log line and telemetry event must include full hierarchy metadata (`world_id`, `city_id`, `department_id`, `lemming_id`, `instance_id`). This enables observability of the runtime engine in development and lays the foundation for production monitoring.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules (no debug prints, structured logging)
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contract #4 (status taxonomy with all transitions), #16 (PubSub topics)
- [ ] `lib/lemmings_os_web/telemetry.ex` - Existing telemetry setup
- [ ] Task 03 output (executor GenServer) - All state transitions to instrument
- [ ] Task 04 output (DepartmentScheduler) - Admission and dispatch events

## Expected Outputs

- [ ] Modified `lib/lemmings_os/lemming_instances/executor.ex` - Added Logger and telemetry calls at each state transition
- [ ] Modified `lib/lemmings_os/lemming_instances/department_scheduler.ex` - Added Logger and telemetry calls for admission events
- [ ] Modified `lib/lemmings_os/lemming_instances/resource_pool.ex` - Added Logger and telemetry calls for pool acquire/release
- [ ] Modified `lib/lemmings_os/lemming_instances/dets_store.ex` - Added Logger and telemetry for snapshot success/failure
- [ ] Possibly new `lib/lemmings_os/lemming_instances/telemetry.ex` - Centralized telemetry event definitions and helper functions

## Acceptance Criteria

### Executor Lifecycle Events
- [ ] `[:lemmings_os, :instance, :created]` - Instance record created
- [ ] `[:lemmings_os, :instance, :started]` - Executor process started (`started_at` set)
- [ ] `[:lemmings_os, :instance, :queued]` - Work item enqueued, waiting for admission
- [ ] `[:lemmings_os, :instance, :processing]` - Work item execution begun
- [ ] `[:lemmings_os, :instance, :retrying]` - Structured output validation failed, retrying
- [ ] `[:lemmings_os, :instance, :idle]` - Queue empty, instance idle
- [ ] `[:lemmings_os, :instance, :failed]` - Terminal failure after retry exhaustion
- [ ] `[:lemmings_os, :instance, :expired]` - Idle timeout elapsed, instance terminated

### Scheduler Events
- [ ] `[:lemmings_os, :scheduler, :admission_granted]` - Scheduler admitted an instance
- [ ] `[:lemmings_os, :scheduler, :admission_denied]` - No pool capacity available
- [ ] `[:lemmings_os, :scheduler, :work_announced]` - New work announced via PubSub

### Resource Pool Events
- [ ] `[:lemmings_os, :pool, :acquired]` - Pool slot acquired (include resource key)
- [ ] `[:lemmings_os, :pool, :released]` - Pool slot released (include resource key)
- [ ] `[:lemmings_os, :pool, :exhausted]` - Pool at capacity, request denied

### DETS Snapshot Events
- [ ] `[:lemmings_os, :dets, :snapshot_written]` - Snapshot successfully written
- [ ] `[:lemmings_os, :dets, :snapshot_failed]` - Snapshot write failed (must not fail the instance)

### Metadata Requirements
- [ ] Every event includes: `world_id`, `city_id`, `department_id`, `lemming_id`, `instance_id`
- [ ] Scheduler events include `department_id` as the organizational scope
- [ ] Pool events include `resource_key` (e.g., `ollama:llama3.2`)
- [ ] Retry events include `attempt` and `max_attempts`
- [ ] Processing events include `duration_ms` measurement where applicable
- [ ] Failed events include `reason` (structured, not raw provider errors)

### Logger Integration
- [ ] Each telemetry event has a corresponding `Logger.info/2` or `Logger.warning/2` call
- [ ] Log level: `:info` for normal transitions, `:warning` for retries and snapshot failures, `:error` for terminal failures
- [ ] Logger metadata uses the same hierarchy keys as telemetry
- [ ] No `IO.inspect`, `IO.puts`, or `dbg()` calls

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os_web/telemetry.ex                       # Existing telemetry setup
lib/lemmings_os/lemming_instances/executor.ex           # Task 03 output
lib/lemmings_os/lemming_instances/department_scheduler.ex # Task 04 output
lib/lemmings_os/lemming_instances/resource_pool.ex      # Task 05 output
lib/lemmings_os/lemming_instances/dets_store.ex         # Task 07 output
lib/lemmings_os/application.ex                          # Logger bootstrap reference
```

### Patterns to Follow
- Use `:telemetry.execute/3` with measurements map and metadata map
- Use `Logger.info/2` with keyword metadata (not string interpolation for structured fields)
- Follow existing logging patterns from `application.ex` (e.g., `Logger.log(level, message, event: ..., status: ...)`)
- Centralize event name constants in a telemetry helper module if the list grows large

### Constraints
- Telemetry events must not raise -- failures in telemetry/logging must not crash the process
- Do not log raw provider error payloads (may contain sensitive prompt content)
- Do not log the full `config_snapshot` (may be large); log only identifying fields
- DETS snapshot failure logging must not prevent the instance from continuing to operate

## Execution Instructions

### For the Agent
1. Read existing telemetry setup in `telemetry.ex`.
2. Read Task 03, 04, 05, 07 outputs to identify all transition points.
3. Define the telemetry event names and metadata contracts.
4. Add `:telemetry.execute/3` calls at each transition point.
5. Add corresponding `Logger` calls with structured metadata.
6. Create a telemetry helper module if needed for event name constants and metadata builders.
7. Verify no debug prints or raw error payloads are logged.

### For the Human Reviewer
1. Verify every status transition from Frozen Contract #4 has a telemetry event.
2. Verify full hierarchy metadata on every event.
3. Verify log levels are appropriate (info/warning/error).
4. Verify no raw provider errors or full config snapshots are logged.
5. Verify telemetry calls cannot crash the process (wrapped in try/rescue if needed).
6. Verify resource pool events include resource key, not Department/City.

---

## Execution Summary
*[Filled by executing agent after completion]*

### Work Performed
- [What was actually done]

### Outputs Created
- [List of files/artifacts created]

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|

### Blockers Encountered
- [Blocker 1] - Resolution: [How resolved or "Needs human input"]

### Questions for Human
1. [Question needing human input]

### Ready for Next Task
- [ ] All outputs complete
- [ ] Summary documented
- [ ] Questions listed (if any)

---

## Human Review
*[Filled by human reviewer]*

### Review Date
[YYYY-MM-DD]

### Decision
- [ ] APPROVED - Proceed to next task
- [ ] REJECTED - See feedback below

### Feedback

### Git Operations Performed
```bash
# human-only
```
