# Task 08: Reference File Knowledge LiveView Surface

## Status

- **Status**: COMPLETE
- **Approved**: [x] Human sign-off

## Assigned Agent

`dev-frontend-ui-engineer` - Frontend engineer for Phoenix LiveView, HEEx, accessible components, and responsive UI.

## Agent Invocation

Act as `dev-frontend-ui-engineer`. Replace the `/knowledge` Templates placeholder with the Reference Files management surface.

## Objective

Add operator-facing list, filter, upload/register, edit, and archive flows for reference files on the existing Knowledge LiveView.

## Implementation Scope

- Rename the Templates tab to Reference Files.
- Add list states for empty, populated, filtered empty, and archived filter.
- Add filters for text, type, tags, status, and scope where supported.
- Add upload/register form for title, optional description, flexible type, tags, scope, and file.
- Add metadata edit flow for title, description, type, tags, and metadata.
- Add archive action and archived state copy.
- Show safe descriptor fields without raw storage refs or paths.
- Use stable DOM IDs for all forms, filters, buttons, rows, badges, and key state containers.

## Constraints

- LiveView templates must remain HEEx.
- Begin pages with `<Layouts.app ...>` as already implemented.
- Use imported `<.input>`, `<.button>`, `<.icon>`, `<.form>`, and existing component patterns where possible.
- Do not embed `<script>` tags.
- Do not describe reference files as RAG-indexed source files or as required Artifacts.
- Keep existing Memories and Source Files UI behavior intact.

## Expected Outputs

- `/knowledge` Reference Files tab with usable management flows.
- Stable selectors for future LiveView tests.
- Accessible labels, keyboard-friendly controls, and responsive layout consistent with the current Knowledge page.

## Suggested Checks

- `mix format`
- Narrow Knowledge LiveView tests once added
- Existing `test/lemmings_os_web/live/knowledge_live_test.exs`

## Human Approval Gate

Human reviewer validates the UI management surface and no-regression expectations, then approves Task 09.
