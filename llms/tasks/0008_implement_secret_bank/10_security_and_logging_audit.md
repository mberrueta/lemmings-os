# Task 10: Security and Logging Audit

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`audit-security`

## Supporting Agent
`dev-logging-daily-guardian`

## Agent Invocation
Act as `audit-security`. Review the Secret Bank implementation, tests, and diffs for secret handling risks. Coordinate with `dev-logging-daily-guardian` for logging/audit event consistency if needed.

## Objective
Find and fix secret leakage, unsafe crypto/configuration, authorization-scope, validation, and observability issues before UI accessibility and docs work.

## Expected Outputs
- Security findings and fixes, if needed.
- Logging/audit consistency notes.
- Updated tests if fixes require regression coverage.

## Acceptance Criteria
- No raw secret value or derived preview is persisted, logged, rendered, broadcast, traced, included in telemetry, sent to model runtime, or stored in snapshots.
- Secret value encryption uses Cloak/Cloak.Ecto, not custom cryptography.
- Production encryption key material comes from environment-backed configuration and is not hardcoded.
- Dev/test key material, if present, is clearly labelled as non-production and cannot silently be used in production.
- Decrypt failures and exceptions are safe.
- Runtime access path is narrow and only resolves `$secrets.*` references present in trusted tool/adapter configuration; it does not resolve model-provided, Lemming-provided, user-provided, or runtime tool args.
- World scoping and hierarchy IDs are enforced.
- Durable audit events are safe and complete.

## Review Notes
Findings should lead with severity and file/line references. Human approval is required before continuing.
