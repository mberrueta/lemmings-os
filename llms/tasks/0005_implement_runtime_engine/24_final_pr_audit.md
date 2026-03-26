# Task 24: Final PR Audit

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`audit-pr-elixir` - staff-level PR reviewer for Elixir/Phoenix backends focusing on correctness, design quality, security, performance, logging, and test coverage.

## Agent Invocation
Act as `audit-pr-elixir` following `llms/constitution.md` and perform the final comprehensive PR audit of the runtime engine branch. Review against the plan's branch-level acceptance criteria, the security review findings (Task 23), and the ADR updates (Task 22).

## Objective
Perform the definitive PR review before merge. Verify: (1) all branch-level acceptance criteria from plan.md are met, (2) all Critical/High findings from the security review (Task 23) are resolved, (3) ADR and architecture docs are consistent with implementation, (4) test coverage is adequate, (5) no regressions to existing functionality. Produce a final PR review with approve/request-changes verdict.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Branch-level acceptance criteria (bottom of plan)
- [ ] `llms/tasks/0005_implement_runtime_engine/security_review.md` - Task 23 output (findings to verify resolved)
- [ ] Task 22 output - ADR and architecture updates
- [ ] Task 21 output - Branch validation results, coverage report
- [ ] All new and modified files across the branch
- [ ] `git diff main...HEAD` - Full branch diff

## Expected Outputs

- [ ] New `llms/tasks/0005_implement_runtime_engine/pr_review.md` - Final PR review document
- [ ] Verdict: APPROVE or REQUEST CHANGES with specific items

## Acceptance Criteria

### Branch-Level Criteria Verification
Each of the following from plan.md must be verified as implemented:

- [ ] Persisted `lemming_instances` table with correct columns (FKs, status, config_snapshot, temporal markers)
- [ ] Persisted `lemming_instance_messages` table with correct columns (role, content, provider/model/token fields, `total_tokens`, `usage` jsonb)
- [ ] `LemmingsOs.LemmingInstances.LemmingInstance` and `LemmingsOs.LemmingInstances.Message` schemas
- [ ] `LemmingsOs.LemmingInstances` context exposes a small explicit non-bang API (`spawn_instance/3`, `get_instance/2`, `list_instances/2`, `update_status/3`, `enqueue_work/3`, `list_messages/2`, `topology_summary/1`)
- [ ] `LemmingsOs.Runtime.spawn_session/3` (or equivalent) exists as the single web-facing spawn entrypoint
- [ ] Instance executor GenServer with FIFO queue, state machine, retry, idle timeout
- [ ] DepartmentScheduler with oldest-eligible-first, pool-bounded concurrency
- [ ] Resource pool limiting concurrent model execution (keyed by resource key, not Department/City)
- [ ] Ollama model execution via `Req` with structured output contract and retry
- [ ] ETS ephemeral runtime state; DETS best-effort snapshots on idle
- [ ] Spawn flow from Lemming detail page (modal with initial request)
- [ ] LiveView does not directly start executors or notify schedulers; spawn orchestration stays in the runtime/application layer
- [ ] Instance session page with live status, transcript, follow-up input
- [ ] All 7 runtime statuses rendered correctly in UI
- [ ] PubSub for runtime signals
- [ ] Testability gates for deterministic testing
- [ ] Telemetry events on lifecycle transitions with hierarchy metadata
- [ ] `Req` in `mix.exs`
- [ ] No `MockData` calls for runtime state
- [ ] Tests covering: schema, context, executor, scheduler, pool, FIFO, retry, idle expiry, spawn flow, session page
- [ ] `mix test` passes
- [ ] `mix precommit` passes
- [ ] Coverage report generated
- [ ] ADR updates complete

### Security Review Resolution
- [ ] All Critical findings from Task 23 are resolved
- [ ] All High findings from Task 23 are resolved
- [ ] Medium/Low findings are documented with resolution or deferral rationale

### ADR Consistency
- [ ] ADR-0021 matches implemented schema shapes
- [ ] v1 status taxonomy documented as deliberate simplification of ADR-0004
- [ ] DepartmentScheduler namespace clarification documented
- [ ] Runtime state split documented
- [ ] Architecture.md reflects the runtime layer

### Code Quality
- [ ] No TODO comments without linked issue/task
- [ ] No commented-out code
- [ ] No debug prints or `IO.inspect` calls
- [ ] Consistent error handling patterns
- [ ] Public functions documented
- [ ] Module documentation present

### Test Quality
- [ ] Tests are deterministic (no timing deps)
- [ ] Tests use factories (no fixtures)
- [ ] OTP tests use `start_supervised/1`
- [ ] No real Ollama calls in tests
- [ ] Coverage is reasonable for new modules

## Technical Notes

### Review Approach
1. Start with `git diff main...HEAD --stat` for scope overview
2. Review migrations first (schema truth)
3. Review schemas and context (domain logic)
4. Review OTP processes (runtime correctness)
5. Review LiveViews (user-facing behavior)
6. Review tests (coverage and quality)
7. Review ADRs (documentation accuracy)
8. Cross-reference against branch-level acceptance criteria

### Constraints
- This is a review task -- produce the review document, do not fix code
- If Critical issues are found, verdict MUST be REQUEST CHANGES
- If only Medium/Low issues remain, verdict can be APPROVE with notes
- The review must be actionable -- every finding must have a specific recommendation

## Execution Instructions

### For the Agent
1. Read the full branch diff (`git diff main...HEAD`).
2. Read the security review findings (Task 23 output).
3. Read the ADR updates (Task 22 output).
4. Verify each branch-level acceptance criterion from plan.md.
5. Verify security review findings are resolved.
6. Check code quality standards.
7. Check test quality standards.
8. Produce the PR review with verdict.

### For the Human Reviewer
1. Read the PR review document.
2. Verify the verdict is justified by findings.
3. If APPROVE: proceed with PR creation and merge.
4. If REQUEST CHANGES: create follow-up tasks for required fixes.
5. Final decision on merge readiness.

---

## Execution Summary
*[Filled by executing agent after completion]*

### Work Performed
- [What was actually done]

### Outputs Created
- [List of files/artifacts created]

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|

### Blockers Encountered
- [Blocker 1] - Resolution: [How resolved or "Needs human input"]

### Questions for Human
1. [Question needing human input]

### Ready for Next Task
- [ ] All outputs complete
- [ ] Summary documented
- [ ] Questions listed (if any)

---

## Human Review
*[Filled by human reviewer]*

### Review Date
[YYYY-MM-DD]

### Decision
- [ ] APPROVED - Merge the PR
- [ ] REJECTED - See feedback below

### Feedback

### Git Operations Performed
```bash
# human-only
```
