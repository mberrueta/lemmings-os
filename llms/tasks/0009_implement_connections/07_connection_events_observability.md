# Task 07: Connection Events and Observability

## Status
- **Status**: REVISED

## Objective
Keep Connection lifecycle/resolve/test operations observable with safe metadata.

## Requirements
- Emit lifecycle, resolve, and test events.
- Event payload includes ids/scope/type/status and safe summaries.
- No raw secret values or resolved credentials in events/logs.

## Acceptance
- Event payloads are useful for operations and safe for security.
