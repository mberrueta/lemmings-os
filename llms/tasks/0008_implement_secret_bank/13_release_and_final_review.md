# Task 13: Release and Final Review

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`rm-release-manager`

## Supporting Agent
`audit-pr-elixir`

## Agent Invocation
Act as `rm-release-manager`. Prepare release notes, migration/runbook, rollback notes, and final validation instructions. Then have `audit-pr-elixir` perform the final PR review.

## Objective
Close the Secret Bank branch with operational notes, validation evidence, and a final staff-level Elixir/Phoenix review.

## Expected Outputs
- Release notes/runbook updates where appropriate.
- Final validation summary with commands run.
- Final PR audit findings or explicit no-findings statement.

## Acceptance Criteria
- Migration risk, Cloak dependency impact, encryption key configuration, and rollback implications are documented.
- Narrow tests have passed and final `mix precommit` has passed.
- Final review covers correctness, security, logging/audit, performance, UI integration, and test coverage.
- Any remaining risks or deferred work are explicitly listed for human decision.

## Review Notes
Do not perform git add/commit/push. Human handles all version control operations.
