# Task 11: Instance Session Page -- Core

## Status
- **Status**: COMPLETE
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer` - frontend engineer for Phoenix LiveView, components, and interactive UI.

## Agent Invocation
Act as `dev-frontend-ui-engineer` following `llms/constitution.md` and build the instance session page with route, status display, conversation transcript, and live PubSub updates.

## Objective
Create a new LiveView page at `/lemmings/instances/:id` that displays the full session for a `LemmingInstance`. The page shows real-time status via PubSub subscription, the conversation transcript (user messages and assistant replies), metadata per message (provider, model, token usage), and breadcrumb navigation back to the parent Lemming. This task covers display only -- follow-up input is Task 12.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contracts #2, #3, #4, #16; UX States (Instance Session Page); User Stories US-2, US-4, US-8
- [ ] `lib/lemmings_os_web/live/lemmings_live.ex` - Existing LiveView patterns
- [ ] `lib/lemmings_os_web/live/lemmings_live.html.heex` - Template patterns
- [ ] `lib/lemmings_os_web/router.ex` - Route registration patterns
- [ ] `lib/lemmings_os_web/components/lemming_components.ex` - Existing component patterns
- [ ] Task 03 output (executor GenServer) - Status values, PubSub broadcasts
- [ ] Task 09 output (PubSub helpers) - Topic patterns, broadcast payloads
- [ ] Task 10 output (Lemming detail page) - Route registration approach, component patterns

## Expected Outputs

- [ ] New `lib/lemmings_os_web/live/instance_live.ex` - Instance session LiveView
- [ ] New `lib/lemmings_os_web/live/instance_live.html.heex` - Instance session template
- [ ] New or extended `lib/lemmings_os_web/components/instance_components.ex` - Reusable instance UI components (status badge, message bubble, transcript list)
- [ ] Modified `lib/lemmings_os_web/router.ex` - Route `live "/lemmings/instances/:id", InstanceLive, :show`

## Acceptance Criteria

### Route and Navigation (US-2)
- [ ] Route `live "/lemmings/instances/:id", InstanceLive, :show` is registered in the router
- [ ] Page loads the `LemmingInstance` by ID via `LemmingInstances.get_instance/2` (World-scoped, `{:ok, instance}` / `{:error, :not_found}`)
- [ ] If instance not found, render a "Not Found" state (not a crash)
- [ ] Breadcrumb or back-link navigates to the parent Lemming detail page (`/lemmings/:lemming_id`)

### Status Display (US-2, US-4, US-8)
- [ ] Status badge renders all 7 runtime statuses: `created`, `queued`, `processing`, `retrying`, `idle`, `failed`, `expired`
- [ ] Each status has distinct visual styling:
  - `created`: neutral/muted
  - `queued`: info/waiting
  - `processing`: active/primary with elapsed time indicator
  - `retrying`: warning styling showing retry count as `retrying (n/3)`
  - `idle`: success/calm with idle timeout indicator
  - `failed`: error/danger
  - `expired`: muted/disabled
- [ ] Status updates live via PubSub without page refresh
- [ ] Page subscribes to `"instance:#{instance_id}:status"` topic in `mount/3`

### Conversation Transcript (US-2)
- [ ] Messages are loaded from `LemmingInstances.list_messages/2` on mount
- [ ] Messages are displayed in chronological order (oldest first)
- [ ] User messages are visually distinct from assistant messages (different alignment or color)
- [ ] The first user message (the initial spawn request) appears at the top of the transcript -- there is NO `initial_request` column on `lemming_instances`; the first message comes from the Message table
- [ ] Assistant messages show: provider name, model name, token usage (input/output/total) when available
- [ ] `total_tokens` and `usage` (jsonb) fields on Message render correctly when present; gracefully omitted when null
- [ ] New messages arriving via PubSub append to the transcript without page refresh
- [ ] Empty transcript state: "Waiting for first response..." when only user message exists

### Instance Metadata
- [ ] Display instance `started_at` (process birth time)
- [ ] Display instance `last_activity_at` (last runtime move)
- [ ] Display parent Lemming name with link

### UX States (from plan.md)
- [ ] **Created**: "Starting..." with spinner
- [ ] **Queued**: "Waiting for capacity..." status
- [ ] **Processing**: "Processing" with elapsed time indicator; no input (Task 12)
- [ ] **Retrying**: "Retrying (n/3)" with warning styling
- [ ] **Idle**: "Idle" status; input handled by Task 12
- [ ] **Failed**: "Failed" with error styling; no input
- [ ] **Expired**: "Expired" with muted styling; no input
- [ ] **Not Found**: "Instance not found" if ID is invalid

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os_web/live/lemmings_live.ex       # LiveView patterns to follow
lib/lemmings_os_web/live/lemmings_live.html.heex # Template patterns to follow
lib/lemmings_os_web/components/lemming_components.ex # Component patterns
lib/lemmings_os_web/router.ex                    # Route registration
lib/lemmings_os/lemming_instances.ex             # Task 02 context (get_instance/2, list_messages/2)
```

### Patterns to Follow
- Follow existing LiveView patterns in `lemmings_live.ex` for mount, handle_params, assigns
- Use daisyUI component classes for badges, cards, chat bubbles
- PubSub subscription in `mount/3` with `Phoenix.PubSub.subscribe/2`
- Status badges following existing convention from lemming status rendering
- Use context functions only -- no direct `Repo` calls from LiveView

### Constraints
- The first user message preview MUST come from the Message table, NOT from any column on `lemming_instances`
- Do not implement follow-up input -- that is Task 12
- The `processing` elapsed time indicator should use a JS hook or LiveView timer for updating display
- Subscribe to PubSub for both status changes and new messages
- Handle PubSub messages with `handle_info/2` clauses
- World scoping: the instance must be loaded in the context of the current World (via `Worlds.Cache` or equivalent)

### Temporal Marker Semantics
- `inserted_at` = record creation time (when `spawn_instance/3` was called)
- `started_at` = OTP process birth time (set once at spawn, not at first work item)
- `last_activity_at` = last real runtime state change
- `stopped_at` = set only on terminal outcomes (`failed`, `expired`)

## Execution Instructions

### For the Agent
1. Read the existing `lemmings_live.ex` and its template thoroughly for patterns.
2. Read plan.md UX States for the Instance Session Page.
3. Create the new `InstanceLive` module with mount, handle_params, handle_info.
4. Create the template with status display, transcript, and metadata sections.
5. Create reusable components for status badges and message rendering.
6. Register the route in the router.
7. Subscribe to PubSub topics for live updates.
8. Handle the "Not Found" case gracefully.

### For the Human Reviewer
1. Verify all 7 status states render with correct styling.
2. Verify PubSub subscription for live updates.
3. Verify transcript renders messages chronologically with correct role styling.
4. Verify token usage and provider/model metadata render for assistant messages.
5. Verify `total_tokens` and `usage` jsonb fields render when present, are absent when null.
6. Verify first user message comes from Message table (no `initial_request` column reference).
7. Verify route is registered correctly.
8. Verify no follow-up input is implemented (that is Task 12).
9. Verify breadcrumb/back-link to parent Lemming page works.

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
