# Task 07: Knowledge LiveView Surface Core

## Status
- **Status**: COMPLETED
- **Approved**: [x] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer` - Frontend engineer for LiveView UI and interaction workflows.

## Agent Invocation
Act as `dev-frontend-ui-engineer`. Build the first Knowledge surface for memory management with create/edit/delete and effective list views.

## Objective
Implement the operator-facing Knowledge UI for memories, with stable IDs, form flows, list rendering, and basic filters/pagination controls aligned to the context APIs.

## Inputs Required
- [ ] `llms/tasks/0013_memory_store/plan.md`
- [ ] Tasks 03 and 04 outputs
- [ ] Existing LiveView patterns in `WorldLive`, `CitiesLive`, `DepartmentsLive`, and `LemmingsLive`

## Expected Outputs
- [ ] New LiveView route/page for Knowledge memory management (default `/knowledge` unless reviewer approves a different repo-compatible placement).
- [ ] Memory create/edit/delete form flows using `to_form/2` and stable DOM IDs.
- [ ] Effective memory list with source/scope/owner indicators, tags, and timestamps.
- [ ] Empty/error states for no data and filtered-no-result paths.

## Acceptance Criteria
- [ ] User can create, edit, and hard delete memories from the Knowledge surface.
- [ ] UI distinguishes source (`user`/`llm`) and owning scope/inherited state.
- [ ] Form validation errors are visible and actionable.
- [ ] IDs/selectors are stable for LiveView tests.

## Technical Notes
### Constraints
- Follow existing component style and LiveView interaction conventions.
- Use imported component helpers (`<.form>`, `<.input>`, `<.icon>`, `<.link>`).

### Scope Boundaries
- Do not add file/reference knowledge tabs in this task.

## Execution Instructions
### For the Agent
1. Implement base page route, LiveView module, and HEEx template.
2. Wire CRUD handlers to backend context from prior tasks.
3. Keep copy concise and operational, consistent with current app surfaces.

### For the Human Reviewer
1. Verify usability of primary memory workflows.
2. Verify DOM ID conventions are test-friendly and stable.

## Execution Summary
*[Filled by executing agent after completion]*

## Human Review
*[Filled by human reviewer]*

