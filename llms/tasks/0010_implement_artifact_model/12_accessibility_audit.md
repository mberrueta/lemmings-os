# Task 12: Accessibility Audit

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`audit-accessibility` - Accessibility auditor for Phoenix LiveView apps.

## Agent Invocation
Act as `audit-accessibility`. Review the Artifact promotion/update/download UI and implement focused accessibility fixes.

## Objective
Ensure Artifact timeline controls and references are usable with keyboard and assistive technologies while preserving safe rendering behavior.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] Tasks 08-11 outputs
- [ ] `lib/lemmings_os_web/live/instance_live.ex`
- [ ] `lib/lemmings_os_web/live/instance_live.html.heex`
- [ ] `lib/lemmings_os_web/components/instance_components.ex`
- [ ] Existing LiveView tests

## Expected Outputs
- [ ] Accessibility audit findings documented in this task file.
- [ ] Focused UI fixes for labels, keyboard reachability, focus management, status feedback, and details/popover semantics.
- [ ] LiveView tests or assertions for key accessibility regressions where practical.

## Acceptance Criteria
- [ ] Promotion, update, promote-as-new, and download controls have stable IDs and clear accessible names.
- [ ] Status/flash feedback is perceivable and does not require mouse interaction.
- [ ] Notes disclosure is keyboard usable and semantically appropriate.
- [ ] Focus behavior is not broken after promotion/update actions.
- [ ] No accessibility fix introduces raw content/path/metadata leakage.
- [ ] Narrow LiveView tests pass.

## Technical Notes
### Relevant Code Locations
```
lib/lemmings_os_web/live/instance_live.ex
lib/lemmings_os_web/live/instance_live.html.heex
lib/lemmings_os_web/components/instance_components.ex
test/lemmings_os_web/live/instance_live_test.exs
```

### Constraints
- Preserve existing design system and visual language.
- Do not embed scripts in HEEx.
- Do not introduce broad UI redesigns.

## Execution Instructions

### For the Agent
1. Read all inputs listed above.
2. Audit keyboard, focus, naming, and semantic behavior.
3. Implement focused fixes only.
4. Add/update tests where practical.
5. Run narrow LiveView tests.
6. Document findings, fixes, residual risks, and commands in Execution Summary.

### For the Human Reviewer
After agent completes:
1. Review UI behavior manually if possible.
2. Approve before Task 13 begins.

---

## Execution Summary
*[Filled by executing agent after completion]*
