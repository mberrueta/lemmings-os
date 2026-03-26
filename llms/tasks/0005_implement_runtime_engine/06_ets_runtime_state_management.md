# Task 06: ETS Runtime State Management

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for ETS table design and runtime state management.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and implement the `LemmingsOs.LemmingInstances.EtsStore` module for ephemeral runtime state management.

## Objective
Create the ETS store module at `lib/lemmings_os/lemming_instances/ets_store.ex`. This module manages a single named ETS table (`:lemming_instance_runtime`) that holds ephemeral runtime state for all active LemmingInstance executors. The state includes the work item queue, current item, retry state, accumulated conversation context, status, and temporal markers. This module provides the read/write API that the Executor and DepartmentScheduler use.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contract #5 (ETS key schema), #9 (Persistence split)

## Expected Outputs

- [ ] `lib/lemmings_os/lemming_instances/ets_store.ex` - ETS store module

## Acceptance Criteria

### Table Setup
- [ ] Named ETS table: `:lemming_instance_runtime`
- [ ] Table type: `:set` (one entry per instance)
- [ ] Table options: `:public`, `:named_table`, `read_concurrency: true`
- [ ] Table is created at application startup (or lazily on first use)
- [ ] `init_table/0` function for explicit creation

### Key Schema (Frozen Contract #5)
- [ ] Key: `{instance_id}` where `instance_id` is a binary UUID string
- [ ] Value is a map with:
  - `department_id` -- binary_id, required for scheduler filtering
  - `queue` -- `:queue.queue()` (Erlang FIFO queue)
  - `current_item` -- work item map or `nil`
  - `retry_count` -- non-neg integer
  - `max_retries` -- integer (default 3, from config)
  - `context_messages` -- list of maps (accumulated conversation context)
  - `status` -- atom (`:created`, `:queued`, `:processing`, `:retrying`, `:idle`, `:failed`, `:expired`)
  - `started_at` -- `DateTime.t()`
  - `last_activity_at` -- `DateTime.t()`

### API Surface
- [ ] `init_table/0` -- Creates the ETS table if it does not exist
- [ ] `put/2` -- Inserts or replaces an entry: `put(instance_id, state_map)`
- [ ] `get/1` -- Returns `{:ok, state_map}` or `{:error, :not_found}`
- [ ] `update/2` -- Updates specific keys in an existing entry
- [ ] `delete/1` -- Removes an entry
- [ ] `list_by_status/2` -- Returns entries matching a given status within a Department scope using `department_id` stored in the ETS value map
- [ ] `enqueue_work_item/2` -- Adds a work item to the instance's queue
- [ ] `dequeue_work_item/1` -- Pops the next work item from the queue
- [ ] `get_queue_depth/1` -- Returns the number of items in the queue

### Work Item Structure
- [ ] Work items are maps with: `id` (UUID), `content` (string), `origin` (`:user`), `inserted_at` (DateTime)

### Cleanup
- [ ] `cleanup/1` -- Removes ETS entry for an instance (called on expiry/failure)

## Technical Notes

### Relevant Code Locations
```
# No existing ETS module in the project -- this is the first
lib/lemmings_os/worlds/cache.ex  # Existing ETS-like cache pattern (if any)
```

### Patterns to Follow
- Module-based API wrapping raw ETS operations
- All functions are pure wrappers -- no GenServer needed for the ETS module itself
- The ETS table is owned by the application supervisor (or a dedicated owner process)

### Constraints
- ETS state is ephemeral -- lost on node restart
- The ETS module does NOT own business logic -- it is a storage API
- Status in ETS is the canonical runtime status; DB status is synced on transitions by the Executor
- Do not store secrets in ETS (config snapshot secrets are never stored per ADR-0008)
- `department_id` must be present in the ETS value map so the scheduler can filter by department

## Execution Instructions

### For the Agent
1. Read plan.md Frozen Contract #5 and #9 for the ETS schema and persistence split.
2. Create `lib/lemmings_os/lemming_instances/ets_store.ex`.
3. Implement the named ETS table with all API functions.
4. Include `department_id` in the value map for scheduler queries.
5. Use `:queue` module for FIFO queue operations.
6. Add `@doc` and `@spec` to all public functions.

### For the Human Reviewer
1. Verify ETS table name matches `:lemming_instance_runtime`.
2. Verify key schema matches Frozen Contract #5.
3. Verify work item structure includes `id`, `content`, `origin`, `inserted_at`.
4. Verify queue operations use Erlang `:queue` module.
5. Verify cleanup function exists for expiry/failure paths.

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
