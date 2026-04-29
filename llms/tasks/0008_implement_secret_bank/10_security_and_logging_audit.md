# Task 10 — Security and Logging/Audit Review

## Goal

Verify that the Secret Bank implementation preserves the core security guarantees of the product slice and that all secret-related operations are observable without leaking sensitive values.

This task is not about adding new product features. It is a security, observability, and documentation validation pass before closing the Secret Bank MVP.

---

## Scope

Review the implemented Secret Bank behavior across:

* UI rendering
* context/module APIs
* runtime secret resolution
* tool/runtime access paths
* logs
* audit events
* telemetry/traces
* errors and exceptions
* tests
* documentation and ADR updates

---

## Security Requirements

### Secret values are write-only

Secret values must never be readable after creation.

Verify that the system does not expose secret values through:

* UI tables
* detail views
* edit forms
* LiveView assigns rendered to the client
* flash messages
* validation errors
* logs
* audit events
* telemetry metadata
* traces
* exceptions
* test output
* prompts
* Lemming context
* runtime snapshots/checkpoints

### No derived previews

The system must not expose derived fragments of secret values.

Do not log or render:

* first characters
* last characters
* masked previews containing real characters
* hashes of secret values
* fingerprints derived from values
* copied or transformed secret material

Safe display should use metadata only, for example:

```text
SECRET_X  (this_dep)  [configured]
```

### Inherited secrets are protected

Verify that inherited secrets:

* are visible only as configured references;
* show their effective source;
* cannot be deleted from child scopes;
* can be overridden by creating a local secret with the same key;
* do not reveal parent values.

### Delete behavior is real delete

Verify that deleting a local secret:

* permanently removes it from that scope;
* does not create a disabled state;
* does not use feature flags;
* reveals the inherited parent value if one exists;
* makes the key unresolved if no parent value exists.

---

## Logging and Audit Requirements

Secret Bank operations must produce safe operational events.

Minimum expected events:

| Event                   | Trigger                               | Required safe metadata                  | Forbidden data       |
| ----------------------- | ------------------------------------- | --------------------------------------- | -------------------- |
| `secret.created`        | Local secret created                  | key, scope, source, timestamp           | value                |
| `secret.replaced`       | Local secret value replaced           | key, scope, timestamp                   | old value, new value |
| `secret.deleted`        | Local secret deleted                  | key, scope, timestamp                   | value                |
| `secret.resolved`       | Runtime resolves effective secret     | key, requested scope, resolved source   | value                |
| `secret.resolve_failed` | Runtime cannot resolve secret         | key, requested scope, reason            | value                |
| `secret.used_by_tool`   | Tool/runtime receives resolved secret | key, tool name, lemming instance, scope | value                |

Events must be useful for local admin troubleshooting while remaining safe to inspect.

---

## Review Checklist

### UI

* [ ] Secret values are never rendered after submit.
* [ ] Secret list shows key, source, and configured status only.
* [ ] Inherited secrets show source, for example `(env)`, `(world_main)`, `(city_a)`, `(this_dep)`.
* [ ] Inherited secrets do not show delete/replace actions for the child scope.
* [ ] Local secrets show replace/delete actions.
* [ ] Replace flow asks for a new value but never displays the previous value.
* [ ] Delete flow only applies to local secrets.
* [ ] Flash messages do not include values.
* [ ] Validation errors do not include values.

### Runtime/API

* [ ] Secret resolution follows `lemming type → department → city → world → env`.
* [ ] Runtime receives raw values only inside the trusted Secret Bank/tool execution path.
* [ ] Lemmings receive only safe references or safe errors.
* [ ] LLM prompts never include raw secret values.
* [ ] Missing secrets return safe errors.
* [ ] Decrypt/provider failures return safe errors.

### Logs/Audit/Telemetry

* [ ] Create emits a safe event.
* [ ] Replace emits a safe event.
* [ ] Delete emits a safe event.
* [ ] Resolve success emits a safe event.
* [ ] Resolve failure emits a safe event.
* [ ] Tool usage emits a safe event.
* [ ] No event includes raw or derived secret values.
* [ ] No exception path logs secret values.

### Tests

* [ ] Tests cover write-only UI behavior.
* [ ] Tests cover inherited source display.
* [ ] Tests cover local override behavior.
* [ ] Tests cover delete restoring parent inheritance.
* [ ] Tests cover runtime resolution order.
* [ ] Tests assert logs/audit events do not contain secret values.
* [ ] Tests cover safe failures for missing/decrypt/provider errors where applicable.

### Documentation

* [ ] ADR-0008 reviewed for persistence wording around secret values vs encrypted Secret Bank storage.
* [ ] ADR-0009 updated for MVP scope chain and UI behavior.
* [ ] ADR-0010/0011 sequencing clarified if needed: MVP has local admin, no auth/RBAC yet.
* [ ] Event/audit documentation updated with secret events if an event catalog exists.
* [ ] Operator-facing docs explain create, replace, delete, inheritance, and safe monitoring.

---

## Acceptance Criteria

This task is complete when:

* no UI path can reveal a saved secret value;
* no logging/audit/telemetry path contains secret values or derived previews;
* inherited/local secret behavior is observable and safe;
* local delete behavior is real delete;
* runtime resolution is traceable without exposing values;
* tests cover the critical safety behaviors;
* relevant ADRs and operator docs are updated or explicitly confirmed as already aligned.

---

## Non-Goals

Do not add these as part of this task:

* authentication;
* RBAC;
* per-user secret permissions;
* external secret manager integrations;
* approval workflows;
* compliance-grade audit reporting;
* secret rotation automation.

---

## Security Review Findings

### Scope Reviewed

Reviewed the Secret Bank PR on branch `feat/secret-bank` against `main`, focusing on:

* encrypted persistence and schema constraints;
* `LemmingsOs.SecretBank` context APIs;
* runtime secret resolution through `LemmingsOs.Tools.Runtime`;
* web tool adapter use of resolved secrets;
* durable events, logs, telemetry metadata, and activity UI;
* LiveView Secret Bank surfaces;
* relevant ExUnit coverage.

Validation run:

```sh
mix test test/lemmings_os/secret_bank_test.exs test/lemmings_os/tools/runtime_test.exs test/lemmings_os/events_test.exs test/lemmings_os_web/live/world_live_test.exs
```

Result: `37 tests, 5 doctests, 0 failures`.

One warning was emitted during the run:

```text
durable event failed to record
```

This warning occurred for `secret.access_failed` and should be investigated because audit reliability is part of the acceptance criteria.

### Threat Model Snapshot

Actors:

* local operator using the Phoenix LiveView console;
* model/Lemming output selecting tool calls and tool arguments;
* runtime/tool adapter code resolving and using secrets;
* external web services receiving authenticated requests;
* observers of logs, durable events, telemetry, traces, raw snapshots, and persisted tool executions.

Sensitive assets:

* encrypted local Secret Bank values;
* allowlisted environment fallback values;
* raw values after runtime resolution;
* tool request headers containing resolved secrets;
* persisted tool results, previews, errors, model context messages, and raw trace views.

Entrypoints:

* Secret Bank create/replace/delete LiveView events;
* `SecretBank.upsert_secret/3`, `delete_secret/2`, `list_effective_metadata/2`, `resolve_runtime_secret/3`;
* `Tools.Runtime.execute/5`;
* web adapter `trusted_config` headers;
* durable `events` storage and runtime trace/persistence paths.

### Findings

#### SEC-1: Secret refs must be resolved by the consuming tool, not by Tool Runtime

Severity: High

Category: Secrets / Logging

Locations:

* `lib/lemmings_os/tools/runtime.ex`
* `lib/lemmings_os/tools/adapters/web.ex`
* `lib/lemmings_os/lemming_instances/executor.ex:1027`
* `lib/lemmings_os/lemming_instances/executor/finalization_payload.ex:20`
* `lib/lemmings_os/lemming_instances/executor/context_messages.ex:68`

Risk:

Tool Runtime should not know how Secret Bank refs are resolved. It should route model-visible args and public trusted config only. The tool that consumes a credential should call Secret Bank inside its own trusted execution boundary, register exact redaction values, and redact every output before returning to runtime persistence/model context.

The original implementation replaced secret refs with raw values in the normal tool configuration path, which made it too easy for secret-bearing data to be persisted, logged, traced, returned to the Lemming, or sent back into model context.

The concrete leak path is a reflected-secret response:

```text
$GITHUB_TOKEN gets replaced with raw value
↓
adapter result/body/preview may contain reflected secret
↓
executor persists result/preview
↓
finalization sends preview/details back into model context
```

Evidence:

The original implementation resolved `$GITHUB_TOKEN` in `Tools.Runtime` by replacing the placeholder with the raw secret before invoking the adapter. The web adapter then stored response `body` and `preview`. The executor persisted `result` and `preview`. Finalization sent preview/details into model context.

Current redaction catches key-patterned values, but it does not register exact resolved secret values as a redaction context. If a remote service reflects a secret without a sensitive field name, the reflected value can escape the trusted boundary.

Recommendation:

Do not use runtime-level placeholder replacement. Keep model-provided args and model-visible data as safe refs/placeholders. Runtime should not reference Secret Bank or contain secret resolution/redaction logic.

The consuming adapter should resolve refs only inside its trusted execution boundary and pass raw values through a private in-memory execution envelope.

Implementation shape:

```elixir
%ToolExecution{
  public_args: args_without_secret_values,
  private_credentials: resolved_secrets,
  redaction_values: Map.values(resolved_secrets)
}
```

Required flow:

1. Policy authorizes the tool.
2. Runtime dispatches public args/config plus world/instance context.
3. Consuming adapter resolves secret refs with Secret Bank.
4. Consuming adapter builds an exact-value redactor from resolved values.
5. Adapter executes with `private_credentials`.
6. Adapter output, errors, previews, traces, and persisted results are redacted before leaving the boundary.
7. Only safe results are persisted, returned, logged, traced, or sent to model context.
8. Audit emits `secret.resolved` and `secret.used_by_tool`, never the value.

Add a Bypass regression test where the server echoes the Authorization header and assert the token is absent from persisted result, preview, finalization context, and model messages.

Status:

Fixed for the web adapter path. `LemmingsOs.Tools.Runtime` no longer references Secret Bank or secret/redaction helpers. `LemmingsOs.Tools.Adapters.Web` now owns Secret Bank resolution and exact-value redaction for web tool private headers.

#### SEC-2: Secret audit event taxonomy does not match the required events

Severity: Medium

Category: Logging/PII

Locations:

* `lib/lemmings_os/secret_bank.ex:25`
* `lib/lemmings_os/secret_bank.ex:741`
* `lib/lemmings_os/secret_bank.ex:763`
* `test/lemmings_os/secret_bank_test.exs:357`

Risk:

Audit records do not satisfy the task's minimum observable events. Runtime troubleshooting and compliance checks will miss required event names and metadata.

Evidence:

The implementation records `secret.accessed` and `secret.access_failed`. This task requires:

* `secret.resolved`
* `secret.resolve_failed`
* `secret.used_by_tool`

The current payload also lacks the lemming instance ID required for `secret.used_by_tool`. Tests assert the non-required event names, so the mismatch is currently locked in by test coverage.

Recommendation:

Emit the required events separately:

* `secret.resolved` and `secret.resolve_failed` from `SecretBank`;
* `secret.used_by_tool` from `Tools.Runtime`, including tool name and lemming instance ID.

Update tests to assert the required event names and safe metadata.

Status:

Fixed. Secret Bank now emits `secret.resolved` and
`secret.resolve_failed`; the web adapter emits `secret.used_by_tool` with
tool name, adapter name, lemming instance ID, scope IDs, key, and resolved
source. Regression tests assert the old `secret.accessed` /
`secret.access_failed` names are not emitted on the reviewed paths.

#### SEC-3: Secret scope hierarchy consistency is not enforced

Severity: Medium

Category: Access Control / Secrets

Locations:

* `priv/repo/migrations/20260428134026_create_secret_bank_data_model.exs:8`
* `lib/lemmings_os/secret_bank/secret.ex:61`
* `lib/lemmings_os/secret_bank.ex:462`

Risk:

Secret scope consistency relies on caller-provided struct IDs and independent foreign keys. A malformed internal caller can create or resolve rows with mismatched world/city/department/lemming ancestry.

Evidence:

The migration validates each foreign key independently. The changeset validates only nil/non-nil scope shape. `scope_data/1` trusts IDs already present in structs.

Recommendation:

Enforce hierarchy consistency before insert and resolve, or add composite database constraints/indexes that ensure child scope belongs to the same world/parent chain.

Add negative tests with cross-world city/department/lemming structs.

Status:

Fixed. Secret Bank validates persisted scope ancestry before create, replace, delete, effective metadata listing, recent activity listing, and runtime resolution. Mismatched child scopes and non-persisted world scopes return safe `:scope_mismatch` errors before env fallback resolution.

### Recheck — 2026-04-29

Reviewed the addressed findings again against the current branch. Additional
gap found and fixed: world-scoped Secret Bank calls now require a persisted
World row before writes, metadata/activity listing, or runtime resolution. This
prevents forged world scopes from resolving env fallback values and avoids
foreign-key failures while recording audit events.

Validation run:

```sh
mix test test/lemmings_os/secret_bank_test.exs test/lemmings_os/tools/runtime_test.exs test/lemmings_os/events_test.exs test/lemmings_os_web/live/world_live_test.exs
mix precommit
```

Result: `45 tests, 5 doctests, 0 failures`.
Final validation: `mix precommit` passed.

No `durable event failed to record` warning was observed during this run.

### Completed Remediations

1. Added exact-value redaction for resolved secrets before adapter output leaves the trusted web adapter boundary.
2. Replaced `secret.accessed` / `secret.access_failed` with the required event taxonomy on reviewed paths.
3. Added hierarchy consistency validation for Secret Bank scope structs and persisted rows.
4. Expanded tests to cover reflected-secret responses, required audit events, and non-persisted world scopes.

### Secure-by-Default Checklist

* [x] Secret values are encrypted at rest using Cloak/Cloak.Ecto.
* [x] Production encryption key material is loaded from `LEMMINGS_SECRET_BANK_KEY_BASE64`.
* [x] Dev/test key material is labelled as non-production.
* [x] UI metadata paths reviewed for direct saved-value rendering.
* [x] Flash messages reviewed for direct value disclosure.
* [x] Secret metadata queries avoid selecting `value_encrypted`.
* [x] Reflected resolved secrets are redacted from tool results before persistence, traces, and finalization prompts can consume them.
* [x] Required audit event names are emitted.
* [x] Tool-use audit events include lemming instance metadata.
* [x] Secret scope hierarchy consistency is enforced beyond nil/non-nil shape.
* [x] Durable event failure warning is investigated and resolved.

### Out-of-Scope / Follow-ups

* Authentication, RBAC, and per-user secret permissions remain non-goals for this MVP.
