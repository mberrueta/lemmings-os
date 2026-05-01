# Artifact Domain Model Execution Plan

## Scope Update (2026-05-01)

This PR slice excludes durable Artifact audit/event persistence.

### In-scope for this slice
- Keep Artifact schema, storage, promotion/update, download route, UI, and core docs behavior.
- Keep safety constraints for observability:
  - no file contents
  - no `storage_ref`
  - no resolved filesystem path
  - no raw workspace path
  - no notes/full metadata dumps
  - no secrets
- Allow only lightweight, optional non-durable observability (safe logs/telemetry).

### Out-of-scope for this slice
- Durable Artifact lifecycle event writes to `events`.
- Durable event wrappers such as `LemmingsOs.Artifacts.AuditEvents`.
- Durable `artifact.read` audit.
- Platform-wide audit taxonomy and policy design.

## Task 05 Rename

- From: `Artifact Events and Observability`
- To: `Artifact Instrumentation and Safe Logging`

## Future Work Note

Platform audit/event model should be designed separately. That future design should define durable vs transient events, actor attribution, retention, immutability, event taxonomy, read/download audit, filtering/export, and whether the current `events` table is the audit log or a domain activity log.
