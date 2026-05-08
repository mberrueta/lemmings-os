# Task 15: Reference File Test Style Audit

## Status

- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent

`qa-elixir-test-author` - QA-driven Elixir test writer for test quality, determinism, and coverage gaps.

## Agent Invocation

Act as `qa-elixir-test-author`. Audit the reference-file tests for style, determinism, coverage, and maintainability.

## Objective

Ensure backend, tool, and LiveView tests follow `llms/coding_styles/elixir_tests.md` and provide meaningful outcome-based coverage.

## Audit Scope

- Tests use factories, not fixture-style helpers or `*_fixture` naming.
- Tests are grouped with meaningful `describe` blocks and behavior-oriented names.
- DB tests use DataCase/ConnCase/LiveViewCase appropriately.
- LiveView tests use stable selectors and `Phoenix.LiveViewTest` helpers.
- Assertions check outcomes and read models, not broad raw HTML.
- No external network, sleeps, ordering flakiness, or unsafe temp-file assumptions.
- Coverage includes acceptance criteria, edge cases, regressions, and no-leak assertions from Task 01.

## Expected Outputs

- Findings ordered by severity.
- Focused test fixes for confirmed issues, if any.
- Coverage gap summary for final PR review.

## Suggested Checks

- `mix format`
- Narrow test suites changed by this audit

## Human Approval Gate

Human reviewer validates test quality and coverage, then approves Task 16.
