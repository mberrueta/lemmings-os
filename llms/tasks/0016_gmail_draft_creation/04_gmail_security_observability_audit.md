# Task 04: Gmail Security And Observability Audit

## Status

- **Status**: NOT STARTED
- **Approved**: [ ] Human sign-off

## Assigned Agent

`audit-security` - Security reviewer for authentication, authorization, input validation, secrets management, OWASP risks, and PII safety.

## Agent Invocation

Act as `audit-security`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/tasks/0016_gmail_draft_creation/plan.md`, Tasks 01-03, and the implementation diff. Perform a security and observability audit of the Gmail OAuth onboarding and `email.create_draft` implementation.

## Objective

Verify that the implementation is safe for credentials, OAuth state handling, attachment boundaries, provider errors, and operational visibility.

## Audit Scope

- OAuth state generation, expiry, session binding, and callback validation.
- CSRF and browser-session assumptions under current local-admin control-plane mode.
- Gmail compose-only scope and absence of read/send/sync functionality.
- Secret Bank storage of refresh tokens and runtime-only resolution.
- Connection config containing refs and safe metadata only.
- Gmail adapter credential exchange and authorization header handling.
- Artifact attachment access by ID through scope-checked APIs only.
- Sanitized tool errors, provider failures, events, logs, raw context pages, and timeline payloads.
- Best-effort event recording that cannot fail successful draft creation.
- No token, credential, storage ref, local path, or raw provider body leakage.

## Expected Outputs

- Security findings ordered by severity.
- Observability findings about event/log completeness and safety.
- Targeted remediation requirements for confirmed defects.
- Explicit residual risks, including the current absence of implemented per-user control-plane auth.
- Recommendation to proceed, block, or re-audit.

## Suggested Checks

```bash
mix test test/lemmings_os/connections test/lemmings_os/tools test/lemmings_os/artifacts
mix sobelow # if already available in the project
```

## Acceptance Criteria

- OAuth callback cannot be replayed or completed with missing, invalid, expired, or mismatched state.
- No credential material is persisted outside Secret Bank or emitted to unsafe surfaces.
- No Gmail read/send/sync capability is reachable.
- Attachment scope enforcement is server-side and tested.
- Events include useful safe metadata for success and failure without raw payload leakage.
- Confirmed high and medium security findings are fixed or explicitly waived by the human reviewer.

## Human Approval Gate

Human reviewer validates security and observability findings before the accessibility audit begins.
