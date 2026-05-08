# Task 17: Reference File Accessibility Audit

## Status

- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent

`audit-accessibility` - Accessibility auditor for Phoenix + LiveView interfaces, keyboard navigation, focus management, ARIA semantics, and WCAG compliance.

## Agent Invocation

Act as `audit-accessibility`. Audit the Reference Files UI for accessibility and responsive usability.

## Objective

Ensure the Reference Files management surface is accessible, keyboard usable, and consistent with the rest of the Knowledge UI.

## Audit Scope

- Tab semantics, `role="tablist"`, `role="tab"`, `aria-selected`, `aria-controls`, and panel labeling.
- Forms have labels, field-level errors, and stable focus behavior.
- Upload, edit, archive, filter, detail, and promotion controls are keyboard reachable.
- Icon-only buttons have accessible names and titles where appropriate.
- Empty, filtered-empty, archived, unreadable, and error states are perceivable.
- Text remains readable and does not overlap or overflow on mobile and desktop.
- Color contrast and disabled states are acceptable within the existing design system.

## Expected Outputs

- Accessibility findings ordered by severity.
- Focused UI fixes for confirmed issues, if any.
- Residual manual-testing notes for human review.

## Suggested Checks

- Narrow LiveView tests affected by any fixes
- Manual browser keyboard pass if a dev server is available

## Human Approval Gate

Human reviewer validates accessibility findings and fixes, then approves Task 18.
