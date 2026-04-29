# Secret Bank

## Purpose

Secret Bank stores runtime credentials for tools without exposing raw values to
Lemmings, LLM prompts, operator pages, logs, runtime snapshots, or durable audit
events. It is implemented for the current local self-hosted control plane, where
the operator is an implicit trusted local admin.

The feature is intentionally narrower than the long-term architecture in
ADR-0009:

- current secret references are uppercase bank-key references such as
  `$GITHUB_TOKEN`;
- `$secrets.*` references such as `$secrets.github.token` are rejected as
  invalid by the shipped key validator;
- there are no tool binding tables, connection-object tables, connection UI, or
  external secret-manager integrations in this MVP.

Earlier planning examples such as
`$secrets.github.token -> github.token -> GITHUB_TOKEN` and
`env_fallbacks: ["github.token", {"openrouter.default", "OPENROUTER_API_KEY"}]`
describe a future logical-key shape, not the current implementation.

## Who Uses It

The MVP assumes one local admin operating a trusted/private installation. There
is no application login, RBAC, per-user permission check, approval workflow, or
per-user secret visibility in this slice. Future control-plane authentication
and authorization must wrap these flows without changing the runtime lookup
semantics.

## Data Model

Persisted local secrets live in `secret_bank_secrets`.

- `bank_key` is safe metadata and remains readable to database readers.
- Scope columns (`world_id`, `city_id`, `department_id`, `lemming_id`) identify
  the exact hierarchy level that owns the local value.
- `value_encrypted` stores the encrypted secret value.
- The Ecto schema exposes the logical field as `:value` using
  `LemmingsOs.SecretBank.EncryptedBinary`, a `Cloak.Ecto.Binary` type backed by
  `LemmingsOs.Vault`.
- Unique partial indexes enforce one local value per bank key at each exact
  scope.

Context APIs return safe metadata instead of schema structs for normal listing
and UI flows. Safe metadata includes key, effective scope, source, configured
state, timestamps, and allowed actions. It does not include raw values, masked
previews, hashes, fingerprints, or environment variable values.

## Configuration

Production encryption key material is required at runtime:

```bash
LEMMINGS_SECRET_BANK_KEY_BASE64=<base64 encoded 32 byte key>
```

`config/runtime.exs` decodes this value and raises if it does not decode to
exactly 32 bytes. Development and test use a deterministic dev/test-only key
from `config/config.exs`; do not reuse that key material in production.

Environment fallback is configured in application config:

```elixir
config :lemmings_os, LemmingsOs.SecretBank,
  allowed_env_vars: [
    "$GITHUB_TOKEN",
    "$OPENROUTER_API_KEY"
  ],
  env_fallbacks: [
    "$GITHUB_TOKEN",
    {"OPENROUTER_API_KEY", "$OPENROUTER_API_KEY"}
  ]
```

`allowed_env_vars` is the closed list of process environment variables Secret
Bank may read. `env_fallbacks` maps bank keys to those env vars:

- a string entry is a convention mapping, for example `$GITHUB_TOKEN` maps bank
  key `GITHUB_TOKEN` to env var `GITHUB_TOKEN`;
- a two-tuple is an explicit override, for example
  `{"OPENROUTER_API_KEY", "$OPENROUTER_API_KEY"}`;
- entries are ignored unless the normalized env var is also present in
  `allowed_env_vars`.

The process environment is never treated as an open keyspace.

## Key and Reference Format

Current bank keys must match:

```text
^[A-Z_][A-Z0-9_]*$
```

The runtime accepts either a normalized bank key or a `$` reference:

```text
GITHUB_TOKEN
$GITHUB_TOKEN
${GITHUB_TOKEN}
```

The shipped tool runtime resolves secret references only from trusted adapter
configuration, currently through `:tools_runtime_trusted_config`. It does not
resolve secret-like strings from model-provided tool arguments. For example, a
`web.fetch` URL argument of `$GITHUB_TOKEN` is treated as an invalid URL, not as
a secret request.

## Hierarchy and Resolution

Effective metadata is displayed from least specific to most specific as:

```text
env allowlist -> world -> city -> department -> lemming
```

Runtime lookup checks the most specific available source first:

```text
lemming -> department -> city -> world -> env allowlist
```

The most specific configured value for a bank key wins. If a Department has no
local `GITHUB_TOKEN`, it may inherit from City, World, or the env allowlist. If
the Department creates a local `GITHUB_TOKEN`, that local value becomes
effective. Deleting the local Department value reveals the next inherited source
if one exists.

Every write, delete, metadata listing, and runtime resolution validates that the
provided World, City, Department, and Lemming IDs belong to one persisted
ancestry chain. Forged or mismatched structs return safe errors such as
`:scope_mismatch`.

In this MVP, Lemming scope means the persisted durable `lemmings` row. It does
not refer to a future reusable Lemming Type/template entity.

## Operator Flows

Secret surfaces are available on World, City, Department, and Lemming detail
views.

The local admin can:

- create a local secret by entering a bank key and value;
- replace a local secret by submitting the same bank key with a new value;
- delete a local secret at the exact current scope;
- see effective safe metadata for local and inherited secrets;
- see configured env fallback policy metadata;
- see recent safe Secret Bank activity.

The UI never shows, copies, exports, previews, hashes, or partially reveals a
saved value. Editing a row pre-fills the key and focuses the password field; the
previous value is not loaded into the form.

Inherited secrets are visible as effective metadata but cannot be deleted from a
child scope. They can be overridden by creating a local value with the same key.

## Runtime Access

Raw values are returned only by the trusted runtime API:

```elixir
LemmingsOs.SecretBank.resolve_runtime_secret(scope, "$GITHUB_TOKEN")
```

The web tool adapter walks trusted config maps/lists, resolves `$KEY` strings,
uses the raw values only inside the adapter request path, and tracks the resolved
values for response redaction. If an external service reflects a resolved secret
back in a response body, the adapter replaces it with `[REDACTED]` before
returning or persisting the tool result.

The adapter records `secret.used_by_tool` only for resolved secrets used in
trusted request headers. Missing, invalid, scope-mismatched, or undecryptable
secrets stop adapter execution and return safe tool errors.

## Audit Events

Secret Bank uses the shared `events` table with `event_family: "audit"`.

Durable event types currently emitted:

| Event | Trigger | Safe payload |
|---|---|---|
| `secret.created` | Local secret created | `secret_ref`, `bank_key`, `scope`, `source` |
| `secret.replaced` | Local value replaced | `secret_ref`, `bank_key`, `scope`, `source` |
| `secret.deleted` | Local value deleted | `secret_ref`, `bank_key`, `scope`, `source` |
| `secret.resolved` | Runtime resolution succeeded | `key`, `requested_scope`, `resolved_source` |
| `secret.resolve_failed` | Runtime resolution failed | `key`, `requested_scope`, `reason` |
| `secret.used_by_tool` | Web adapter used a resolved header secret | `key`, `tool_name`, `adapter_name`, `lemming_instance_id`, hierarchy IDs, `resolved_source` |

The older event names `secret.accessed` and `secret.access_failed` are not used
by the shipped implementation.

Audit events must not include raw secret values, old values, new values, env
values, derived previews, hashes, or fingerprints.

## Local IEx and Dev Verification

Development seeds are idempotent:

```bash
mix run priv/repo/seeds.exs
```

The seed script creates the default hierarchy and, only if no effective
`GITHUB_TOKEN` already exists at the World, stores a fake dev-only sample value:
`dev_only_mock_github_token`. Re-running seeds does not duplicate that sample
row and does not replace an existing effective `GITHUB_TOKEN`.

Example verification in IEx:

```elixir
alias LemmingsOs.SecretBank
alias LemmingsOs.Worlds

world = Worlds.get_default_world()
SecretBank.list_effective_metadata(world, bank_key: "$GITHUB_TOKEN")
```

Expected safe metadata shape:

```elixir
[
  %{
    bank_key: "GITHUB_TOKEN",
    scope: "world",
    source: "local",
    configured: true,
    allowed_actions: ["upsert", "delete"],
    inserted_at: %DateTime{},
    updated_at: %DateTime{}
  }
]
```

The raw fake value is returned only through the trusted runtime resolution API:

```elixir
SecretBank.resolve_runtime_secret(world, "$GITHUB_TOKEN")
```

Use that API only from trusted runtime/tool code. Operator-facing pages and
metadata APIs must continue to use safe metadata functions.

## Known Limitations

- No login, sessions, RBAC, per-user secret permissions, or actor attribution
  for human admin changes in this slice.
- No external secret managers, KMS integrations, or rotation automation.
- No connection-object persistence or UI.
- No `secret_bank_tool_bindings` table, binding context, or binding UI.
- Current bank keys are uppercase env-style identifiers; lower-case logical keys
  such as `github.token` are future architecture, not shipped behavior.
- `$secrets.*` references are rejected as invalid in the current implementation.
- Runtime resolution is integrated with trusted web adapter config; it is not a
  general-purpose prompt or tool-argument interpolation system.
- Changing or losing the production Cloak key makes previously stored local
  secret values unreadable without a coordinated migration/recovery process.
