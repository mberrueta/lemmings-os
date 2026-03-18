# Task 11: Test Scenarios and Coverage Plan

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 07, Task 08, Task 09, Task 10
- **Blocks**: Task 12

## Assigned Agent

`qa-test-scenarios` - Test scenario designer.

## Agent Invocation

Use `qa-test-scenarios` to define the test matrix for City foundations, runtime presence, UI behavior, and demo-level risks.

## Objective

Enumerate the exact deterministic scenarios that require automated coverage before the City branch can be accepted.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] Tasks 01 through 10 outputs
- [ ] `llms/constitution.md`
- [ ] `test/`

## Expected Outputs

- [ ] scenario matrix for schema/context behavior
- [ ] scenario matrix for resolver behavior
- [ ] startup/first-city scenarios
- [ ] heartbeat and stale-liveness scenarios
- [ ] LiveView selector coverage plan
- [ ] checklist for security/performance review focus areas

## Acceptance Criteria

- [ ] the scenario set covers domain, runtime, UI, and demo behavior
- [ ] scenarios are deterministic and aligned with DB sandbox testing
- [ ] the plan explicitly covers stale/unknown/alive behavior
- [ ] the plan calls out N+1, preload, and runtime exposure risks for review
- [ ] the plan does not assume Department or Lemming desmoke

## Technical Notes

### Relevant Code Locations

- `test/lemmings_os/`
- `test/lemmings_os_web/live/`
- `test/support/`

### Constraints

- Use factories rather than fixture-style helpers
- Prefer selector-driven LiveView verification
- Keep timing-sensitive behavior testable without sleep-heavy flows

## Execution Instructions

### For the Agent

1. Read the final approved implementation tasks before drafting scenarios.
2. Split scenarios by layer: data, runtime, read models, LiveViews, demo behavior.
3. Call out what should be unit, integration, or LiveView coverage.
4. Include a focused checklist for the later security/performance review.

### For the Human Reviewer

1. Confirm the scenario set is complete enough for the branch risk profile.
2. Confirm timing-sensitive areas are testable deterministically.
3. Confirm the later review tasks have the right focus list.
4. Approve before Task 12 begins.
