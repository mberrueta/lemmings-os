# Task 08: ADR Updates

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`docs-feature-documentation-author`

## Agent Invocation
Act as `docs-feature-documentation-author` following `llms/constitution.md` and document the shipped collaboration behavior.

## Objective
Record architectural decisions and user/operator-visible behavior for multi-lemming calls.

## Inputs Required
- [ ] Tasks 01-07 outputs
- [ ] Existing ADR/doc structure
- [ ] `llms/project_context.md`

## Expected Outputs
- [ ] ADR covering durable lemming calls, manager designation, boundary enforcement, and state mapping.
- [ ] Documentation notes for seeded company setup and collaboration UI behavior.
- [ ] Any project-context update needed to reflect new invariants.

## Required ADR Topics
- Manager designation via `collaboration_role`.
- Call records are separate from runtime instance statuses.
- Same-World and same-City enforcement.
- Manager-only cross-department path.
- Successor call links for expired-child continuation.
- Observability and privacy constraints.

## Acceptance Criteria
- [ ] Docs match actual implemented behavior.
- [ ] No closed prior task plans are rewritten.
- [ ] New invariants do not conflict with constitution or project context.
- [ ] Follow-up work remains explicitly out of scope.

## Execution Instructions
1. Inspect final implementation before writing docs.
2. Keep ADR concise and decision-focused.
3. Mention migration/compatibility notes if needed.

## Human Review
Approve docs before final PR review.
