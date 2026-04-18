# Task 10: Lemming Detail Page -- Spawn and Instances

## Status
- **Status**: COMPLETED
- **Approved**: [x] Human sign-off

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
Task completed with the runtime detail page wired to the new runtime engine slices.

### Work Performed
- Extended [lib/lemmings_os_web/live/lemmings_live.ex](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os_web/live/lemmings_live.ex) with spawn modal state, spawn event handling, live instance loading, and PubSub refreshes.
- Updated [lib/lemmings_os_web/components/lemming_components.ex](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os_web/components/lemming_components.ex) so the lemming detail workspace renders the spawn CTA, modal, and active instance list.
- Added [lib/lemmings_os_web/live/instance_live.ex](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os_web/live/instance_live.ex) as a minimal runtime session page.
- Added [lib/lemmings_os/runtime.ex](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/runtime.ex) as a thin spawn service boundary.
- Added the instance session route in [lib/lemmings_os_web/router.ex](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os_web/router.ex).
- Added focused LiveView tests for the spawn workspace and instance session page.
- Added happy-path coverage for the supporting runtime modules so the spawn/list/session flow is exercised end-to-end from the public API surface.

### Outputs Created
- [lib/lemmings_os/runtime.ex](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os/runtime.ex)
- [lib/lemmings_os_web/live/instance_live.ex](/mnt/data4/matt/code/personal_stuffs/lemmings-os/lib/lemmings_os_web/live/instance_live.ex)
- [test/lemmings_os_web/live/lemmings_live_runtime_test.exs](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os_web/live/lemmings_live_runtime_test.exs)
- [test/lemmings_os_web/live/instance_live_test.exs](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os_web/live/instance_live_test.exs)
- [test/lemmings_os/runtime_test.exs](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os/runtime_test.exs)
- [test/lemmings_os/model_runtime/response_test.exs](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os/model_runtime/response_test.exs)
- [test/lemmings_os/lemming_instances/dets_store_test.exs](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os/lemming_instances/dets_store_test.exs)
- [test/lemmings_os/lemming_instances/ets_store_test.exs](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os/lemming_instances/ets_store_test.exs)
- [test/lemmings_os/lemming_instances/resource_pool_test.exs](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os/lemming_instances/resource_pool_test.exs)
- [test/lemmings_os/lemming_instances/executor_test.exs](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os/lemming_instances/executor_test.exs)
- [test/lemmings_os/lemming_instances/department_scheduler_test.exs](/mnt/data4/matt/code/personal_stuffs/lemmings-os/test/lemmings_os/lemming_instances/department_scheduler_test.exs)

### Assumptions Made
| Assumption | Rationale |
|------------|-----------|
| The detail page should show only non-terminal instances in the workspace list. | That keeps the list focused on actionable runtime sessions while still satisfying the active-instance UX. |
| The instance session page can remain intentionally minimal for this task. | Task 11 can expand transcript actions and controls without changing the routing contract. |

### Decisions Made
| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Used a thin `Runtime.spawn_session/3` wrapper instead of calling the context from the LiveView directly. | Direct context calls vs. a runtime boundary. | Keeps the web layer decoupled from persistence/runtime orchestration and leaves room for future spawn policy changes. |
| Rendered the instance preview by joining messages from the context rather than denormalizing the first request onto `lemming_instances`. | Denormalized column vs. message join. | Matches the task contract and avoids data duplication. |
| Added a dedicated `InstanceLive` page. | Reusing the lemming detail view vs. a separate session page. | The route is required for navigation, and the dedicated page is a cleaner runtime boundary. |

### Blockers Encountered
- None.

### Questions for Human
1. None.

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
