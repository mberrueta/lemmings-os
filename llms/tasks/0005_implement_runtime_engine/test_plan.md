# Runtime Engine Test Plan

## Purpose

This document defines the test scenario and coverage plan for the runtime engine
vertical slice introduced by `0005_implement_runtime_engine`. It is the input
for:

- Task 18: backend ExUnit implementation
- Task 19: LiveView test implementation

The plan is organized by test layer and by target file so implementation can be
split into small, deterministic test units that follow the repo’s testing
guidelines.

## Test Principles

- Use `DataCase` for schema/context tests and DB-backed runtime integration.
- Use `ConnCase` + `Phoenix.LiveViewTest` for LiveView scenarios.
- Use `start_supervised!/1` for all OTP/runtime process tests.
- Avoid `Process.sleep/1`; prefer explicit testability gates, `assert_receive`,
  and synchronous APIs.
- Use World-scoped calls explicitly in all context scenarios.
- Use factories by default. Task 20 should add `:lemming_instance` and
  `:lemming_instance_message` factories to reduce boilerplate in Tasks 18/19.
- Use Bypass for HTTP-level Ollama tests. Do not hit a real Ollama instance in
  automated tests.

## Existing Coverage Snapshot

The branch already contains meaningful runtime coverage in:

- `test/lemmings_os/lemming_instances_test.exs`
- `test/lemmings_os/runtime_test.exs`
- `test/lemmings_os/lemming_instances/executor_test.exs`
- `test/lemmings_os/lemming_instances/department_scheduler_test.exs`
- `test/lemmings_os/lemming_instances/resource_pool_test.exs`
- `test/lemmings_os/lemming_instances/ets_store_test.exs`
- `test/lemmings_os/lemming_instances/dets_store_test.exs`
- `test/lemmings_os/lemming_instances/pubsub_test.exs`
- `test/lemmings_os/lemming_instances/telemetry_test.exs`
- `test/lemmings_os/model_runtime_test.exs`
- `test/lemmings_os/model_runtime/providers/ollama_test.exs`
- `test/lemmings_os_web/live/lemmings_live_runtime_test.exs`
- `test/lemmings_os_web/live/instance_live_test.exs`

Tasks 18 and 19 should treat those files as the implementation base, then fill
gaps identified in this plan rather than creating duplicate tests.

## User Story Coverage Matrix

| User Story | Required coverage | Primary file(s) |
|---|---|---|
| US-1 Spawn a LemmingInstance | context spawn, runtime spawn orchestration, spawn modal UI | `test/lemmings_os/lemming_instances_test.exs`, `test/lemmings_os/runtime_test.exs`, `test/lemmings_os_web/live/lemmings_live_runtime_test.exs` |
| US-2 View instance session with live status | session page render, PubSub-driven status refresh, chronological transcript | `test/lemmings_os_web/live/instance_live_test.exs` |
| US-3 Send additional requests to idle instance | context enqueue, LiveView input enable/disable, transcript append | `test/lemmings_os/lemming_instances_test.exs`, `test/lemmings_os_web/live/instance_live_test.exs` |
| US-4 Retry on invalid output | executor retry path, retry status rendering, retry exhaustion | `test/lemmings_os/lemming_instances/executor_test.exs`, `test/lemmings_os_web/live/instance_live_test.exs` |
| US-5 Idle expiry | executor idle timer, expiry cleanup, expired UI | `test/lemmings_os/lemming_instances/executor_test.exs`, `test/lemmings_os_web/live/instance_live_test.exs` |
| US-6 Resource-aware scheduling | scheduler admission, pool exhaustion, FIFO/oldest-first | `test/lemmings_os/lemming_instances/department_scheduler_test.exs`, `test/lemmings_os/lemming_instances/resource_pool_test.exs` |
| US-7 View active instances on detail page | list query, first user message preview join, live updates | `test/lemmings_os/lemming_instances_test.exs`, `test/lemmings_os_web/live/lemmings_live_runtime_test.exs` |
| US-8 Failure is visible and terminal | executor terminal failure, input disabled, failed status display | `test/lemmings_os/lemming_instances/executor_test.exs`, `test/lemmings_os_web/live/instance_live_test.exs` |

## Planned Test File Layout

### Backend

- `test/lemmings_os/lemming_instances_test.exs`
  Context and schema-adjacent integration tests.
- `test/lemmings_os/runtime_test.exs`
  Runtime orchestration boundary tests.
- `test/lemmings_os/lemming_instances/executor_test.exs`
  Executor state machine and runtime behavior.
- `test/lemmings_os/lemming_instances/department_scheduler_test.exs`
  Scheduler selection/admission behavior.
- `test/lemmings_os/lemming_instances/resource_pool_test.exs`
  Pool concurrency and gating behavior.
- `test/lemmings_os/lemming_instances/ets_store_test.exs`
  ETS persistence contract.
- `test/lemmings_os/lemming_instances/dets_store_test.exs`
  DETS snapshot behavior and failure tolerance.
- `test/lemmings_os/model_runtime_test.exs`
  ModelRuntime boundary and provider selection.
- `test/lemmings_os/model_runtime/providers/ollama_test.exs`
  Ollama HTTP contract and structured output parsing.

### Frontend

- `test/lemmings_os_web/live/lemmings_live_runtime_test.exs`
  Spawn CTA, modal, and active instance list.
- `test/lemmings_os_web/live/instance_live_test.exs`
  Session page status, transcript, and follow-up flow.

## Scenario Catalog

Scenario IDs are grouped by layer so Tasks 18 and 19 can implement and review
them incrementally.

### A. Schema / Changeset Scenarios

Target file: `test/lemmings_os/lemming_instances_test.exs`

- `SCH-001` `LemmingInstance` accepts valid attrs with `lemming_id`, `world_id`,
  `city_id`, `department_id`, `status`, and `config_snapshot`.
- `SCH-002` `LemmingInstance` rejects missing required fields.
- `SCH-003` `LemmingInstance` rejects invalid runtime status values.
- `SCH-004` `LemmingInstance` accepts nullable `started_at`, `stopped_at`, and
  `last_activity_at`.
- `SCH-005` `LemmingInstance` enforces FK constraints for world/city/department/lemming.
- `SCH-006` `Message` accepts valid attrs for `user` role.
- `SCH-007` `Message` accepts valid attrs for `assistant` role with provider,
  model, token, `total_tokens`, and `usage`.
- `SCH-008` `Message` rejects missing required fields.
- `SCH-009` `Message` rejects invalid role values.
- `SCH-010` `Message` accepts nullable token fields and nullable `usage`.

### B. Context Integration Scenarios

Target file: `test/lemmings_os/lemming_instances_test.exs`

- `CTX-001` `spawn_instance/2` persists a created instance and the first user message.
- `CTX-002` `spawn_instance/2` snapshots resolved configuration from the hierarchy.
- `CTX-003` `spawn_instance/2` copies `world_id`, `city_id`, `department_id`, and `lemming_id`.
- `CTX-004` `spawn_instance/2` rejects non-active lemmings.
- `CTX-005` `list_instances/2` is World-scoped.
- `CTX-006` `list_instances/2` filters by `status`.
- `CTX-007` `list_instances/2` filters by `lemming_id`.
- `CTX-008` `list_instances/2` preloads/join-loads the first user message preview.
- `CTX-009` `list_instances/2` orders newest/oldest consistently for UI consumers.
- `CTX-010` `get_instance/2` returns `{:ok, instance}` in scope.
- `CTX-011` `get_instance/2` returns `{:error, :not_found}` out of scope or missing.
- `CTX-012` `list_messages/1` returns chronological transcript order.
- `CTX-013` `update_status/3` persists status changes and temporal markers.
- `CTX-014` `update_status/3` allows runtime-driven updates without centrally enforcing the entire state graph.
- `CTX-015` `enqueue_work/3` adds work for `idle` instances.
- `CTX-016` `enqueue_work/3` rejects `failed` instances.
- `CTX-017` `enqueue_work/3` rejects `expired` instances.
- `CTX-018` `enqueue_work/3` persists the follow-up user message before dispatch.
- `CTX-019` `topology_summary/1` reports runtime counts accurately if exposed to UI/runtime dashboards.

### C. Runtime Boundary Scenarios

Target file: `test/lemmings_os/runtime_test.exs`

- `RUN-001` `Runtime.spawn_session/3` is the single runtime boundary used by the web layer.
- `RUN-002` `Runtime.spawn_session/3` persists the instance and message, then starts scheduler and executor.
- `RUN-003` `Runtime.spawn_session/3` enqueues the first request onto the executor.
- `RUN-004` `Runtime.spawn_session/3` returns the created instance or instance id in a stable tuple contract.
- `RUN-005` `Runtime.retry_session/2` retries a failed live executor without creating a new instance.
- `RUN-006` `Runtime.retry_session/2` recovers a failed instance when the executor is gone.
- `RUN-007` `recover_created_sessions/1` reattaches recoverable persisted instances.
- `RUN-008` `recover_created_sessions/1` respects the configured recovery limit.
- `RUN-009` runtime startup gating disables automatic process startup in test config.

### D. Executor OTP Scenarios

Target file: `test/lemmings_os/lemming_instances/executor_test.exs`

- `EXE-001` executor starts with `started_at` set and initial runtime state persisted to ETS.
- `EXE-002` enqueueing work from `created` transitions to `queued`.
- `EXE-003` scheduler admission transitions `queued -> processing`.
- `EXE-004` successful processing persists assistant message and transitions `processing -> idle`.
- `EXE-005` when more queued items exist, successful processing transitions `processing -> queued`.
- `EXE-006` queue ordering is FIFO across multiple work items.
- `EXE-007` invalid model output or provider failure transitions `processing -> retrying`.
- `EXE-008` retry resumes `retrying -> processing`.
- `EXE-009` retry exhaustion transitions `retrying -> failed`.
- `EXE-010` `retry/1` requeues failed work on a live executor.
- `EXE-011` idle transition writes a DETS snapshot.
- `EXE-012` idle timeout expires the instance and cleans up runtime state.
- `EXE-013` idle timer is cancelled/reset when new work arrives before expiry.
- `EXE-014` expired executor cleans ETS/DETS state and releases pool capacity.
- `EXE-015` terminal instances ignore newly enqueued work.
- `EXE-016` model timeout produces deterministic failure behavior.
- `EXE-017` model runtime is injectable through `:model_mod`.
- `EXE-018` clock is injectable through `:now_fun`.
- `EXE-019` idle timeout is controllable through `:idle_timeout_ms`.
- `EXE-020` `load_context_messages` recovery mode rehydrates transcript context correctly.
- `EXE-021` executor emits status PubSub updates for all visible runtime states.
- `EXE-022` executor emits telemetry for `started`, `queued`, `processing`,
  `retrying`, `idle`, `failed`, and `expired`.

### E. Scheduler OTP Scenarios

Target file: `test/lemmings_os/lemming_instances/department_scheduler_test.exs`

- `SCHD-001` scheduler process registers by department id.
- `SCHD-002` `oldest_eligible_first/1` sorts by oldest queued work item.
- `SCHD-003` `:auto` mode reacts to `work_available` PubSub signals.
- `SCHD-004` `:auto` mode reacts to `capacity_released` PubSub signals.
- `SCHD-005` `:manual` mode does not auto-admit until `admit_next/1` is called.
- `SCHD-006` `admit_next/1` grants admission to the next eligible instance only.
- `SCHD-007` scheduler denies admission when pool capacity is exhausted.
- `SCHD-008` scheduler skips candidates without resource key/config snapshot.
- `SCHD-009` scheduler skips candidates whose executor is unavailable.
- `SCHD-010` scheduler emits admission-granted telemetry.
- `SCHD-011` scheduler emits admission-denied telemetry on pool exhaustion.
- `SCHD-012` scheduler snapshot API reports queued ids and admission mode accurately.

### F. Resource Pool Scenarios

Target file: `test/lemmings_os/lemming_instances/resource_pool_test.exs`

- `POOL-001` pool registers by resource key, not department/city.
- `POOL-002` checkout increments usage and checkin decrements it.
- `POOL-003` configured capacity of `1` serializes access.
- `POOL-004` capacity override can be set explicitly in tests.
- `POOL-005` closed gate blocks checkouts.
- `POOL-006` open gate re-enables checkouts.
- `POOL-007` holder crash automatically releases capacity.
- `POOL-008` checkout by resource key lazily starts the pool under the pool supervisor.
- `POOL-009` pool status and snapshot APIs expose current/max usage for assertions.
- `POOL-010` pool emits `acquired`, `released`, and `exhausted` telemetry events.

### G. ETS / DETS Scenarios

Target files:

- `test/lemmings_os/lemming_instances/ets_store_test.exs`
- `test/lemmings_os/lemming_instances/dets_store_test.exs`

- `STORE-001` ETS table is initialized by the long-lived owner.
- `STORE-002` ETS `put/read/delete/list_by_status` preserve runtime fields used by scheduler/executor.
- `STORE-003` ETS entries survive executor restarts because the table owner outlives executors.
- `STORE-004` DETS `snapshot/2` stores idle runtime state.
- `STORE-005` DETS `read/1` returns the stored snapshot.
- `STORE-006` DETS `delete/1` removes the snapshot.
- `STORE-007` DETS snapshot failures return `{:error, reason}` without crashing the caller.
- `STORE-008` DETS emits `snapshot_written` and `snapshot_failed` telemetry.

### H. Model Runtime / Provider Scenarios

Target files:

- `test/lemmings_os/model_runtime_test.exs`
- `test/lemmings_os/model_runtime/providers/ollama_test.exs`

- `MODEL-001` ModelRuntime selects the configured provider module.
- `MODEL-002` ModelRuntime rejects missing model/provider config.
- `MODEL-003` Ollama provider performs HTTP requests through `Req`.
- `MODEL-004` Ollama provider parses valid structured output into the response struct.
- `MODEL-005` Ollama provider normalizes non-200 responses into safe domain errors.
- `MODEL-006` Ollama provider normalizes network failures and timeouts.
- `MODEL-007` Ollama provider tests run through Bypass only.

### I. Spawn Flow LiveView Scenarios

Target file: `test/lemmings_os_web/live/lemmings_live_runtime_test.exs`

- `LV-SPAWN-001` Spawn CTA is visible for active lemmings.
- `LV-SPAWN-002` Spawn CTA is hidden or disabled for draft lemmings.
- `LV-SPAWN-003` Spawn CTA is hidden or disabled for archived lemmings.
- `LV-SPAWN-004` clicking Spawn opens the modal.
- `LV-SPAWN-005` confirm is disabled for empty input.
- `LV-SPAWN-006` successful submit calls the runtime service boundary once and navigates to the session page.
- `LV-SPAWN-007` failed submit keeps the modal open and preserves input.
- `LV-SPAWN-008` detail page active-instances list renders empty state.
- `LV-SPAWN-009` active-instances list shows status badge, first user message preview, and creation time.
- `LV-SPAWN-010` instance preview comes from the earliest `Message` row, not a denormalized instance column.
- `LV-SPAWN-011` active-instances list updates from PubSub without full-page reload.

### J. Session Page LiveView Scenarios

Target file: `test/lemmings_os_web/live/instance_live_test.exs`

- `LV-SESSION-001` valid instance id renders the session page.
- `LV-SESSION-002` invalid instance id renders not-found state.
- `LV-SESSION-003` `created` status renders the starting state.
- `LV-SESSION-004` `queued` status renders waiting-for-capacity state.
- `LV-SESSION-005` `processing` status renders processing state and disables follow-up input.
- `LV-SESSION-006` `retrying` status renders warning copy with attempt information.
- `LV-SESSION-007` `idle` status enables follow-up input.
- `LV-SESSION-008` `failed` status disables follow-up input and shows failure context.
- `LV-SESSION-009` `expired` status disables follow-up input and shows expired state.
- `LV-SESSION-010` transcript renders messages chronologically.
- `LV-SESSION-011` user and assistant messages render distinct visual treatments.
- `LV-SESSION-012` assistant metadata renders provider/model/token data when present.
- `LV-SESSION-013` assistant metadata renders `total_tokens` and `usage` when present.
- `LV-SESSION-014` follow-up submit appends a new user message and clears the form on success.
- `LV-SESSION-015` follow-up submit is blocked for non-idle statuses.
- `LV-SESSION-016` status PubSub updates patch the UI without reload.
- `LV-SESSION-017` transcript PubSub updates append new messages without reload.
- `LV-SESSION-018` retry action for failed instances behaves according to the runtime service contract, if the UI exposes it.

## Edge Case Mapping

### Spawn Edge Cases

- `EDGE-SPAWN-001` spawning an archived lemming is rejected.
- `EDGE-SPAWN-002` spawning with blank initial request is rejected.
- `EDGE-SPAWN-003` spawn preserves the initial request only on `Message`, not on `LemmingInstance`.

### Scheduling Edge Cases

- `EDGE-SCHED-001` multiple queued instances with capacity `1` admit oldest first.
- `EDGE-SCHED-002` no executor process means the scheduler skips the candidate safely.
- `EDGE-SCHED-003` no resource key/config snapshot means the scheduler skips the candidate safely.

### Retry Edge Cases

- `EDGE-RETRY-001` network/provider failures consume retry attempts.
- `EDGE-RETRY-002` invalid structured output consumes retry attempts.
- `EDGE-RETRY-003` failure after max retries is terminal and further enqueue is rejected.

### Idle / Expiry Edge Cases

- `EDGE-IDLE-001` idle timer reset on new work prevents premature expiry.
- `EDGE-IDLE-002` expiry releases pool capacity if a resource key is still associated.
- `EDGE-IDLE-003` expiry cleans ETS and DETS state.

### Message Persistence Edge Cases

- `EDGE-MSG-001` user message order is preserved across initial and follow-up requests.
- `EDGE-MSG-002` assistant metadata fields remain nullable when provider usage data is absent.
- `EDGE-MSG-003` first-message preview query stays scoped to the instance/world.

### Process Safety Edge Cases

- `EDGE-PROC-001` runtime startup gate keeps registries/supervisors absent in test config until explicitly started.
- `EDGE-PROC-002` runtime ETS owner process can be started independently in tests.
- `EDGE-PROC-003` executor, scheduler, and pool use Registry naming and never dynamic atoms.

### Permission / Scope Edge Cases

- `EDGE-SCOPE-001` cross-World `get_instance/2` returns not found.
- `EDGE-SCOPE-002` cross-World `list_instances/2` never leaks rows.
- `EDGE-SCOPE-003` instance session page returns not-found UI for out-of-scope ids.

## Acceptance Criteria Mapping

Each Acceptance Criteria block from `plan.md` maps to the scenario groups below:

- US-1 Spawn a LemmingInstance:
  `CTX-001` to `CTX-004`, `RUN-001` to `RUN-004`, `LV-SPAWN-001` to `LV-SPAWN-007`, `EDGE-SPAWN-001` to `EDGE-SPAWN-003`
- US-2 View instance session with live status:
  `LV-SESSION-001` to `LV-SESSION-017`
- US-3 Send additional requests to an idle instance:
  `CTX-015` to `CTX-018`, `LV-SESSION-007`, `LV-SESSION-014`, `LV-SESSION-015`
- US-4 Retry behavior on invalid output:
  `EXE-007` to `EXE-010`, `EDGE-RETRY-001` to `EDGE-RETRY-003`
- US-5 Instance expires after idle timeout:
  `EXE-011` to `EXE-014`, `EDGE-IDLE-001` to `EDGE-IDLE-003`
- US-6 Resource-aware scheduling:
  `SCHD-003` to `SCHD-012`, `POOL-001` to `POOL-010`, `EDGE-SCHED-001` to `EDGE-SCHED-003`
- US-7 View active instances on Lemming detail:
  `CTX-005` to `CTX-009`, `LV-SPAWN-008` to `LV-SPAWN-011`, `EDGE-MSG-003`
- US-8 Instance failure is visible:
  `EXE-009`, `EXE-016`, `LV-SESSION-008`, `EDGE-RETRY-003`

## Test Infrastructure Requirements

### Factories

Task 20 should add:

- `:lemming_instance`
- `:lemming_instance_message`

Recommended default shape:

- `:lemming_instance` should build a full world/city/department/lemming chain by default.
- `:lemming_instance_message` should default to a built/inserted `:lemming_instance`.

### Bypass Usage

Use Bypass only for:

- `MODEL-003` to `MODEL-007`
- any high-level integration that intentionally exercises the HTTP provider boundary

Do not use Bypass for executor state-machine tests when an injected fake model module is sufficient.

### Testability Gates

Use the existing gates/options for deterministic runtime tests:

- scheduler `admission_mode: :manual`
- executor `model_mod: FakeModelRuntime`
- executor `now_fun: fn -> fixed_time end`
- executor `idle_timeout_ms: small_integer | nil`
- pool `gate: :open | :closed`
- pool `capacity:` or `max_capacity:`

### Manual Runtime Startup in Tests

Tests that need runtime supervisors/registries under `runtime_engine_on_startup: false`
must start them explicitly with `start_supervised!/1`:

- `ExecutorRegistry`
- `SchedulerRegistry`
- `PoolRegistry`
- `RuntimeTableOwner`
- `PoolSupervisor`
- `ExecutorSupervisor`
- `SchedulerSupervisor`

## Recommended Implementation Order

For Task 18:

1. Fill schema/context gaps in `test/lemmings_os/lemming_instances_test.exs`
2. Fill runtime orchestration gaps in `test/lemmings_os/runtime_test.exs`
3. Fill executor edge cases
4. Fill scheduler/pool edge cases
5. Fill store/provider gaps

For Task 19:

1. Finish spawn flow assertions in `test/lemmings_os_web/live/lemmings_live_runtime_test.exs`
2. Finish session page status/transcript/follow-up assertions in `test/lemmings_os_web/live/instance_live_test.exs`
3. Add explicit PubSub-driven live-update assertions last

## Known Gaps To Prioritize

Based on the current branch, the highest-value remaining additions are:

- explicit schema/changeset rejection coverage for invalid status/role values
- stronger world-scope failure coverage for `get_instance/2` and list APIs
- explicit FIFO multi-item executor coverage
- explicit idle-timer reset race coverage
- Bypass-backed provider tests that prove no real Ollama calls are needed
- stronger UI assertions around assistant token/usage metadata rendering
- explicit assertion that the spawn/follow-up web layer calls only the runtime/context boundary

## Done Criteria For Tasks 18 and 19

The backend/frontend test implementation tasks should be considered complete when:

- every scenario in this document is either implemented or explicitly waived in-task with rationale
- all runtime tests are deterministic and DB-sandbox compatible
- no test hits a real network service
- `mix test` passes
- `mix precommit` passes
- coverage report generation is documented for the final validation task
