# Task 05: Gmail Accessibility Audit

## Status

- **Status**: NOT STARTED
- **Approved**: [ ] Human sign-off

## Assigned Agent

`audit-accessibility` - Accessibility auditor for Phoenix LiveView apps, keyboard navigation, focus management, ARIA semantics, and WCAG compliance.

## Agent Invocation

Act as `audit-accessibility`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/tasks/0016_gmail_draft_creation/plan.md`, Task 03, and the implementation diff. Audit the Gmail connection UI and any draft-result UI changes for accessibility.

## Objective

Verify that the Gmail onboarding controls and result states are usable with keyboard, screen readers, and responsive layouts.

## Audit Scope

- Gmail connect controls on World, City, and Department Connections tabs.
- OAuth success, failure, unavailable-config, loading, and retry states.
- Focus behavior after opening the connect flow, returning from callback, and displaying validation errors.
- Accessible names for buttons and links.
- Flash/error announcements and `aria-live` behavior where appropriate.
- Color contrast and non-color-only status communication.
- Existing generic Connection UI regressions.
- Instance timeline display for `email.create_draft` results, if UI changes were made.

## Expected Outputs

- Accessibility findings ordered by severity.
- Targeted remediation requirements for confirmed defects.
- Notes on residual manual-testing gaps.
- Recommendation to proceed, block, or re-audit.

## Suggested Checks

```bash
mix test test/lemmings_os_web/live/world_live_test.exs
mix test test/lemmings_os_web/live/cities_live_test.exs
mix test test/lemmings_os_web/live/departments_live_test.exs
mix test test/lemmings_os_web/live/instance_live_test.exs
```

## Acceptance Criteria

- Gmail connect controls are reachable by keyboard and have clear accessible names.
- OAuth status and error states are announced or discoverable without relying only on color.
- Text fits in mobile and desktop layouts without overlap.
- Existing Connection UI accessibility does not regress.
- Confirmed high and medium accessibility findings are fixed or explicitly waived by the human reviewer.

## Human Approval Gate

Human reviewer validates accessibility findings before final PR audit begins.
