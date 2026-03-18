# Task 09: Minimal City CRUD Read Operator Flows

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
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
