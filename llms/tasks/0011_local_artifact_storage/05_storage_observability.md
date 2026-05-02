# Task 05: Storage Observability

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-logging-daily-guardian` - Logging quality guardian for structured safe metadata and telemetry consistency.

## Agent Invocation
Act as `dev-logging-daily-guardian`. Add or review only local Artifact storage observability. You may add narrow Logger/telemetry instrumentation and focused tests, but you must not change storage behavior.

## Objective
Ensure storage write/update/open/health paths emit safe Logger metadata and telemetry while explicitly avoiding durable audit/event persistence for this issue.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/project_context.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/tasks/0011_local_artifact_storage/plan.md`
- [ ] Tasks 01-04 outputs
- [ ] `lib/lemmings_os/artifacts/local_storage.ex`
- [ ] `lib/lemmings_os/artifacts.ex`
- [ ] Existing logging/telemetry patterns under `lib/lemmings_os/**`

## Expected Outputs
- [ ] Safe `Logger` metadata for storage success/failure paths where useful.
- [ ] Safe `:telemetry.execute/3` events for storage write/update/open/health outcomes.
- [ ] Canonical telemetry event names use atom-list events: `[:lemmings_os, :artifact_storage, :write, :start]`, `[:lemmings_os, :artifact_storage, :write, :stop]`, `[:lemmings_os, :artifact_storage, :write, :exception]`, `[:lemmings_os, :artifact_storage, :open, :stop]`, `[:lemmings_os, :artifact_storage, :open, :exception]`, `[:lemmings_os, :artifact_storage, :health_check, :stop]`, and `[:lemmings_os, :artifact_storage, :health_check, :exception]`.
- [ ] Artifact update/replacement uses the same storage write telemetry events; use metadata `operation: :update` when distinguishing replacement from first write is useful.
- [ ] String-style names such as `"artifact.storage.write.succeeded"` are used only for Logger `:event` metadata or log messages, not telemetry event names.
- [ ] Metadata includes hierarchy ids where available, operation, reason token, size/checksum where safe.
- [ ] Metadata excludes absolute paths, root path, raw workspace path, file contents, full metadata, notes, and secrets.
- [ ] No Artifact storage audit/telemetry rows are persisted with `LemmingsOs.Events`.
- [ ] Focused observability tests or test guidance for Task 06.

## Acceptance Criteria
- [ ] Telemetry event names match the canonical atom-list shapes from this task.
- [ ] All emitted telemetry has hierarchy metadata where available.
- [ ] Reason values are normalized safe tokens, not inspected exceptions with paths.
- [ ] `rg "Events.record_event|LemmingsOs.Events"` in Artifact storage paths shows no new durable event persistence for this feature.
- [ ] Tests or documented assertions verify forbidden fields are absent.

## Technical Notes
### Relevant Code Locations
```text
lib/lemmings_os/artifacts/local_storage.ex
lib/lemmings_os/artifacts.ex
lib/lemmings_os/events.ex                 # Durable events API; do not use for this issue
lib/lemmings_os/runtime/activity_log.ex   # In-memory feed; not required for this issue
```

### Constraints
- May add narrow Logger/telemetry instrumentation and focused tests.
- Must not change storage behavior, storage refs, file writing, path resolution, or download semantics.
- Do not write durable audit rows through `LemmingsOs.Events`.
- Do not log file contents, host paths, workspace paths, notes, full metadata, or secrets.
- Do not broaden feature behavior.
- Do not perform git operations.

## Execution Instructions
1. Read all inputs and current observability patterns.
2. Add or adjust safe Logger/telemetry only where useful.
3. Verify no durable Artifact storage audit persistence was introduced.
4. Run targeted tests or compilation checks.
5. Document metadata shape, commands, and any residual risk.

---

## Execution Summary
- Added safe Logger metadata and canonical `:telemetry` events for local storage write, open, and health-check outcomes.
- Telemetry events use `[:lemmings_os, :artifact_storage, ...]` atom-list names for write start/stop/exception, open stop/exception, and health_check stop/exception.
- Metadata is limited to ids, operation, sanitized filename token, size/checksum, status, and normalized reason tokens.
- Added tests for write/open/health telemetry, metadata leakage prevention, and safe failure logs.
- Verified no durable `LemmingsOs.Events` persistence is used in artifact storage/controller paths.

## Human Review
*[Filled by human reviewer]*
