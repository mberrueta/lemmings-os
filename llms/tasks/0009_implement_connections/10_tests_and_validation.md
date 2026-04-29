# Task 10: Tests and Validation

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`qa-elixir-test-author`

## Agent Invocation
Act as `qa-elixir-test-author`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir_tests.md`, `llms/tasks/0009_implement_connections/plan.md`, and Tasks 01-09, then implement focused tests and run narrow validation.

## Objective
Add deterministic ExUnit and LiveView coverage for the implemented Connection MVP before final docs, audits, and precommit cleanup.

## Expected Outputs
- Schema and changeset tests.
- Context tests for CRUD, exact-scope behavior, status transitions, and hierarchy lookup.
- Runtime facade tests proving it resolves only safe Connection identity/visibility, rejects disabled/invalid records, blocks sibling Department and cross-World access, and does not call Secret Bank.
- Provider Caller tests for just-in-time secret ref resolution, missing secret refs, sanitized results, and no raw secret return values.
- Mock provider tests for deterministic success and failure.
- Event payload tests proving safe metadata and no secret leakage.
- LiveView tests for listing, CRUD/status/test controls, inherited scope indicators, redacted secret refs, and stable DOM selectors.
- Validation notes listing narrow commands run and results.

## Acceptance Criteria
- Tests cover the implemented acceptance criteria from `plan.md`.
- Tests use factories and do not introduce fixture-style helpers.
- Tests are deterministic and do not depend on real network calls.
- Secret values used in tests do not appear in runtime facade results, Caller return values, UI HTML, event payloads, logs, errors, or persisted Connection fields.
- Narrow relevant `mix test` commands pass.
- Any unrelated failures are documented with exact command output and evidence.

## Review Notes
Reject if tests require real providers, widen Tool Runtime scope, or assert against large raw HTML instead of stable selectors.
