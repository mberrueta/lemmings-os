# Connection Model Product Plan

## 0. Planning Metadata

- Task Directory: `llms/tasks/0009_implement_connections/`
- Status: `REVISED_MVP`
- Source Issue: <https://github.com/mberrueta/lemmings-os/issues/28>
- Product Contract: this file

## 1. Goal

Implement a simplified Connections MVP with one Connection per `type` per exact scope.

A Connection stores one non-secret/safe `config` payload that may include Secret Bank references (for example `"$GITHUB_TOKEN"`).

## 2. Core Decisions

- Exactly one Connection per `type` per scope.
- Supported scopes remain World, City, Department.
- Child scopes override parent Connection of the same `type`.
- No `slug`, `name`, `provider`, `secret_refs`, `metadata`, `last_tested_at`, `last_test_status`, `last_test_error`.
- One `last_test` text field stores the latest sanitized test summary.
- Runtime facade resolves identity/visibility/status/safe config only.
- Runtime facade must not call Secret Bank.
- Only type Caller modules resolve Secret Bank refs just-in-time.
- Caller modules return sanitized success/failure only (never raw secrets).

## 3. Data Model

`connections` table fields:

- `id`
- `world_id`
- `city_id` nullable
- `department_id` nullable
- `type` string, required
- `status` string, required, default `"enabled"`
- `config` map, required, default `%{}`
- `last_test` text nullable
- `inserted_at`
- `updated_at`

Scope shapes:

- World: `world_id` set, `city_id` null, `department_id` null
- City: `world_id` + `city_id`, `department_id` null
- Department: `world_id` + `city_id` + `department_id`
- `department_id` is never allowed without `city_id`

Uniqueness (partial unique indexes):

- world scope: `[:world_id, :type]` where `city_id IS NULL AND department_id IS NULL`
- city scope: `[:world_id, :city_id, :type]` where `city_id IS NOT NULL AND department_id IS NULL`
- department scope: `[:world_id, :city_id, :department_id, :type]` where `city_id IS NOT NULL AND department_id IS NOT NULL`

Parent deletion:

- Scope-owner FKs use `on_delete: :delete_all`.
- No FK behavior may nilify scope-owner IDs and promote scope.

## 4. Type Registry

Connections are type-registry backed.

Registry responsibilities:

- list supported types for UI
- map `type` to caller module
- provide type label
- provide default config example
- provide config validation behavior
- indicate test support

Current MVP type:

- `mock -> LemmingsOs.Connections.Providers.MockCaller`

## 5. Runtime Boundary

- Facade resolves nearest visible Connection by `type`.
- Facade enforces status usability (`enabled` only).
- Facade returns only safe descriptor fields.
- Facade never resolves secrets and never returns secret values.

Caller boundary:

- Resolve secret refs from configured fields inside trusted execution.
- Execute deterministic type behavior.
- Return sanitized result maps/errors.
- Never return raw secret values.

## 6. UI Contract

Connections UI (local admin):

- surface Connections inside existing World/City/Department pages (tabbed like Secrets)
- each scope page manages Connections for that exact scope (no standalone `/connections` page)
- select `type` from registry
- auto-fill config textarea when type changes using registry default example
- edit config as YAML or JSON
- save parsed config to `config` column
- show local/inherited source scope
- allow delete only for local rows
- allow test action
- never render resolved secrets

Generated label is display-only, for example:

- `World / mock`
- `City / github`
- `Department / openrouter`

No DB column for display label.

## 7. Testing Requirements

- schema tests for simplified fields and per-scope type uniqueness
- hierarchy tests for nearest-wins by `type`
- UI tests for type dropdown and default config population
- runtime facade tests proving it does not call Secret Bank
- caller tests proving caller-only secret resolution
- tests proving raw secrets never appear in UI/events/logs/errors/runtime facade results/`last_test`

## 8. Out of Scope

- real GitHub/OpenRouter integrations
- broader Tool Runtime refactor
- auth/RBAC/approval workflow
- raw secret storage
- compatibility maintenance for old slug/provider/secret_refs model
