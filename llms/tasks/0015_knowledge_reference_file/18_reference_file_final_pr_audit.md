# Task 18: Reference File Final PR Audit

## Status

- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent

`audit-pr-elixir` - Senior PR reviewer for Elixir/Phoenix correctness, design, performance, logging, and test coverage.

## Agent Invocation

Act as `audit-pr-elixir`. Perform the final end-to-end PR audit for the reference-file implementation and resolve confirmed high-priority findings.

## Objective

Verify merge readiness across architecture alignment, product scope, implementation quality, tests, security, accessibility, and operational readiness.

## Audit Scope

- Reference files are Knowledge-managed fixed files and do not require Artifacts.
- Optional Artifact provenance is not the storage/read/search contract.
- Reference files do not create source-file chunks, embeddings, or vector indexes.
- Scope enforcement is server-side and independent in mutation, availability, search, and read paths.
- `knowledge.store` remains memory-only.
- `knowledge.search` and `knowledge.read` preserve source-file behavior while adding reference-file behavior safely.
- UI distinguishes Memories, Source Files, Reference Files, and Artifacts.
- Events/logs/tool outputs/descriptors omit unsafe storage and content details.
- Database changes are consolidated into one migration file for the PR.
- DB constraints are limited to references, uniqueness, and necessary indexes; business rules are enforced in Ecto/schema/context validation.
- Elixir code style, test style, security, and accessibility audit findings are resolved or documented.

## Expected Outputs

- Final findings report ordered by severity.
- Targeted corrections for confirmed defects, if any.
- Explicit residual risks and testing gaps.
- Clear merge recommendation for human reviewer.

## Suggested Checks

- Relevant narrow tests after any fixes
- `mix test`
- `mix precommit`

## Human Approval Gate

Human reviewer validates final audit results and approves Task 19 for release validation.
