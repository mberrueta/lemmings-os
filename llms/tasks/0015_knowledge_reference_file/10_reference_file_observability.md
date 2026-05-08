# Task 10: Reference File Observability

## Status

- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent

`dev-logging-daily-guardian` - Logging quality guardian for structured events, hierarchy metadata, and safe observability.

## Agent Invocation

Act as `dev-logging-daily-guardian`. Add or normalize safe observability for reference-file lifecycle and access behavior.

## Objective

Ensure reference-file create, update, archive, search, read, and Artifact promotion events are observable without leaking content, paths, storage details, or secrets.

## Implementation Scope

- Use `LemmingsOs.Events.record_event/4` or established local patterns for durable events.
- Add safe event types such as `knowledge.reference_file.created`, `updated`, `archived`, `search_performed`, `read`, and `artifact_promoted`.
- Include hierarchy metadata and safe IDs: `world_id`, `city_id`, `department_id`, `lemming_id`, `lemming_instance_id`, `knowledge_item_id`, `reference_ref`, type, status, source, and result count where safe.
- Normalize Logger metadata where lifecycle or failure logs are useful.
- Ensure search/read event payloads do not include query content if it may contain sensitive text.

## Constraints

- Never log or emit full file content, raw file paths, storage roots, temp paths, raw storage refs, secrets, credentials, raw extraction output, or unsafe runtime state.
- Avoid noisy logs for normal search/read paths.
- Keep observability changes scoped to reference-file behavior.

## Expected Outputs

- Safe durable events or logs for lifecycle and access operations.
- Tests or test support for event payload safety.
- No increased log noise with full user payloads.

## Suggested Checks

- `mix format`
- Narrow event/log tests where practical
- Existing event-related tests

## Human Approval Gate

Human reviewer validates observability payloads and no-leak guarantees, then approves Task 11.
