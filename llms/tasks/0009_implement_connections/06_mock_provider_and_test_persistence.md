# Task 06: Mock Provider and Test Persistence

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, `llms/tasks/0009_implement_connections/plan.md`, and Tasks 01-05, then implement deterministic mock provider validation and Connection test behavior.

## Objective
Prove the Connection model with deterministic mock provider behavior and safe persisted test status.

No real network call or provider integration is allowed in this task.

## Expected Outputs
- Mock provider module under the Connections boundary.
- `LemmingsOs.Connections.Providers.MockCaller` or equivalent provider Caller module.
- Validation for executable `type: "mock"` behavior.
- Deterministic success mode (`mode: "echo"`) when config is valid and required secret refs in `config` resolve.
- Deterministic failures for invalid config and missing/unresolvable secret refs.
- Context API for testing a Connection.
- Safe persistence of `last_test` summary text.
- Safe test events for started, succeeded, and failed outcomes.
- When testing an inherited Connection, persist `last_test_*` on the resolved source Connection row, not on the caller scope.
- When testing an inherited Connection, persist `last_test` on the resolved source Connection row, not on the caller scope.
- Do not create an implicit child override during test.
- The Caller is the only module in this slice allowed to call `LemmingsOs.SecretBank.resolve_runtime_secret/2` or `/3`.
- The Caller resolves secret references stored in `config` just-in-time and never returns raw secret values.
- The Caller returns only sanitized success/failure results.

## Acceptance Criteria
- Mock provider tests do not make network calls.
- Valid mock config plus resolvable secret refs succeeds.
- Invalid mock config fails with a safe reason.
- Missing secret refs fail inside the Caller without returning partial credentials.
- Disabled or invalid Connections do not pass runtime testing.
- Testing an inherited City or World Connection from a Department updates the inherited source row only.
- Testing an inherited Connection never inserts a child-scope override.
- Persisted `last_test` never includes raw secret values or resolved credentials.
- Unsupported provider combinations do not perform provider-specific behavior.
- Runtime-facing facades do not resolve Secret Bank refs; only the provider Caller performs just-in-time secret resolution.

## Review Notes
Reject if this task adds SMTP, Gmail, OpenRouter, storage, messaging, GitHub, OAuth, or any other real provider adapter.
