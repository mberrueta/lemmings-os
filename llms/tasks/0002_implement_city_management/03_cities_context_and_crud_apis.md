# Task 03: Cities Context and CRUD APIs

## Status

- **Status**: 🔒 BLOCKED
- **Approved**: [ ]
- **Blocked by**: Task 02
- **Blocks**: Task 04, Task 07, Task 08, Task 09

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix.

## Agent Invocation

Use `dev-backend-elixir-engineer` to implement the `LemmingsOs.Cities` context and explicit World-scoped CRUD/read APIs.

## Objective

Expose the core City domain boundary with explicit world scope, reusable query composition, and the minimal runtime support APIs required by startup and heartbeat flows, while keeping normal operator CRUD separate from runtime presence semantics.

## Inputs Required

- [ ] `llms/tasks/0002_implement_city_management/plan.md`
- [ ] `llms/tasks/0002_implement_city_management/02_shared_config_embeds_and_city_schema.md`
- [ ] `lib/lemmings_os/worlds.ex`
- [ ] `llms/constitution.md`
- [ ] `llms/project_context.md`

## Expected Outputs

- [ ] `LemmingsOs.Cities`
- [ ] `list_cities/2` and supporting query helpers
- [ ] explicit get/fetch helpers scoped by world
- [ ] create/update/delete APIs for operator-managed city records
- [ ] narrow runtime support API: `upsert_runtime_city/2`
- [ ] narrow heartbeat persistence API used by the heartbeat worker and later tasks
- [ ] context tests

## Acceptance Criteria

- [ ] all public retrieval/list APIs require explicit World scope
- [ ] list APIs accept `opts`
- [ ] filtering lives in private multi-clause `filter_query/2`
- [ ] failure-returning functions use tuples
- [ ] web layers can depend on the context instead of schemas/repos directly
- [ ] preload behavior is explicit where later resolver/read-model work needs `:world`

## Technical Notes

### Relevant Code Locations

- `lib/lemmings_os/worlds.ex`
- `lib/lemmings_os/`
- `test/lemmings_os/worlds_test.exs`
- `test/support/factory.ex`

### Constraints

- No implicit global city queries
- Use `Ecto.Multi` when a flow touches more than one table
- Keep the public API small and composable
- Avoid over-design for future clustering
- Keep runtime support APIs narrow and explicitly internal to startup/presence flows
- Do not let runtime upsert semantics reshape the general CRUD contract

## Execution Instructions

### For the Agent

1. Mirror the rigor and shape of `LemmingsOs.Worlds`.
2. Keep world scoping explicit in every public read path.
3. Keep operator CRUD and runtime presence support clearly separated in naming and behavior.
4. Add only the narrow runtime helpers needed by downstream startup/heartbeat tasks.
5. Document any guardrails needed around delete semantics.

### For the Human Reviewer

1. Confirm the API is explicitly World-scoped.
2. Confirm `filter_query/2` and list-query composition exist where needed.
3. Confirm there is no hidden implicit-global helper.
4. Approve before Task 04, Task 07, Task 08, and Task 09 begin.
