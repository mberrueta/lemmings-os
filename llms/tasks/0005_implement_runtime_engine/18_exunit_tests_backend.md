# Task 18: ExUnit Tests -- Backend

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`qa-elixir-test-author` - QA-driven Elixir test writer converting scenarios into ExUnit tests.

## Agent Invocation
Act as `qa-elixir-test-author` following `llms/constitution.md` and implement ExUnit tests for all backend components: schemas, context, executor, scheduler, resource pool, ETS, DETS, FIFO queue, retry logic, and idle expiry.

## Objective
Implement the backend ExUnit tests defined in the test plan (Task 17 output). Cover: schema changesets, context CRUD and timestamp/status persistence behavior, executor state machine, DepartmentScheduler dispatch, resource pool capacity, FIFO ordering, retry logic, idle timeout/expiry, ETS lifecycle, and DETS snapshot tolerance. All tests must be deterministic, DB-sandbox compatible, and use testability gates (Task 15) and factories (Task 20).

## Inputs Required

- [ ] `llms/constitution.md` - Global rules (test discipline, DB sandbox, deterministic)
- [ ] `llms/coding_styles/elixir_tests.md` - Test coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - All Acceptance Criteria and Edge Cases
- [ ] `llms/tasks/0005_implement_runtime_engine/test_plan.md` - Task 17 output (test scenarios)
- [ ] `test/lemmings_os/lemmings_test.exs` - Context test precedent
- [ ] `test/support/factory.ex` - Factory with `:lemming_instance` and `:lemming_instance_message` (Task 20 output)
- [ ] Task 02 outputs - Schemas and context under test
- [ ] Task 03 output (`executor.ex`) - Executor under test
- [ ] Task 04 output (`department_scheduler.ex`) - Scheduler under test
- [ ] Task 05 output (`resource_pool.ex`) - Pool under test
- [ ] Task 06 output (`ets_store.ex`) - ETS under test
- [ ] Task 07 output (`dets_store.ex`) - DETS under test
- [ ] Task 15 output (testability gates) - `:manual` admission, injectable deps

## Expected Outputs

- [ ] New `test/lemmings_os/lemming_instances_test.exs` - Context tests (CRUD, spawn, transitions, queries)
- [ ] New `test/lemmings_os/lemming_instances/lemming_instance_test.exs` - Schema changeset tests
- [ ] New `test/lemmings_os/lemming_instances/message_test.exs` - Message schema changeset tests
- [ ] New `test/lemmings_os/lemming_instances/executor_test.exs` - Executor OTP process tests
- [ ] New `test/lemmings_os/lemming_instances/department_scheduler_test.exs` - Scheduler OTP process tests
- [ ] New `test/lemmings_os/lemming_instances/resource_pool_test.exs` - Pool tests

## Acceptance Criteria

### Schema Tests
- [ ] `LemmingInstance` changeset validates required fields: `lemming_id`, `world_id`, `city_id`, `department_id`, `config_snapshot`
- [ ] `LemmingInstance` changeset validates status inclusion in allowed values
- [ ] `LemmingInstance` changeset validates FK constraints (lemming, world, city, department)
- [ ] `Message` changeset validates required fields: `lemming_instance_id`, `world_id`, `role`, `content`
- [ ] `Message` changeset validates role inclusion (`"user"`, `"assistant"`)
- [ ] `Message` changeset allows nullable: `provider`, `model`, `input_tokens`, `output_tokens`, `total_tokens`, `usage`

### Context Tests
- [ ] `spawn_instance/3` creates instance with `"created"` status, captures config snapshot, populates hierarchy FKs
- [ ] `spawn_instance/3` creates the first `Message` with `role = "user"` from the input text
- [ ] `Runtime.spawn_session/3` (or equivalent runtime service) orchestrates persistence + executor start + scheduler wake behind a single runtime boundary
- [ ] `list_instances/2` returns World-scoped instances with first user message preview via join
- [ ] `list_instances/2` supports filtering by status, lemming_id
- [ ] `get_instance/2` returns `{:ok, instance}` within World scope and `{:error, :not_found}` when not found or outside World scope
- [ ] `list_messages/2` returns messages in chronological order
- [ ] `update_status/3` updates temporal markers and persists status changes without centrally enforcing the runtime transition graph in v1

### Executor Tests
- [ ] Executor starts and registers via Registry with instance UUID
- [ ] Executor processes first work item through mock model runtime/provider
- [ ] FIFO: multiple enqueued items process in order
- [ ] Executor follows the valid operational transition graph from Frozen Contract #4
- [ ] Retry: invalid structured output triggers retry, retry count increments
- [ ] Retry: max retries (3) exhaustion transitions to `failed`
- [ ] Idle: queue empty after processing transitions to `idle`
- [ ] Idle timeout: configurable timeout triggers `expired` transition
- [ ] Idle timer reset: new work on idle instance cancels timer, transitions to `queued`
- [ ] Race: work arriving during expiry is handled correctly (rejected if expiry initiated)
- [ ] Injectable model runtime/provider returns controlled responses for deterministic testing
- [ ] Injectable `:now_fn` controls time for timeout testing

### Scheduler Tests
- [ ] `:manual` mode: instances queue but do not auto-admit
- [ ] `:manual` mode: `admit_next/1` admits oldest eligible instance
- [ ] `:auto` mode: instances admitted when pool has capacity
- [ ] Oldest-eligible-first: given multiple queued instances, oldest is admitted first
- [ ] Scheduler admissions preserve the valid operational transition graph (for example, `queued -> processing`)
- [ ] PubSub: scheduler responds to work announcement messages
- [ ] Pool at capacity: admission denied, instance stays queued

### Resource Pool Tests
- [ ] Acquire slot: returns `:ok` when capacity available
- [ ] Acquire slot: returns `:error` when pool exhausted
- [ ] Release slot: frees capacity
- [ ] Capacity enforcement: exactly `pool_size` concurrent slots
- [ ] Pool keyed by resource key (e.g., `ollama:llama3.2`), not Department/City
- [ ] Slot release on failure/expiry

### Test Infrastructure
- [ ] All tests use DB sandbox (`use LemmingsOs.DataCase`)
- [ ] OTP process tests use `start_supervised/1`
- [ ] Ollama HTTP calls mocked via Bypass or injectable mock client
- [ ] No timing-dependent assertions (use testability gates)
- [ ] All tests deterministic and independently runnable

## Technical Notes

### Relevant Code Locations
```
test/lemmings_os/lemmings_test.exs                    # Context test precedent
test/support/factory.ex                                # Factory with instance/message factories
lib/lemmings_os/lemming_instances/                     # All modules under test
```

### Patterns to Follow
- Follow `lemmings_test.exs` for context test structure: setup, describe blocks, factory usage
- Use `start_supervised/1` for all OTP process tests
- Use `:manual` admission mode for scheduler tests
- Use injectable model runtime/provider for executor tests (return controlled JSON responses)
- Use `Bypass` for any tests that need HTTP-level Ollama mocking
- Assert on return values and state, not on timing

### Constraints
- Tests MUST NOT hit a real Ollama server
- Tests MUST be deterministic -- no `Process.sleep` for timing
- Tests MUST use factories from Task 20, not fixture helpers
- Tests MUST use the DB sandbox (async-safe where possible)
- Follow `elixir_tests.md` coding style

## Execution Instructions

### For the Agent
1. Read `elixir_tests.md` and existing test files for patterns.
2. Read Task 17 test plan for all scenarios to implement.
3. Implement schema tests first (simplest, no process deps).
4. Implement context tests (DB-level, factory-driven).
5. Implement executor tests with injectable mock client and `:manual` admission.
6. Implement scheduler tests with `:manual` mode.
7. Implement pool tests.
8. Verify all tests pass with `mix test` (request human to run).

### For the Human Reviewer
1. Verify all test plan scenarios from Task 17 are covered.
2. Verify no real Ollama calls in tests.
3. Verify deterministic assertions (no timing deps).
4. Verify `start_supervised/1` for all OTP processes.
5. Verify factory usage (no fixtures).
6. Run `mix test` and verify green.

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
