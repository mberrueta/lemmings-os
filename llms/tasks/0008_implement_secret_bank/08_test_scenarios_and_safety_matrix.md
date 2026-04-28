# Task 08: Test Scenarios and Safety Matrix

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`qa-test-scenarios`

## Agent Invocation
Act as `qa-test-scenarios`. Build an implementation-aware test scenario plan for Secret Bank.

## Objective
Define the backend, runtime, LiveView, audit, and leak-prevention scenarios required before implementation can be considered complete.

## Expected Outputs
- Scenario matrix added to this task's execution summary or a linked test plan file under this task directory.
- Clear mapping from product acceptance criteria to test layers.

## Acceptance Criteria
- Scenarios cover create, replace, delete, effective source display, inherited delete prevention, and override fallback at every hierarchy level.
- Scenarios cover config-file env allowlist fallback and non-allowlisted env behavior.
- Scenarios cover `$secrets.*` normalization, missing secret, malformed secret reference, and failed decrypt/provider states.
- Scenarios cover durable audit events for admin changes and runtime access/failure.
- Safety matrix identifies every surface that must not contain secret values: UI, assigns, logs, audit events, telemetry, PubSub events, prompts, snapshots, and finalization payloads.
- Plan identifies narrow tests to run after Task 09 and final `mix precommit`.

## Review Notes
Reject if tests only verify happy paths or omit negative leak-prevention assertions.
