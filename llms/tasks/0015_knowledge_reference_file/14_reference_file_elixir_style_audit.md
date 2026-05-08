# Task 14: Reference File Elixir Style Audit

## Status

- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent

`audit-pr-elixir` - Senior PR reviewer for Elixir/Phoenix correctness, design quality, security, performance, logging, and test coverage.

## Agent Invocation

Act as `audit-pr-elixir`. Audit the reference-file implementation for Elixir/Phoenix style and make focused corrections for confirmed issues.

## Objective

Ensure production code aligns with `llms/coding_styles/elixir.md`, the constitution, and existing Phoenix/Knowledge patterns before final audits.

## Audit Scope

- Public context APIs are explicitly scoped and documented where behavior is non-trivial.
- Context functions return tuples or clear read-model values consistently with the surrounding code.
- `filter_query/2` and scope helpers follow existing Knowledge patterns.
- Changesets use `@required`/`@optional`, `Ecto.Changeset.get_field/2`, and localized validation messages.
- Business-rule validations live in schemas/changesets/context code, not DB `CHECK` constraints.
- The PR uses a single migration file for all reference-file DB changes.
- No `String.to_atom/1`, struct map-access misuse, raw SQL interpolation, or unbounded process behavior.
- LiveView code uses HEEx, `to_form/2`, imported components, stable IDs, and verified routes.
- No broad refactors outside reference-file scope.

## Expected Outputs

- Findings ordered by severity.
- Focused fixes for confirmed style/correctness issues, if any.
- Explicit residual risks or waivers for human review.

## Suggested Checks

- `mix format`
- Narrow tests affected by any fixes
- `mix compile --warnings-as-errors` if the implementation is ready for it

## Human Approval Gate

Human reviewer validates style findings and fixes, then approves Task 15.
