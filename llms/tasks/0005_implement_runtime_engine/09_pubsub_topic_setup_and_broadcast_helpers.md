# Task 09: PubSub Topic Setup and Broadcast Helpers

## Status
- **Status**: COMPLETED
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for PubSub integration and messaging patterns.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and implement the `LemmingsOs.LemmingInstances.PubSub` module with topic helpers and broadcast functions for runtime signals.

## Objective
Create the PubSub helper module at `lib/lemmings_os/lemming_instances/pubsub.ex`. This module centralizes topic construction, subscription, and broadcast helpers for all runtime signals between Executor, DepartmentScheduler, and LiveView. It uses the existing `LemmingsOs.PubSub` Phoenix.PubSub instance.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contract #16 (PubSub topics)
- [ ] `lib/lemmings_os/application.ex` - PubSub configuration

## Expected Outputs

- [ ] `lib/lemmings_os/lemming_instances/pubsub.ex` - PubSub helper module

## Acceptance Criteria

### Topic Patterns (Frozen Contract #16)
- [ ] `scheduler_topic(department_id)` -- Returns `"department:#{department_id}:scheduler"`
- [ ] `instance_topic(instance_id)` -- Returns `"instance:#{instance_id}:status"`

### Subscribe Functions
- [ ] `subscribe_scheduler(department_id)` -- Subscribes caller to scheduler topic
- [ ] `subscribe_instance(instance_id)` -- Subscribes caller to instance status topic

### Broadcast Functions
- [ ] `broadcast_work_available(department_id)` -- Broadcasts `:work_available` on scheduler topic
- [ ] `broadcast_capacity_released(department_id)` -- Broadcasts `:capacity_released` on scheduler topic
- [ ] `broadcast_status_change(instance_id, status, metadata \\ %{})` -- Broadcasts status update on instance topic
- [ ] All broadcasts use `Phoenix.PubSub.broadcast/3` with `LemmingsOs.PubSub` as the pubsub server

### Message Shapes
- [ ] Scheduler messages: `{:work_available, %{department_id: id}}`
- [ ] Capacity messages: `{:capacity_released, %{department_id: id, resource_key: key}}`
- [ ] Status messages: `{:status_changed, %{instance_id: id, status: status, metadata: map}}`

### Module Design
- [ ] Pure helper module -- no GenServer, no state
- [ ] All functions are direct wrappers around `Phoenix.PubSub` calls
- [ ] Uses `LemmingsOs.PubSub` (already configured in application.ex)

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/application.ex  # {Phoenix.PubSub, name: LemmingsOs.PubSub}
```

### Patterns to Follow
- Simple module with `@doc` on all public functions
- Consistent message tuple shapes for pattern matching in subscribers
- Topic strings constructed via function calls, not inline string interpolation

### Constraints
- Do NOT create a new PubSub server -- use the existing `LemmingsOs.PubSub`
- Topics are runtime-scoped -- not persisted, not configurable
- Keep message payloads minimal -- only IDs and status, not full structs

## Execution Instructions

### For the Agent
1. Read plan.md Frozen Contract #16 for topic patterns.
2. Read `application.ex` to confirm PubSub server name.
3. Create `lib/lemmings_os/lemming_instances/pubsub.ex`.
4. Implement topic construction, subscribe, and broadcast functions.
5. Define consistent message tuple shapes.
6. Add `@doc` and `@spec` to all public functions.

### For the Human Reviewer
1. Verify topic patterns match Frozen Contract #16 exactly.
2. Verify `LemmingsOs.PubSub` is used (not a new PubSub server).
3. Verify message shapes are consistent tagged tuples.
4. Verify no state or GenServer -- pure helper module.

---

## Execution Summary
*Filled after implementation.*

### Work Performed
- Added `LemmingsOs.LemmingInstances.PubSub` as a stateless helper module for runtime topics, subscriptions, and broadcasts.
- Centralized the scheduler and instance topic construction behind `scheduler_topic/1` and `instance_topic/1`.
- Added broadcast helpers for `work_available`, `capacity_released`, `status_changed`, and the existing executor/scheduler admission signal.
- Wired `LemmingsOs.LemmingInstances.Executor` to use the new helper for scheduler notifications and instance status broadcasts.
- Wired `LemmingsOs.LemmingInstances.DepartmentScheduler` to use the new helper for topic subscription and admission broadcasts.
- Added focused ExUnit coverage for topic construction and PubSub payload shapes.

### Outputs Created
- `lib/lemmings_os/lemming_instances/pubsub.ex`
- `test/lemmings_os/lemming_instances/pubsub_test.exs`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| The existing `LemmingsOs.PubSub` server is sufficient for all runtime signals in v1. | The plan explicitly calls for reuse of the existing PubSub server rather than creating a new one. |
| `scheduler_admit` remains part of the runtime coordination flow between scheduler and executor. | The executor already listens for this signal, so I centralized it alongside the new helper functions to avoid leaving the runtime split across direct PubSub calls. |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Keep the helper module stateless and thin. | Introduce a GenServer or config-driven wrapper. | The task called for pure helpers only, and the runtime does not need state here. |
| Add tests around the helper module instead of only relying on downstream integration tests. | Wait for later executor/scheduler tests. | PubSub topics and payloads are a contract boundary and should be locked down early. |

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
