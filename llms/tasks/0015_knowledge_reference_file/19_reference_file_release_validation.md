# Task 19: Reference File Release Validation

## Status

- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent

`rm-release-manager` - Release manager for Elixir/Phoenix apps, release notes, runbooks, migration risk, and rollback plans.

## Agent Invocation

Act as `rm-release-manager`. Prepare release validation artifacts for the reference-file Knowledge feature after implementation and audits are complete.

## Objective

Document what changed, how to validate it, how to roll it back, and which limitations remain outside this PR.

## Implementation Scope

- Prepare release notes describing the new Reference Files Knowledge category.
- Document migration and rollback considerations.
- Document validation steps for upload/register, metadata edit, archive, search/read, availability, Artifact promotion, scope denial, and no-path-leak checks.
- Document any new environment variables or storage configuration.
- Capture known limitations and follow-up items from `plan.md`.
- Confirm final validation evidence, including `mix precommit`, is linked or summarized.

## Constraints

- Do not claim support for template rendering, PDF generation, advanced versioning, hard delete, restore/recover, public sharing, or automatic LLM promotion.
- Do not expose internal storage paths or secrets in release notes.
- Keep release notes aligned with actual implemented behavior.

## Expected Outputs

- Release notes and operational validation checklist.
- Migration/rollback notes.
- Known limitations and follow-up list.
- Final human sign-off packet.

## Suggested Checks

- Confirm `mix precommit` result from Task 18 or rerun if changes were made.
- Review generated docs for accurate scope and limitations.

## Human Approval Gate

Human reviewer performs final release sign-off. Implementation sequence is complete after this approval.
