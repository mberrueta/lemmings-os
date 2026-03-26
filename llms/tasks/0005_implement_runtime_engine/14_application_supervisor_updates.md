# Task 14: Runtime Service and Application Supervisor Updates

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for Elixir/Phoenix.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and implement the runtime spawn service plus update `LemmingsOs.Application` to supervise the runtime engine processes: DynamicSupervisor for executors, ETS table owner, and DepartmentScheduler startup.

## Objective
Wire the new runtime engine OTP processes into the application supervision tree and expose a single runtime/application spawn entrypoint for the web layer. This includes: (1) a `LemmingsOs.Runtime` module with `spawn_session/3` (or equivalent) that persists state, starts the executor, wakes the scheduler if needed, and returns the new instance ID, (2) a `DynamicSupervisor` for instance executor GenServers, (3) a `Registry` for executor process naming, (4) the ETS runtime state table owner process, (5) the resource pool process(es), and (6) conditional startup gating (similar to `runtime_city_heartbeat_child/0`) so tests can disable runtime processes. DepartmentSchedulers are started on-demand (not at application boot), but their DynamicSupervisor must be registered.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contracts #5 (ETS key schema), #7 (DepartmentScheduler), #8 (Resource pool), #17 (Testability)
- [ ] `lib/lemmings_os/application.ex` - Current supervisor tree
- [ ] Task 02 output (`lemming_instances.ex`) - Durable spawn persistence API
- [ ] Task 03 output (executor GenServer) - Process start requirements, naming convention
- [ ] Task 04 output (DepartmentScheduler) - Process start requirements
- [ ] Task 05 output (resource pool) - Pool process requirements

## Expected Outputs

- [ ] Modified `lib/lemmings_os/application.ex` - Updated supervision tree with runtime engine children
- [ ] New `lib/lemmings_os/runtime.ex` (or equivalent) - Runtime/application spawn service
- [ ] Possibly new `lib/lemmings_os/lemming_instances/instance_supervisor.ex` - DynamicSupervisor wrapper if needed

## Acceptance Criteria

### Runtime/Application Spawn Service
- [ ] `LemmingsOs.Runtime.spawn_session/3` (or equivalent) is the single entrypoint used by LiveView to spawn a session
- [ ] The runtime service persists the `LemmingInstance` and first `Message` through `LemmingsOs.LemmingInstances`
- [ ] The runtime service starts the executor process via the runtime supervisor infrastructure
- [ ] The runtime service wakes or notifies the DepartmentScheduler if needed
- [ ] The runtime service returns the created `instance_id` (or created instance struct) to the caller
- [ ] Web-layer callers do not directly interact with `DynamicSupervisor`, executor modules, or scheduler PubSub topics

### Supervision Tree
- [ ] `DynamicSupervisor` for instance executors is started as a named child (e.g., `LemmingsOs.LemmingInstances.ExecutorSupervisor`)
- [ ] `DynamicSupervisor` for DepartmentSchedulers is started as a named child (e.g., `LemmingsOs.LemmingInstances.SchedulerSupervisor`)
- [ ] `Registry` for executor process naming is started (e.g., `LemmingsOs.LemmingInstances.ExecutorRegistry`)
- [ ] ETS table `:lemming_instance_runtime` is created by a long-lived owner process (not by individual executors)
- [ ] Resource pool process(es) are started or startable on demand

### Startup Gating
- [ ] Runtime engine children are conditionally started based on application config (similar to `runtime_city_heartbeat_child/0` pattern)
- [ ] Config key: `Application.get_env(:lemmings_os, :runtime_engine_on_startup, true)`
- [ ] When disabled (e.g., in test config), no runtime processes start
- [ ] Tests that need runtime processes use `start_supervised/1` explicitly

### Boot Order
- [ ] Runtime engine children start **after** `LemmingsOs.Repo` and `Phoenix.PubSub` (both are already in the tree)
- [ ] Runtime engine children start **before** `LemmingsOsWeb.Endpoint`
- [ ] Supervision strategy: `:one_for_one` (existing) is acceptable; individual runtime process crashes should not cascade

### Resource Pool Keying
- [ ] Resource pool is keyed by **resource key** (e.g., `ollama:llama3.2`), not by Department or City
- [ ] The pool process naming must support multiple resource keys (one pool per active key)

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/application.ex              # Current supervisor tree
lib/lemmings_os/cities/heartbeat.ex         # Conditional startup pattern to follow
lib/lemmings_os/lemming_instances/           # Task 03, 04, 05 outputs
```

### Patterns to Follow
- Follow `runtime_city_heartbeat_child/0` pattern for conditional startup
- Use `{DynamicSupervisor, name: ..., strategy: :one_for_one}` for executor supervisor
- Use `{Registry, keys: :unique, name: ...}` for executor registry
- ETS table owner can be a simple GenServer that creates the table in `init/1` and holds it alive

### Constraints
- Do not start DepartmentSchedulers at boot -- they are started on-demand when instances are spawned in a Department
- Do not start resource pools for specific resource keys at boot -- they are started on-demand when first needed
- The DynamicSupervisors and Registry MUST be available at boot so on-demand starts can use them
- Process naming must use UUIDs via Registry, never dynamic atoms
- Keep web-triggered spawn orchestration out of LiveView; it belongs in the runtime/application service

## Execution Instructions

### For the Agent
1. Read `application.ex` thoroughly to understand current tree structure.
2. Read Task 03, 04, 05 outputs to understand process requirements.
3. Create the runtime/application spawn service (`LemmingsOs.Runtime.spawn_session/3` or equivalent).
4. Add runtime engine children to the supervision tree with conditional startup.
5. Create ETS table owner process if not already handled by Task 06.
6. Ensure boot order is correct (after Repo/PubSub, before Endpoint).
7. Add the config gate and document the test config setting.

### For the Human Reviewer
1. Verify the runtime/application spawn service is the single entrypoint used by the web layer.
2. Verify DynamicSupervisors are named and started correctly.
3. Verify Registry is configured for unique keys.
4. Verify conditional startup gate works (set config to false, verify no runtime processes).
5. Verify boot order is correct.
6. Verify ETS table ownership is handled by a long-lived process.
7. Verify resource pool uses resource key (e.g., `ollama:llama3.2`), not Department/City.
8. Add `config :lemmings_os, runtime_engine_on_startup: false` to `config/test.exs` if needed.

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
