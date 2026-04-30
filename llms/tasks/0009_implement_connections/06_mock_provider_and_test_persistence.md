# Task 06: Mock Provider and Test Persistence

## Status
- **Status**: REVISED

## Objective
Implement deterministic `mock` caller behavior and persist sanitized `last_test` text.

## Requirements
- `mock` type validates expected config structure.
- Caller resolves configured secret refs from `config` only.
- Caller returns sanitized result maps/errors.
- Context test action persists `last_test` on source row.
- Never persist or return raw secrets.

## Acceptance
- Success and failure paths update `last_test` safely.
- Inherited test updates parent source row only.
