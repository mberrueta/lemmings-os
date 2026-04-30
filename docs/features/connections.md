# Connections MVP (Simplified)

Connections are reusable integration configs scoped by hierarchy:

- World
- City
- Department

Rule: exactly one Connection per `type` per exact scope.

## Data shape

`connections` columns:

- `id`
- `world_id`
- `city_id` nullable
- `department_id` nullable
- `type` (required)
- `status` (`enabled|disabled|invalid`, default `enabled`)
- `config` map (required, default `%{}`)
- `last_test` text nullable
- timestamps

No `slug`, `name`, `provider`, `secret_refs`, `metadata`, or split test-status fields.

## Override behavior

Nearest visible scope wins by `type`:

- Department checks Department -> City -> World
- City checks City -> World
- World checks World only

Example:

- World has `mock`
- City has `mock` -> City overrides World for that City
- Department has `mock` -> Department overrides City/World for that Department

## Secret boundary

- Runtime facade resolves only identity/visibility/status/safe config.
- Runtime facade does **not** call Secret Bank.
- Only type Caller modules resolve secret refs just-in-time from `config`.
- Caller modules return sanitized success/failure only.

## Type registry

Connections use a registry under `LemmingsOs.Connections.TypeRegistry`.

Current type:

- `mock` -> `LemmingsOs.Connections.Providers.MockCaller`

Registry metadata is used by UI for type selection and default config examples.

## UI behavior

The Connections UI supports:

- scope selection (World/City/Department)
- type selection from registry
- config editing as YAML or JSON
- auto-fill config default when type changes
- local vs inherited source indicators
- local-only delete
- test action

Generated label is display-only (for example `World / mock`).
