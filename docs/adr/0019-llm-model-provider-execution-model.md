# ADR-0019 — Model Runtime

- Status: Accepted
- Date: 2026-03-14
- Decision Makers: Maintainer(s)

---

# 1. Context

LemmingsOS is a runtime for autonomous agents that interact with large language
models as their primary reasoning engine. Multiple ADRs already assume the
existence of a model execution layer:

- ADR-0004 defines the Lemming execution model and references model calls as
  runtime events, but does not define the provider contract.
- ADR-0008 describes context persistence and compaction, but does not define
  how the context is assembled into a prompt or how provider responses are
  processed.
- ADR-0015 defines cost governance and tracks LLM token usage as a first-class
  cost source, but assumes token counts are available without specifying how
  they are produced.

Without a formal definition of the model execution layer, each Lemming
implementation risks coupling directly to a specific provider, and governance
subsystems such as cost tracking and policy inheritance have no clear runtime
boundary to hook into.

LemmingsOS is explicitly designed to be **accessible by default**. A developer
or small team should be able to run a fully functional installation at zero
cost. This means Ollama is the primary provider, free-tier cloud providers
are the recommended cloud fallback, and paid providers are optional
operator-configured upgrades.

> **Note:** Consumer AI subscriptions (ChatGPT Plus, Claude.ai Pro,
> Gemini Advanced) do not include API access. They are separate products
> with per-seat billing. Programmatic API access requires dedicated API keys
> with per-token pricing, independent of any subscription. LemmingsOS
> integrates with provider APIs, not consumer products.

The system must also support several operational requirements that go beyond
a simple HTTP call to an inference endpoint:

- **Model policy inheritance** — which model a Lemming uses must be resolvable
  through the hierarchy `World → City → Department → Lemming type → instance`.
- **Token usage tracking** — raw usage data from the provider must be captured
  and forwarded to the cost governance subsystem.
- **Retry and timeout policy** — provider calls may fail transiently and must
  operate under configurable runtime limits.
- **Structured output** — some Lemmings require machine-readable responses.
  The execution model must define how structured outputs are requested and
  validated.
- **Streaming** — long-form responses benefit from streaming delivery. The
  execution model must define whether streaming is supported and how it
  interacts with the Lemming state machine.
- **Prompt assembly** — the structured context stored in ADR-0008 must be
  serialized into a provider-compatible message sequence. This translation
  must happen at a well-defined boundary, not scattered across Lemming
  implementations.

---

# 2. Decision Drivers

1. **Accessibility** — zero-cost operation must be possible out of the box,
   with no API keys or cloud accounts required. This drives Ollama as the
   default and shapes the provider tier design.

2. **Provider independence** — Lemming definitions must remain unchanged
   regardless of which provider backs them. Provider selection is an
   operational concern, not a code concern.

3. **Governance integration** — model calls generate cost, require audit
   trails, and must respect the same hierarchical policy model as tools
   and secrets. The execution boundary must be a first-class governance
   integration point, not an afterthought.

4. **Consistency with existing runtime boundaries** — the system already
   has a Tool Runtime as the controlled boundary for external side effects.
   The model execution layer must follow the same design patterns: supervised,
   auditable, policy-driven, and City-scoped.

5. **Operational simplicity** — the abstraction must not introduce accidental
   complexity. A developer building a Lemming should not need to understand
   provider-specific APIs. Configuration changes at World or Department scope
   must be sufficient to switch providers.

6. **OTP alignment** — model calls are asynchronous, may be slow, and can
   fail transiently. The execution model must fit naturally within the
   GenServer state machine defined in ADR-0004.

---

# 3. Considered Options

## Option A — Direct provider calls inside each Lemming

Each Lemming implementation calls the provider API directly, managing its
own HTTP client, retries, and token tracking.

**Pros:**

- simplest implementation per Lemming
- no shared infrastructure to design or maintain

**Cons:**

- every Lemming duplicates provider client logic and retry handling
- no central point for cost governance integration
- provider credentials would need to be passed to every Lemming process,
  violating the Secret Bank isolation model from ADR-0009
- switching providers requires modifying every Lemming definition
- audit coverage is inconsistent across implementations

Rejected. Violates governance, secret isolation, and provider independence
requirements simultaneously.

---

## Option B — Model calls as Tools

Wrap LLM inference as a Tool, routed through the existing Tool Runtime
(ADR-0005). Lemmings invoke an `llm_complete` tool the same way they invoke
any other tool.

**Pros:**

- reuses existing Tool Runtime infrastructure, policy model, and audit pipeline
- no new runtime subsystem required

**Cons:**

- conceptually incorrect: Tools are for external side effects with defined
  inputs and outputs. Model inference is the agent's internal reasoning engine.
  Treating it as a Tool conflates the reasoning layer with the effect layer.
- the Tool invocation model assumes structured, bounded inputs and outputs.
  Model calls involve large context windows, streaming, and complex assembly
  logic that does not fit the Tool contract.
- tool authorization (ADR-0012) is not the right governance model for model
  selection. Policy inheritance for model selection has different semantics
  than tool allowlists.
- model calls are on the critical path of every Lemming execution step.
  Routing them through the Tool approval and risk classification pipeline
  (ADR-0013, ADR-0014) adds unnecessary overhead for a non-side-effecting
  operation.

Rejected. Conceptually incorrect and adds governance overhead that does not
apply to model inference.

---

## Option C — Dedicated Model Runtime with provider behaviour abstraction (chosen)

Introduce a dedicated **Model Runtime** subsystem as a peer of the Tool
Runtime. It defines a provider behaviour that all adapters implement, owns
prompt assembly, enforces model policy, integrates with cost governance,
and emits audit events through the shared event model.

**Pros:**

- clean separation of concerns: reasoning engine vs external effects
- single authoritative integration point for cost governance and audit
- provider abstraction enables zero-code provider switching via configuration
- fits naturally with the OTP supervision model and City execution boundary
- prompt assembly is centralized, preventing divergent implementations

**Cons:**

- introduces a new supervised subsystem that must be designed, tested,
  and maintained
- adds an abstraction layer between Lemming and provider; debugging
  inference issues requires understanding the assembly pipeline

Chosen. The trade-offs are justified by the governance requirements and the
consistency with existing runtime design patterns.

---

## Option D — Single OpenAI-compatible adapter for all providers

Standardize on the OpenAI HTTP API contract and require all providers to be
accessed through an OpenAI-compatible endpoint (Ollama supports this;
providers like LiteLLM or OpenRouter can proxy others).

**Pros:**

- single adapter implementation
- any OpenAI-compatible provider works without code changes

**Cons:**

- Anthropic's API has a different message structure (system field, tool use
  blocks) that loses expressiveness when proxied through an
  OpenAI-compatible layer
- Gemini's native API exposes features not available through the compatibility
  shim
- provider-specific usage reporting (cache tokens, reasoning tokens) is lost
  or inconsistently mapped, breaking accurate cost governance
- operators are forced to run a proxy service even for direct provider
  integrations, adding operational overhead

Rejected. The cost in expressiveness and governance accuracy is not justified
by the implementation simplicity gain. Native adapters per provider remain
the correct approach.

---

# 4. Decision

LemmingsOS introduces a **Model Runtime** subsystem responsible for all
interactions between Lemming instances and LLM providers.

Lemmings never call providers directly. All inference requests flow through
the Model Runtime, which acts as the controlled boundary for:

- provider routing and abstraction
- prompt assembly from structured context
- model policy resolution
- response validation and structured output handling
- token usage capture
- retry and timeout enforcement
- audit event emission

The Model Runtime is a peer of the Tool Runtime in the execution architecture.
It is not a Tool. Tools are for external side effects. The Model Runtime is
the internal reasoning engine boundary.

## 4.1 Phase 1 Runtime Slice

This ADR defines the long-term Model Runtime boundary. The Phase 1 runtime slice adopts that boundary with a deliberately narrow provider scope:

- `ModelRuntime` is the only model execution entrypoint used by runtime orchestration
- prompt assembly happens inside `ModelRuntime`
- provider-specific HTTP logic lives behind a provider behaviour
- `Providers.Ollama` is the first provider implementation for Phase 1

Additional providers, richer streaming semantics, and broader output modes are extensions to this contract, not reasons to collapse model execution back into `LemmingInstances` or the web layer.

---

# 5. Provider Abstraction

The Model Runtime defines a **provider behaviour** that all provider adapters
must implement.

Conceptual behaviour contract:

```elixir
@callback complete(request :: ModelRequest.t(), opts :: keyword()) ::
  {:ok, ModelResponse.t()} | {:error, reason}

@callback stream(request :: ModelRequest.t(), pid :: pid(), opts :: keyword()) ::
  {:ok, stream_ref} | {:error, reason}

@callback health_check(config :: map()) ::
  :ok | {:error, reason}
```

Provider adapters are registered at startup and resolved by name.

Built-in adapters for v1 are organized by cost tier:

**Zero cost (default)**

- `ollama` — local inference via Ollama HTTP API. No API key required.
  Runs on any machine with sufficient RAM. Recommended models for agents:
  `llama3.2`, `qwen2.5-coder`, `mistral`, `phi4`.

**Free tier (cloud, no credit card required)**

- `gemini` — Google AI Studio free tier. Requires a Google account and an
  API key from Google AI Studio. Specific rate limits and daily quotas are
  set by Google and subject to change; consult the Google AI Studio
  documentation for current limits before relying on this tier for
  production workloads.

**OpenAI-compatible (paid, optional)**

- `openai` — OpenAI direct API and any provider that implements the OpenAI
  HTTP contract. This includes OpenRouter, which aggregates multiple providers
  and exposes some free-tier models under the same interface. Requires a
  configured API key and paid credits, except for OpenRouter's free-tier models.

**Paid cloud (optional, operator-configured)**

- `anthropic` — Anthropic Messages API. Requires an API key with billing
  configured. Intended for organizations that want access to more capable
  models and are willing to pay per token.

The adapter is selected from the resolved model policy at execution time.
Lemmings reference a logical model name, not a provider-specific model string.

Example logical model reference in Lemming configuration:

```
model: default
```

The Model Runtime resolves `default` to a concrete provider and model
identifier using the inherited model policy. Out of the box, `default`
resolves to Ollama.

---

# 6. Model Policy Inheritance

Each Lemming executes against an **effective model policy** resolved
hierarchically from:

```
World → City → Department → Lemming type → instance override
```

A model policy entry defines:

- provider adapter
- provider-specific model identifier
- temperature and sampling parameters
- max token budget for completion
- timeout
- retry policy

Example policy at World scope (out-of-the-box default, zero cost):

```
model_policy:
  default:
    provider: ollama
    model: llama3.2
    temperature: 0.7
    max_tokens: 4096
    timeout_ms: 60_000
    retries: 2
```

Example World-level policy using the Gemini free tier:

```
model_policy:
  default:
    provider: gemini
    model: gemini-1.5-flash
    temperature: 0.7
    max_tokens: 4096
    timeout_ms: 30_000
    retries: 2
```

Example override at Department scope for an organization using paid models:

```
# A company configures their Anthropic key at World scope via the Secret Bank.
# Individual Departments that need more capable models override the policy here.
# Departments without an override continue using the World default (free tier).

model_policy:
  default:
    provider: anthropic
    model: claude-sonnet-4-6
    max_tokens: 8192
```

This pattern means an operator can run most Departments on Ollama or Gemini
free tier while pointing a single high-stakes Department at a paid model.
The cost difference remains visible in cost governance without any Lemming
code change.

Resolution follows nearest-scope precedence. The instance executes against
a resolved snapshot of this policy, consistent with how tool policy and cost
budgets are resolved throughout the system.

---

# 7. Prompt Assembly

The Model Runtime assembles the inference request from the Lemming's
structured working context defined in ADR-0008.

Prompt assembly is the exclusive responsibility of the Model Runtime.
Lemming implementations do not construct raw prompt strings.

The assembly pipeline maps structured context fields to a provider-compatible
message sequence:

```
Working context
  system_prompt       → system message
  task_goal           → injected into first user turn
  instructions        → injected into system or user message
  constraints         → injected as system guidance
  recent_messages     → prior conversation turns
  working_summary     → condensed context if compaction has occurred
  tool_results        → tool result turns as required by provider format
  last_output         → assistant turn for continuation if applicable
```

The output of assembly is a `ModelRequest` struct:

```elixir
%ModelRequest{
  provider: :anthropic,
  model: "claude-sonnet-4-6",
  messages: [...],
  system: "...",
  max_tokens: 8192,
  temperature: 0.7,
  response_format: :text | :json,
  tools: [...],
  metadata: %{
    world_id: ...,
    city_id: ...,
    department_id: ...,
    lemming_id: ...,
    correlation_id: ...
  }
}
```

The `metadata` field carries hierarchy context used for cost governance
and audit event emission. It is never sent to the provider.

---

# 8. Response Model

The Model Runtime returns a `ModelResponse` struct to the Lemming:

```elixir
%ModelResponse{
  content: "...",
  role: :assistant,
  stop_reason: :end_turn | :max_tokens | :tool_use | :stop_sequence,
  usage: %{
    input_tokens: integer(),
    output_tokens: integer(),
    cache_read_input_tokens: integer() | nil,
    cache_write_input_tokens: integer() | nil
  },
  model: "...",
  provider: :anthropic,
  latency_ms: integer()
}
```

The `usage` field is always populated. The Model Runtime forwards usage
data to the cost governance subsystem immediately after receiving the
provider response, before returning to the Lemming.

Lemmings receive only the `ModelResponse`. They never receive raw provider
HTTP responses.

---

# 9. Structured Output

Some Lemmings require machine-readable responses rather than free-form text.

The Model Runtime supports two structured output modes.

**JSON mode**

The provider is instructed to return valid JSON. The Model Runtime validates
that the response parses as JSON before returning it to the Lemming. If
validation fails, the response is treated as a provider error.

```elixir
%ModelRequest{response_format: :json, ...}
```

**Schema-validated JSON**

The Lemming type may declare an expected output schema. The Model Runtime
validates the parsed JSON against the schema. If validation fails, the
runtime may retry or return a structured error.

```elixir
%ModelRequest{response_format: {:json_schema, schema}, ...}
```

v1 supports both modes where the provider natively allows it. For providers
that do not support JSON mode, the runtime injects a system instruction
requesting JSON output and applies best-effort parsing.

---

# 10. Streaming

Streaming is **supported but opt-in** in v1.

The Lemming execution model (ADR-0004) treats model calls as asynchronous
events. Streaming is compatible with this model: the Lemming transitions to
a `waiting_model` state and receives either a completion event or incremental
stream events depending on the configured mode.

Streaming mode:

```
Lemming
   ↓ request with stream: true
Model Runtime
   ↓
Provider adapter (streaming)
   ↓
Incremental token events → Lemming process mailbox
   ↓
Completion event with full usage stats → Lemming
```

Non-streaming mode (default):

```
Lemming
   ↓ request
Model Runtime
   ↓
Provider adapter (blocking request)
   ↓
ModelResponse → Lemming
```

Token usage is always reported on the completion event, regardless of mode.

---

# 11. Retry and Timeout Policy

The Model Runtime enforces a **retry policy** derived from the effective
model policy.

Default retry behavior:

```
retries: 2
retry_backoff: exponential
initial_backoff_ms: 500
timeout_ms: 30_000
```

Retryable conditions:

- network timeout
- provider 429 (rate limit)
- provider 500 / 503 (transient server error)

Non-retryable conditions:

- provider 400 (invalid request — retrying without input change will not help)
- provider 401 / 403 (authentication failure)
- response validation failure (structured output did not match schema)
- max token budget exceeded

If all retries are exhausted, the Model Runtime returns a structured error
to the Lemming. The Lemming transitions to a failure or retry-backoff state
as defined in ADR-0004.

---

# 12. Cost Governance Integration

After every provider response, the Model Runtime emits a usage event to the
cost governance subsystem defined in ADR-0015.

The event includes:

- provider
- model identifier
- input token count
- output token count
- estimated cost in USD
- hierarchy scope: world, city, department, lemming instance
- correlation identifier

**Cost estimation by provider tier:**

Local providers such as Ollama report token counts but carry zero monetary
cost. The cost governance subsystem still records token volume — this matters
for context budget enforcement and operational observability even when there
is no financial cost.

Free-tier cloud providers report token counts. Monetary cost is zero within
free-tier limits. The runtime records usage for observability and future
policy decisions, but does not trigger monetary budget enforcement until the
operator configures explicit limits.

Paid providers report token counts and have a known per-token price. The
runtime computes estimated cost and enforces monetary budgets as defined
in ADR-0015.

Conceptual execution flow:

```
Lemming
   ↓
Model Runtime
   ↓
Model policy resolution
   ↓
Budget evaluation (cost governance check)
   ↓
Prompt assembly
   ↓
Provider call
   ↓
Usage captured → cost governance updated
   ↓
Audit event emitted
   ↓
ModelResponse returned to Lemming
```

If budget is exhausted at the evaluation step, the Model Runtime rejects
the request before any provider call is made. The Lemming receives
`{:error, :budget_exhausted}`.

For zero-cost providers this check is a no-op unless the operator has
configured explicit token quotas.

---

# 13. Audit Events

The Model Runtime emits a minimal, stable set of events covering every significant
lifecycle transition. These events are the authoritative contract between the Model
Runtime and the rest of the platform — cost governance (ADR-0015), audit
(ADR-0018), and the Lemming execution model (ADR-0004) all depend on them.

**Telemetry events** (observability, operational monitoring):

- `model.request_started` — inference request assembled and dispatched to the
  provider adapter; payload includes provider, model, token budget, correlation_id
- `model.response_received` — provider returned a successful response; payload
  includes stop_reason, latency_ms, correlation_id
- `model.retry` — a retryable provider error triggered a retry attempt; payload
  includes attempt number, error code, backoff_ms
- `model.request_failed` — all retry attempts exhausted; payload includes final
  error code and total attempt count

**Audit events** (governance, accountability):

- `model.budget_denied` — request blocked before dispatch because the effective
  cost budget (ADR-0015) was exhausted; audit family, requires actor/scope fields
- `model.structured_output_invalid` — provider response failed schema validation
  after retries; payload includes schema name and validation error summary

**Cost event** (emitted to cost governance subsystem, also stored as telemetry):

- `model.usage` — emitted immediately after every successful response, before
  returning to the Lemming; payload includes provider, model, input_tokens,
  output_tokens, cache_read_tokens, cache_write_tokens, cost_usd_estimate;
  this event is the sole input for token accounting in ADR-0015

The distinction between `model.response_received` and `model.usage` is intentional:
`model.response_received` is the general lifecycle signal; `model.usage` is the
cost-governance-specific event with the full token breakdown. Separating them keeps
the cost governance subsystem decoupled from the broader response lifecycle.

Each event carries the full hierarchy scope (`world_id`, `city_id`, `department_id`,
`lemming_id`) and `correlation_id`, consistent with the canonical envelope defined
in ADR-0018.

Secret material (API keys, credentials) must never appear in event payloads.
Provider credentials are resolved through the Secret Bank (ADR-0009) and
injected only into the adapter at execution time.

---

# 14. Runtime Architecture

## Internal subsystem view

Each inference request passes through five internal components of the Model Runtime
before reaching the provider and after receiving the response:

```
Lemming
   │
   ▼
Model Runtime
   │
   ├─ PromptAssembler        reads working context (ADR-0008), builds ModelRequest
   ├─ ProviderRouter         resolves model policy, selects provider adapter
   ├─ RetryEngine            enforces retry/backoff policy on transient failures
   ├─ StructuredOutputValidator  validates JSON schema on structured responses
   └─ UsageTracker           captures token counts, emits model.usage event (ADR-0015)
   │
   ▼
Provider Adapter
   │
   ▼
Model Provider (Ollama / Gemini / OpenAI-compatible / Anthropic)
```

Each component has a single responsibility. A Lemming that calls the Model Runtime
is unaware of which component handles any given concern — the interface is always
`ModelRequest → ModelResponse`.

## Position in the full runtime

The Model Runtime is a peer of the Tool Runtime. Both are subordinate to the Lemming
execution layer and report to the same governance infrastructure:

```
                 ┌──────────────────┐
                 │     Lemming      │
                 └────────┬─────────┘
                          │
           ┌──────────────┴──────────────┐
           │                             │
           ▼                             ▼
   ┌───────────────┐             ┌───────────────┐
   │ Model Runtime │             │  Tool Runtime │
   └───────┬───────┘             └───────┬───────┘
           │                             │
           ▼                             ▼
   model providers                external world
```

Neither runtime calls the other. The Lemming is the only component that interacts
with both — it sends a `ModelRequest`, receives a `ModelResponse`, interprets any
tool-use decision, and dispatches it to the Tool Runtime as a separate call.

Both runtimes feed the same cross-cutting infrastructure in parallel:

```
Model Runtime ──► Cost Governance  (model.usage)
Model Runtime ──► Audit Log        (model.* events)
Tool Runtime  ──► Audit Log        (tool.* events)
Tool Runtime  ──► Cost Governance  (tool cost events)
```

## OTP supervision tree

The Model Runtime is a supervised process tree within each City.

```
City Supervisor
   └─ Model Runtime Supervisor
         ├─ Provider Registry
         ├─ Prompt Assembler
         └─ Provider Adapters (per configured provider)
               ├─ Ollama Adapter             (zero cost, always available)
               ├─ Gemini Adapter             (free tier, Google AI Studio key)
               ├─ OpenAI-compatible Adapter  (OpenAI direct, OpenRouter, etc.)
               └─ Anthropic Adapter          (paid, optional)
```

Provider adapters may maintain connection pools or persistent HTTP clients.
This is an internal adapter concern and does not affect the Lemming-facing
contract.

The Model Runtime is City-scoped, consistent with the City execution model
defined in ADR-0017. Lemming instances interact with the Model Runtime of
their own City and never cross City boundaries for inference.

---

# 15. Consequences

## Positive

- **Provider independence is guaranteed at the contract level.** A Lemming
  definition never references a provider or model string. Operators switch
  providers through configuration alone, with no code changes required.

- **Accessibility goal is met structurally.** The default World policy points
  to Ollama. A fresh installation runs with zero API keys, zero cost, and zero
  cloud dependencies. Upgrading to a paid provider is a single configuration
  change at World scope.

- **Cost governance has a reliable integration point.** Every token consumed
  flows through the Model Runtime. ADR-0015 enforcement is consistent and
  complete — there is no path for a Lemming to bypass token accounting.

- **Prompt assembly is centralized.** Divergent prompt construction across
  Lemming types is structurally prevented. Context field semantics are defined
  once, translated once, and tested once.

- **The governance model is consistent across the runtime.** Model calls
  follow the same audit, credential isolation, and City-scoping patterns
  as tool execution. Contributors working on one subsystem can reason about
  the other by analogy.

## Negative / Trade-offs

- **A new supervised subsystem adds operational surface area.** The Model
  Runtime Supervisor, Provider Registry, and individual adapters all need
  to be started, monitored, and maintained. A bug in the prompt assembler
  affects every Lemming in the City.

- **The abstraction layer adds a debugging indirection.** When a provider
  returns an unexpected response, the failure is observed at the
  `ModelResponse` level, not at the raw HTTP level. Adapter-level
  introspection requires understanding the assembly pipeline.

- **Provider-specific features require explicit adapter work.** Features
  that do not map to the shared `ModelRequest` / `ModelResponse` contract
  (Anthropic cache control, Gemini grounding, OpenAI reasoning effort)
  require deliberate adapter implementation. The abstraction does not expose
  them automatically.

- **Free-tier limits are external and not enforced by the runtime.** Gemini
  and OpenRouter free-tier quotas are enforced by the provider, not by
  LemmingsOS. Operators hitting free-tier limits will see 429 errors handled
  by the retry policy, not a clean `budget_exhausted` signal. Explicit token
  quotas must be configured manually to get early warnings.

## Mitigations

- Adapter failures are isolated by the supervision tree. A crashed Anthropic
  adapter does not affect the Ollama adapter serving other Departments.
- The `health_check` callback allows the Provider Registry to surface
  unhealthy adapters in the control plane before they affect Lemming execution.
- Provider-specific features can be exposed through the `metadata` field of
  `ModelRequest` as an escape hatch, allowing adapter extensions without
  breaking the shared contract.

---

# 16. Non-Goals

The following capabilities are explicitly out of scope for v1:

- fine-tuning or model training integration
- embedding generation (deferred to a dedicated ADR when RAG is introduced)
- multi-modal inputs (images, audio, documents)
- model performance benchmarking
- automatic provider failover
- prompt caching (provider-specific optimization, deferred to future adapter work)
- A/B testing between model configurations

---

# 17. Future Extensions

Potential future improvements include:

- embedding provider abstraction for retrieval-augmented workflows
- automatic provider failover when primary is unavailable
- prompt caching support for providers that expose it
- multi-modal input support
- per-Lemming type prompt templates registered in the control plane
- model performance metrics and latency tracking in the observability dashboard

These extensions can build on the provider abstraction and policy inheritance
model defined in this ADR without changing the core execution contract.

---

# 18. Rationale

LemmingsOS already treats Tools as the controlled boundary for all external
side effects. Model inference is not a side effect in the same sense — it is
the primary reasoning engine for every Lemming. However, it shares the same
governance requirements: it generates cost, requires credential management,
must be auditable, and must operate under hierarchical policy.

A dedicated Model Runtime keeps these concerns centralized and makes the
provider abstraction a first-class contract rather than an implementation
detail buried in individual Lemmings.

The provider tier design follows directly from the accessibility principle.
The abstraction layer means a developer with no API keys runs Ollama locally
at zero cost. The same installation, with a single configuration change,
upgrades to a free-tier cloud provider or a paid API as the team and
requirements grow. No Lemming code changes. No architecture changes.
Only configuration.

This is the correct separation of concerns: Lemming definitions describe
*what* an agent does; model policy describes *with what capability and at
what cost* it reasons. Those are operationally independent decisions and
should be independently configurable.
