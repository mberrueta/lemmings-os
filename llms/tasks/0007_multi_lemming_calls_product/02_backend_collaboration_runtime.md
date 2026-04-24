# Task 02: Backend Collaboration Runtime

## Status
- **Status**: COMPLETED
- **Approved**: [x] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md`, `llms/project_context.md`, and `llms/coding_styles/elixir.md`.

## Objective
Wire structured lemming calls into the runtime so manager instances can spawn or continue child work while preserving system-enforced boundaries.

## Inputs Required
- [ ] Task 01 outputs
- [ ] `lib/lemmings_os/model_runtime.ex`
- [ ] `lib/lemmings_os/model_runtime/response.ex`
- [ ] `lib/lemmings_os/lemming_instances/executor.ex`
- [ ] `lib/lemmings_os/lemming_instances.ex`
- [ ] `lib/lemmings_os/lemmings.ex`
- [ ] `lib/lemmings_os/departments.ex`

## Expected Outputs
- [ ] `ModelRuntime.Response` supports `:lemming_call`.
- [ ] Structured output contract includes `{"action":"lemming_call","target":"slug-or-capability","request":"bounded task text","continue_call_id":null}`.
- [ ] Runtime exposes available lemming-call capabilities in system context for managers only.
- [ ] Executor handles `:lemming_call` by calling `LemmingsOs.LemmingCalls`, not by prompt-only behavior.
- [ ] Child completion, failure, partial result, and needs-more-context states update durable call records.
- [ ] Direct child user input updates child transcript and parent call record.

## Boundary Rules
- Managers may call same-department workers in the same World and City.
- Managers may call other department managers in the same World and City.
- Workers may not call workers or other departments directly.
- User-opened workers do not gain delegation rights.
- Cross-World and cross-City calls return explicit errors.

## Runtime State Mapping
- `accepted`: call record created and target resolved.
- `running`: child instance created/enqueued and not terminal.
- `needs_more_context`: child requests clarification/escalation to manager.
- `partial_result`: child or manager records usable incomplete output.
- `completed`: child output summarized and available to manager.
- `failed`: call execution failed.
- `dead`: UI-derived state for unrecoverable/closed runtime or call recovery.

## Acceptance Criteria
- [ ] Existing tool-call flow still passes unchanged.
- [ ] Managers can spawn multiple child calls concurrently subject to existing limits.
- [ ] Refinement can continue an existing call when `continue_call_id` is valid.
- [ ] New work creates a new child call/instance.
- [ ] Expired child continuation creates a successor call linked by `root_call_id`/`previous_call_id`.
- [ ] LLM output cannot bypass boundary rules.

## Execution Instructions
1. Extend model response parsing and structured prompt contract.
2. Add capability discovery for manager-visible lemming calls.
3. Add executor handling for `:lemming_call`.
4. Implement deterministic parent-child synchronization for direct child input.
5. Keep orchestration in backend modules; avoid broad UI changes here.

## Human Review
Verify boundary rules and state mapping before seed/observability tasks proceed.
