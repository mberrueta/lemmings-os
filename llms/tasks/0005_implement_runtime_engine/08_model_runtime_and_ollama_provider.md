# Task 08: ModelRuntime and Ollama Provider

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer` - senior backend engineer for runtime boundaries, provider abstractions, and HTTP integrations.

## Agent Invocation
Act as `dev-backend-elixir-engineer` following `llms/constitution.md` and implement the `LemmingsOs.ModelRuntime` boundary, a provider behaviour, and the `LemmingsOs.ModelRuntime.Providers.Ollama` module with Req-based HTTP client, provider translation, structured output parsing, and retry-friendly error handling.

## Objective
Create a dedicated model execution boundary outside `LemmingInstances`:

- `lib/lemmings_os/model_runtime.ex`
- `lib/lemmings_os/model_runtime/provider.ex`
- `lib/lemmings_os/model_runtime/providers/ollama.ex`

`LemmingsOs.ModelRuntime` owns model execution orchestration, prompt assembly, provider selection, and the structured output validation contract. The provider behaviour defines the contract for concrete providers. `Providers.Ollama` handles Ollama-specific transport and translation: receiving an already-assembled request shape from `ModelRuntime`, calling the `/api/chat` endpoint via `Req`, mapping Ollama request/response fields, and returning typed provider results. `LemmingInstances.Executor` must delegate through `ModelRuntime` and must not know Ollama-specific details.

## Inputs Required

- [ ] `llms/constitution.md` - Global rules
- [ ] `llms/project_context.md` - Project conventions
- [ ] `llms/coding_styles/elixir.md` - Elixir coding style
- [ ] `llms/tasks/0005_implement_runtime_engine/plan.md` - Frozen Contracts #13 (Structured output), #14 (Prompt assembly), #15 (Ollama integration)
- [ ] Task 13 output (Req dependency added to mix.exs)

## Expected Outputs

- [ ] `lib/lemmings_os/model_runtime.ex` - Model runtime boundary
- [ ] `lib/lemmings_os/model_runtime/provider.ex` - Provider behaviour
- [ ] `lib/lemmings_os/model_runtime/providers/ollama.ex` - Ollama provider implementation
- [ ] `lib/lemmings_os/model_runtime/response.ex` - Response struct (optional, may be inline)

## Acceptance Criteria

### API Surface
- [ ] `LemmingsOs.ModelRuntime.run/3` (or equivalent) delegates to the configured provider and returns `{:ok, response}` or `{:error, reason}`
- [ ] `LemmingsOs.ModelRuntime.Provider` defines the provider callback contract
- [ ] `LemmingsOs.ModelRuntime.Providers.Ollama.chat/3` (or equivalent provider callback implementation) performs the actual Ollama call
- [ ] Response struct includes: `reply` (string), `provider` ("ollama"), `model` (string), `input_tokens` (integer or nil), `output_tokens` (integer or nil), `total_tokens` (integer or nil), `usage` (map or nil), `raw` (raw provider response for debugging)

### Prompt Assembly (Frozen Contract #14)
- [ ] Prompt assembly happens inside `ModelRuntime`, not inside `Providers.Ollama`
- [ ] System message assembled from: Lemming `instructions` + structured output contract definition + runtime rules
- [ ] Conversation history: list of `%{role: "user" | "assistant", content: "..."}` maps
- [ ] Current request: the work item content appended as the latest user message
- [ ] Prompt is NOT stored in assembled form

### Structured Output Contract (Frozen Contract #13)
- [ ] Requests JSON format via `format: "json"` parameter to Ollama
- [ ] Expected response structure: `{"action": "reply", "reply": "..."}`
- [ ] Validates response: must be valid JSON, must have `action` field, must have `reply` field when `action` is `"reply"`
- [ ] Returns `{:error, :invalid_structured_output}` on validation failure (triggers retry in Executor)
- [ ] Returns `{:error, :unknown_action}` for unrecognized `action` values (triggers retry in v1)

### HTTP Client (Frozen Contract #15)
- [ ] Uses `Req` for HTTP calls (constitution mandate)
- [ ] Endpoint: configurable via application config, defaults to `http://localhost:11434`
- [ ] API path: `/api/chat`
- [ ] Timeout: configurable, default 120 seconds
- [ ] Parses `message.content` from Ollama response, then JSON-parses that content
- [ ] Returns `{:error, :network_error}` on connection failures
- [ ] Returns `{:error, :provider_error}` on non-200 HTTP responses
- [ ] Returns `{:error, :timeout}` on request timeout

### Token Tracking
- [ ] Extracts `prompt_eval_count` as `input_tokens`
- [ ] Extracts `eval_count` as `output_tokens`
- [ ] Computes `total_tokens` as sum when both available, or from `total_duration` estimate if not
- [ ] Captures full Ollama usage fields in `usage` map (eval_duration, prompt_eval_duration, etc.)

### Provider Abstraction
- [ ] `ModelRuntime` is the dedicated boundary used by runtime orchestration code
- [ ] `ModelRuntime` owns orchestration, prompt assembly, provider selection, and structured output validation
- [ ] `LemmingsOs.ModelRuntime.Provider` is a `@callback`-based behaviour
- [ ] Provider selection happens through `ModelRuntime`, not in `LemmingInstances.Executor`
- [ ] `Providers.Ollama` owns transport and Ollama-specific request/response translation only
- [ ] Provider name is always `"ollama"` in the Ollama provider implementation

## Technical Notes

### Relevant Code Locations
```
lib/lemmings_os/lemming_instances/executor.ex  # Runtime caller; should depend on ModelRuntime only
mix.exs  # Task 13 adds {:req, "~> 0.5"}
```

### Patterns to Follow
- `Req.new()` with base URL and default options, then `Req.post!()` or `Req.post()`
- Pattern match on HTTP response status for error classification
- Use `Jason.decode/1` for JSON parsing
- Structured logging on provider errors

### Constraints
- No streaming in v1 -- full response only
- Only `action: "reply"` is implemented; other actions trigger retry
- Do not expose raw provider error payloads to the operator (security)
- Token fields from Ollama may not always be present -- handle gracefully
- The system message must include the structured output contract definition so the model knows to respond in JSON
- Do not place provider modules under `LemmingInstances`; model execution lives behind `ModelRuntime`

## Execution Instructions

### For the Agent
1. Read plan.md Frozen Contracts #13, #14, #15 thoroughly.
2. Verify `Req` is available in `mix.exs` (Task 13 output).
3. Create `ModelRuntime`, the provider behaviour, and the Ollama provider modules.
4. Implement the runtime boundary so callers depend on `ModelRuntime`, not the concrete provider.
5. Implement `ModelRuntime` prompt assembly plus the Ollama provider's HTTP call and provider-specific translation.
6. Implement structured output validation.
7. Handle all error cases with typed error tuples.
8. Extract token usage from Ollama response fields.
9. Add `@doc` and `@spec` to all public functions.

### For the Human Reviewer
1. Verify structured output validation checks for both `action` and `reply` fields.
2. Verify the executor depends on `ModelRuntime`, not directly on `Providers.Ollama`.
3. Verify all error paths return typed tuples (not raw exceptions).
4. Verify token extraction from Ollama-specific fields.
5. Verify system message includes structured output contract definition.
6. Verify configurable endpoint and timeout.
7. Verify no raw provider errors leak to user-facing paths.

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
