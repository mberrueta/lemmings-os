# Task 13: Release and Final Review

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`rm-release-manager`

## Supporting Agent
`audit-pr-elixir`

## Agent Invocation
Act as `rm-release-manager`. Prepare release notes, migration/runbook, rollback notes, and final validation instructions. Then have `audit-pr-elixir` perform the final PR review.

## Objective
Close the Secret Bank branch with operational notes, validation evidence, and a final staff-level Elixir/Phoenix review.

## Expected Outputs
- Release notes/runbook updates where appropriate.
- Final validation summary with commands run.
- Final PR audit findings or explicit no-findings statement.

## Acceptance Criteria
- Migration risk, Cloak dependency impact, encryption key configuration, and rollback implications are documented.
- Narrow tests have passed and final `mix precommit` has passed.
- Final review covers correctness, security, logging/audit, performance, UI integration, and test coverage.
- Any remaining risks or deferred work are explicitly listed for human decision.

## Review Notes
Do not perform git add/commit/push. Human handles all version control operations.

## Execution Notes

- Release/runbook notes are kept in this task file only. No `docs/releases`
  artifacts were added because the project is not near an initial release.
- No `CHANGELOG.md` entry was added; changelog introduction is deferred until a
  later PR.
- Narrow validation:
  - `mix test test/lemmings_os/secret_bank_test.exs test/lemmings_os/events_test.exs test/lemmings_os/tools/runtime_test.exs test/lemmings_os/seeds_test.exs test/lemmings_os_web/live/world_live_test.exs`
  - Result before final audit hardening: passed on 2026-04-29, 47 tests, 5 doctests, 0 failures.
- Final validation:
  - `mix precommit`
  - Previous result before final audit hardening: passed on 2026-04-29; Dialyzer reported 0 errors, Credo found no priority issues.
- Final audit hardening:
  - Blocked secret-bearing web headers unless trusted config explicitly allowlists the destination host.
  - Recorded `secret.used_by_tool` with actual request outcome instead of pre-request success.
  - Made Secret Bank create/replace/delete fail closed when their durable audit event cannot be persisted.
  - Preserved secret value bytes except rejecting blank-only values.
  - Added hierarchy IDs to Secret Bank mutation audit payloads.
  - `mix test test/lemmings_os/secret_bank_test.exs test/lemmings_os/tools/runtime_test.exs`
  - Result: passed on 2026-04-29, 40 tests, 4 doctests, 0 failures.
- Final validation rerun:
  - `mix precommit`
  - Result: passed on 2026-04-29; Dialyzer reported 0 errors, Credo found no priority issues.
  - `mix test test/lemmings_os/secret_bank_test.exs test/lemmings_os/events_test.exs test/lemmings_os/tools/runtime_test.exs test/lemmings_os/seeds_test.exs test/lemmings_os_web/live/world_live_test.exs`
  - Result: passed on 2026-04-29, 50 tests, 5 doctests, 0 failures.

## Final PR Audit Disposition

- Critical finding fixed: secret-bearing `web.fetch` headers are blocked unless trusted config explicitly allowlists the request destination host.
- High audit finding fixed: Secret Bank create/replace/delete now persist the durable audit event in the same transaction and fail closed if the event cannot be recorded.
- Medium findings fixed: `secret.used_by_tool` records actual request outcome, secret values preserve leading/trailing bytes, and mutation audit payloads include immutable hierarchy IDs.
- Remaining human sign-off risk: Secret Bank operator UI lives on the existing unauthenticated control-plane routes. This is consistent with the MVP's local trusted-admin assumption, but production deployment must use external/private access controls until the auth/authz slices land.
- Merge recommendation: conditional on human acceptance of the unauthenticated-control-plane deployment constraint.

## Branch Readiness Notes

### Migration and Data Risk

- Migration: `priv/repo/migrations/20260428134026_create_secret_bank_data_model.exs`
- Creates new `secret_bank_secrets` and `events` tables with lookup and audit indexes.
- Does not rewrite existing tables or backfill existing rows.
- Rollback is destructive if Secret Bank has been used: dropping the migration removes encrypted local secrets and durable audit history.

### Configuration

- Production boot requires `LEMMINGS_SECRET_BANK_KEY_BASE64`.
- The value must be Base64 that decodes to exactly 32 bytes.
- Losing or changing this key makes existing local Secret Bank values unreadable without a coordinated recovery/migration process.

### Operational Checks

- Confirm the application boots with Vault configured.
- Create, replace, and delete a fake World secret from the UI.
- Confirm UI and audit activity never expose raw values.
- Configure a trusted web tool secret header with an explicit `allowed_hosts` entry and verify it succeeds only for that host.
- Remove the allowlist and verify `tool.secret.destination_not_allowed`.

### Remaining Risks / Deferred Work

- Control-plane routes remain unauthenticated in this MVP and require external/private access controls for any real deployment.
- No automated key rotation or external KMS integration.
- No connection-object UI or persisted provider binding model; trusted tool config plus exact host allowlists are the current boundary.
