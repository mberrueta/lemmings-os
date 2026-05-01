# Task 12: Accessibility Audit

## Status
- **Status**: ✅ COMPLETE 
- **Approved**: [X] Human sign-off

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
- [x] Accessibility audit findings documented in this task file.
- [x] Focused UI fixes for labels, keyboard reachability, focus management, status feedback, and details/popover semantics.
- [x] LiveView tests or assertions for key accessibility regressions where practical.

## Acceptance Criteria
- [x] Promotion, update, promote-as-new, and download controls have stable IDs and clear accessible names.
- [x] Status/flash feedback is perceivable and does not require mouse interaction.
- [x] Notes disclosure is keyboard usable and semantically appropriate.
- [x] Focus behavior is not broken after promotion/update actions.
- [x] No accessibility fix introduces raw content/path/metadata leakage.
- [x] Narrow LiveView tests pass.

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
### Findings
1. **Medium**: Artifact help affordance used an inert `<button>` with `title`, which is mouse-biased and provides weak keyboard/AT semantics.
   - Location: `lib/lemmings_os_web/components/instance_components.ex`
   - Fix: replaced with semantic `<details>/<summary>` help disclosure and stable IDs.
2. **Medium**: Promotion status feedback lacked explicit live-region semantics and focus behavior for non-visual users.
   - Location: `lib/lemmings_os_web/components/instance_components.ex`
   - Fix: added `aria-live`, `aria-atomic`, `tabindex="-1"`, and `phx-mounted` focus to status message.
3. **Low**: Notes disclosure and download link lacked stronger semantic wiring.
   - Location: `lib/lemmings_os_web/components/instance_components.ex`
   - Fix: added `summary` id + `aria-controls` for notes body and explicit `aria-label` for download link.

### Implemented Changes
- Added stable accessibility IDs:
  - `artifact-promotion-heading-*`
  - `artifact-promotion-help-*`
  - `artifact-reference-notes-summary-*`
- Promotion region:
  - `role="region"` and `aria-labelledby` on promotion container.
  - `aria-describedby` on promotion form tying source/help/status.
- Promotion action buttons:
  - preserved stable IDs and labels.
  - added `phx-disable-with` progress copy for submit feedback.
- Promotion status:
  - role remains `status`/`alert` based on outcome.
  - added `aria-live` (`polite` or `assertive`) + `aria-atomic="true"`.
  - added `tabindex="-1"` and mount focus command.
- Notes disclosure:
  - semantic `<details>/<summary>` retained.
  - summary now references notes content via `aria-controls`.
- Download control:
  - retains stable ID.
  - now includes explicit accessible name with filename.

### Regression Tests Updated
- `test/lemmings_os_web/live/instance_live_test.exs`
  - Expanded `S08l` with assertions for:
    - promotion help IDs and form `aria-describedby`
    - status live-region attributes
    - download link accessible name
  - Expanded `S08m` with assertion for notes summary `aria-controls`.

### Commands Run
- `mix format lib/lemmings_os_web/components/instance_components.ex test/lemmings_os_web/live/instance_live_test.exs`
- `mix test test/lemmings_os_web/live/instance_live_test.exs`
- `MIX_ENV=test mix precommit`

### Validation Results
- Narrow LiveView tests passed.
- `MIX_ENV=test mix precommit` passed (Dialyzer + Credo clean).

### Residual Risks
- Focus announcement is scoped to promotion status mount only. If future behavior requires focus restoration to the triggering button, that should be handled in a dedicated follow-up interaction pattern task.
