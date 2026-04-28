# Task 12: Feature Documentation

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`docs-feature-documentation-author`

## Agent Invocation
Act as `docs-feature-documentation-author`. Inspect the implemented code and tests, then document the actual Secret Bank behavior.

## Objective
Create developer/operator documentation and ADR updates for Secret Bank that explain implemented behavior, workflows, permissions assumptions, runtime access, safety guarantees, audit events, configuration, and limitations.

## Expected Outputs
- Feature documentation under the closest discoverable location, likely `docs/features/secret_bank.md`.
- ADR updates where MVP behavior differs from existing architecture text.
- Links or references from existing README/docs if needed.

## Acceptance Criteria
- Docs describe actual implemented behavior, not intended future behavior.
- Review and update ADRs where MVP behavior differs from existing architecture text.
- ADR updates distinguish current MVP behavior from intended future behavior and implementation sequencing constraints.
- At minimum, review:
  - `docs/adr/0008-lemming-persistence-model.md`
  - `docs/adr/0009-secret-bank-hierarchical-secret-management.md`
  - `docs/adr/0010-control-plane-authentication-admin-access.md`
  - `docs/adr/0011-control-plane-authorization-model.md`
  - `docs/adr/0017-runtime-topology-city-execution-model.md`
  - `docs/adr/0018-audit-log-event-model.md`
  - `docs/adr/0020-hierarchical-configuration-model.md`
- ADR updates explicitly call out that this MVP uses convention-based `$secrets.*` references and does not implement tool binding tables or full connection management.
- Docs explain local-admin assumption and lack of RBAC/auth in this slice.
- Docs document env configuration needed for encryption key material and config-file env allowlist fallback.
- Docs include the env fallback config contract:
  `env_fallbacks: ["github.token", {"openrouter.default", "OPENROUTER_API_KEY"}]`.
- Docs document that persisted secret values are encrypted with Cloak/Cloak.Ecto and stored in `value_encrypted`, while safe metadata remains visible to DB readers.
- Docs document `$secrets.github.token -> github.token -> GITHUB_TOKEN` convention and the absence of tool binding tables/UI.
- Docs explain hierarchy override order and runtime lookup order.
- Docs include a local IEx/dev verification section using the seeded fake secret and `$secrets.github.token`, including the expected safe metadata result and a warning that raw values are only returned by the trusted runtime resolution API.
- Docs explain that `mix run priv/repo/seeds.exs` is idempotent and uses fake dev-only sample secret values.
- Docs explain write-only value behavior and what the UI will never show.
- Docs list durable audit events and safe metadata.
- Docs list known limitations and out-of-scope items from the MVP.

## Review Notes
Reject if documentation claims support for auth/RBAC, external secret managers, rotation automation, or value reveal/export behavior.
