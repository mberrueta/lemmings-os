# Task 09: Test Implementation

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`qa-elixir-test-author`

## Agent Invocation
Act as `qa-elixir-test-author`. Implement ExUnit, context, runtime, and LiveView tests from Task 08 using existing factory and test conventions.

## Objective
Add deterministic coverage for Secret Bank behavior and safety guarantees.

## Expected Outputs
- Tests under `test/**`.
- Factory additions under `test/support/factory.ex` if needed.
- Task summary listing exact test commands run.

## Acceptance Criteria
- Tests cover schema/context behavior, hierarchy resolution, `$secrets.*` normalization, tool integration, durable audit events, config-file/convention env fallback behavior, and UI workflows.
- Tests verify `value_encrypted` stores a binary Cloak ciphertext that does not equal or contain the submitted plaintext.
- Tests verify context metadata/list APIs do not expose decrypted values even though the schema can decrypt inside the Secret Bank boundary.
- Tests verify no `secret_bank_tool_bindings` table/schema/context/UI exists.
- Tests verify `$secrets.*` references in model-provided or Lemming-provided tool args are not resolved and do not trigger secret access audit events.
- Tests verify `$secrets.*` references in trusted tool/adapter configuration are resolved for the trusted adapter/runtime path.
- Tests cover idempotent seeds: running `priv/repo/seeds.exs` repeatedly does not duplicate sample Secret Bank rows and keeps seeded hierarchy counts stable.
- Tests cover the seeded/demo secret resolution path with fake values only.
- Tests assert raw secret values do not appear in metadata read models, LiveView rendered HTML, audit events, telemetry/log payloads where captured, PubSub runtime events, prompts, snapshots, or finalization payloads.
- LiveView tests use stable selectors and `Phoenix.LiveViewTest` helpers.
- Tests use factories, not fixture-style helpers.
- Narrow relevant tests pass before handing off.

## Review Notes
Reject if tests assert against large raw HTML blobs or depend on timing/order without deterministic controls.

## Execution Summary

- Added schema safety regression to assert `secret_bank_tool_bindings` table does not exist.
- Extended tools runtime coverage to assert untrusted tool args using secret-like refs do not produce `secret.accessed` events.
- Extended seeds idempotency coverage to assert Secret Bank sample row count stability across reruns and ciphertext-only storage when a seeded local row exists.

## Commands Run

```bash
mix format test/lemmings_os/secret_bank_test.exs test/lemmings_os/tools/runtime_test.exs test/lemmings_os/seeds_test.exs llms/tasks/0008_implement_secret_bank/09_test_implementation.md
mix test test/lemmings_os/secret_bank_test.exs test/lemmings_os/tools/runtime_test.exs test/lemmings_os/seeds_test.exs
mix format test/lemmings_os/seeds_test.exs
mix test test/lemmings_os/secret_bank_test.exs test/lemmings_os/tools/runtime_test.exs test/lemmings_os/seeds_test.exs
mix precommit
```
