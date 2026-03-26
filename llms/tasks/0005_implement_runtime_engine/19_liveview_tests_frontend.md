# Task 19: LiveView Tests -- Frontend

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`qa-elixir-test-author` - QA-driven Elixir test writer converting scenarios into ExUnit tests.

## Agent Invocation
Act as `qa-elixir-test-author` following `llms/constitution.md` and implement LiveView tests for the spawn flow, instance session page, live status updates, and follow-up input.

## Objective
Implement LiveView tests defined in the test plan (Task 17 output). Cover: spawn modal interaction, spawn denied for non-active lemmings, successful spawn navigation, session page rendering for all 7 statuses, conversation transcript display, first user message from Message table (no `initial_request` column), provider/model/token metadata display, `total_tokens` and `usage` jsonb rendering, follow-up input enable/disable by status, PubSub-driven live updates, and not-found handling.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/coding_styles/elixir_tests.md` - Test coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - UX States, Acceptance Criteria US-1 through US-8
- [ ] `llms/tasks/0005_implement_runtime_engine/test_plan.md` - Task 17 output (test scenarios)
- [ ] `test/lemmings_os_web/live/lemmings_live_test.exs` - Existing LiveView test precedent
- [ ] `test/support/factory.ex` - Factory with `:lemming_instance`, `:lemming_instance_message`
- [ ] Task 10 output (spawn flow UI) - Spawn CTA, modal, instances list
- [ ] Task 11 output (session page) - Status display, transcript, metadata
- [ ] Task 12 output (follow-up input) - Input enable/disable logic

## Expected Outputs

- [ ] New `test/lemmings_os_web/live/instance_live_test.exs` - Session page LiveView tests
- [ ] Modified `test/lemmings_os_web/live/lemmings_live_test.exs` - Spawn flow test additions

## Acceptance Criteria

### Spawn Flow Tests (extend `lemmings_live_test.exs`)
- [ ] Spawn CTA visible on active Lemming detail page
- [ ] Spawn CTA disabled/hidden for draft Lemming
- [ ] Spawn CTA disabled/hidden for archived Lemming
- [ ] Clicking Spawn opens the modal
- [ ] Modal: empty input prevents submission (confirm button disabled)
- [ ] Modal: cancel closes without creating anything
- [ ] Modal: successful submission creates instance and navigates to session page
- [ ] Modal: successful submission calls a single runtime/application service from the LiveView
- [ ] Instances list on Lemming detail page renders active instances
- [ ] Instances list shows first user message preview (joined from Message table, NOT from `initial_request` column)
- [ ] Instances list shows status badges
- [ ] Instances list empty state: "No active instances" message

### Session Page Tests (new `instance_live_test.exs`)
- [ ] Page renders for valid instance ID
- [ ] Page shows "Instance not found" for invalid ID
- [ ] Status badge renders correctly for each of the 7 statuses: `created`, `queued`, `processing`, `retrying`, `idle`, `failed`, `expired`
- [ ] `retrying` status shows retry count as "(n/3)"
- [ ] Transcript renders user messages and assistant messages in chronological order
- [ ] User and assistant messages are visually distinct (different CSS classes/alignment)
- [ ] First user message is the initial spawn request (from Message table)
- [ ] Assistant messages show provider and model name when present
- [ ] Assistant messages show token usage (input_tokens, output_tokens) when present
- [ ] Assistant messages show `total_tokens` when present (nullable field renders correctly)
- [ ] Assistant messages show `usage` jsonb data when present (nullable field renders correctly or is gracefully omitted)
- [ ] Token and usage fields are absent when null (no "null" text rendered)
- [ ] Breadcrumb/back-link navigates to parent Lemming page
- [ ] Instance metadata displays `started_at` and `last_activity_at`

### Follow-up Input Tests
- [ ] Input form visible on session page
- [ ] Input enabled when instance status is `idle`
- [ ] Input disabled when instance status is `created`
- [ ] Input disabled when instance status is `queued`
- [ ] Input disabled when instance status is `processing`
- [ ] Input disabled when instance status is `retrying`
- [ ] Input disabled when instance status is `failed` (permanently)
- [ ] Input disabled when instance status is `expired` (permanently)
- [ ] Successful submission clears input field
- [ ] Submitted message appears in transcript

### PubSub Live Update Tests
- [ ] Status change broadcast updates status badge without page refresh
- [ ] New message broadcast appends message to transcript
- [ ] Status transition from `idle` to `queued` disables input
- [ ] Status transition from `processing` to `idle` enables input

## Technical Notes

### Relevant Code Locations
```
test/lemmings_os_web/live/lemmings_live_test.exs       # Existing test file to extend
lib/lemmings_os_web/live/lemmings_live.ex               # Spawn flow under test
lib/lemmings_os_web/live/instance_live.ex               # Session page under test
test/support/factory.ex                                  # Factories
```

### Patterns to Follow
- Follow `lemmings_live_test.exs` patterns: `use LemmingsOsWeb.ConnCase`, `import Phoenix.LiveViewTest`
- Use `live/2` to mount LiveViews
- Use `has_element?/2,3` for presence assertions
- Use `render_click/2`, `render_submit/2` for interactions
- Use `Phoenix.PubSub.broadcast/3` to simulate PubSub events in tests
- Factory setup: insert world, city, department, lemming, then instances and messages as needed

### Testing PubSub Updates
To test live updates without real OTP processes:
1. Mount the LiveView (it subscribes to PubSub in mount)
2. Broadcast a status change message via `Phoenix.PubSub.broadcast/3`
3. Assert the rendered HTML updates

### Constraints
- Tests MUST NOT start real executor/scheduler processes -- use factories for data and PubSub for events
- Tests MUST be DB sandbox compatible
- No timing-dependent assertions
- LiveView tests should assert the web layer depends on a single runtime/application service boundary, not direct OTP orchestration
- First user message preview MUST be verified to come from Message table (create instance without any `initial_request` field, create a Message with `role: "user"`, verify it renders)
- Verify `total_tokens` and `usage` jsonb render when present AND are absent when null

## Execution Instructions

### For the Agent
1. Read `elixir_tests.md` and existing LiveView test files for patterns.
2. Read Task 17 test plan for all LiveView scenarios.
3. Extend `lemmings_live_test.exs` with spawn flow tests.
4. Create new `instance_live_test.exs` for session page tests.
5. Test all 7 status states with factory-created instances.
6. Test PubSub live updates by broadcasting events directly.
7. Test follow-up input enable/disable by status.
8. Verify `total_tokens` and `usage` rendering for present and null cases.
9. Verify first user message comes from Message factory, not from instance field.

### For the Human Reviewer
1. Verify all test plan LiveView scenarios from Task 17 are covered.
2. Verify spawn flow tests cover CTA visibility, modal interaction, navigation.
3. Verify session page tests cover all 7 statuses.
4. Verify transcript tests cover message rendering, metadata, token usage.
5. Verify `total_tokens` and `usage` jsonb are tested for both present and null.
6. Verify first user message is from Message table (no `initial_request` column).
7. Verify follow-up input tests cover all status-based enable/disable.
8. Verify PubSub tests simulate events without real OTP processes.
9. Run `mix test` and verify green.

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
