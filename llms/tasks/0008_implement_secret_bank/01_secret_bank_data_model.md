# Task 01: Secret Bank Data Model

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-db-performance-architect`

## Agent Invocation
Act as `dev-db-performance-architect`. Read `llms/constitution.md`, `llms/project_context.md`, ADR-0009, ADR-0018, and `llms/tasks/0008_implement_secret_bank/plan.md`, then design and implement the Secret Bank database migrations.

## Objective
Create the durable data foundation for Cloak-backed encrypted scoped secrets and safe audit events if no canonical durable event store already exists.

The database must never contain plaintext secret values. Anyone with direct database access may see safe operational metadata such as hierarchy IDs, Secret Bank keys, timestamps, and audit event names, but must not be able to recover secret values from database contents alone. Secret value encryption must use Cloak/Cloak.Ecto rather than a hand-rolled encryption format.

Do not create a `secret_bank_env_fallbacks` table or schema. Env fallback allowlist mappings are application configuration, not persisted data.
Do not create a `secret_bank_tool_bindings` table or schema. Tool configs reference secrets by convention with `$secrets.<provider>.<name>`.

## Data Contract

Task 01 must implement the following concrete tables unless code discovery finds an already-approved equivalent. If an equivalent exists, adapt it only where needed and document the mapping in the execution summary.

### `secret_bank_secrets`

Stores encrypted local secret values at hierarchy scopes. Secret values are encrypted by Cloak before insertion and stored only in a binary encrypted column. This table never stores raw values, derived previews, hashes, first/last characters, or masked real data.

| Column | Type | Null | Notes |
|---|---:|---:|---|
| `id` | `:binary_id` | no | Primary key |
| `world_id` | FK `worlds.id` | no | Hard isolation boundary; `on_delete: :delete_all` |
| `city_id` | FK `cities.id` | yes | Present for City, Department, and Lemming scope; `on_delete: :delete_all` |
| `department_id` | FK `departments.id` | yes | Present for Department and Lemming scope; `on_delete: :delete_all` |
| `lemming_id` | FK `lemmings.id` | yes | Present for Lemming scope; `on_delete: :delete_all` |
| `bank_key` | `:string` | no | Concrete Bank key, e.g. `github.token` |
| `value_encrypted` | `:binary` | no | Cloak ciphertext payload; the only persisted representation of the secret value |
| `inserted_at` | `:utc_datetime` | no | Standard timestamp |
| `updated_at` | `:utc_datetime` | no | Standard timestamp; changes on replace |

Required constraints/indexes:

- FK indexes on `world_id`, `city_id`, `department_id`, and `lemming_id`.
- Lookup index on `[:world_id, :bank_key]`.
- Lookup index on `[:world_id, :city_id, :department_id, :lemming_id, :bank_key]` if useful for the query plan, but this index does not replace the partial unique indexes below because Postgres normal unique indexes do not treat `NULL` values as equal.
- Partial unique index for World secrets on `[:world_id, :bank_key]` where `city_id IS NULL AND department_id IS NULL AND lemming_id IS NULL`.
- Partial unique index for City secrets on `[:world_id, :city_id, :bank_key]` where `city_id IS NOT NULL AND department_id IS NULL AND lemming_id IS NULL`.
- Partial unique index for Department secrets on `[:world_id, :city_id, :department_id, :bank_key]` where `city_id IS NOT NULL AND department_id IS NOT NULL AND lemming_id IS NULL`.
- Partial unique index for Lemming secrets on `[:world_id, :city_id, :department_id, :lemming_id, :bank_key]` where `city_id IS NOT NULL AND department_id IS NOT NULL AND lemming_id IS NOT NULL`.
- The partial unique indexes must guarantee that duplicates are impossible at every inferred scope. For example, two rows with `(world_a, NULL, NULL, NULL, "github.token")` must be rejected.
- Check constraint that prevents invalid hierarchy shapes, especially `department_id` without `city_id` and `lemming_id` without both `city_id` and `department_id`.
- All hierarchy foreign keys use `on_delete: :delete_all`: deleting a World deletes all its secrets, deleting a City deletes all secrets scoped to that City or below, deleting a Department deletes all secrets scoped to that Department or below, and deleting a Lemming deletes its own secrets.

Encryption requirement:

- The raw value is encrypted through a Cloak Ecto type before database insert/update.
- The raw value is never written to any column, including JSON/map columns.
- `value_encrypted` must be a Cloak ciphertext binary payload, not reversible encoding such as Base64.
- Do not add separate `nonce`, `algorithm`, or `key_id` columns for the secret value unless Cloak usage in this app requires them; Cloak embeds cipher metadata in the encrypted binary payload and key/cipher configuration belongs in application config.
- A database-only attacker without the master key must not be able to recover the secret value.
- A database-only attacker may still see safe metadata like `bank_key` and scope IDs. If hiding Bank key names themselves becomes a requirement, that is a separate metadata-encryption design and is out of scope for this MVP.

Scope is inferred from ID presence:

| Scope | Required IDs | Must be `NULL` |
|---|---|---|
| `"world"` | `world_id` | `city_id`, `department_id`, `lemming_id` |
| `"city"` | `world_id`, `city_id` | `department_id`, `lemming_id` |
| `"department"` | `world_id`, `city_id`, `department_id` | `lemming_id` |
| `"lemming"` | `world_id`, `city_id`, `department_id`, `lemming_id` | none |

### `audit_events`

If an `audit_events` table already exists and matches ADR-0018, reuse it. If not, create a minimal generic durable event table that Secret Bank can use now and future features can reuse for API calls, tool decisions, approvals, model requests, auth events, and other governance/observability records.

Before creating `audit_events`, inspect whether the project already has or expects a canonical `events` table from ADR-0018. Do not create a parallel durable event store if a canonical event store exists.

This is a generic append-only event envelope, not a Secret Bank-specific table. Secret Bank is only the first consumer in this slice.

Keep this intentionally small. `event_type` carries the important semantic meaning, and `message` provides a short safe operator-readable summary. `payload` is optional structured safe metadata for cases where a future feature needs filtering or details beyond the message.

| Column | Type | Null | Notes |
|---|---:|---:|---|
| `id` | `:binary_id` | no | Primary key / event id |
| `event_type` | `:string` | no | Stable event name, e.g. `secret.created`, `api.requested`, `tool.invocation_started` |
| `occurred_at` | `:utc_datetime` | no | When the action happened |
| `world_id` | FK `worlds.id` | yes | Hierarchy scope; `on_delete: :nilify_all` to preserve immutable events |
| `city_id` | FK `cities.id` | yes | Optional hierarchy scope; `on_delete: :nilify_all` |
| `department_id` | FK `departments.id` | yes | Optional hierarchy scope; `on_delete: :nilify_all` |
| `lemming_id` | FK `lemmings.id` | yes | Optional hierarchy scope; `on_delete: :nilify_all` |
| `message` | `:text` | no | Short safe summary, e.g. `github.token used in tools.gh` |
| `payload` | `:map` | no | Default `%{}`; optional safe structured metadata |
| `inserted_at` | `:utc_datetime` | no | Persistence timestamp; no `updated_at` column |

Required constraints/indexes:

- FK indexes on hierarchy IDs.
- Index on `[:event_type, :occurred_at]`.
- Index on `[:world_id, :occurred_at]`.
- Index on `[:world_id, :city_id, :occurred_at]`.
- Index on `[:world_id, :city_id, :department_id, :occurred_at]`.
- Index on `[:world_id, :city_id, :department_id, :lemming_id, :occurred_at]`.
- Audit events are immutable history. They must not be deleted by hierarchy cascades. When a World, City, Department, or Lemming is deleted, related `audit_events` hierarchy IDs are nilified and the event row remains.
- `audit_events` is insert-only: do not add an `updated_at` column, update changeset/API, or normal delete API.

For this MVP, the minimum Secret Bank event types are:

- `secret.created`
- `secret.replaced`
- `secret.deleted`
- `secret.accessed`
- `secret.access_failed`

Future event examples that should fit this same table without migration:

- `api.requested`
- `api.succeeded`
- `api.failed`
- `tool.invocation_started`
- `tool.invocation_failed`
- `model.request_started`
- `approval.requested`

Example rows:

```text
# Secret Bank runtime access
event_type:    secret.accessed
world_id:      world_main
city_id:       city_a
department_id: department_api
lemming_id:    github_issue_creator
message:       github.token used in tools.gh
payload:       %{secret_ref: "$secrets.github.token", resolved_source: "department"}

# Future generic API call event using the same table
event_type:    api.requested
world_id:      world_main
city_id:       city_a
department_id: department_api
lemming_id:    github_issue_creator
message:       POST api.github.com/repos/{owner}/{repo}/issues requested
payload:       %{method: "POST", host: "api.github.com", endpoint: "/repos/{owner}/{repo}/issues"}
```

## Expected Outputs
- Migration(s) under `priv/repo/migrations/`.
- Schema/index notes in this task's execution summary.
- Explicit confirmation that no env fallback migration/table was created.
- Explicit confirmation that no tool binding migration/table was created.
- No Elixir context implementation beyond what is strictly required by migration conventions.

## Acceptance Criteria
- Persisted local secrets support World, City, Department, and Lemming scope with explicit `world_id` and nullable lower scope IDs as appropriate.
- Secret rows cascade delete with their World, City, Department, or Lemming hierarchy owner.
- Local secret uniqueness prevents duplicate local values for the same Secret Bank key at the same scope.
- Secret rows store only `value_encrypted` Cloak ciphertext for the secret value; no raw value, preview, hash, first/last characters, or copied value material is stored.
- No env fallback allowlist table or schema is added.
- No tool binding table or schema is added.
- Generic durable event storage exists for Secret Bank events now and future event types later, either by reusing ADR-0018 storage or adding the minimal missing table.
- Indexes support hierarchy resolution by `world_id`, scope IDs, Secret Bank key, and recent audit lookup.
- Migrations follow existing UUID, timestamp, FK, index, and constraint style.

## Review Notes
Reject if the schema stores raw secret values or derived previews, omits World scoping, invents a custom encryption column format instead of Cloak ciphertext, or introduces user/RBAC concepts.
