# Artifacts

## Observability scope

- Artifact lifecycle operations do not write durable audit rows to the `events` table.
- Artifact code does not rely on `LemmingsOs.Events` for lifecycle audit semantics.
- Any Artifact observability in this slice is limited to lightweight logging/telemetry only, with allowlisted safe fields.

## Future work

Platform audit/event model should be designed separately. That future design should define durable vs transient events, actor attribution, retention, immutability, event taxonomy, read/download audit, filtering/export, and whether the current `events` table is the audit log or a domain activity log.
