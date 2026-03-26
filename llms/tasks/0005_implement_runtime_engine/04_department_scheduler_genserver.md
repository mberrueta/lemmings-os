# Task 04: DepartmentScheduler GenServer

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for OTP processes and scheduling systems.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and implement the `LemmingsOs.LemmingInstances.DepartmentScheduler` GenServer with event-driven dispatch, pool admission, and PubSub integration.

## Objective
Create the DepartmentScheduler GenServer at `lib/lemmings_os/lemming_instances/department_scheduler.ex`. One scheduler exists per active Department. It owns scheduling truth for all instances within that Department: it listens for work-available signals via PubSub, queries for eligible instances, requests pool capacity by resource key, and grants admission tokens to instance executors. The v1 selection policy is oldest-eligible-first.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contracts #7 (DepartmentScheduler ownership), #8 (Resource pool), #16 (PubSub topics), #17 (Testability gate)
- [ ] `lib/lemmings_os/cities/heartbeat.ex` - GenServer pattern precedent
- [ ] Task 03 output (executor.ex) - How executors receive admission
- [ ] Task 05 output (resource pool) - Pool token API
- [ ] Task 09 output (PubSub helpers) - Broadcast/subscribe helpers

## Expected Outputs

- [ ] `lib/lemmings_os/lemming_instances/department_scheduler.ex` - DepartmentScheduler GenServer module

## Acceptance Criteria

### Process Identity
- [ ] One scheduler per Department, named via Registry: `{:via, Registry, {LemmingsOs.LemmingInstances.SchedulerRegistry, department_id}}`
- [ ] `start_link/1` accepts keyword opts including `:department_id`
- [ ] `child_spec/1` compatible with DynamicSupervisor
- [ ] Injectable dependencies (`:pool_mod`, `:ets_mod`, `:pubsub_mod`, `:context_mod`)

### Event-Driven Dispatch (Frozen Contract #7)
- [ ] Subscribes to `"department:#{department_id}:scheduler"` PubSub topic on init
- [ ] Reacts to `:work_available` messages by attempting to schedule
- [ ] Reacts to `:capacity_released` messages by attempting to schedule waiting instances
- [ ] Selection policy: oldest-eligible-first (by `inserted_at` of the queued work item)
- [ ] Does NOT execute work directly -- grants admission tokens to executors

### Pool Integration (Frozen Contract #8)
- [ ] Requests pool tokens by resource key (e.g., `ollama:llama3.2`), NOT by Department or City
- [ ] Resource key is derived from the instance's config snapshot (`models_config`)
- [ ] If pool grants capacity: sends admission message to executor
- [ ] If pool denies (at capacity): instance remains `queued`, scheduler retries on next capacity release

### Admission Flow
- [ ] Scheduler queries ETS for instances in `queued` status within its Department
- [ ] Sorts by oldest `inserted_at` first
- [ ] For each eligible instance: requests pool token, on success sends admission to executor
- [ ] Stops scheduling loop when pool is at capacity or no more queued instances

### Namespace (Critical Correction)
- [ ] Module lives at `LemmingsOs.LemmingInstances.DepartmentScheduler`
- [ ] Organizational scope = Department (one scheduler per Department)
- [ ] Implementation namespace = `LemmingInstances` (runtime concern, not Department management)

### Testability (Frozen Contract #17)
- [ ] Accepts `:admission_mode` option: `:auto` (default, production) or `:manual` (tests)
- [ ] In `:manual` mode: does not auto-dispatch; exposes `admit_next/1` for manual control
- [ ] Pattern follows Heartbeat's `:manual` interval convention

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/cities/heartbeat.ex                    # GenServer pattern with injectable deps
lib/lemmings_os/lemming_instances/executor.ex          # Task 03 executor
lib/lemmings_os/lemming_instances/resource_pool.ex     # Task 05 pool
lib/lemmings_os/lemming_instances/pubsub.ex            # Task 09 helpers
```

### Patterns to Follow
- Injectable deps via opts defaulting to production modules
- Registry-based process naming (not atoms)
- PubSub subscription in `init/1`
- `handle_info` for PubSub messages
- `handle_call` for `:manual` mode admission control

### Constraints
- The scheduler does NOT store queue state -- it queries ETS on each scheduling attempt
- The scheduler does NOT own the pool -- it requests tokens from the pool module
- Crashed executors should be detected (via pool release or process monitor) so pool slots are reclaimed
- Future dependency-aware scheduling must be left as a clean extension point in the interface but not implemented
- The pluggable selection policy interface should be visible (e.g., a `@callback` or function head) but v1 hardcodes oldest-first

## Execution Instructions

### For the Agent
1. Read the Heartbeat GenServer for the injectable deps and manual mode pattern.
2. Read plan.md Frozen Contracts #7, #8, #16, #17 thoroughly.
3. Create `lib/lemmings_os/lemming_instances/department_scheduler.ex`.
4. Implement event-driven dispatch via PubSub subscription.
5. Implement pool token requests by resource key (not Department/City).
6. Implement `:manual` admission mode for tests.
7. Leave clean seam for future pluggable selection policy.
8. Add `@doc` and `@spec` to all public functions.

### For the Human Reviewer
1. Verify scheduler subscribes to correct PubSub topic.
2. Verify pool requests use resource key, not Department/City key.
3. Verify oldest-eligible-first selection policy.
4. Verify `:manual` admission mode works for test control.
5. Verify module namespace is `LemmingsOs.LemmingInstances.DepartmentScheduler`.
6. Verify future extension seam for selection policy is visible.

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
