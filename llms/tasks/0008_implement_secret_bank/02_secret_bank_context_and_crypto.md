# Task 02: Secret Bank Context and Crypto Boundary

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Add Cloak/Cloak.Ecto, configure the application Vault and encrypted Ecto type, then implement schemas, changesets, context APIs, and encryption/decryption boundaries for the data model from Task 01.

## Objective
Provide Cloak-backed encrypted persistence plus safe backend APIs for local admin create, replace, delete, list-effective metadata, config-file env fallback resolution, and convention-based `$secrets.*` normalization.

## Expected Outputs
- Add `:cloak` and `:cloak_ecto` dependencies to `mix.exs` and update `mix.lock`.
- New `LemmingsOs.Vault` module using `Cloak.Vault`.
- New encrypted Ecto type module, e.g. `LemmingsOs.Encrypted.Binary`, using `Cloak.Ecto.Binary`.
- Cloak configuration in `config/config.exs` for dev/test only with clearly labelled dev/test key material.
- Production/runtime configuration in `config/runtime.exs` that reads environment-provided key material and raises when required production key material is missing.
- Config-file env fallback allowlist support with entries shaped as either `"github.token"` or `{"openrouter.default", "OPENROUTER_API_KEY"}`.
- Secret reference parser/normalizer for `$secrets.<provider>.<name>` references, producing `<provider>.<name>`.
- Idempotent local/demo seed support in `priv/repo/seeds.exs` that creates a non-real sample secret using the Secret Bank context.
- New or updated modules under `lib/lemmings_os/**`.
- Schemas and context APIs with `@doc` for important public functions.
- Configuration reads for encryption master key material through environment-backed config, with no hardcoded production cryptographic secrets.

## Acceptance Criteria
- Secret schema maps the logical value field through the encrypted Ecto type to `source: :value_encrypted`.
- Admin APIs accept raw values only at create/replace boundaries and rely on Cloak.Ecto to encrypt before persistence.
- Loaded schema structs may contain decrypted values only inside the Secret Bank context/runtime boundary; metadata/list APIs must explicitly drop or avoid exposing them.
- The logical decrypted schema field is marked `redact: true` where applicable so inspect/log output does not reveal decrypted values.
- Cloak Vault supports key rotation shape with tagged ciphers where practical, following the Doctor Smart pattern as a reference, but without copying app-specific names.
- Read/list APIs return safe metadata only: Secret Bank key, scope, source, configured state, timestamps, and allowed actions.
- No context API returns raw secret values except the dedicated trusted runtime resolution API introduced in Task 03.
- Changesets use project conventions, localized validation messages, and constraints from Task 01.
- Delete only deletes local scoped secrets and returns `:inherited_secret_not_deletable` for inherited sources.
- Replace requires a local secret and returns `:local_secret_required_for_replace` when appropriate.
- Env fallback is allowed only for configured Secret Bank keys from application config/runtime config.
- If a configured key has no explicit env var override, derive the env var name by convention, e.g. `github.token -> GITHUB_TOKEN`.
- If a configured key has an explicit env var override, use that name, e.g. `{"openrouter.default", "OPENROUTER_API_KEY"}`.
- Env fallback never queries the process environment as an open keyspace.
- No env allowlist CRUD context or Ecto schema is introduced.
- No tool binding CRUD context or Ecto schema is introduced.
- `$secrets.github.token` normalizes to `github.token`; malformed `$secrets.*` references return `:invalid_key`.
- Seeds can be run repeatedly without creating duplicate secret rows or changing existing sample secret values unless the seed intentionally owns that sample row.
- Seeded sample values are clearly fake, e.g. `dev_only_mock_github_token`, and must never look like real provider credentials.
- An IEx-friendly verification path exists for local development, e.g. create/list effective metadata and resolve `$secrets.github.token` in a seeded hierarchy.
- Error atoms align with the product taxonomy in section 12 of the product plan.

## Review Notes
Reject if any public metadata API exposes raw, partial, hashed, or previewed values, or if the implementation hand-rolls crypto instead of using Cloak/Cloak.Ecto.
