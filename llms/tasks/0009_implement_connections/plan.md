# Connection Model Product Plan

## 0. Planning Metadata

- Task Directory: `llms/tasks/0009_implement_connections/`
- Status: `PLANNING`
- Planning Agent: `po-analyst`
- Source Issue: <https://github.com/mberrueta/lemmings-os/issues/28>
- Product Contract: This file
- Follow-up Owner: Architecture / implementation planning

### Agent Roles

- `po-analyst`: product contract validation against codebase reality.
- `tl-architect`: implementation task breakdown after this product contract is approved.
- `dev-db-performance-architect`: database shape, indexes, constraints, and migration safety.
- `dev-backend-elixir-engineer`: schema, context, hierarchy resolution, runtime facade, mock provider, and safe event behavior.
- `dev-frontend-ui-engineer`: basic operator UI/read-model support.
- `qa-test-scenarios`: acceptance and regression scenario design.
- `qa-elixir-test-author`: ExUnit and LiveView/read-model test implementation.
- `dev-logging-daily-guardian`: telemetry/audit/runtime event consistency and safe metadata review.
- `audit-security`: secret-reference and raw-secret leak-prevention review.
- `audit-accessibility`: UI accessibility review where UI is implemented.
- `docs-feature-documentation-author`: implementation-aligned feature documentation.
- `rm-release-manager`: migration notes, release notes, and final validation coordination.
- `audit-pr-elixir`: final PR review.

## 1. Goal

Introduce Connections as reusable external-service configurations that Tools can reference by logical slug.

A Connection represents safe, reusable client configuration for an external service endpoint, provider, credential set, bucket, dataset, model provider, or similar integration boundary. Connections are not secrets. They store safe config plus `secret_refs` that point to Secret Bank-compatible env-style references supported by the implemented Secret Bank API.

The first slice proves the shared model with a deterministic mock provider, safe hierarchy-aware resolution, basic local-admin UI/read-model visibility, test status persistence, and safe observability. It must not implement real production integrations.

## 2. Product Intent

External integrations should not each invent their own config format, secret-reference rules, validation behavior, runtime preparation, or observability vocabulary.

Connections provide a common boundary so future Tools can request a configured external integration by logical identifier. Runtime-facing code resolves only the visible Connection identity and safe configuration descriptor. Provider Caller modules resolve any required secrets internally just-in-time inside trusted execution and return only sanitized results.

Example future Tool call shape:

```text
email.create_draft(connection_ref: "smtp_sales", ...)
```

The Lemming and model-facing context know only the logical `connection_ref`. They must never receive resolved credentials.

## 3. Scope

### In scope

- Connection schema/model scoped to World, City, or Department.
- Basic backend context/API functions for create, update, delete, enable, disable, invalid status handling, listing, resolving, validating, and testing.
- Safe separation between non-secret `config` and Secret Bank-backed `secret_refs`.
- Hierarchy-aware connection lookup by slug.
- Connection runtime-facing facade that returns a safe runtime descriptor without resolving secrets.
- Mock provider Caller boundary that resolves `secret_refs` internally just-in-time and returns sanitized test results.
- Mock provider for deterministic validation and test behavior.
- Connection test result persistence through safe status/result fields.
- Telemetry/audit/runtime events through the existing project event mechanism.
- Basic local-admin UI/read-model support, likely at `/connections`, for CRUD/status/test/scope inspection if that fits the existing UI structure.
- Architecture and feature documentation updates.

### Out of scope

- Lemming-owned Connections.
- SMTP, Gmail, OpenRouter, MinIO/S3, RAGFlow/AnythingLLM, Telegram/WhatsApp/Discord, GitHub, Gotenberg, OAuth, or any other real production provider integration.
- Migrating the current Ollama API call.
- Connection marketplace or provider marketplace.
- Secret storage, encryption, rotation, or raw secret management.
- Full provider-specific adapters.
- Broad Tool Runtime refactor.
- New authentication, authorization, RBAC, approval workflow, or multi-user policy layer.

## 4. User and Operator Experience

The first user is the current local admin operating the self-hosted control plane.

The local admin can:

- create and edit Connections at World, City, or Department scope;
- enable, disable, or inspect invalid Connections;
- delete local Connections;
- test a Connection and see the latest safe test status;
- inspect visible Connections by scope;
- see slug, name, type, provider, status, safe config, last test status, and last tested timestamp;
- see `secret_refs` only as references or redacted metadata, never as raw secret values;
- inspect recent connection-related events where existing event surfaces support this.

The local admin cannot:

- view, copy, export, or preview resolved secret values through Connections;
- use a child scope to inspect sibling-only Connections;
- resolve a Connection across World boundaries;
- configure real provider-specific behavior beyond the mock provider in this slice.

Inherited Connections must show their source scope in the UI/read model.

Example:

- A Connection that references `$GITHUB_TOKEN` and is inherited from City is visible in Department scope as inherited.
- The Department cannot delete the inherited City Connection from the Department page.
- Creating a Department Connection with the same slug overrides the inherited one for that Department.
- Deleting the Department override reveals the inherited parent Connection again.

## 5. Connection Model

A Connection belongs to exactly one World and optionally one City and one Department.

Supported first-slice scopes:

- World scope: available to the World and descendants.
- City scope: available to that City and descendant Departments.
- Department scope: available only to that Department.

Lemming scope is intentionally not included in this slice.

Scope invariants:

- World-scoped Connection: `world_id` set, `city_id` null, `department_id` null.
- City-scoped Connection: `world_id` and `city_id` set, `department_id` null.
- Department-scoped Connection: `world_id`, `city_id`, and `department_id` set.
- A Department-scoped Connection must belong to the same City and World as its Department.
- A City-scoped Connection must belong to the same World as its City.

Required product fields:

- `id`
- `world_id`
- `city_id` nullable
- `department_id` nullable
- `slug`
- `name`
- `type`
- `provider`
- `status`
- `config`
- `secret_refs`
- `metadata`
- `last_tested_at`
- `last_test_status`
- `last_test_error`
- `inserted_at`
- `updated_at`

Status values:

- `enabled`
- `disabled`
- `invalid`

Initial type/provider support must include `mock` / `mock`. Other type/provider values may be structurally allowed only if they do not imply a real provider implementation in this issue.

`config` stores safe provider configuration. `secret_refs` stores Secret Bank-compatible env-style references, for example `$GITHUB_TOKEN`, `$OPENAI_API_KEY`, or another current project-supported `$ENV_VAR` reference.

Connections may have empty `secret_refs` when the provider/configuration does not require credentials.

## 6. Runtime Lookup and Caller Boundary

Connections resolve by requested caller scope plus slug.

Resolution rule:

```text
nearest visible scope wins
```

Examples:

- A Department request first checks that Department, then its City, then its World.
- A City request first checks that City, then its World.
- A World request checks only its World.
- A sibling Department cannot see or use another Department's Connection.
- A different World can never see or use the Connection.

The Connection runtime-facing facade resolves only Connection identity, visibility, status, and safe config metadata.

It is responsible for:

- resolving a logical connection slug within the caller's hierarchy;
- rejecting disabled or inaccessible Connections;
- loading safe config;
- returning a safe runtime descriptor;
- recording safe observability metadata.

It must not resolve Secret Bank refs and must not return raw secret values.

Provider Caller modules are responsible for:

- accepting the safe runtime descriptor plus operation arguments;
- resolving `secret_refs` just-in-time inside trusted execution;
- performing the provider action or deterministic mock behavior;
- returning sanitized results only;
- recording safe observability metadata.

Raw secrets may exist only inside the provider Caller boundary during trusted execution. They must never be returned to runtime facades, persisted, logged, exposed to Lemmings, sent to model prompts, stored in snapshots, broadcast in PubSub, returned to UI, included in event payloads, or included in exception messages.

## 7. Mock Provider Behavior

The mock provider exists to validate the Connection model without implementing a real external service.

Required deterministic behavior:

- `type: "mock"` and `provider: "mock"` are the only provider combination that must execute provider-specific validation/test behavior in this slice.
- Valid mock config includes required safe fields sufficient to prove validation, such as a base URL and mode.
- A supported mode such as `echo` succeeds when config is valid and all required `secret_refs` resolve inside the mock provider Caller.
- Invalid config marks validation/test as failed and safely records an error reason.
- Missing or unresolvable secret refs fail deterministically inside the Caller and do not return partial credentials.
- Disabled or invalid Connections cannot be used by the runtime-facing facade or provider Caller.

Mock provider tests must prove both success and failure without any real network call.

## 8. Observability and Safety

Connection lifecycle, resolution, and test behavior must be observable without exposing credentials.

Emit telemetry/audit/runtime events through the existing project event mechanism; persist them only if the current event infrastructure supports durable persistence.

Expected event vocabulary includes:

- `connection.created`
- `connection.updated`
- `connection.deleted`
- `connection.enabled`
- `connection.disabled`
- `connection.marked_invalid`
- `connection.resolve.started`
- `connection.resolve.succeeded`
- `connection.resolve.failed`
- `connection.test.started`
- `connection.test.succeeded`
- `connection.test.failed`

Events should include safe metadata such as:

- `world_id`
- `city_id`
- `department_id`
- `connection_id`
- `connection_slug`
- `connection_type`
- `provider`
- `status`
- safe failure reason

Events must not include:

- raw secret values
- resolved credentials
- API keys
- passwords
- bearer tokens
- derived secret previews or hashes

## 9. Acceptance Criteria

- A `Connection` schema/model exists.
- Connections are scoped to World, City, or Department.
- Connections support `slug`, `name`, `type`, `provider`, `status`, `config`, `secret_refs`, `metadata`, and safe test-result fields.
- Status values include `enabled`, `disabled`, and `invalid`.
- Connection lookup enforces hierarchy visibility and nearest-wins slug resolution.
- Cross-World and sibling Department resolution fail safely.
- Connection runtime-facing facade exists and produces only a safe runtime descriptor.
- Runtime-facing facades do not resolve Secret Bank refs.
- Secret refs are resolved only by provider Caller modules through the implemented Secret Bank boundary, inside trusted execution.
- Provider Caller modules return only sanitized results and never return raw secret values.
- Raw secret values are never persisted or exposed to Lemmings, UI, events, logs, snapshots, or prompts.
- A mock connection provider exists for deterministic success and failure tests.
- Connection test status is recorded safely.
- Connection lifecycle, resolution, and test operations emit safe observable events through the existing project mechanism.
- Basic local-admin UI/read-model support exists for CRUD/status/test/scope inspection when this fits the existing UI structure.
- Relevant architecture/docs are updated.
- No real provider integration is implemented.
- The issue is not used as a broad Tool Runtime refactor.

## 10. Test Plan

- Schema/context tests for required fields, safe config vs `secret_refs`, scope shape, slug uniqueness per exact scope, status values, and nearest-wins lookup.
- Hierarchy tests proving World Connections are visible to descendants, Department Connections are not visible to siblings, and cross-World resolution fails.
- Runtime facade tests proving it resolves only safe Connection identity/visibility and does not call Secret Bank.
- Provider Caller tests proving Secret Bank refs are resolved only inside trusted Caller execution and raw values do not appear in returned results, events, UI read models, errors, logs, snapshots, or Lemming-facing payloads.
- Mock provider tests for deterministic success, invalid config failure, missing secret failure, disabled Connection behavior, and safe `last_test_*` updates.
- Observability tests for lifecycle/resolve/test events with hierarchy/provider/status metadata and no secret leakage.
- LiveView/read-model tests for CRUD/status/test/scope inspection, safe config display, redacted secret refs, and stable DOM selectors where UI is implemented.
- Final validation should run narrow relevant checks first, then `mix precommit`.

## 11. Planning Assumptions

- Secret Bank is implemented and available through its existing public runtime API.
- The first Connection MVP does not support Lemming-owned Connections.
- `secret_refs` use Secret Bank-compatible env-style references supported by the current project implementation.
- The local-admin control-plane model remains unchanged; no new authentication/RBAC is added.
- The UI is basic operator visibility, not a polished final settings product.
- Real provider integrations are follow-up work.
- A `tl-architect` implementation task breakdown should be created only after this Product/BA contract is accepted.
