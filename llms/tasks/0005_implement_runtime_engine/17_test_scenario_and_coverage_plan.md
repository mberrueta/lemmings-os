# Task 17: Test Scenario and Coverage Plan

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`qa-test-scenarios` - test scenario designer defining what to test without writing implementation code.

## Agent Invocation
Act as `qa-test-scenarios` following `llms/constitution.md` and design a comprehensive test scenario and coverage plan for the runtime engine feature, covering schemas, context, OTP processes, LiveView flows, and edge cases.

## Objective
Produce a detailed test plan document that defines every test scenario for the runtime engine: schema validations, context CRUD and transitions, executor state machine, scheduler dispatch, pool capacity, FIFO ordering, retry logic, idle expiry, spawn flow, session page, live status updates, and all edge cases from the spec. This plan is the input for Task 18 (backend tests) and Task 19 (LiveView tests).

## Inputs Required

- [ ] `llms/constitution.md` - Global rules (test discipline, DB sandbox, deterministic tests)
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir_tests.md` - Test coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - All User Stories, Acceptance Criteria, Edge Cases, Frozen Contracts
- [ ] `test/lemmings_os/lemmings_test.exs` - Context test precedent
- [ ] `test/lemmings_os_web/live/lemmings_live_test.exs` - LiveView test precedent
- [ ] `test/support/factory.ex` - Factory patterns (Task 20 will add instance/message factories)
- [ ] Task 10 output - Spawn flow UI
- [ ] Task 11 output - Session page UI
- [ ] Task 12 output - Follow-up input UI
- [ ] Task 22 output - ADR updates (status taxonomy documentation)

## Expected Outputs

- [ ] New `llms/tasks/0005_implement_runtime_engine/test_plan.md` - Comprehensive test scenario document

## Acceptance Criteria

### Coverage Scope
- [ ] Every User Story (US-1 through US-8) has at least one test scenario
- [ ] Every Acceptance Criterion (Given/When/Then) maps to a specific test scenario
- [ ] Every Edge Case from plan.md maps to a specific test scenario
- [ ] Scenarios are organized by test layer: unit, context integration, OTP process, LiveView

### Schema Test Scenarios
- [ ] `LemmingInstance` changeset: valid attrs, required fields, FK constraints, status values, temporal markers
- [ ] `Message` changeset: valid attrs, required fields, role values, nullable token fields, nullable `total_tokens`, nullable `usage` jsonb

### Context Test Scenarios
- [ ] `spawn_instance/3`: happy path for durable persistence, config snapshot capture, hierarchy field population, first message creation
- [ ] `Runtime.spawn_session/3` (or equivalent): orchestrates persistence + executor start + scheduler wake as a single runtime boundary
- [ ] `list_instances/2`: World-scoped, filtering by status/lemming, preload first user message preview via join
- [ ] `get_instance/2`: returns `{:ok, instance}` or `{:error, :not_found}` with World scope enforcement
- [ ] `list_messages/2`: chronological order, World scope
- [ ] `update_status/3`: updates temporal markers and persists status changes without centrally enforcing the runtime transition graph in v1
- [ ] `enqueue_work/3` (or equivalent): adds work to idle instance, rejects work for failed/expired

### OTP Process Test Scenarios
- [ ] Executor: start, initial work processing, FIFO queue ordering, retry on invalid output, max retry failure, idle timeout, idle timer reset on new work, expiry cleanup
- [ ] Executor and DepartmentScheduler: follow the valid operational transition graph from Frozen Contract #4 even though the context API does not enforce it centrally in v1
- [ ] DepartmentScheduler: admission in `:auto` mode, admission in `:manual` mode, oldest-eligible-first selection, PubSub notification handling
- [ ] Resource pool: acquire/release, capacity enforcement, pool exhaustion, slot release on failure/expiry, resource key-based keying (not Department/City)
- [ ] ETS: read/write/cleanup, table survives executor restart (owned by long-lived process)
- [ ] DETS: snapshot on idle, snapshot failure tolerance, cleanup on expiry

### LiveView Test Scenarios
- [ ] Spawn flow: modal opens, empty input prevention, successful spawn navigates to session page, spawn denied for non-active lemming
- [ ] Spawn flow web contract: LiveView calls a single runtime/application service and does not directly start executors or notify schedulers
- [ ] Session page: renders all 7 statuses correctly, transcript displays messages chronologically, user/assistant messages styled differently
- [ ] Session page: first user message from Message table (no `initial_request` column), provider/model/token display on assistant messages, `total_tokens` and `usage` jsonb render when present
- [ ] Follow-up input: enabled only for idle, disabled for other statuses, submission enqueues work, input clears after submit
- [ ] Live updates: PubSub status changes reflected without page refresh, new messages append to transcript

### Edge Case Scenarios
- [ ] All spawn edge cases from plan.md
- [ ] All scheduling edge cases from plan.md
- [ ] All retry edge cases from plan.md
- [ ] All idle/expiry edge cases from plan.md
- [ ] All message persistence edge cases from plan.md
- [ ] All process safety edge cases from plan.md
- [ ] All permission/scope edge cases from plan.md

### Test Infrastructure Notes
- [ ] Document which tests need Bypass for Ollama HTTP mocking
- [ ] Document which tests need `:manual` admission mode
- [ ] Document which tests need injectable model runtime
- [ ] Document factory requirements (`:lemming_instance`, `:lemming_instance_message` from Task 20)

## Technical Notes

### Relevant Code Locations
```
test/lemmings_os/lemmings_test.exs                    # Context test precedent
test/lemmings_os_web/live/lemmings_live_test.exs       # LiveView test precedent
test/support/factory.ex                                # Factory precedent
llms/coding_styles/elixir_tests.md                     # Test style guide
```

### Test Layer Organization
The test plan should organize scenarios into these files:
- `test/lemmings_os/lemming_instances_test.exs` - Context tests
- `test/lemmings_os/lemming_instances/executor_test.exs` - Executor OTP tests
- `test/lemmings_os/lemming_instances/department_scheduler_test.exs` - Scheduler OTP tests
- `test/lemmings_os/lemming_instances/resource_pool_test.exs` - Pool tests
- `test/lemmings_os_web/live/instance_live_test.exs` - Session page LiveView tests
- `test/lemmings_os_web/live/lemmings_live_test.exs` - Spawn flow additions to existing test file

### Constraints
- All tests must be DB sandbox compatible and deterministic
- No timing-dependent assertions -- use testability gates (Task 18)
- OTP process tests must use `start_supervised/1`
- LiveView tests use `Phoenix.LiveViewTest`
- Ollama HTTP calls must be mocked via Bypass, never hit a real server in tests

## Execution Instructions

### For the Agent
1. Read all User Stories, Acceptance Criteria, and Edge Cases from plan.md.
2. Read existing test files to understand patterns and conventions.
3. Read `elixir_tests.md` for test coding style.
4. Organize scenarios by test layer (unit, context, OTP, LiveView).
5. Map every AC and edge case to a specific scenario.
6. Document test infrastructure needs (Bypass, gates, factories).
7. Output the plan as `llms/tasks/0005_implement_runtime_engine/test_plan.md`.

### For the Human Reviewer
1. Verify every User Story has test coverage.
2. Verify every Acceptance Criterion maps to a scenario.
3. Verify every Edge Case maps to a scenario.
4. Verify test infrastructure needs are documented.
5. Verify test file organization follows project conventions.
6. Verify scenarios are deterministic (no timing dependencies).

---

## Execution Summary
Task completed. A concrete scenario and coverage plan now exists for the runtime engine backend and LiveView test layers.

### Work Performed
- Reviewed the runtime engine plan’s User Stories, Acceptance Criteria, and Edge Case sections.
- Reviewed the repo’s test style guide, context test precedent, LiveView test precedent, and current runtime test inventory.
- Produced [llms/tasks/0005_implement_runtime_engine/test_plan.md](/mnt/data4/matt/code/personal_stuffs/lemmings-os/llms/tasks/0005_implement_runtime_engine/test_plan.md) with scenario IDs, test-layer organization, User Story mapping, edge-case coverage, infrastructure requirements, and recommended implementation order for Tasks 18 and 19.
- Included an explicit existing-coverage snapshot so Tasks 18 and 19 extend the current runtime tests instead of duplicating them.

### Outputs Created
- [llms/tasks/0005_implement_runtime_engine/test_plan.md](/mnt/data4/matt/code/personal_stuffs/lemmings-os/llms/tasks/0005_implement_runtime_engine/test_plan.md)
- Updated [llms/tasks/0005_implement_runtime_engine/17_test_scenario_and_coverage_plan.md](/mnt/data4/matt/code/personal_stuffs/lemmings-os/llms/tasks/0005_implement_runtime_engine/17_test_scenario_and_coverage_plan.md)

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
- Tasks 18 and 19 should build on the runtime tests already present in the branch instead of creating parallel duplicate files. | The repository already has substantial runtime coverage in the expected target areas, so the plan should direct completion work rather than ignore existing assets. |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
- Organized the plan by both scenario layer and target test file. | A purely requirement-based checklist without file mapping. | The task explicitly calls out file organization, and mapping scenarios to files makes follow-on implementation materially easier. |
- Included a “Known Gaps To Prioritize” section. | Only listing comprehensive scenarios. | Tasks 18 and 19 need a practical execution order, not just exhaustive scope coverage. |

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
