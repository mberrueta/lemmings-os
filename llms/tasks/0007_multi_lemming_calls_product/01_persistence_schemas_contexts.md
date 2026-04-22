# Task 01: Persistence, Schemas, Contexts

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md`, `llms/project_context.md`, and `llms/coding_styles/elixir.md`.

## Objective
Add durable data structures and world-scoped context APIs for manager designation and lemming-to-lemming collaboration records.

## Inputs Required
- [ ] `llms/tasks/0007_multi_lemming_calls_product/plan.md`
- [ ] `llms/tasks/0007_multi_lemming_calls_product/implementation_plan.md`
- [ ] `lib/lemmings_os/lemmings/lemming.ex`
- [ ] `lib/lemmings_os/lemming_instances/lemming_instance.ex`
- [ ] Existing migration and context patterns

## Expected Outputs
- [ ] Migration adding `collaboration_role` to `lemmings` with allowed values `manager` and `worker`, default `worker`.
- [ ] Migration creating `lemming_instance_calls`.
- [ ] Schema for `LemmingsOs.LemmingCalls.LemmingCall`.
- [ ] Context module `LemmingsOs.LemmingCalls` with explicit world-scoped APIs.
- [ ] Factory support for manager lemmings and call records.

## Required Call Record Shape
`lemming_instance_calls` must preserve at least:
- `id`, `world_id`, `city_id`
- `caller_department_id`, `callee_department_id`
- `caller_lemming_id`, `callee_lemming_id`
- `caller_instance_id`, `callee_instance_id`
- `root_call_id`, `previous_call_id`
- `request_text`, `status`, `result_summary`, `error_summary`
- `recovery_status`, `started_at`, `completed_at`
- timestamps

## Required Context APIs
- `list_calls(world_or_id, opts \\ [])`
- `get_call(id, world: world_or_id)`
- `create_call(attrs, opts \\ [])`
- `update_call_status(call, status, attrs \\ %{})`
- `list_manager_calls(manager_instance, opts \\ [])`
- `list_child_calls(child_instance, opts \\ [])`
- `manager?(lemming)`
- `worker?(lemming)`

## Acceptance Criteria
- [ ] All public context APIs require explicit World scope where applicable.
- [ ] Call statuses are validated as `accepted`, `running`, `needs_more_context`, `partial_result`, `completed`, `failed`.
- [ ] `root_call_id`/`previous_call_id` support successor chains without cross-World links.
- [ ] Web layer does not call Repo or schemas directly.
- [ ] Migrations include indexes for world, caller instance, callee instance, status, root call, and department filtering.

## Execution Instructions
1. Add migrations and schema changes.
2. Add changesets with `@required`/`@optional` lists and localized validation messages.
3. Add `LemmingCalls` context with documentation on public behavior.
4. Add factories only; leave tests for Task 05.

## Human Review
Confirm schema names, fields, and context boundaries before backend runtime work starts.
