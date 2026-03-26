# Task 09: PubSub Topic Setup and Broadcast Helpers

## Status
- **Status**: PENDING
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
