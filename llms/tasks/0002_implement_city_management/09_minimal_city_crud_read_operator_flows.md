# Task 09: Minimal City CRUD Read Operator Flows

## Status

- **Status**: COMPLETE
- **Approved**: [X]
- **Blocked by**: Task 07
- **Blocks**: Task 11

## Assigned Agent

`dev-frontend-ui-engineer` - Frontend engineer for Phoenix LiveView.

## Agent Invocation

Use `dev-frontend-ui-engineer` to add the minimal City CRUD/read operator flows required by this issue.

## Objective

Provide only the minimum operator-facing create/edit/delete/read surfaces required to manage City metadata and local override config for this issue.

This task is intentionally a narrow operator surface, not a broad city administration console and not runtime orchestration UX.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] `llms/tasks/0002_implement_city_management/07_city_read_models_and_cities_live_desmoke.md`
- [ ] `lib/lemmings_os_web/router.ex`
- [ ] `lib/lemmings_os_web/`
- [ ] `llms/constitution.md`

## Expected Outputs

- [ ] routes and LiveView updates if needed
- [ ] forms for minimal city operator workflows
- [ ] HEEx templates with stable IDs
- [ ] validation/error states aligned with current Phoenix conventions

## Acceptance Criteria

- [ ] forms use `to_form` and `<.input>`
- [ ] forms do not access raw changesets in HEEx
- [ ] key form and action elements have explicit IDs
- [ ] operator flows stay narrow to City metadata and override buckets
- [ ] the task does not expand into department/lemming management

## Technical Notes

### Relevant Code Locations

- `lib/lemmings_os_web/router.ex`
- `lib/lemmings_os_web/live/`
- `lib/lemmings_os_web/components/`
- `test/lemmings_os_web/live/`

### Constraints

- Follow Phoenix 1.8 LiveView rules from `AGENTS.md`
- Keep routes/layout use consistent with the existing app shell
- Preserve explicit world scoping in web calls to contexts
- Do not broaden this task into Department or Lemming desmoke
- Do not introduce a broad city administration console
- Prefer extending existing City pages/routes before adding new standalone surfaces
- Do not add runtime control, attach, connect, or orchestration actions
- Keep delete flows intentionally minimal and guarded

## Execution Instructions

### For the Agent

1. Implement the minimum city operator flows the plan requires.
2. Reuse existing LiveView surfaces where possible.
3. Add new routes/pages only when the current surfaces cannot support the required minimal operator flow cleanly.
4. Keep templates and form handling idiomatic for this repo.
5. Avoid adding management affordances that imply remote runtime attachment.
6. Record any UX tradeoff made to keep scope finishable.

### For the Human Reviewer

1. Confirm the flows are minimal and finishable.
2. Confirm forms and templates follow repo conventions.
3. Confirm the UI does not imply richer orchestration than the backend supports.
4. Approve before Task 11 proceeds.

---

## Execution Summary

### Work Performed

Extended `CitiesLive` and `cities_live.html.heex` with minimal CRUD operator flows for City metadata. No new routes or standalone pages were added — all flows operate within the existing `/cities` surface using LiveView event-driven overlays.

### Files Created / Modified

| File | Action | Notes |
|---|---|---|
| `lib/lemmings_os_web/live/cities_live.ex` | Modified | Added CRUD event handlers, form assign management, world-scoped context calls |
| `lib/lemmings_os_web/live/cities_live.html.heex` | Modified | Added form overlay panel, "New city" button in list panel, Edit/Delete actions in detail panel |
| `priv/gettext/world.pot` | Modified | Added 22 new msgid keys for form labels, actions, flash messages |
| `priv/gettext/en/LC_MESSAGES/world.po` | Modified | English translations for all new keys |
| `priv/gettext/es/LC_MESSAGES/world.po` | Modified | Spanish translations for all new keys |

### Event Handlers Added

| Event | Handler | Description |
|---|---|---|
| `new_city` | `handle_event/3` | Opens create form with empty changeset |
| `edit_city` | `handle_event/3` | Fetches city by world-scoped ID, opens edit form |
| `validate_city` | `handle_event/3` | Live validation via `phx-change`; uses actual city struct for edit mode |
| `save_city` | `handle_event/3` | Dispatches to `create_city/2` or `update_city/2` based on `form_mode` |
| `cancel_form` | `handle_event/3` | Clears form assigns |
| `delete_city` | `handle_event/3` | World-scoped fetch + delete; uses `data-confirm` for browser-native confirmation guard |

### Assigns Added

| Assign | Type | Purpose |
|---|---|---|
| `:form` | `Phoenix.HTML.Form.t()` or nil | Active form built from changeset via `to_form/2` |
| `:form_mode` | `:new | :edit | nil` | Controls form title and submit label |
| `:form_city_id` | `String.t()` or nil | City ID being edited; nil for new city |

### Form Fields

Create and edit share a single form. Fields:

- `name` (required)
- `slug` (required)
- `node_name` (required, `name@host` format)
- `status` (select, sourced from `City.status_options()`)
- `host` (optional)
- `distribution_port` (optional, number)
- `epmd_port` (optional, number)

### Key IDs for Tests

| Element | ID |
|---|---|
| Page container | `#cities-page` |
| New city button | `#cities-new-button` |
| Form overlay | `#city-form-overlay` |
| Form panel | `#city-form-panel` |
| Form element | `#city-form` |
| Name field | `#city-form-name` |
| Slug field | `#city-form-slug` |
| Node name field | `#city-form-node-name` |
| Status select | `#city-form-status` |
| Host field | `#city-form-host` |
| Distribution port | `#city-form-distribution-port` |
| EPMD port | `#city-form-epmd-port` |
| Submit button | `#city-form-submit-button` |
| Cancel button | `#city-form-cancel-button` |
| Edit button (detail panel) | `#city-edit-button` |
| Delete button (detail panel) | `#city-delete-button` |
| Detail panel | `#city-detail-panel` |

### Acceptance Criteria

- [x] Forms use `to_form` and `<.input>` — no raw changeset access in HEEx
- [x] All key form and action elements have explicit `id` attributes
- [x] Operator flows stay narrow to City metadata (name, slug, node_name, host, ports, status)
- [x] No department or lemming management added
- [x] World scoping preserved — all context calls pass world from snapshot
- [x] Status select uses `City.status_options()` from schema
- [x] Delete uses `data-confirm` for native browser guard (idiomatic Phoenix)
- [x] All user-facing strings via `dgettext("world", ...)`
- [x] `<.status kind={:city} value={...} />` used for status badges (no custom tone helpers)
- [x] `push_patch` used post-save/delete for clean re-render without full remount

### UX Tradeoffs

| Tradeoff | Rationale |
|---|---|
| Form as in-page overlay panel, not a modal dialog | Consistent with existing page panel pattern; no new overlay/backdrop infrastructure needed |
| Edit validation makes a DB call on each keystroke | Minimal implementation; avoids storing raw City struct in assigns; acceptable for operator-only tool |
| No optimistic UI for create/edit | Keeps the flow simple and honest; snapshot reload after save reflects actual DB state |
| Single form for create and edit | Reduces template duplication; `form_mode` assign drives labels and submit text |

### Questions for Human Reviewer

1. The form overlay sits above the page content as a panel (not a floating modal with backdrop). If a proper modal overlay is preferred, that would require adding a modal component or CSS overlay class — confirm preference before Task 12 tests are written.
2. The delete confirmation uses the browser-native `data-confirm` dialog. If a custom confirmation step is preferred (e.g., a secondary form panel), that can be added in a follow-up.
