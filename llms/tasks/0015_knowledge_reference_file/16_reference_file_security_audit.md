# Task 16: Reference File Security Audit

## Status

- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent

`audit-security` - Security reviewer for authentication, authorization, input validation, secrets management, OWASP risks, and PII safety.

## Agent Invocation

Act as `audit-security`. Review the completed reference-file implementation for security and privacy risks.

## Objective

Confirm that reference-file behavior enforces scope, protects storage internals, and avoids content/path/secret leakage.

## Audit Scope

- World, City, Department, and Lemming scope enforcement in create, update, archive, availability, search, read, and promotion.
- Cross-World, sibling City, sibling Department, and wrong-Lemming denial.
- Lemming no-mutation boundary for create/edit/archive/delete/promote flows.
- Storage ref and path confidentiality in UI, tools, events, logs, errors, and descriptors.
- Filename/path validation, traversal rejection, symlink/root confinement, and temp upload handling.
- Artifact promotion cannot expose or depend on inaccessible Artifacts.
- Search/read errors do not reveal inaccessible resource existence.
- No secrets, configured roots, provider responses, full content bodies, or unsafe runtime state in outputs.

## Expected Outputs

- Security findings ordered by severity.
- Focused fixes for confirmed high-priority issues, if any.
- Explicit residual risks and recommended waivers/follow-ups.

## Suggested Checks

- Security-focused narrow tests
- `mix sobelow` if web/security surfaces changed and the repo task is available
- `mix precommit` when all security fixes are complete

## Human Approval Gate

Human reviewer validates security findings, fixes, and residual risks, then approves Task 17.
