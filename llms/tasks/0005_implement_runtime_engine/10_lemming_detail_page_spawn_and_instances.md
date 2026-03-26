# Task 10: Lemming Detail Page -- Spawn and Instances

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer` - frontend engineer for Phoenix LiveView, components, and interactive UI.

## Agent Invocation
Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and extend the Lemming detail page with a Spawn CTA, spawn modal, and active instances list.

## Objective
Extend the existing Lemming detail page (`LemmingsLive :show`) with three new UI elements: (1) a Spawn CTA button visible only for active lemmings, (2) a modal for entering the first user request and confirming spawn, and (3) a list of active instances showing status, first user message preview, and creation time. The first message preview must be sourced from the Message table via join -- there is NO `initial_request` column on `lemming_instances`.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contract #12 (Spawn UX contract), UX States (Lemming Detail Page, Spawn Modal), User Stories US-1, US-7
- [ ] `lib/lemmings_os_web/live/lemmings_live.ex` - Existing Lemming detail page
- [ ] `lib/lemmings_os_web/live/lemmings_live.html.heex` - Existing template
- [ ] `lib/lemmings_os_web/components/lemming_components.ex` - Existing components
- [ ] Task 02 output (`lemming_instances.ex`) - durable persistence APIs, `list_instances/2`
- [ ] Task 14 output - `LemmingsOs.Runtime.spawn_session/3` (or equivalent runtime service) for spawn lifecycle orchestration

## Expected Outputs

- [ ] Modified `lib/lemmings_os_web/live/lemmings_live.ex` - Added spawn and instances functionality
- [ ] Modified `lib/lemmings_os_web/live/lemmings_live.html.heex` - Added spawn CTA, modal, instances list
- [ ] Possibly new component functions in `lib/lemmings_os_web/components/lemming_components.ex` or a new `instance_components.ex`

## Acceptance Criteria

### Spawn CTA (US-1)
- [ ] "Spawn" button visible on the Lemming detail page only when lemming status is `"active"`
- [ ] Button is disabled/hidden with explanatory tooltip for `"draft"` or `"archived"` lemmings
- [ ] Clicking "Spawn" opens the spawn modal

### Spawn Modal (US-1, Frozen Contract #12)
- [ ] Modal overlay with a text input for the initial request
- [ ] Confirm button is disabled until text is non-empty
- [ ] Cancel button closes the modal without creating anything
- [ ] On confirm:
  1. Calls `LemmingsOs.Runtime.spawn_session/3` (or equivalent runtime/application service) with the lemming and input text
  2. Receives the new `instance_id`
  3. Navigates to the instance session page (`/lemmings/instances/:id`)
- [ ] Submitting state shows loading indicator, disables confirm button
- [ ] Error state shows error message, preserves form input

### Active Instances List (US-7)
- [ ] Displayed on the Lemming detail page below the existing content
- [ ] Shows all non-expired, non-failed instances (or all instances with status badges -- design choice)
- [ ] Each row shows: status badge, first user message preview, creation time
- [ ] First user message preview is sourced by joining the earliest Message with `role = "user"` -- NOT from any denormalized column on `lemming_instances`
- [ ] Each instance links to its session page
- [ ] Empty state: "No active instances" message when no instances exist
- [ ] List updates live via PubSub subscription to instance status topics

### Route
- [ ] Instance session page route: `live "/lemmings/instances/:id", InstanceLive, :show` (or similar -- coordinate with Task 11)

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os_web/live/lemmings_live.ex       # Current detail page
lib/lemmings_os_web/live/lemmings_live.html.heex # Current template
lib/lemmings_os_web/components/lemming_components.ex # Existing components
lib/lemmings_os_web/router.ex                    # Route registration
lib/lemmings_os/lemming_instances.ex             # Task 02 context
```

### Patterns to Follow
- Follow existing LiveView patterns in `lemmings_live.ex`
- Use daisyUI modal component pattern
- Status badges following existing convention
- PubSub subscription in `mount/3` for live updates

### Constraints
- The first message preview MUST come from joining Messages, NOT from an `initial_request` column
- Do not call `Repo` directly from LiveView -- go through context functions
- LiveView must not directly start executors, call DynamicSupervisor, or notify schedulers
- Spawn flow orchestration belongs to a runtime/application service, not the web layer
- Navigation to instance page should use `push_navigate/2`

## Execution Instructions

### For the Agent
1. Read the existing `lemmings_live.ex` and template thoroughly.
2. Read plan.md UX States for the Lemming Detail Page and Spawn Modal.
3. Extend the LiveView with spawn and instances functionality.
4. Implement the modal with form validation.
5. Implement the instances list with Message join for preview.
6. Add the instance session page route to the router.
7. Subscribe to PubSub for live updates.

### For the Human Reviewer
1. Verify Spawn CTA only shows for active lemmings.
2. Verify first message preview comes from Message join, not a denormalized column.
3. Verify spawn flow calls the runtime/application service once and then navigates.
4. Verify modal validation (empty text prevention).
5. Verify route is registered in router.
6. Verify PubSub subscription for live instance list updates.

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
