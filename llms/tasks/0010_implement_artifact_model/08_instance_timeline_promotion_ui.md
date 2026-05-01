# Task 08: Instance Timeline Promotion UI

## Status
- **Status**: ⏳ PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer` - Phoenix LiveView frontend engineer for accessible, responsive UI using existing design patterns.

## Agent Invocation
Act as `dev-frontend-ui-engineer`. Add manual Artifact promotion UI to the existing instance timeline.

## Objective
Allow operators to manually promote generated workspace files from the instance timeline and render safe Artifact references after promotion.

## Inputs Required
- [ ] `llms/constitution.md`
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/tasks/0010_implement_artifact_model/plan.md`
- [ ] Tasks 01-07 outputs
- [ ] `lib/lemmings_os_web/live/instance_live.ex`
- [ ] `lib/lemmings_os_web/live/instance_live.html.heex`
- [ ] `lib/lemmings_os_web/components/instance_components.ex`
- [ ] Existing LiveView tests for instance timeline

## Expected Outputs
- [ ] `Promote to Artifact` action for eligible workspace file events.
- [ ] Existing same-scope filename state detects and presents `Update Artifact` and `Promote as New Artifact` actions.
- [ ] Event handlers that call `LemmingsOs.Artifacts.promote_workspace_file/2` with explicit scope.
- [ ] Safe Artifact reference rendering in timeline.
- [ ] Notes display using unobtrusive accessible pattern such as `<details>`.
- [ ] Stable DOM IDs for buttons, forms, references, status messages, and notes controls.

## Acceptance Criteria
- [ ] UI renders only safe descriptor fields: filename, type, status, size, created_at, creator instance/tool execution IDs where known.
- [ ] UI does not render raw file contents, raw filesystem paths, storage root path, full metadata, prompt/model/tool raw output, or notes as large inline content.
- [ ] Notes are not sent to LLM context by default.
- [ ] Buttons are keyboard reachable and have clear accessible names.
- [ ] Existing timeline behavior remains intact.

## Technical Notes
### Relevant Code Locations
```
lib/lemmings_os_web/live/instance_live.ex        # Event handling and data loading
lib/lemmings_os_web/live/instance_live.html.heex # Page layout
lib/lemmings_os_web/components/instance_components.ex # Timeline card components
test/lemmings_os_web/live/instance_live_test.exs # Stable selector patterns
```

### Constraints
- Preserve existing visual language and component patterns.
- Use HEEx `:if`, `:for`, and `{}` interpolation; avoid raw EEx blocks.
- Do not embed `<script>` tags.
- Do not call schemas or Repo directly from web code.
- Do not call Secret Bank.

## Execution Instructions

### For the Agent
1. Read all inputs listed above.
2. Add the smallest UI/data-loading changes needed for manual promotion.
3. Add or update focused LiveView tests if necessary, but leave broad testing to Task 09.
4. Run narrow LiveView tests affected by UI changes.
5. Document assumptions, files changed, and test commands in Execution Summary.

### For the Human Reviewer
After agent completes:
1. Review UI copy, safe fields, and stable DOM IDs.
2. Verify no raw path/content leakage in rendered HTML.
3. Approve before Task 09 begins.

---

## Execution Summary
*[Filled by executing agent after completion]*
