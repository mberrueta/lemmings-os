# Task 05: Connection Runtime Facade Without Secret Resolution

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, `llms/tasks/0009_implement_connections/plan.md`, and Tasks 01-04, then implement the narrow Connection runtime-facing facade without resolving secrets.

## Objective
Add a narrow runtime-facing facade that resolves a logical Connection slug to a safe runtime descriptor for trusted execution.

This facade must not resolve Secret Bank refs and must not return raw secret values. Secret resolution is owned by provider-specific Caller modules in the execution boundary.

Runtime resolves identity and policy. Caller modules resolve credentials and perform execution. UI, read models, and events receive only sanitized metadata.

## Expected Outputs
- Runtime-facing module under the Connections boundary.
- API that accepts caller scope plus slug and returns a safe runtime descriptor.
- Safe resolution events for started, succeeded, and failed outcomes.
- Safe error taxonomy for missing, inaccessible, disabled, and invalid cases.
- No Secret Bank calls in this facade.
- No runtime facade return struct or map containing raw secrets.

## Runtime Boundary Safety

- Do not introduce any runtime facade return value that contains resolved secret values.
- Do not derive or implement any encoder that could serialize credentials from runtime facade results.
- Ensure `Inspect` output for runtime facade return values contains only safe Connection metadata.
- Do not include secret values in exception messages or changeset errors.

## Acceptance Criteria
- Runtime facade lookup uses the hierarchy lookup from Task 04.
- Disabled and invalid Connections are not usable through the runtime-facing facade.
- Runtime facade does not call `LemmingsOs.SecretBank.resolve_runtime_secret/2` or `/3`.
- Runtime facade does not return any struct or map containing raw secret values.
- Runtime facade results are safe for `IO.inspect/1`, Logger formatting, test failure output, and debug output.
- Exception messages and changeset errors never include secret values.
- Cross-World and sibling Department attempts fail safely.
- No Tool Runtime call path is changed except where strictly needed to compile isolated Connection runtime code.

## Review Notes
Reject if this task resolves Secret Bank refs, returns raw credentials, wires Connections into real tools, changes prompt payloads, persists credentials, or broadens into a Tool Runtime refactor.
