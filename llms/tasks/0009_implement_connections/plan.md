# Connection Model Plan (Current Baseline)

## Status
- Baseline aligned to current implementation.

## Goal
Keep Connections as a simplified reusable integration config model scoped by hierarchy:

- World
- City
- Department

Nearest visible scope wins by `type`.

## Implemented Data Model
`connections` stores:

- `id`
- `world_id`
- `city_id` nullable
- `department_id` nullable
- `type`
- `status` (`enabled|disabled|invalid`)
- `config` map
- `last_test` text
- timestamps

Not in this simplified model:

- `slug`
- `name`
- `provider`
- `secret_refs` column
- `metadata`
- split test fields (`last_tested_at`, `last_test_status`, `last_test_error`)

## Scope Rules
- World: `world_id`, no `city_id`/`department_id`
- City: `world_id` + `city_id`, no `department_id`
- Department: `world_id` + `city_id` + `department_id`

Uniqueness: one row per `type` per exact scope (partial unique indexes).

## Runtime and Secret Boundary
- `LemmingsOs.Connections.Runtime` resolves visibility/status and returns safe descriptors.
- Runtime does not resolve secrets.
- Secret resolution is caller-only (`LemmingsOs.Connections.Providers.MockCaller`) via Secret Bank, just-in-time.
- Secret refs live inside `config` values (for example `"$MOCK_API_KEY"`), not in a separate DB column.

## Implemented Type Registry
- Registry module: `LemmingsOs.Connections.TypeRegistry`
- Current executable type: `mock` (`LemmingsOs.Connections.Providers.MockCaller`)

## UI Baseline
- Connections surfaces are integrated in World/City/Department tabs.
- UI supports create, edit, delete local, enable/disable, and test.
- Source scope indicators show local vs inherited.
- Config input supports YAML/JSON payload parsing.

## Observability Baseline
Implemented event vocabulary:

- `connection.created`
- `connection.updated`
- `connection.deleted`
- `connection.enabled`
- `connection.disabled`
- `connection.marked_invalid`
- `connection.resolve.started`
- `connection.resolve.succeeded`
- `connection.resolve.failed`
- `connection.test.started`
- `connection.test.succeeded`
- `connection.test.failed`

Payloads are safe metadata only (no raw secret values).

## Out of Scope
- Real provider integrations.
- Tool runtime refactors.
- Auth/RBAC/approval workflows.
