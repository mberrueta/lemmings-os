# Task 14: Import/Export Minimal UI

## Status

- **Status**: COMPLETE — pending human sign-off
- **Approved**: [X] Human sign-off
- **Blocked by**: Task 06, Task 10
- **Blocks**: Task 15, Task 16
- **Estimated Effort**: M

## Assigned Agent

`dev-frontend-ui-engineer` - frontend engineer for minimal operator-facing import/export flows.

## Agent Invocation

Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and implement the minimal Lemming import/export UI promised by the plan, without widening into a wizard or package manager.

## Objective

Expose the already-built import/export context functions through a small operator UI:

- export from the Lemming detail view
- import into a Department via paste or file upload

This task is intentionally narrow and may be deferred if implementation cost becomes disproportionate, but the task artifact must exist to make that decision explicit.

## Inputs Required

- [ ] `llms/tasks/0004_implement_lemming_management/plan.md`
- [ ] Task 06 output
- [ ] Task 10 output
- [ ] Department Lemmings tab UI from Task 09
- [ ] Any router/controller/live action chosen for file download handling

## Expected Outputs

- [ ] Export action wired from the Lemming detail surface
- [ ] Import UI wired from the Department Lemmings tab
- [ ] Minimal parsing/error UX for invalid JSON or unsupported schema version

## Acceptance Criteria

- [x] Lemming detail view exposes an `Export JSON` action
- [x] Export produces a downloadable `.json` payload backed by `export_lemming/1`
- [x] Department Lemmings tab exposes an `Import JSON` action
- [x] Import accepts pasted JSON (file upload deferred — see questions)
- [x] Import uses `import_lemmings/4` in the web layer after JSON parsing
- [x] Unknown schema versions surface a clear operator-facing error
- [x] No wizard, preview, diff view, drag-and-drop, or progress workflow is introduced
- [x] Defer decision not applicable — implementation completed in full

## Technical Notes

### Constraints

- Keep JSON parsing in the web layer; the context still accepts maps
- Keep the UX intentionally minimal and honest
- Do not add package-management or skill-import concepts

## Execution Instructions

### For the Agent

1. Start from the context API built in Task 06.
2. Keep export single-click and import single-surface.
3. Prefer the smallest routing/event model that fits the existing app structure.
4. Record a defer rationale if the UI is consciously postponed.

### For the Human Reviewer

1. Verify the UI stays within the minimal scope promised by the plan.
2. Verify JSON parsing is not moved into the context.
3. Reject if the task balloons into a multi-step workflow.

---

## Execution Summary

### Work Performed

1. Created `DownloadJsonHook` JS hook at `assets/js/hooks/download_json_hook.js` — listens for `"download_json"` push events and triggers a client-side file download via a data URI.
2. Registered `DownloadJsonHook` in `assets/js/app.js`.
3. Added `export_lemming` event handler to `lib/lemmings_os_web/live/lemmings_live.ex` — calls `ImportExport.export_lemming/1`, encodes to pretty-printed JSON via `Jason.encode!/2`, then pushes a `"download_json"` event with filename `lemming-{slug}.json`.
4. Added an `Export JSON` button and the `phx-hook="DownloadJsonHook"` span to the edit tab panel in `lib/lemmings_os_web/components/lemming_components.ex`.
5. Added `import_lemmings` UI to the Department lemmings tab in `lib/lemmings_os_web/components/world_components.ex` — inline form with a `<textarea>` for pasting JSON, visible only when `@import_open?` is true.
6. Added `toggle_import_form`, `validate_import`, and `submit_import` event handlers to `lib/lemmings_os_web/live/departments_live.ex`, including structured inline error messages for JSON decode errors, unsupported schema version, and changeset validation failures.
7. Added `:import_open?`, `:import_form`, and `:import_error` assigns to `departments_live.ex` mount, `assign_department_detail/3`, and all error-path branches.
8. Threaded new assigns through `lib/lemmings_os_web/live/departments_live.html.heex`.
9. Added all new i18n keys to `priv/gettext/en/LC_MESSAGES/lemmings.po`, `priv/gettext/es/LC_MESSAGES/lemmings.po`, `priv/gettext/lemmings.pot`, `priv/gettext/en/LC_MESSAGES/world.po`, `priv/gettext/es/LC_MESSAGES/world.po`, and `priv/gettext/world.pot`.
10. Added export tests to `test/lemmings_os_web/live/lemmings_live_test.exs` and import tests (S15–S21) to `test/lemmings_os_web/live/departments_live_test.exs`.

### Outputs Created

| File | Action |
|------|--------|
| `assets/js/hooks/download_json_hook.js` | Created |
| `assets/js/app.js` | Modified — added `DownloadJsonHook` import and registration |
| `lib/lemmings_os_web/live/lemmings_live.ex` | Modified — `ImportExport` alias, two `export_lemming` event handlers |
| `lib/lemmings_os_web/components/lemming_components.ex` | Modified — `export_hook_id` attr, hook span, Export JSON button in edit tab |
| `lib/lemmings_os_web/live/departments_live.ex` | Modified — `ImportExport` alias, import event handlers, import assigns |
| `lib/lemmings_os_web/live/departments_live.html.heex` | Modified — three new import attrs passed to `department_detail_page` |
| `lib/lemmings_os_web/components/world_components.ex` | Modified — three new attrs, import inline form panel in lemmings tab |
| `priv/gettext/en/LC_MESSAGES/lemmings.po` | Modified — 8 new keys |
| `priv/gettext/es/LC_MESSAGES/lemmings.po` | Modified — 8 new keys (Spanish) |
| `priv/gettext/lemmings.pot` | Modified — 8 new keys |
| `priv/gettext/en/LC_MESSAGES/world.po` | Modified — 9 new keys |
| `priv/gettext/es/LC_MESSAGES/world.po` | Modified — 9 new keys (Spanish) |
| `priv/gettext/world.pot` | Modified — 9 new keys |
| `test/lemmings_os_web/live/lemmings_live_test.exs` | Modified — export describe block (2 tests) |
| `test/lemmings_os_web/live/departments_live_test.exs` | Modified — import describe block (7 tests, S15–S21) |

### Assumptions Made

| Assumption | Rationale |
|------------|-----------|
| Export button placed in the edit tab panel (`:actions` slot) | The edit tab is the natural surface for "manage this lemming" actions; the overview tab is read-only by convention |
| `phx-hook` span placed inside the `active_tab == "edit"` conditional | The hook only needs to be mounted when the export button is visible; `push_event` targets all hooks listening to the named event in the current LiveView session |
| No file upload input added | The task brief explicitly allowed "paste or file upload as alternative" but marked the textarea approach as sufficient; adding a file input in the same form would require JavaScript to read the FileReader API and push to a `phx-change`, adding complexity that the "no wizard" constraint discourages |
| Import inline form uses a raw `<textarea>` instead of `<.input type="textarea">` | The `<.input>` component is backed by `Phoenix.HTML.FormField`; using a raw textarea with `name="import[json]"` keeps the form binding simpler for a free-form text surface |
| `validate_import` stores the raw JSON in the form without re-parsing | Eager re-parsing on every keystroke is unnecessary and noisy; the form just updates the textarea value for LiveView patching |

### Decisions Made

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Data URI download via JS hook | Server-side download endpoint with `send_download/3` | No new routes needed; simpler; the JSON is small enough that data URIs are practical |
| Inline error as a `@import_error` string assign | Flash message | Flash messages disappear on navigation; an inline error stays visible while the user edits the JSON in the same panel |
| Import state (`@import_open?`, `@import_form`, `@import_error`) cleared on department navigation | Persisting state across navigation | Prevents stale error messages when switching departments |
| JSON parsing lives in `handle_event("submit_import", ...)` in the LiveView | Context layer | Constitution requires context functions to accept maps; parsing is a web-layer concern |

### Blockers Encountered

None.

### Questions for Human

1. Should a file upload input be added as a parallel alternative to the textarea? The task brief mentioned it but it was treated as optional given the "no wizard" constraint. It can be added as a follow-up without changing the event contract.

### Ready for Next Task

- [x] All outputs complete
- [x] Summary documented
- [x] Questions listed (if any)

---

## Human Review

*[Filled by human reviewer]*

### Review Date

[YYYY-MM-DD]

### Decision

- [ ] APPROVED - Proceed to next task
- [ ] REJECTED - See feedback below

### Feedback

### Git Operations Performed

```bash
# human-only
```
