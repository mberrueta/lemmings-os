# Task 03: Connection Context CRUD

## Status
- **Status**: REVISED

## Objective
Provide exact-scope CRUD and lifecycle actions for simplified Connections.

## Requirements
- Keep world-scoped APIs explicit.
- CRUD at exact local scope only.
- `enable`, `disable`, `mark_invalid` status transitions.
- Events remain safe and do not include secret values.
- Use `type` as logical identity in local/visible lookup APIs.

## Acceptance
- Context APIs operate with simplified schema only.
- No slug/provider/secret_refs legacy behavior remains.
