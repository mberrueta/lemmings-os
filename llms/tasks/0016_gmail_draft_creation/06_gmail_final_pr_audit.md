# Task 06: Gmail Final PR Audit

## Status

- **Status**: COMPLETED
- **Approved**: [ ] Human sign-off

## Final Audit Result (2026-05-12)

### Summary

- Reviewed the cumulative Gmail onboarding and `email.create_draft` branch diff
  against `main`, including OAuth, Connection validation, Secret Bank handling,
  Gmail HTTP boundaries, Artifact attachment loading, UI surfaces, docs, and
  tests.
- Confirmed Tasks 01-05 are marked complete and Tasks 01-05 human sign-off is
  recorded where required.
- Confirmed the app exposes Gmail draft creation only: no Gmail send, read,
  sync, watch, delete, or mailbox ingestion path is registered in catalog,
  runtime, router, or Gmail client code.
- Applied final cleanup for committed credential placeholders, Gmail env
  fallback policy, documentation alignment, and task-file whitespace.
- Applied follow-up runtime hardening so `email.create_draft` accepts common LLM
  recipient shapes and defaults `body_format` to `text/plain`.
- No unresolved BLOCKER or MAJOR findings remain in the Gmail PR scope.

### Risk Assessment

**Medium**. The Gmail slice handles credentials through Secret Bank refs,
session-bound OAuth state, safe result/event payloads, and server-side Artifact
scope checks. Residual risk remains medium because the current control plane is
still local-admin mode with no per-user RBAC, and because Google's
`gmail.compose` scope has provider-side capabilities broader than the app's
exposed draft-only path.

### BLOCKER

- None remaining.

### MAJOR

- None remaining.

### MINOR

- **Where**: `lib/lemmings_os_web/connections_surface.ex`, Gmail create/edit
  form behavior.
  **Why it matters**: Operators can use `Save config` before completing OAuth,
  which intentionally persists client credential refs without a refresh-token
  ref. Draft execution then fails safely with a connection authentication error
  until `Connect Gmail` completes.
  **Suggested fix**: Accept for this MVP because the UI documents the
  pre-OAuth state and the runtime fails closed. If this becomes confusing in
  operator testing, disable generic Save for new Gmail rows or persist pre-OAuth
  rows as `invalid` until callback completion.

### NITS

- None remaining.

### Resolved Findings

- **Where**: `.envrc`.
  **Why it mattered**: The branch included Gmail credential-looking placeholder
  exports in a tracked file, violating public-repository credential hygiene.
  **Fix applied**: Removed placeholder values and documented that optional
  Gmail OAuth env vars belong in `.envrc.custom`.
- **Where**: `config/config.exs`, `docs/features/connections.md`,
  `docs/features/secret_bank.md`.
  **Why it mattered**: The documentation described Secret Bank env fallback use
  for Gmail OAuth refs, but the default Secret Bank allowlist did not include
  Gmail OAuth env vars.
  **Fix applied**: Added explicit Gmail OAuth env fallback allowlist entries and
  aligned docs with the shipped `$GMAIL_*` defaults and accepted aliases.
- **Where**:
  `llms/tasks/0016_gmail_draft_creation/01_gmail_connection_oauth_and_secret_storage.md`,
  `llms/tasks/0016_gmail_draft_creation/02_email_create_draft_backend_tool.md`.
  **Why it mattered**: `git diff --check` found trailing whitespace in task
  metadata.
  **Fix applied**: Removed trailing whitespace.
- **Where**: `LemmingsOs.ModelRuntime` and `LemmingsOs.Tools.Adapters.Email`.
  **Why it mattered**: The model-facing tool contract did not describe
  `email.create_draft` arguments, and the adapter rejected common model output
  shapes such as `"to": "person@example.com"` or omitted `body_format`.
  **Fix applied**: Added the email draft argument contract to the model runtime
  prompt and normalized single/comma-separated recipient strings, blank
  optional `cc`/`bcc`, blank attachment IDs, and default `body_format`.

### Test Coverage Notes

- Backend coverage includes Gmail provider config validation, OAuth state
  rejection/success paths, Secret Bank refresh-token persistence, tool catalog
  registration, runtime normalization, adapter validation, Gmail client fakes,
  MIME/attachment handling, provider failure normalization, and no-send
  regression assertions.
- UI/controller coverage includes World, City, and Department Gmail connection
  controls, OAuth redirect/callback behavior, generic Connection regression
  coverage, and Instance timeline safe draft-result rendering.
- Residual manual gaps: browser-based Google OAuth flow, screen-reader pass
  through the external redirect, and production reverse-proxy callback URL
  verification.

### Observability Notes

- OAuth events are safe and present:
  `connection.gmail.oauth_started`, `connection.gmail.oauth_succeeded`,
  `connection.gmail.oauth_failed`, and profile lookup failure.
- Draft events are safe and present:
  `email.draft_requested`, `email.draft_created`, `email.draft_failed`.
- Reviewed event/result surfaces avoid raw OAuth codes, refresh tokens, access
  tokens, authorization headers, raw provider bodies, Artifact storage refs, and
  local filesystem paths.

### Validation Evidence

```bash
mix test test/lemmings_os/connections test/lemmings_os/tools test/lemmings_os/artifacts test/lemmings_os/model_runtime_test.exs
# 55 doctests, 220 tests, 0 failures

mix test test/lemmings_os_web/live/world_live_test.exs test/lemmings_os_web/live/cities_live_test.exs test/lemmings_os_web/live/departments_live_test.exs test/lemmings_os_web/live/instance_live_test.exs test/lemmings_os_web/controllers/gmail_oauth_controller_test.exs
# 102 tests, 0 failures

mix format
git diff main --check
# no output

mix precommit
# passed successfully; Credo found no issues; Dialyzer total errors: 0
```

### Merge Recommendation

**APPROVE after the human reviewer accepts the documented local-admin/RBAC
residual risk.**

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
