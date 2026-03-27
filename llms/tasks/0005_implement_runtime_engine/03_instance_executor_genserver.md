# Task 03: Instance Executor GenServer

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for OTP processes, state machines, and runtime systems.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and implement the `LemmingsOs.LemmingInstances.Executor` GenServer with per-instance FIFO queue, state machine, retry logic, and idle timeout.

## Objective
Create the Instance Executor GenServer at `lib/lemmings_os/lemming_instances/executor.ex`. Each `LemmingInstance` has exactly one Executor process. The Executor owns the instance's runtime state machine, manages the ETS-backed work item queue, delegates model execution through `LemmingsOs.ModelRuntime`, handles retry on structured output validation failure, manages idle timeout, and persists durable Messages on successful completion. It coordinates with the DepartmentScheduler via PubSub for admission control.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contracts #4 (status taxonomy), #5 (ETS key schema), #6 (retry behavior), #9 (persistence split), #10 (DETS snapshot), #11 (idle lifecycle), #13 (structured output), #14 (prompt assembly), #16 (PubSub topics)
- [ ] `lib/lemmings_os/cities/heartbeat.ex` - GenServer pattern precedent (injectable deps, manual mode)
- [ ] Task 02 output (`lemming_instances.ex`) - Context for DB operations
- [ ] Task 06 output (ETS module) - Runtime state read/write
- [ ] Task 07 output (DETS module) - Snapshot on idle
- [ ] Task 08 output (ModelRuntime boundary and Ollama provider) - Model execution
- [ ] Task 09 output (PubSub helpers) - Broadcast helpers

## Expected Outputs

- [ ] `lib/lemmings_os/lemming_instances/executor.ex` - Executor GenServer module

## Acceptance Criteria

### Process Identity
- [ ] Process name derived from instance UUID: `{:via, Registry, {LemmingsOs.LemmingInstances.ExecutorRegistry, instance_id}}`
- [ ] `start_link/1` accepts keyword opts including `:instance_id`, `:instance`, `:config_snapshot`
- [ ] `child_spec/1` compatible with DynamicSupervisor
- [ ] Injectable dependencies following Heartbeat pattern (`:context_mod`, `:ets_mod`, `:dets_mod`, `:model_mod`, `:pubsub_mod`)

### State Machine (Frozen Contract #4)
- [ ] Implements all v1 status transitions:
  - `created -> queued` (work enqueued, scheduler notified)
  - `queued -> processing` (scheduler grants admission)
  - `processing -> idle` (work item completed, queue empty)
  - `processing -> queued` (work item completed, more items in queue)
  - `processing -> retrying` (structured output validation failed)
  - `retrying -> processing` (retry attempt begins)
  - `retrying -> failed` (max retries exhausted)
  - `idle -> queued` (new work item arrives)
  - `idle -> expired` (idle timeout elapses)
- [ ] Status transitions update both ETS state and Postgres (via context)
- [ ] `started_at` is set once at process init (GenServer `init/1`), NOT at first work item
- [ ] `last_activity_at` is updated on every real runtime move

### Work Item Queue (Frozen Contract #5)
- [ ] FIFO queue stored in ETS via the ETS module (Task 06)
- [ ] Work items are maps with: `id`, `content`, `origin` (`:user`), `inserted_at`
- [ ] `enqueue_work/2` public function to add work items from external callers
- [ ] Queue does not advance while current item is retrying

### Retry Logic (Frozen Contract #6)
- [ ] Automatic retry on structured output validation failure
- [ ] Maximum attempts: 3 (from config snapshot `runtime_config`)
- [ ] Non-structured-output failures (network, provider errors) also trigger retry
- [ ] After max retries: transition to `failed`, set `stopped_at`
- [ ] Each retry includes full conversation context

### Model Execution
- [ ] Delegates to `LemmingsOs.ModelRuntime` (Task 08) for model execution
- [ ] Assembles prompt from: system message (instructions + structured output contract), conversation history (from ETS context_messages), current work item
- [ ] On valid structured response: persists assistant Message to Postgres, updates ETS context_messages
- [ ] On invalid response: increments retry count, transitions to `retrying`

### Idle Lifecycle (Frozen Contract #11)
- [ ] On queue empty after successful processing: transition to `idle`
- [ ] Start idle timer (`Process.send_after/3`) using `idle_ttl_seconds` from config snapshot
- [ ] On timer expiry: transition to `expired`, set `stopped_at`, cleanup ETS/DETS, stop process
- [ ] Timer is cancelled when new work arrives (idle -> queued)
- [ ] DETS snapshot attempted on transition to idle (via DETS module, Task 07)

### PubSub Integration (Frozen Contract #16)
- [ ] Broadcasts status changes on `"instance:#{instance_id}:status"` topic
- [ ] Notifies scheduler on `"department:#{department_id}:scheduler"` when work is enqueued
- [ ] Subscribes to scheduler admission messages

### Temporal Markers (Critical Correction)
- [ ] `inserted_at` = record creation (handled by Ecto, not executor)
- [ ] `started_at` = OTP process birth, set once in `init/1`
- [ ] `last_activity_at` = updated on every status transition, work completion, retry, idle entry
- [ ] `stopped_at` = set only on terminal outcomes (`failed`, `expired`), never on intermediate states

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/cities/heartbeat.ex           # GenServer pattern with injectable deps
lib/lemmings_os/cities/runtime.ex             # Runtime identity pattern
lib/lemmings_os/lemming_instances.ex          # Task 02 context
lib/lemmings_os/lemming_instances/ets_store.ex # Task 06 ETS module
lib/lemmings_os/lemming_instances/dets_store.ex # Task 07 DETS module
lib/lemmings_os/model_runtime.ex               # Task 08 runtime boundary
lib/lemmings_os/model_runtime/provider.ex      # Task 08 provider behaviour
lib/lemmings_os/model_runtime/providers/ollama.ex # Task 08 Ollama provider
lib/lemmings_os/lemming_instances/pubsub.ex    # Task 09 PubSub helpers
```

### Patterns to Follow
- Injectable deps via opts (`:context_mod`, `:ets_mod`, etc.) defaulting to production modules
- `start_link/1` + `child_spec/1` compatible with `start_supervised/1` in tests
- Process registration via Registry (not atom names)
- `handle_info` for timer messages and PubSub broadcasts
- `handle_call` for synchronous queries (status, queue depth)
- `handle_cast` for fire-and-forget operations (enqueue work)

### Constraints
- The Executor does NOT decide when to start processing -- it waits for scheduler admission
- The Executor does NOT manage pool tokens -- the scheduler/pool handle that
- The Executor does NOT implement provider-specific HTTP details or provider selection logic -- that belongs to `ModelRuntime`
- Process crashes should be handled by the DynamicSupervisor -- the Executor does not self-restart
- No streaming in v1 -- full response only
- `started_at` must be set at process init, not at first work item completion

## Execution Instructions

### For the Agent
1. Read the Heartbeat GenServer for the injectable deps pattern.
2. Read plan.md Frozen Contracts #4, #5, #6, #9-#14, #16 thoroughly.
3. Create `lib/lemmings_os/lemming_instances/executor.ex`.
4. Implement the full state machine with all transitions from Frozen Contract #4.
5. Set `started_at` in `init/1`, not on first work item.
6. Implement idle timer with cancellation on new work.
7. Add `@doc` and `@spec` to all public functions.

### For the Human Reviewer
1. Verify all status transitions from Frozen Contract #4 are implemented.
2. Verify `started_at` is set in `init/1`.
3. Verify idle timer is cancelled on new work arrival.
4. Verify retry logic respects max attempts from config snapshot.
5. Verify DETS snapshot is attempted on idle transition.
6. Verify PubSub broadcasts on status changes.
7. Verify injectable deps pattern matches Heartbeat convention.

---

## Execution Summary
*[Filled by executing agent after completion]*

### Work Performed
- Implemented `LemmingsOs.LemmingInstances.Executor` GenServer with FIFO queue, status transitions, retry/idle lifecycle, and PubSub notifications.
- Added injectable dependency seams for context/ETS/DETS/model/PubSub while keeping a minimal, self-contained ETS runtime table fallback.
- Added doctests for all public API functions and kept the API limited to executor lifecycle, enqueue, status, queue depth, and admission.

### Outputs Created
- `lib/lemmings_os/lemming_instances/executor.ex`

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| `config_snapshot` may contain either atom or string keys | Snapshot is stored as JSONB and may be decoded with string keys; runtime handles both. |
| `model_mod.execute/1` returns `{:ok, response}` or `{:error, reason}` | Task 08 is not implemented yet; executor uses a small, explicit expectation. |
| PubSub uses Phoenix.PubSub with `LemmingsOs.PubSub` name | Application already starts PubSub under that name; custom module can be injected later. |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Use internal ETS table fallback when `ets_mod` is not provided | Creating a Task 06 module now | Avoids expanding scope while still persisting queue/state in ETS. |
| Allow `name: nil` to skip registry naming | Forcing registry usage always | Keeps doctests and tests simple without requiring a Registry. |
| Retry immediately via a `:retry` message | Inline synchronous retry in the same callback | Preserves explicit `retrying -> processing` transition and keeps callbacks non-blocking. |

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
