# Task 12: Security Audit for Secret Leakage

## Status
- **Status**: COMPLETED
- **Approved**: [x] Human sign-off

## Assigned Agent
`audit-security`

## Agent Invocation
Act as `audit-security`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/tasks/0009_implement_connections/plan.md`, and Tasks 01-11, then review the complete Connection implementation for secret leakage and scope isolation failures.

## Objective
Verify that Connections preserve the product safety guarantees around secret references, Caller-only credential resolution, safe observability, and hierarchy isolation.

## Scope
Review:

- database schema and migrations;
- schema changesets;
- context APIs;
- hierarchy lookup;
- runtime facade and provider Caller boundary;
- mock provider and test persistence;
- durable events, logs, and telemetry;
- UI rendering and LiveView assigns;
- tests;
- documentation.

## Security Requirements
- Runtime facades must not resolve Secret Bank refs.
- Only provider Caller modules may resolve secrets, and only inside trusted execution.
- Audit all `LemmingsOs.SecretBank` call sites added or touched by this slice and verify only approved provider Caller modules call runtime secret resolution.
- No other module added or modified by this Connections slice should call Secret Bank runtime resolution directly.
- Raw secrets must not leave the Caller boundary.
- Raw secrets must never be persisted in Connections.
- Secret references are expected inside `config` values; no separate `secret_refs` column exists in this simplified model.
- Raw secrets must never be rendered in UI, flash messages, validation errors, logs, events, telemetry, docs, test output, snapshots, prompts, or Lemming-facing payloads.
- No secret previews, hashes, fingerprints, first/last characters, or transformed credential material may be exposed.
- Sibling Department and cross-World resolution must fail safely.
- Disabled and invalid Connections must not be usable by the runtime-facing facade or provider Callers.

## Expected Outputs
- Security review findings with file/line references where applicable.
- Fixes for any blocking leak-prevention or isolation defects introduced by this slice.
- Explicit final disposition for any remaining risks that require human decision.

## Acceptance Criteria
- No reviewed path exposes raw or derived secret values.
- Runtime facades resolve identity and visibility only, and do not call Secret Bank.
- Provider Caller modules resolve credentials just-in-time and return only sanitized results.
- Secret Bank runtime resolution call sites are inventoried and limited to the intended provider Caller modules.
- Raw credentials do not escape the Caller boundary.
- Safe events contain useful hierarchy/Connection metadata without credentials.
- UI never reveals resolved secret values.
- Cross-World and sibling Department access are blocked.
- No new auth/RBAC/approval workflow was added.

## Review Notes
Reject if secret leakage exists through any code, UI, event, log, test, or documentation path.

## Findings
- **Blocker (fixed): caller-provided `last_test` could be persisted and emitted in events.**
  - `lib/lemmings_os/connections/connection.ex` previously cast `:last_test` in the main CRUD changeset.
  - This allowed non-runtime callers of `create_connection/2` and `update_connection/3` to inject arbitrary `last_test` text.
  - Fix: removed `:last_test` from castable optional fields so only internal runtime test persistence (`Ecto.Changeset.change/2`) updates it.
  - Regression coverage: `test/lemmings_os/connections_test.exs` ("ignores caller-provided last_test when creating/updating connection").

- **Blocker (fixed): provider caller allowed direct use of disabled/invalid connections.**
  - `lib/lemmings_os/connections/providers/mock_caller.ex` accepted any `%Connection{}` with type `mock` and valid config.
  - A direct caller could invoke credential resolution even when `status` was `disabled` or `invalid`.
  - Fix: added early status guards returning `{:error, :disabled}` / `{:error, :invalid}` before any secret resolution.
  - Regression coverage: `test/lemmings_os/connections/providers/mock_caller_test.exs` ("rejects disabled and invalid connections before any secret resolution").

## Secret Resolution Call-Site Inventory (Connections Slice)
- `lib/lemmings_os/connections/providers/mock_caller.ex`: `SecretBank.resolve_runtime_secret/3` (approved provider Caller boundary).
- No other module in the Connections slice directly calls `SecretBank.resolve_runtime_secret/3`.
- `lib/lemmings_os/connections/runtime.ex` remains identity/visibility/status-only and does not resolve secrets.

## Audit Summary by Requirement
- Runtime facade secret boundary: pass (`LemmingsOs.Connections.Runtime` performs visibility/status checks only).
- Caller-only resolution: pass (runtime secret resolution confined to `MockCaller`).
- Raw credential egress: pass (caller returns sanitized fields only; events persist safe payloads only).
- Persistence boundary: pass after hardening `last_test` casting.
- UI/rendering boundary: pass for resolved credentials (UI only shows config text/refs and safe test summaries).
- Isolation boundary: pass (mismatched child ownership fails closed; sibling department/cross-world blocked).
- Disabled/invalid usability: pass after `MockCaller` status guard fix.

## Remaining Risk Requiring Human Decision
- Current enforcement prevents raw secret storage for known secret-bearing fields in supported connection types (for `mock`, `api_key` must be a `$REF`), but does not apply generic secret-pattern detection across every arbitrary `config` string field.
- Decision required: keep contract-based validation (current approach) vs. add global heuristic scanning with potential false positives.

## Validation Notes
- `mix test test/lemmings_os/connections_test.exs test/lemmings_os/connections/runtime_test.exs test/lemmings_os/connections/providers/mock_caller_test.exs`
  - Result: pass (`23 doctests, 31 tests, 0 failures`)
- `mix precommit`
  - Result: pass (Dialyzer/Credo clean)
