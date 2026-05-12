# Task 03: Gmail Connection UI And Documentation

## Status

- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent

`dev-frontend-ui-engineer` - Frontend engineer for Phoenix LiveView UI, forms, accessible states, and responsive operator workflows.

## Agent Invocation

Act as `dev-frontend-ui-engineer`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, `llms/coding_styles/elixir_tests.md`, `llms/tasks/0016_gmail_draft_creation/plan.md`, Tasks 01-02, and this task. Implement only the user-facing Gmail connection onboarding controls, safe UI states, instance timeline adjustments if required, documentation updates, and tests.

## Objective

Expose the Gmail connection flow to operators and ensure draft creation results are reviewable without leaking credentials or storage internals.

## Expected Outputs

- Gmail connect control in the existing Connections surfaces for World, City, and Department scopes.
- Stable DOM IDs for Gmail connect buttons, status messages, error states, and any callback result UI.
- Safe success and failure flashes/states for OAuth start/callback outcomes.
- Existing generic Connection create/edit/test/delete behavior remains intact.
- Existing instance timeline/tool execution cards render `email.create_draft` summaries, previews, and safe results clearly. Add targeted UI handling only if current generic cards are insufficient.
- Documentation updates:
  - `docs/features/tools.md` for `email.create_draft`
  - `docs/features/connections.md` for Gmail Connection config and onboarding
  - `docs/features/secret_bank.md` only if needed for Gmail secret refs
  - Google OAuth setup how-to covering Gmail API enablement, OAuth consent, OAuth Web Client, authorized redirect URI, required env vars, and the in-app `Connections -> + Create -> Gmail -> Connect Gmail` flow
- Clear documentation that sending, reading, sync, mailbox watch, and approval records are out of scope.

## UI Safety Rules

- Do not render refresh tokens, access tokens, client secrets, authorization headers, Secret Bank resolved values, Artifact storage refs, or local filesystem paths.
- Do not show raw Google error bodies.
- Do not add a send button or any UI that implies email can be sent from this PR.
- Use existing LiveView navigation conventions and HEEx rules.
- Use imported `<.icon>` where icons are needed.
- Use stable selectors and accessible labels for tests.

## Testing Requirements

- LiveView tests cover Gmail connect controls on World, City, and Department Connections tabs.
- Tests verify controls have stable IDs, accessible labels, and expected disabled/error state when OAuth config is unavailable.
- ConnCase or controller tests cover success/failure callback UI behavior if not already covered in Task 01.
- LiveView tests verify generic `mock` Connection create/edit/test/delete flows still work.
- Instance timeline test verifies an `email.create_draft` tool execution renders safe subject, recipient summary, and Artifact IDs without token values, raw provider payloads, storage refs, or local paths.
- Documentation review checks confirm required docs mention env vars, compose-only scope, manual send in Gmail, and explicit non-goals.

## Suggested Checks

```bash
mix test test/lemmings_os_web/live/world_live_test.exs
mix test test/lemmings_os_web/live/cities_live_test.exs
mix test test/lemmings_os_web/live/departments_live_test.exs
mix test test/lemmings_os_web/live/instance_live_test.exs
mix format
```

When the task is complete and ready for human approval, run `mix precommit` if the task changes are stable enough for a full gate.

## Acceptance Criteria

- Operators can start Gmail connection onboarding from the Connections UI.
- OAuth success/failure is represented safely and understandably.
- The UI never exposes token values, raw provider payloads, storage refs, or local paths.
- Draft creation tool results are reviewable in existing runtime UI.
- No send action appears anywhere in the UI.
- Documentation is aligned with the shipped behavior and non-goals.
- Human reviewer can approve audit work after reviewing UI tests, screenshots or local verification notes, and docs.

## Human Approval Gate

Human reviewer validates the UI workflow, documentation, no-leak behavior, and no-send boundary before audit tasks begin.
