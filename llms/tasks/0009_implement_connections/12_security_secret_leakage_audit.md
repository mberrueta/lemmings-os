# Task 12: Security Audit for Secret Leakage

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

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
