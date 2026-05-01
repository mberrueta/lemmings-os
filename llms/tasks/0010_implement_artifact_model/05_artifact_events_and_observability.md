# Task 05: Artifact Events and Observability

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-logging-daily-guardian` - Logging quality guardian for safe structured events and metadata hygiene.

## Agent Invocation
Act as `dev-logging-daily-guardian`. Add safe Artifact lifecycle observability without changing product behavior.

## Objective
Emit durable/safe Artifact events for lifecycle operations and add tests proving event/log payloads do not leak content, filesystem paths, storage refs, notes, full metadata, or secret values.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/tasks/0010_implement_artifact_model/plan.md`
- [ ] Tasks 01-04 outputs
- [ ] `lib/lemmings_os/events.ex`
- [ ] `test/lemmings_os/events_test.exs`

## Expected Outputs
- [ ] `LemmingsOs.Artifacts.Events` or equivalent event helper.
- [ ] Emission for `artifact.created`, `artifact.promoted`, `artifact.updated`, `artifact.status_changed`, `artifact.deleted`, `artifact.read`, `artifact.promotion_failed`, and `artifact.error` as implemented paths allow.
- [ ] Allowlisted event payload fields from the source plan only.
- [ ] Tests proving forbidden fields are absent.

## Acceptance Criteria
- [ ] Event payloads include safe hierarchy/provenance IDs and artifact metadata only.
- [ ] Event payloads exclude file contents, `storage_ref`, resolved filesystem path, raw workspace path, full metadata blindly, notes by default, and secret values.
- [ ] Reason values are safe reason tokens, not exception dumps containing paths/content.
- [ ] Telemetry/logging metadata includes hierarchy fields where relevant.
- [ ] Existing generic `LemmingsOs.Events` is reused; no duplicate event table is introduced.

## Technical Notes
### Relevant Code Locations
```
lib/lemmings_os/events.ex              # Durable event API
lib/lemmings_os/events/event.ex        # Event schema
lib/lemmings_os/lemming_instances/executor/tool_lifecycle.ex # Logging metadata examples
test/lemmings_os/events_test.exs       # Durable event test patterns
```

### Constraints
- Do not log storage roots, storage refs, raw workspace paths, or file contents.
- Do not add UI.
- Do not call Secret Bank.

## Execution Instructions

### For the Agent
1. Read all inputs listed above.
2. Add event helper and wire it into completed Artifact context operations.
3. Add leakage-focused tests with sentinel path/content values.
4. Run narrow events/context tests.
5. Document assumptions, files changed, and test commands in Execution Summary.

### For the Human Reviewer
After agent completes:
1. Inspect event payload allowlist manually.
2. Verify no sensitive values appear in event/log tests.
3. Approve before Task 06 begins.

---

## Execution Summary
*[Filled by executing agent after completion]*
