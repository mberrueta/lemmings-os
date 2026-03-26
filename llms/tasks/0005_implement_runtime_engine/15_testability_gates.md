# Task 15: Testability Gates

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for Elixir/Phoenix.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and add testability gates to the executor, scheduler, and resource pool so tests can control admission, hold work in stable states, and release execution deterministically.

## Objective
Make the runtime engine deterministically testable by adding controllable gates to three components: (1) the DepartmentScheduler's admission logic, (2) the resource pool's capacity control, and (3) the executor's dependency injection points. Follow the `Heartbeat` pattern of injectable deps and `:manual` mode.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contract #17 (Testability gate)
- [ ] `lib/lemmings_os/cities/heartbeat.ex` - Injectable deps and `:manual` interval pattern
- [ ] Task 03 output (executor GenServer) - Current init options, dependency points
- [ ] Task 04 output (DepartmentScheduler) - Current init options, admission logic
- [ ] Task 05 output (resource pool) - Current capacity control interface

## Expected Outputs

- [ ] Modified `lib/lemmings_os/lemming_instances/executor.ex` - Injectable deps (model runtime, now_fn, etc.)
- [ ] Modified `lib/lemmings_os/lemming_instances/department_scheduler.ex` - `:admission_mode` option (`:auto` | `:manual`)
- [ ] Modified `lib/lemmings_os/lemming_instances/resource_pool.ex` - Injectable pool gate or test-friendly capacity override
- [ ] Documentation in `@moduledoc` or `@doc` for each gate explaining test usage

## Acceptance Criteria

### DepartmentScheduler Admission Gate
- [ ] Accepts `:admission_mode` option: `:auto` (default, production) or `:manual` (tests)
- [ ] In `:auto` mode, scheduler admits instances as capacity allows (normal behavior)
- [ ] In `:manual` mode, scheduler queues instances but does NOT admit them until explicitly told
- [ ] Exposes a function to manually admit the next eligible instance (e.g., `admit_next/1`)
- [ ] Tests can: start scheduler in `:manual` mode, enqueue work, assert `queued` state, call `admit_next/1`, assert `processing` state

### Resource Pool Gate
- [ ] Pool capacity can be set to specific values in tests (e.g., capacity of 0 to block all, capacity of 1 for serialization)
- [ ] Pool keyed by **resource key** (e.g., `ollama:llama3.2`), not by Department or City
- [ ] Tests can acquire and release pool slots explicitly
- [ ] Pool state is inspectable (current usage, capacity) for test assertions

### Executor Injectable Dependencies
- [ ] Model execution boundary is injectable (e.g., `:model_runtime` option defaulting to `LemmingsOs.ModelRuntime`)
- [ ] Tests can inject a mock/stub model runtime or provider module that returns controlled responses
- [ ] Time/clock function is injectable (`:now_fn` option) for deterministic timeout testing
- [ ] Idle timeout behavior can be controlled (`:idle_timeout` option or `:manual` idle mode)
- [ ] All injectable deps follow the `Heartbeat` pattern: keyword opts in `start_link/1`, stored in GenServer state

### General
- [ ] All gates default to production behavior when no test options are passed
- [ ] Gates do not affect the public API contracts -- only internal dispatch behavior
- [ ] Each gate is documented with usage examples for test authors

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/cities/heartbeat.ex                    # Injectable deps pattern to follow
lib/lemmings_os/lemming_instances/executor.ex           # Task 03 output
lib/lemmings_os/lemming_instances/department_scheduler.ex # Task 04 output
lib/lemmings_os/lemming_instances/resource_pool.ex      # Task 05 output
```

### Heartbeat Pattern Reference
The `Heartbeat` module demonstrates the injectable dependency pattern:
```elixir
def start_link(opts \\ []) do
  GenServer.start_link(__MODULE__, opts, genserver_opts)
end

# In init/1:
state = %{
  interval_ms: Keyword.get(opts, :interval, @default_interval),
  runtime_city: Keyword.get(opts, :runtime_city, Runtime),
  cities: Keyword.get(opts, :cities, Cities),
  now_fun: Keyword.get(opts, :now_fun, &DateTime.utc_now/0),
  ...
}
```

### Constraints
- Do not break the existing public API of any process
- Gates must be opt-in via keyword options, not global config
- `:manual` mode must not leak into production (default is always `:auto`)
- Resource pool gate must use resource key API, not Department/City scoping

## Execution Instructions

### For the Agent
1. Read `heartbeat.ex` to understand the injectable deps pattern thoroughly.
2. Read Task 03, 04, 05 outputs to understand current process interfaces.
3. Add `:admission_mode` to DepartmentScheduler with `:auto`/`:manual` toggle.
4. Add `admit_next/1` public function to DepartmentScheduler for manual admission.
5. Add injectable deps to executor (`:model_runtime`, `:now_fn`, `:idle_timeout`).
6. Add test-friendly capacity control to resource pool.
7. Document each gate in `@doc` blocks.

### For the Human Reviewer
1. Verify all gates default to production behavior.
2. Verify `:manual` admission mode blocks admission until explicit call.
3. Verify executor deps are injectable and follow Heartbeat pattern.
4. Verify resource pool uses resource key, not Department/City.
5. Verify documentation explains test usage for each gate.
6. Verify no public API contracts are changed.

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
