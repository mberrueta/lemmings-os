# Task 08: Test Scenarios and Safety Matrix

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

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

## Execution Summary
- Added linked scenario plan: `llms/tasks/0008_implement_secret_bank/test_plan.md`.
- Covered backend/database, context, runtime/tool integration, LiveView, env fallback, audit/observability, seeds, and leak-prevention scenarios.
- Mapped product acceptance areas to required test layers and scenario IDs.
- Added a safety matrix for UI, assigns/rendered client state, logs, audit events, telemetry, PubSub, prompts, snapshots/checkpoints, finalization payloads, context read models, database storage, and env fallback UI.
- Listed narrow Task 09 test commands before final `mix precommit`.

## Notes For Task 09
- Reconcile `$secrets.*` naming in the product plan with the current implementation's `$` prefix behavior before writing normalization assertions.
- Use fake sentinel values only and assert absence from every serialized/rendered/observable surface.
- Prefer targeted selectors and payload assertions over large raw HTML assertions.
