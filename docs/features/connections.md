# Connections

## Purpose

Connections are persisted, reusable integration configuration records scoped to
LemmingsOS hierarchy levels:

- World
- City
- Department

This MVP gives operators a control-plane place to store safe, non-secret
provider configuration and to choose where that configuration is owned.
Connections are resolved by `type`, can be inherited down the hierarchy, and can
be tested through a deterministic mock provider.

This document describes the shipped behavior only.

## What A Connection Is

A Connection is one exact-scope row in the `connections` table.

Shipped fields:

- `world_id`
- `city_id` or `nil`
- `department_id` or `nil`
- `type`
- `status`
- `config`
- `last_test`
- timestamps

The current shape is intentionally narrow.

It does not include:

- `slug`
- `name`
- `provider`
- `metadata`
- separate secret binding columns
- split test-result columns

Exactly one local Connection per `type` is allowed at a given exact scope.

Examples:

- one World-level `mock` Connection is allowed
- one City-level `mock` Connection is allowed for a given City
- one Department-level `mock` Connection is allowed for a given Department
- two World-level `mock` rows are rejected

## Scope And Ownership

The owning scope is inferred from hierarchy IDs:

- World scope: `world_id` only
- City scope: `world_id + city_id`
- Department scope: `world_id + city_id + department_id`

The context validates ancestry before reading or writing. Invalid or forged
scope shapes fail closed instead of partially resolving data.

Operator-facing pages are scope-local:

- `/world` manages World-local Connections
- `/cities?city=<city_id>` manages City-local Connections for the selected City
- `/departments?city=<city_id>&dept=<department_id>` manages Department-local
  Connections for the selected Department

## Resolution Model

Connections are resolved by `type` using nearest-wins inheritance.

Resolution order:

- Department caller scope: `department -> city -> world`
- City caller scope: `city -> world`
- World caller scope: `world`

The first visible row for a `type` wins.

Example:

- World has `mock`
- City has no local `mock`
- Department has no local `mock`
- the Department sees the World `mock`

If the City later creates its own `mock`, that City row becomes effective for:

- the City itself
- every Department under that City that does not define its own local `mock`

If the Department later creates its own `mock`, that Department row becomes
effective only for that Department.

Deleting a local override does not delete inherited parent rows. It reveals the
next visible parent Connection, if one exists.

## Status Model

Connections have three persisted administrative statuses:

- `enabled`
- `disabled`
- `invalid`

These statuses are operator-facing control-plane state. They are not derived
from runtime health checks.

Effects:

- `enabled` can resolve and can be tested
- `disabled` remains visible in read models but runtime resolution returns
  `{:error, :disabled}` and test execution records a failed result
- `invalid` remains visible in read models but runtime resolution returns
  `{:error, :invalid}` and test execution records a failed result

## Secret Boundary

Connections are not the secret store.

The shipped rule is:

- `config` stores safe configuration data
- secret references may appear inside `config` values
- raw secret values must not be stored directly in Connection rows

For the shipped `mock` type, the `api_key` field must be a Secret Bank style
reference such as `$MOCK_API_KEY`. A raw string like `super-secret-token` is
rejected as invalid config.

This means Connection rows are safe configuration carriers, not credential
vaults.

For secret storage and hierarchy fallback, see
[`docs/features/secret_bank.md`](secret_bank.md).

## Runtime Boundary

The runtime-facing boundary is `LemmingsOs.Connections.Runtime`.

Its responsibility is intentionally narrow:

- resolve which Connection row is visible for a given scope and `type`
- enforce accessibility and administrative status
- return a safe descriptor containing identity, source scope, status, and safe
  config
- emit safe resolution events

It does not:

- resolve Secret Bank references
- return raw credentials
- call external providers directly
- decide provider-specific auth behavior

Provider caller modules own just-in-time credential resolution.

Current split of responsibility:

- `LemmingsOs.Connections.Runtime` resolves identity and visibility
- `LemmingsOs.Connections.Providers.MockCaller` validates mock config, resolves
  secret refs just in time through Secret Bank, and returns sanitized results

This separation is deliberate. Runtime resolution decides which Connection is
usable. Provider callers decide how credentials are consumed.

## Supported Type Registry

Connections use `LemmingsOs.Connections.TypeRegistry` for supported types,
labels, default config examples, config validation, and test dispatch.

Shipped registry entries:

- `mock` -> `LemmingsOs.Connections.Providers.MockCaller`

The UI reads registry metadata to:

- populate type dropdowns
- prefill editable config examples
- validate that the selected type is supported

Real provider integrations are not shipped in this MVP.

## Mock Provider Behavior

`mock` is the only deterministic provider behavior in this slice.

Required config shape:

```json
{
  "mode": "echo",
  "base_url": "https://example.test/mock",
  "api_key": "$MOCK_API_KEY"
}
```

Behavior:

- `mode` must be `echo`
- `base_url` must be a non-empty string
- `api_key` must be a Secret Bank reference beginning with `$`
- secret resolution happens only when the caller runs
- the caller returns a sanitized success map only

Successful test result shape is intentionally narrow and safe:

```elixir
%{
  outcome: "mock_echo_ok",
  mode: "echo",
  resolved_secret_keys: ["api_key"]
}
```

No raw secret values are returned, persisted into `last_test`, or written to
safe event payloads.

## Operator Flows

Connections UI surfaces exist on World, City, and Department pages.

Each page shows the effective visible rows for that scope, not just local rows.
Every row includes:

- a display label such as `World / mock` or `City / mock`
- the type
- the current status badge
- the persisted `last_test` summary
- a source badge showing whether the row is `Local` or `Inherited`

### Create

Operators can open a create form at the current scope.

Behavior:

- type options come from the registry
- changing the selected type refills the example config for that type
- config can be entered as JSON or YAML text
- new rows are created as local rows at the current scope
- the create form submits `status = enabled`

If a parent row already exists for the same `type`, creating a local row at the
child scope overrides that parent row for the child scope only.

### Inspect

The table is the inspection surface.

Operators can see:

- which scope owns the effective row
- whether the row is local or inherited
- whether a local override currently hides a parent row of the same `type`
- the latest persisted test summary in `last_test`

The display label is descriptive only. It is not a durable name field.

### Edit

Local rows can be edited in place.

Behavior:

- only local rows expose edit controls
- the edit form preserves the row status
- config remains editable as JSON or YAML text
- changing type swaps in the new type's default config example

Inherited rows cannot be edited from a child scope. The operator must navigate
to the owning scope or create a local override.

### Test

Operators can run a test for a visible Connection `type` from the current scope.

Behavior:

- the system resolves the nearest visible row by `type`
- the test runs against that resolved source row
- `last_test` is persisted on the resolved source Connection row
- success stores a summary like `succeeded: mock_echo_ok`
- failure stores a safe summary like `failed: missing_secret`

The summary is sanitized and never includes raw secret values.

### Enable And Disable

Operators can change status for local rows only.

Behavior:

- `Enable` sets status to `enabled`
- `Disable` sets status to `disabled`
- inherited rows do not expose lifecycle controls at child scope

The UI hides the redundant action for the current state. For example, an already
`enabled` row does not show an `Enable` button.

### Delete Local

Delete removes only the exact local row at the current scope.

Behavior:

- only local rows expose delete controls
- deleting a local override does not affect parent rows
- after delete, the effective visible row may change to the next inherited row
  of the same `type`

This is the main operator escape hatch for removing an override and returning to
inherited behavior.

## Test Persistence And Event Safety

Connection testing writes a short safe summary into `last_test`.

Examples:

- `succeeded: mock_echo_ok`
- `failed: invalid_config`
- `failed: missing_secret`
- `failed: disabled`

Only safe failure reasons are persisted. Unexpected provider failures are
collapsed to `provider_test_failed` instead of leaking internal detail.

The Connections feature also records safe events for create, update, delete,
status changes, runtime resolution, and test execution. These events contain
safe metadata such as connection IDs, types, statuses, source scope, and safe
test summaries. They must not contain raw credentials.

## Out Of Scope

The following are explicitly not shipped by this MVP:

- real provider integrations beyond deterministic `mock`
- Tool Runtime refactors or generic provider execution unification
- application authentication or RBAC around Connection management
- approval workflows for creating, changing, testing, enabling, disabling, or
  deleting Connections
- dedicated secret-binding tables or raw credential storage inside Connections
- claims that child scopes can edit or delete inherited parent rows directly

Future work can add real providers and authorization layers, but this document
should not be read as claiming those capabilities exist today.
