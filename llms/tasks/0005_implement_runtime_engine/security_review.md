# Runtime Engine Security and Performance Review

## Summary
- The branch delivers the intended runtime slice and the audited runtime-focused tests pass locally.
- The main merge risk is not style or missing plumbing; it is a set of runtime edge cases where work or state can be lost or exposed.
- I found one merge-blocking correctness issue around request dispatch durability.
- I found four high-severity security/performance/OTP issues around provider error exposure, redirect handling, ETS ownership, and synchronous DETS writes.
- World scoping is mostly enforced for persisted instance lookups, but one public runtime-state API still bypasses explicit World scope.

## Risk assessment
- High
- The runtime works on the happy path, but several failure-path behaviors violate the task acceptance criteria: dropped work is possible, provider error details can reach the UI, redirects are not disabled for Req, ETS ownership is not guaranteed to stay with the long-lived owner, and idle snapshots block the executor on disk I/O.

## BLOCKER

- Severity: Critical
- Where: `lib/lemmings_os/runtime.ex:48-57`, `lib/lemmings_os/lemming_instances.ex:334-338`, `lib/lemmings_os/lemming_instances/executor.ex:188-196`
- Why it matters: `spawn_session/3` and `LemmingInstances.enqueue_work/3` both persist the user message first and then rely on `Executor.enqueue_work/2`, which is a plain `GenServer.cast/2`. If the executor dies after PID lookup or startup but before handling the cast, the request is acknowledged to the caller and remains in the transcript, but the in-memory queue never receives it. Because executor restarts do not reconstruct queued work from persisted messages during normal supervision restarts, the request can be silently dropped.
- Suggested fix: Make queue admission acknowledged and durable. The minimal fix is to replace the fire-and-forget cast with a synchronous call that confirms the executor has inserted the work item into ETS state before returning `:ok`. If you want to preserve async execution, persist an explicit pending-work record or reconstruct pending work from transcript messages on executor restart.

## MAJOR

- Severity: High
- Where: `lib/lemmings_os/model_runtime/providers/ollama.ex:47-49`, `lib/lemmings_os/model_runtime/providers/ollama.ex:194-228`, `lib/lemmings_os/lemming_instances/executor.ex:1273-1288`, `lib/lemmings_os_web/components/instance_components.ex:48-56`
- Why it matters: non-success provider responses are summarized from the raw body and then copied into `last_error`. That `last_error` is rendered directly in the instance session failure panel. This violates the task requirement that raw provider error payloads must not be exposed to the UI; upstream model servers often include internal diagnostics, request details, or provider-specific payload fragments in their error bodies.
- Suggested fix: keep detailed provider payloads in logs/telemetry only, behind operator boundaries, and map UI-visible failure text to a fixed sanitized error taxonomy such as `provider_http_error`, `provider_timeout`, and `provider_network_error` without body snippets.

- Severity: High
- Where: `lib/lemmings_os/model_runtime/providers/ollama.ex:32-38`
- Why it matters: the Req client is constructed without `redirect: false`. In the installed Req version in this repo, redirects are enabled by default. That violates the acceptance criterion that model runtime HTTP calls must not follow redirects to arbitrary hosts.
- Suggested fix: set `redirect: false` explicitly in `Req.new/1`. If redirects ever become necessary, restrict them to a known allowlist and keep credential forwarding disabled.

- Severity: High
- Where: `lib/lemmings_os/lemming_instances/runtime_table_owner.ex:33-36`, `lib/lemmings_os/lemming_instances/ets_store.ex:45-62`, `lib/lemmings_os/lemming_instances/executor.ex:1163-1179`
- Why it matters: the design intends `RuntimeTableOwner` to own the named ETS table, but both `EtsStore.init_table/0` and `Executor.ensure_runtime_table/1` will create that table from whatever caller notices it missing first. If the owner process is absent or crashes, an executor, test process, or arbitrary caller can become the new ETS owner. When that short-lived process exits, the whole runtime table disappears, taking active runtime state for every instance with it.
- Suggested fix: centralize table creation in `RuntimeTableOwner` only. All other modules should fail fast or wait for the owner instead of calling `:ets.new/2` themselves. Add a test that kills a non-owner caller after table initialization and proves the table survives, plus a test that a missing owner does not let executors steal ownership.

- Severity: High
- Where: `lib/lemmings_os/lemming_instances/executor.ex:1105-1116`, `lib/lemmings_os/lemming_instances/dets_store.ex:81-84`, `lib/lemmings_os/lemming_instances/dets_store.ex:155-167`
- Why it matters: idle snapshotting is described as best-effort, but the executor performs it synchronously via `GenServer.call/2` into `DetsStore`, and `DetsStore` performs the `:dets.insert/2` before replying. That means the executor’s callback path blocks on disk I/O during the transition to `idle`, which is exactly the behavior the task asked to avoid.
- Suggested fix: make snapshotting asynchronous from the executor’s perspective. For example, cast to `DetsStore`, enqueue work to a dedicated snapshot worker, or send the write onto a supervised task and treat failures as telemetry-only.

## MINOR

- Severity: Medium
- Where: `lib/lemmings_os/lemming_instances.ex:250-260`, `lib/lemmings_os_web/live/instance_live.ex:267-283`, `test/lemmings_os/lemming_instances_test.exs:108-147`
- Why it matters: `get_runtime_state/1` is a public context API for a World-scoped resource, but unlike `list_instances/2` and `get_instance/2`, it accepts only `instance_id` and reads ETS/DETS directly without a World scope check. UUID-based IDs reduce exploitability, but the API still breaks the project’s explicit World-scoping rule and has no test proving cross-World isolation here.
- Suggested fix: require `world:` or `world_id:` for `get_runtime_state/2`, verify the instance belongs to that World before reading ETS/DETS, and add a cross-World negative test mirroring `get_instance/2`.

## NITS

- No low-priority nits worth calling out before merge. The important work here is closing the runtime correctness and failure-path gaps above.

## Test coverage notes
- The audited runtime tests pass locally:
  - `mix test test/lemmings_os/runtime_test.exs test/lemmings_os/lemming_instances_test.exs test/lemmings_os/lemming_instances/executor_test.exs`
- Missing tests:
  - executor death between PID resolution/startup and work enqueue should not acknowledge lost work
  - ETS ownership remains with the long-lived owner and survives executor/process exits
  - provider HTTP failures do not surface upstream error bodies in the instance UI
  - Req redirect responses are rejected instead of followed
  - `get_runtime_state` rejects cross-World access

## Observability notes
- The branch has solid transition/pool/scheduler logging and telemetry coverage overall.
- Provider failure logging is currently too verbose for UI-facing error propagation; keep full details in structured logs only if they stay operator-only.
- Add a dedicated metric or log event for `enqueue acknowledged but queue write failed` once the dispatch path is made durable.

## Merge recommendation
- REQUEST_CHANGES
- Do not merge until the dropped-work bug is fixed.
- The redirect, ETS ownership, DETS blocking, and provider-error exposure issues should also be addressed before merge because they directly violate this task’s acceptance criteria.
