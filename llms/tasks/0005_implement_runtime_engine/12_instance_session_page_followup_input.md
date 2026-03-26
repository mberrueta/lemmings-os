# Task 12: Instance Session Page -- Follow-up Request Input

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer` - frontend engineer for Phoenix LiveView, components, and interactive UI.

## Agent Invocation
Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and add the follow-up request input to the instance session page for idle instances.

## Objective
Extend the instance session page (created in Task 11) with an input form that allows operators to send additional requests to an idle instance. The input is enabled only when the instance is in `idle` status, disabled in all other states, and submitting enqueues a new work item on the instance via the context API.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contract #12 (Spawn UX), User Story US-3, Acceptance Criteria US-3
- [ ] Task 11 output (`instance_live.ex`, `instance_live.html.heex`) - Session page to extend
- [ ] Task 02 output (`lemming_instances.ex`) - `enqueue_work/3` or equivalent context function for adding work items
- [ ] Task 03 output (executor GenServer) - How follow-up requests are enqueued

## Expected Outputs

- [ ] Modified `lib/lemmings_os_web/live/instance_live.ex` - Added follow-up input event handlers
- [ ] Modified `lib/lemmings_os_web/live/instance_live.html.heex` - Added input form at bottom of transcript

## Acceptance Criteria

### Follow-up Input (US-3)
- [ ] Text input with submit button displayed at the bottom of the transcript area
- [ ] Input is **enabled** only when instance status is `idle`
- [ ] Input is **disabled** with explanatory text for all other statuses:
  - `created`: "Starting..." (disabled)
  - `queued`: "Waiting for capacity..." (disabled)
  - `processing`: "Processing..." (disabled)
  - `retrying`: "Retrying..." (disabled)
  - `failed`: "Instance has failed" (disabled, no input)
  - `expired`: "Instance has expired" (disabled, no input)
- [ ] Submit button is disabled when text input is empty
- [ ] On submit:
  1. Calls context function to enqueue work on the instance (e.g., `LemmingInstances.enqueue_work/3`)
  2. Clears the input field
  3. The new user message appears in the transcript immediately
  4. Instance transitions from `idle` to `queued` (reflected via PubSub)
  5. DepartmentScheduler is notified of new work via PubSub
- [ ] Submitting state shows loading indicator on submit button
- [ ] Error state shows error message, preserves form input

### Live State Transitions
- [ ] When instance transitions from `idle` to `queued` after submission, the input disables automatically via PubSub status update
- [ ] When instance returns to `idle` after processing, the input re-enables automatically
- [ ] If instance transitions to `failed` or `expired` while input is visible, input disables permanently

### Context Preservation (US-3 Criteria)
- [ ] New requests are queued via the same work item mechanism as the initial request
- [ ] Context from previous messages is included in prompt assembly (handled by executor, not by this task)
- [ ] Queue is FIFO within the instance (handled by executor, not by this task)

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os_web/live/instance_live.ex        # Task 11 output to extend
lib/lemmings_os_web/live/instance_live.html.heex  # Task 11 template to extend
lib/lemmings_os/lemming_instances.ex              # Task 02 context
```

### Patterns to Follow
- Use a `phx-submit` form with `phx-change` for validation
- Follow existing form patterns from `CreateLemmingLive` or spawn modal in Task 10
- Disable form elements based on `@instance.status` assign
- Clear form after successful submission via assign reset

### Constraints
- Do not call the executor GenServer directly -- go through the context API
- Do not implement any queue manipulation logic -- the context function handles that
- The follow-up message is persisted as a `Message` with `role = "user"` by the context/executor
- Terminal statuses (`failed`, `expired`) permanently disable input -- no recovery in v1

## Execution Instructions

### For the Agent
1. Read the Task 11 output (instance_live.ex and template) thoroughly.
2. Read plan.md US-3 acceptance criteria.
3. Add the input form to the template, conditionally enabled based on status.
4. Add `handle_event` for form submission.
5. Call the context function to enqueue work.
6. Handle success (clear input, optimistic message display) and error states.
7. Ensure PubSub-driven status changes toggle input enabled/disabled state.

### For the Human Reviewer
1. Verify input is enabled only for `idle` status.
2. Verify input is disabled with explanatory text for all other statuses.
3. Verify submission calls context function, not executor directly.
4. Verify input clears after successful submission.
5. Verify new user message appears in transcript immediately.
6. Verify PubSub-driven status changes toggle input state correctly.
7. Verify terminal statuses permanently disable input.

---

## Execution Summary
*[Filled by executing agent after completion]*

### Work Performed
- [What was actually done]

### Outputs Created
- [List of files/artifacts created]

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|

### Blockers Encountered
- [Blocker 1] - Resolution: [How resolved or "Needs human input"]

### Questions for Human
1. [Question needing human input]

### Ready for Next Task
- [ ] All outputs complete
- [ ] Summary documented
- [ ] Questions listed (if any)

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
