# Task 14: Code Style and Precommit Cleanup

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`rm-release-manager`

## Agent Invocation
Act as `rm-release-manager`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/tasks/0009_implement_connections/plan.md`, and Tasks 01-13, then perform final style cleanup, validation coordination, and release notes for the implemented Connection MVP.

## Objective
Close implementation with formatting, final narrow validation reruns, final `mix precommit`, and operational notes after all implementation, documentation, security, and accessibility work is complete.

## Expected Outputs
- `mix format` run.
- Final narrow relevant test commands run after security and accessibility fixes.
- `mix precommit` run.
- Validation summary with commands and results.
- Migration and rollback notes.
- Release/readiness notes appropriate for the current project state.
- Explicit note that human handles git add/commit/push.

## Acceptance Criteria
- Formatting is clean.
- `mix precommit` passes with zero warnings/errors, or failures are documented with exact output and known cause.
- Migration risk and rollback implications are documented.
- Remaining risks or deferred work are listed for human decision.
- No unrelated cleanup or broad refactor is included.

## Review Notes
Do not perform git add, git commit, git push, git checkout, git stash, or git revert. Reject if this task expands feature scope instead of closing validation.
