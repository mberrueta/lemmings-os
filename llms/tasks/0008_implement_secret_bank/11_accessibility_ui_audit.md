# Task 11: Accessibility UI Audit

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`audit-accessibility`

## Agent Invocation
Act as `audit-accessibility`. Review the Secret Bank LiveView surfaces and implement focused accessibility fixes.

## Objective
Ensure Secret Bank workflows are usable with keyboard and assistive technologies while preserving security-sensitive UI behavior.

## Expected Outputs
- Accessibility findings and fixes under `lib/lemmings_os_web/**` as needed.
- Test updates if accessible selectors or states change.

## Acceptance Criteria
- Create/replace/delete forms have labels, error association, focus behavior, and keyboard-operable controls.
- Inherited/local action states are clear without relying only on color.
- Recent activity regions have semantic structure.
- Destructive delete confirmation is accessible and does not expose values.
- No accessibility fix introduces reveal/copy/export behavior or masked value previews.

## Review Notes
Reject if keyboard-only operation cannot complete create, replace, and delete flows.
