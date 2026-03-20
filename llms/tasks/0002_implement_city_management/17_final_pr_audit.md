# Task 17: Final PR Audit

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: Task 16
- **Blocks**: None

## Assigned Agent

`audit-pr-elixir` - Staff-level PR reviewer for Elixir/Phoenix backends.

## Agent Invocation

Use `audit-pr-elixir` to perform the final PR audit for the City branch.

## Objective

Verify the branch is ready for human review with scope control, correctness, security, performance, testing, documentation, and ADR alignment all intact.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] Tasks 01 through 16 outputs
- [ ] test results
- [ ] precommit results
- [ ] coverage report
- [ ] final ADR/doc/runbook updates

## Expected Outputs

- [ ] final PR audit findings or explicit no-findings result
- [ ] residual risk summary
- [ ] recommendation on whether the branch is ready for human merge review

## Acceptance Criteria

- [ ] the audit checks branch scope against the approved City plan
- [ ] the audit checks correctness, regressions, missing tests, and remaining operator risk
- [ ] no unresolved high-severity issues remain
- [ ] any remaining lower-severity risks are documented explicitly

## Technical Notes

### Constraints

- Findings first if any exist
- Focus on bugs, regressions, missing coverage, runtime assumptions, and scope drift
- Keep the review grounded in the actual final branch state

## Execution Instructions

### For the Agent

1. Review the final branch in code-review mode.
2. Prioritize correctness and risk over summaries.
3. Call out any residual mismatch with the approved plan.
4. State explicitly if no findings remain.

### For the Human Reviewer

1. Review the final audit and residual risks.
2. Decide whether the branch is ready for manual git and PR handling.
3. If approved, use the audit as the final handoff checkpoint.

## Execution Summary

### Audit Verdict
APPROVE

### Risk Level
Low

### Findings Summary
| Severity | Count | Description |
|----------|-------|-------------|
| BLOCKER | 0 | None |
| MAJOR | 0 | None |
| MINOR | 3 | M1: `fetch_runtime_city` pattern match not defensive against impossible duplicates. M2: Heartbeat caches `current_city` indefinitely, does not nil on changeset error. M3: Docker Compose `depends_on` lacks health check, city nodes may crash-loop briefly before migrations complete. |
| NITS | 2 | N1: Spec/default asymmetry on `list_cities_query`. N2: All tests use `async: false` even when not required. |

### Scope Drift
No drift detected. Branch stays within frozen plan boundaries. No unplanned modules, migrations, or surface area.

### Coverage Residual Risk
- `cities/heartbeat.ex` at 50% -- acceptable, GenServer lifecycle hard to unit-test, core persistence path covered
- `cities/runtime.ex` at 64.5% -- acceptable, raise paths and derivation helpers have low blast radius
- All other city-domain modules at 80%+ with no risky uncovered paths

### Doc/ADR Alignment
Operator docs and ADRs accurately reflect the implemented system. No mismatches found.

### Residual Risks Accepted
- M1: Protected by database unique index on `(world_id, node_name)` -- impossible in normal operation
- M2: Only triggered if operator deletes and re-creates a city row while the heartbeat worker is running -- unusual workflow, worker restart recovers
- M3: Demo-only race condition, documented in operator guide, Docker restart policy recovers

### Ready for Human Review
- [x] APPROVE -- branch is ready
- [ ] REQUEST_CHANGES -- issues must be fixed first

