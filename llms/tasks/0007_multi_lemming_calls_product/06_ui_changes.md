# Task 06: UI Changes

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer`

## Agent Invocation
Act as `dev-frontend-ui-engineer` following `llms/constitution.md`, AGENTS.md Phoenix/LiveView rules, and existing UI patterns.

## Objective
Expose manager entry, available lemming types, and delegated work state with minimal UI disturbance.

## Inputs Required
- [ ] Tasks 01-05 outputs
- [ ] `lib/lemmings_os_web/live/departments_live.*`
- [ ] `lib/lemmings_os_web/live/instance_live.*`
- [ ] Existing components under `lib/lemmings_os_web/components/`

## Expected Outputs
- [ ] Department page shows primary manager ask entry when a manager exists.
- [ ] Department page lists available lemming types with manager/worker identity.
- [ ] Manager instance page shows delegated work summary.
- [ ] Manager-facing delegated work visibility reflects direct user input added to manager-spawned child sessions.
- [ ] Child instance page shows parent/manager relationship when spawned by a call.
- [ ] Call detail/expandable panel shows requested task, state, result summary, and error summary.
- [ ] User-visible UI states include `queued`, `running`, `retrying`, `completed`, `failed`, `dead`, and `recovery_pending`.

## UI Constraints
- Use `<Layouts.app flash={@flash} ...>`.
- Use LiveView streams for call/delegated-work collections.
- Use existing `<.icon>` and `<.input>` components.
- Add stable DOM IDs for tests.
- No embedded `<script>` tags.
- Keep visual language aligned with existing app.

## Acceptance Criteria
- [ ] Primary chat/session remains manager-centered.
- [ ] Delegated work is visible without a broad redesign.
- [ ] When a manager-spawned child session receives direct user input, the manager surface shows that the delegated work changed through the collaboration UI/state.
- [ ] Historical completed/failed/dead calls remain inspectable.
- [ ] Direct child sessions remain openable.
- [ ] Empty, loading, running, failed, and recovery-pending states are represented.

## Execution Instructions
1. Add page-data/read-model helpers if needed; keep Repo access out of LiveViews.
2. Add minimal components for delegated work cards/rows.
3. Wire PubSub updates from Task 04 where available.
4. Do not add broad navigation or dashboard redesign.

## Human Review
Review UI screenshots or local run before UI tests are finalized.
