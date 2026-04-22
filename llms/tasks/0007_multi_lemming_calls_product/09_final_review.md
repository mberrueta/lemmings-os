# Task 09: Final Review

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`audit-pr-elixir`

## Agent Invocation
Act as `audit-pr-elixir` following `llms/constitution.md` and perform final branch review for `feat/0007_multi_lemming_calls_product`.

## Objective
Review the full branch for correctness, safety, test coverage, observability, and adherence to the approved product and execution plans.

## Inputs Required
- [ ] `llms/tasks/0007_multi_lemming_calls_product/plan.md`
- [ ] `llms/tasks/0007_multi_lemming_calls_product/implementation_plan.md`
- [ ] Tasks 01-08 outputs
- [ ] Full branch diff
- [ ] Final `mix precommit` output

## Expected Outputs
- [ ] Findings ordered by severity with file/line references.
- [ ] Verdict: approve, comment-only, or request changes.
- [ ] Residual risk summary.

## Review Focus
- World and City isolation.
- Manager-only delegation and cross-department enforcement.
- Runtime status and collaboration status separation.
- OTP/process safety.
- Logging/telemetry hierarchy metadata.
- Test coverage for backend and UI acceptance criteria.
- Docs/ADR accuracy.

## Acceptance Criteria
- [ ] `mix precommit` passes before review is considered complete.
- [ ] No git mutations are performed by the reviewing agent.
- [ ] Findings are concrete and actionable.
- [ ] Human reviewer has enough information for merge/no-merge decision.

## Execution Instructions
1. Inspect full diff and relevant tests.
2. Verify the branch stays inside this slice.
3. Report blockers first.
4. Include final verdict.

## Human Review
Human owner decides whether to merge, request fixes, or split follow-up work.
