# Task 05: Resource Pool

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for concurrency control and OTP processes.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and implement the `LemmingsOs.LemmingInstances.ResourcePool` module with counter-based concurrency control keyed by resource key.

## Objective
Create the resource pool at `lib/lemmings_os/lemming_instances/resource_pool.ex`. The pool controls concurrent access to scarce resources (model endpoints). It is keyed by resource key (e.g., `ollama:llama3.2`), NOT by Department or City. The v1 implementation is a simple counter-based semaphore -- one GenServer per active resource key. The DepartmentScheduler requests tokens from the pool before granting admission to executors.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contract #8 (Resource pool)
- [ ] `lib/lemmings_os/cities/heartbeat.ex` - GenServer pattern precedent
- [ ] Task 06 output (ETS module) - May use ETS counters or standalone GenServer state

## Expected Outputs

- [ ] `lib/lemmings_os/lemming_instances/resource_pool.ex` - ResourcePool module

## Acceptance Criteria

### API Surface
- [ ] `checkout(resource_key)` -- Requests a pool token; returns `:ok` or `{:error, :at_capacity}`
- [ ] `checkin(resource_key)` -- Releases a pool token
- [ ] `status(resource_key)` -- Returns `{current, max}` for observability
- [ ] `available?(resource_key)` -- Returns boolean for quick capacity check

### Resource Key Design (Critical Correction)
- [ ] Pool is keyed by resource key (e.g., `"ollama:llama3.2"`), NOT by Department or City
- [ ] The resource key identifies the scarce resource (model endpoint), not the organizational boundary
- [ ] Many instances across many Departments may contend for the same pool
- [ ] One pool process per active resource key

### Concurrency Control
- [ ] Counter-based semaphore: tracks `current_count` vs `max_capacity`
- [ ] Default capacity: 1 (for local Ollama single-threaded inference)
- [ ] Capacity is configurable via application config or resolved `runtime_config`
- [ ] `checkout` increments counter; `checkin` decrements
- [ ] Counter never goes below 0

### Process Management
- [ ] Pool processes are started on demand (first checkout for a resource key)
- [ ] Named via Registry: `{:via, Registry, {LemmingsOs.LemmingInstances.PoolRegistry, resource_key}}`
- [ ] Pool processes notify subscribers on capacity release (PubSub broadcast to department scheduler topics)

### Testability
- [ ] Accepts `:gate` option: `:open` (default) or `:closed` (blocks all checkouts for testing)
- [ ] `open_gate/1` and `close_gate/1` functions for test control
- [ ] Supports `start_supervised/1` for isolated test instances

### Future Extension
- [ ] Resource key namespace design allows future per-City or per-Department scoping (e.g., `"city:<id>:ollama:llama3.2"`) without changing the API contract

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/cities/heartbeat.ex           # GenServer pattern
lib/lemmings_os/lemming_instances/pubsub.ex   # Task 09 broadcast helpers
```

### Patterns to Follow
- GenServer with injectable deps
- Registry-based naming
- Simple internal state: `%{current: 0, max: capacity, gate: :open}`
- Process monitoring for checkout holders (to reclaim on crash)

### Constraints
- The pool is global per resource key -- not per Department, not per City
- Pool must handle holder process crashes by releasing the token (via `Process.monitor/1`)
- The pool does NOT know about instances or Departments -- it only knows resource keys and counts
- Do not use `:atomics` or `:counters` in v1 -- a simple GenServer counter is sufficient for the expected load

## Execution Instructions

### For the Agent
1. Read plan.md Frozen Contract #8 thoroughly.
2. Create `lib/lemmings_os/lemming_instances/resource_pool.ex`.
3. Implement counter-based semaphore with checkout/checkin API.
4. Key by resource key string, not Department/City.
5. Monitor checkout holders to reclaim on crash.
6. Implement `:gate` option for test control.
7. Add `@doc` and `@spec` to all public functions.

### For the Human Reviewer
1. Verify pool is keyed by resource key, not Department/City.
2. Verify checkout holder monitoring for crash reclamation.
3. Verify default capacity is 1.
4. Verify test gate mechanism works.
5. Verify counter never goes negative.

---

## Execution Summary
*[Filled by executing agent after completion]*

### Work Performed
- Implemented `LemmingsOs.LemmingInstances.ResourcePool` as a small GenServer semaphore keyed by resource key.
- Added the public API required by the task: `via_name/1`, `start_link/1`, `child_spec/1`, `checkout/1`, `checkin/1`, `status/1`, `available?/1`, `open_gate/1`, and `close_gate/1`.
- Added holder monitoring with `Process.monitor/1` so crashed callers release capacity automatically.
- Added the `:gate` test control and kept `start_supervised/1` support via a normal child spec.
- Kept the read-only queries side-effect free by resolving an already-running pool before falling back to defaults.
- Added doctests for all public functions and kept the implementation dependency-injectable for PubSub behavior.

### Outputs Created
- `lib/lemmings_os/lemming_instances/resource_pool.ex`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| The runtime app will eventually start `LemmingsOs.LemmingInstances.PoolRegistry` | The pool already exposes Registry-based naming, and the later application supervisor task owns wiring global registries into boot. |
| Read-only queries should not auto-create a pool process | This keeps `status/1` and `available?/1` free of side effects while preserving on-demand startup for checkout. |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Use a GenServer counter with holder monitoring | ETS counters or a lock-based approach | The task explicitly calls for a simple v1 semaphore and process monitoring for crash reclamation. |
| Broadcast a capacity-release PubSub event from the pool | Make the scheduler poll continuously | Event-driven release notification keeps the scheduler responsive without adding busy polling. |
| Keep the API small and return `:ok` / `{:error, :at_capacity}` | Add richer queueing semantics | The first slice only needs admission control, not reservation or waitlisting. |

### Blockers Encountered
- None.

### Questions for Human
1. None.

### Ready for Next Task
- [x] All outputs complete
- [x] Summary documented
- [x] Questions listed (if any)

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
