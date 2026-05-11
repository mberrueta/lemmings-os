# Task 06: Gmail Final PR Audit

## Status

- **Status**: NOT STARTED
- **Approved**: [ ] Human sign-off

## Assigned Agent

`audit-pr-elixir` - Senior PR reviewer for Elixir/Phoenix correctness, design quality, security, performance, logging, and test coverage.

## Agent Invocation

Act as `audit-pr-elixir`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, `llms/coding_styles/elixir_tests.md`, `llms/tasks/0016_gmail_draft_creation/plan.md`, Tasks 01-05, and the implementation diff. Perform the final PR review and resolve confirmed high-priority findings.

## Objective

Verify merge readiness for Gmail connection onboarding and `email.create_draft` across correctness, security, observability, accessibility, documentation, Elixir style, test style, and operational readiness.

## Review Scope

- Task 01 connection/OAuth acceptance criteria are complete.
- Task 02 backend tool acceptance criteria are complete.
- Task 03 UI/docs acceptance criteria are complete.
- Security and observability audit findings are fixed or explicitly documented.
- Accessibility audit findings are fixed or explicitly documented.
- Public API functions added or materially changed include `@doc`, parameter descriptions, `@spec`, and examples/doctests where non-trivial.
- Tests are outcome-based and use factories, stable selectors, Bypass/fakes for HTTP, and no external network.
- No source code hardcodes secrets or generated credential values.
- No code uses `String.to_atom/1` on user input or map access syntax on structs.
- No raw tokens, authorization headers, provider bodies, storage refs, or local paths leak in results, events, logs, raw context pages, timeline entries, docs, or tests.
- No email send/read/sync path is present.

## Expected Outputs

- Final findings report ordered by severity.
- Targeted corrections for confirmed defects, if any.
- Explicit residual risks and testing gaps.
- Final validation evidence.
- Clear merge recommendation for the human reviewer.

## Suggested Checks

```bash
mix test test/lemmings_os/connections test/lemmings_os/tools test/lemmings_os/artifacts
mix test test/lemmings_os_web/live/world_live_test.exs
mix test test/lemmings_os_web/live/cities_live_test.exs
mix test test/lemmings_os_web/live/departments_live_test.exs
mix test test/lemmings_os_web/live/instance_live_test.exs
mix precommit
```

## Acceptance Criteria

- All implementation tasks are complete and approved.
- Security, observability, accessibility, Elixir style, and test style findings are closed or explicitly waived.
- `mix precommit` passes.
- Final PR review recommends merge or clearly lists blockers.

## Human Approval Gate

Human reviewer performs final PR sign-off. Implementation sequence is complete after this approval.
