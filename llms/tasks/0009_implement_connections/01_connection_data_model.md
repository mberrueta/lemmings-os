# Task 01: Connection Data Model

## Status
- **Status**: COMPLETED
- **Approved**: [x] Human sign-off

## Assigned Agent
`dev-db-performance-architect`

## Agent Invocation
Act as `dev-db-performance-architect`. Read `llms/constitution.md`, `llms/project_context.md`, and `llms/tasks/0009_implement_connections/plan.md`, then design and implement the Connection database migration only.

## Objective
Create the durable data foundation for reusable World, City, and Department scoped Connections.

Connections store safe configuration and Secret Bank-compatible secret references. They must not store raw secret values, resolved credentials, credential previews, or provider-specific integration state.

## Data Contract

Create a `connections` table unless code discovery finds an already-approved equivalent.

Required columns:

- `id` as `:binary_id`
- `world_id` required FK to `worlds.id`
- `city_id` nullable FK to `cities.id`
- `department_id` nullable FK to `departments.id`
- `slug` string, required
- `name` string, required
- `type` string, required
- `provider` string, required
- `status` string, required
- `config` map, required, default `%{}`
- `secret_refs` map, required, default `%{}`
- `metadata` map, required, default `%{}`
- `last_tested_at` nullable UTC datetime
- `last_test_status` nullable string
- `last_test_error` nullable string
- timestamps

Scope is inferred from ID presence:

- World scope: `world_id` set, `city_id` null, `department_id` null.
- City scope: `world_id` and `city_id` set, `department_id` null.
- Department scope: `world_id`, `city_id`, and `department_id` set.

Required constraints/indexes:

- FK indexes for `world_id`, `city_id`, and `department_id`.
- Lookup indexes that support hierarchy queries by `world_id`, `city_id`, `department_id`, and `slug`.
- Partial unique index for World scoped slugs: `[:world_id, :slug]` where `city_id IS NULL AND department_id IS NULL`.
- Partial unique index for City scoped slugs: `[:world_id, :city_id, :slug]` where `city_id IS NOT NULL AND department_id IS NULL`.
- Partial unique index for Department scoped slugs: `[:world_id, :city_id, :department_id, :slug]` where `city_id IS NOT NULL AND department_id IS NOT NULL`.
- Check constraint that rejects invalid hierarchy shapes such as `department_id` without `city_id`.

Parent deletion behavior:

- Scope owner FKs must not be nullified in a way that promotes a Connection to a broader scope.
- If a City or Department is deleted, its owned Connections must either be deleted with it or deletion must be restricted.
- Future references from other records to `connections.id` may use `nilify_all`, but the scope-defining owner FKs must not change the Connection's effective scope.

## Expected Outputs
- Migration under `priv/repo/migrations/`.
- Schema/index notes in this task's execution summary.
- Explicit confirmation that no real provider tables were added.
- Explicit confirmation that no auth/RBAC/approval tables were added.
- No context, runtime, or UI implementation beyond what is strictly required by migration conventions.

## Acceptance Criteria
- The migration defines every required product field from `plan.md`.
- Connection rows are always World scoped.
- Scope shapes support World, City, and Department Connections, and reject invalid nullable-ID combinations.
- Slug uniqueness is enforced per exact scope, allowing child scope overrides.
- Indexes support nearest-wins hierarchy lookup.
- Scope-defining owner FKs cannot be nilified in a way that promotes Department Connections to City scope or City Connections to World scope.
- City and Department parent deletion either deletes owned Connections or restricts parent deletion.
- `config`, `secret_refs`, and `metadata` can store safe structured data.
- No raw secret value, secret preview, hash, or resolved credential column is added.
- No new dependency is introduced.

## Review Notes
Reject if the schema stores credentials, introduces real provider-specific tables, omits World scoping, nilifies scope owner FKs in a way that changes effective scope, or adds auth/RBAC/approval workflow structures.
