# Task 01: Gmail Connection OAuth And Secret Storage

## Status

- **Status**: COMPLETED
- **Approved**: [x] Human sign-off

## Implementation Progress (2026-05-11)

### Done

- [x] Added Gmail provider/caller module under Connections:
  `LemmingsOs.Connections.Providers.GmailCaller`.
- [x] Registered `gmail` in `LemmingsOs.Connections.TypeRegistry`.
- [x] Added Gmail config contract validation for:
  - `provider = "gmail"`
  - compose-only Gmail scope
  - secret refs for `client_id`, `client_secret`, and `refresh_token`
  - optional `account_email`
- [x] Added OAuth backend boundary and HTTP client:
  - `LemmingsOs.Connections.GmailOAuth`
  - `LemmingsOs.Connections.GmailOAuth.Client` (Req-based token exchange)
- [x] Added OAuth start + callback routes/controller:
  `LemmingsOsWeb.GmailOAuthController` and router entries.
- [x] Added session-bound OAuth state with expiry checks and callback validation path.
- [x] Added Secret Bank + Connection upsert flow in the Gmail OAuth boundary.
- [x] Wired safe OAuth lifecycle events:
  `connection.gmail.oauth_started`, `connection.gmail.oauth_succeeded`,
  `connection.gmail.oauth_failed`.
- [x] Added initial doctests/tests coverage for:
  - Gmail type registry presence
  - Gmail config validation
  - Connection changeset Gmail validation
  - OAuth start redirect/scope + callback invalid-state rejection

### Remaining Before Approval

- [x] Add automated happy-path callback test proving:
  code exchange, refresh token persistence in Secret Bank, and Connection create/update behavior.
- [x] Add callback rejection matrix coverage for missing/expired/mismatched state-session and explicit scope-tampering cases.
- [x] Expand validation tests for disallowed raw credential patterns (access token/authorization header/password-like values).
- [x] Add no-secret-leak assertions for failure paths/events/provider error handling.
- [x] Run full final gate (`mix precommit`) once the remaining behavior/tests are complete.

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix contexts, external integrations, secrets, observability, and tests.

## Agent Invocation

Act as `dev-backend-elixir-engineer`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, `llms/coding_styles/elixir_tests.md`, `llms/tasks/0016_gmail_draft_creation/plan.md`, and this task. Implement only the Gmail Connection type, OAuth onboarding backend boundary, Secret Bank storage, safe events, and tests needed for connection setup.

## Objective

Add the safe connection foundation for Gmail:

- register a `gmail` Connection type;
- validate Gmail Connection config shape;
- start Google OAuth with the Gmail compose scope only;
- validate OAuth callback state/session;
- exchange the authorization code through a testable HTTP boundary;
- store the returned refresh token through Secret Bank;
- create or update the effective scope-local `gmail` Connection with safe metadata.

This task does not implement `email.create_draft` and does not add Gmail send, read, sync, or mailbox functionality.

## Scope Notes

- `connection_ref = "gmail"` maps to Connection `type = "gmail"` for this MVP.
- The current app has local-admin control-plane behavior and no implemented authenticated user model. Bind OAuth state to the browser session and document this as the ADR-0010 sequencing limitation; do not introduce users/RBAC in this task.
- OAuth state must bind the selected target scope (`world`, `city`, or `department`) to the browser session. The callback must not trust scope identifiers supplied only by callback params.
- Use `Req` for Google token calls and any compose-scope-safe metadata calls. Do not add dependencies.
- Prefer session-bound OAuth state with expiry. Do not add a migration unless implementation discovers a reviewed need.
- Account email is optional. Do not request additional OAuth scopes only to populate `account_email`. If the compose-only scope does not provide safe account metadata, leave `account_email` blank or use a safe operator-provided label.

## Expected Outputs

- Gmail provider/caller module under the Connections boundary.
- `gmail` entry in `LemmingsOs.Connections.TypeRegistry`.
- Config validation that accepts only safe Gmail metadata and Secret Bank refs:
  - `provider = "gmail"`
  - compose-only `scopes`
  - `client_id`, `client_secret`, and `refresh_token` as refs, not raw values
  - optional safe `account_email`
- OAuth start and callback backend routes/controllers or equivalent Phoenix boundary.
- OAuth state generation, expiry, and callback validation.
- Refresh token persistence through `LemmingsOs.SecretBank.upsert_secret/3`.
- Connection create/update through `LemmingsOs.Connections` context APIs.
- Safe `connection.gmail.oauth_started`, `connection.gmail.oauth_succeeded`, and `connection.gmail.oauth_failed` events, or similarly scoped names consistent with existing event vocabulary.
- Documentation and doctests for any new public backend APIs, including parameters, return values, and examples.

## Testing Requirements

- Add doctests for the Gmail provider public functions and any new public OAuth helper module.
- Extend Connection and TypeRegistry tests to prove `gmail` is registered, validated, and listed without regressing `mock`.
- Test Gmail config validation accepts only Secret Bank refs and rejects raw access tokens, refresh tokens, client secrets, authorization headers, and passwords.
- Test OAuth start generates state, stores only safe session data, and redirects with exactly the Gmail compose scope.
- Test callback rejects missing, invalid, expired, and mismatched state/session.
- Test callback rejects scope tampering, such as changing the target scope between OAuth start and callback.
- Test callback exchanges an authorization code through a fake Google endpoint or injected fake client.
- Test refresh token storage uses Secret Bank and Connection config stores only the generated ref.
- Test create/update behavior when a local `gmail` Connection already exists at the selected scope.
- Test failures return safe UI/backend errors and do not include token values or raw Google response bodies.

## Suggested Checks

```bash
mix test test/lemmings_os/connections test/lemmings_os/secret_bank_test.exs
mix test test/lemmings_os_web/controllers
mix format
```

When the task is complete and ready for human approval, run `mix precommit` if the task changes are stable enough for a full gate.

## Acceptance Criteria

- `gmail` is a registered Connection type.
- Normal onboarding creates or updates a scope-local Gmail Connection.
- Refresh tokens are stored only in Secret Bank.
- Connection config contains refs and safe metadata only.
- OAuth state is session-bound, expires, and fails closed.
- OAuth requests only the Gmail compose scope.
- No token value appears in logs, events, Connection config, test failures, or rendered errors.
- Existing `mock` Connection behavior still passes.
- Human reviewer can approve Task 02 after reviewing test evidence and public API docs/doctests.

## Human Approval Gate

Human reviewer validates the connection/OAuth behavior, no-secret-leak tests, and API documentation before backend draft creation work begins.
