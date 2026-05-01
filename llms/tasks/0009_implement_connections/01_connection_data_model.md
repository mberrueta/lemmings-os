# Task 01: Connection Data Model

## Status
- **Status**: COMPLETED
- **Approved**: [x] Human sign-off

## Objective
Define the simplified persisted model for reusable World/City/Department scoped Connections.

## Implemented Data Contract
`connections` table (see `priv/repo/migrations/20260429121500_create_connections.exs`) contains:

- `id` `:binary_id`
- `world_id` required FK (`on_delete: :delete_all`)
- `city_id` nullable FK (`on_delete: :delete_all`)
- `department_id` nullable FK (`on_delete: :delete_all`)
- `type` required string
- `status` required string, default `"enabled"`
- `config` required map, default `%{}`
- `last_test` nullable text
- timestamps (`:utc_datetime`)

Removed from scope in the simplified model: `slug`, `name`, `provider`, `secret_refs`, `metadata`, `last_tested_at`, `last_test_status`, `last_test_error`.

## Scope Shape
Scope is inferred from owner IDs:

- World: `world_id`, no `city_id`/`department_id`
- City: `world_id` + `city_id`, no `department_id`
- Department: `world_id` + `city_id` + `department_id`

Enforced by DB check constraint `connections_scope_shape_check`.

## Indexes and Uniqueness
- FK lookup indexes on `world_id`, `city_id`, `department_id`
- Lookup indexes by scope + `type`
- Partial unique indexes enforce one `type` per exact scope:
  - world scope: `connections_unique_world_scope_type_index`
  - city scope: `connections_unique_city_scope_type_index`
  - department scope: `connections_unique_department_scope_type_index`

## Notes
- No provider-specific tables were added.
- No auth/RBAC/approval tables were added.
