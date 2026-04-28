# Secret Bank Product Plan

## 0. Execution Task Breakdown

### Execution Metadata

- Task Directory: `llms/tasks/0008_implement_secret_bank/`
- Status: `PLANNING`
- Planning Agent: `tl-architect`
- Product Contract: This file, sections 1-15
- Implementation Style: sequential, reviewable chunks with human approval after each task

### Agent Roles

- `dev-db-performance-architect`: database shape, indexes, constraints, migration safety.
- `dev-backend-elixir-engineer`: schemas, contexts, encryption boundaries, runtime integration, durable backend behavior.
- `dev-frontend-ui-engineer`: Phoenix LiveView surfaces and operator workflows.
- `qa-test-scenarios`: acceptance and regression scenario design.
- `qa-elixir-test-author`: ExUnit and LiveView test implementation.
- `dev-logging-daily-guardian`: durable safe audit/logging review and event consistency.
- `audit-security`: secret handling and leak-prevention review.
- `audit-accessibility`: UI accessibility review for Secret Bank surfaces.
- `docs-feature-documentation-author`: implementation-aligned feature documentation.
- `rm-release-manager`: release notes, migration/runbook, rollback notes.
- `audit-pr-elixir`: final PR review.

### Sequential Tasks

1. `01_secret_bank_data_model.md` - database tables, indexes, and constraints for Cloak-backed encrypted secret values and durable audit events.
2. `02_secret_bank_context_and_crypto.md` - Cloak dependency/Vault setup, encrypted Ecto type, schemas, changesets, config-file env allowlist support, safe metadata read models, and admin create/replace/delete APIs.
3. `03_secret_resolution_and_runtime_api.md` - convention-based `$secrets.*` parsing, hierarchical resolution, env fallback, trusted runtime API, and safe error taxonomy.
4. `04_runtime_tool_integration.md` - wire convention-based Secret Bank resolution into tool execution without exposing raw values to Lemmings, prompts, snapshots, or runtime events.
5. `05_durable_audit_events.md` - generic durable event recording used by Secret Bank plus recent activity query support for admin UI.
6. `06_operator_secret_surfaces.md` - World, City, Department, and Lemming Secret surfaces with write-only create/replace/delete workflows.
7. `07_env_allowlist_and_policy_ui.md` - read-only operator visibility into convention-based env fallback behavior.
8. `08_test_scenarios_and_safety_matrix.md` - scenario plan covering hierarchy, write-only behavior, runtime access, auditability, and leak prevention.
9. `09_test_implementation.md` - backend, runtime, LiveView, and regression tests for the implemented behavior.
10. `10_security_and_logging_audit.md` - security review plus logging/audit review focused on secret leakage and durable event quality.
11. `11_accessibility_ui_audit.md` - accessibility review and fixes for the new Secret Bank surfaces.
12. `12_feature_documentation.md` - developer/operator documentation based on actual implemented code.
13. `13_release_and_final_review.md` - release runbook, migration notes, final validation, and PR audit.

### Human Approval Gates

Each task must be reviewed and approved before the next task starts. The only exception is Task 8, which may be drafted before UI completion but must be reconciled with actual implementation before Task 9 begins.

### Planning Assumptions

- The product contract in this file is the source of truth unless a later ADR or human decision supersedes it.
- Secret values will be encrypted at rest with Cloak/Cloak.Ecto using environment-provided key material; no cryptographic secret may be hardcoded. This is an explicit exception to the usual "do not add dependencies" default because the human approved Cloak for this security-sensitive slice.
- Env fallback allowlist mappings are not stored in the database. They are configured in application config/runtime config as a list of allowed Secret Bank keys, optionally paired with an explicit environment variable name.
- Tool secret bindings are not stored in the database. Tools reference secrets by convention with `$secrets.<provider>.<name>`, which normalizes to the Secret Bank key `<provider>.<name>` and env fallback name `<PROVIDER>_<NAME>`.
- Durable events may reuse an existing canonical event store if ADR-0018 has already been implemented; otherwise Task 1 must include a minimal generic durable event store that Secret Bank uses first and future features can reuse.
- Existing detail LiveViews should be extended in place instead of introducing separate resource pages unless code discovery shows a clearer local pattern.
- No RBAC/authentication is added in this slice; the UI remains local-admin oriented.
- All executable logic changes require ExUnit coverage and final `mix precommit`.

## 1. Goal

Define the product behavior for the first Secret Bank MVP in LemmingsOS.

This plan describes what the local admin should be able to do, how secrets behave across the current hierarchy, what the UI should show, how runtime services access secrets safely, and what must be observable through durable safe audit events.

This is a product/BA plan, not a low-level implementation design. Technical decisions such as schema shape, encryption module APIs, LiveView component structure, and exact context module names belong to the architecture/implementation handoff, but the implementation must preserve the product guarantees in this plan.

---

## 2. Product Intent

LemmingsOS needs a safe way to configure credentials used by runtime services and tools without exposing raw secret values to Lemmings, LLMs, logs, traces, checkpoints, runtime snapshots, or operators after creation.

The first MVP is designed for the current local self-hosted app state: no app-level authentication, no users, and no RBAC yet. The primary operator is the local admin running the system in a trusted/private environment.

This is an implementation sequencing decision, not a replacement for ADR-0010 or ADR-0011. Future control-plane authentication and authorization must be able to wrap this feature without changing the Secret Bank runtime semantics.

The Secret Bank must allow the local admin to configure Secret Bank keys at hierarchy scopes and allow trusted runtime/tool execution to resolve secret values using hierarchical override rules.

---

## 3. MVP Assumptions

### In scope for this slice

- Local self-hosted deployment.
- Single implicit local admin.
- Current unauthenticated control plane, assuming trusted/private network access.
- Explicit environment-variable allowlist as the top-level fallback source.
- Encrypted persisted secrets at World, City, Department, and Lemming scope.
- Write-only secret values after submission.
- Tool configs may reference secrets by convention with `$secrets.<provider>.<name>`.
- Trusted runtime/tool execution may resolve raw values internally from convention-based Secret Bank keys.
- Lemmings and LLMs never receive raw secret values.
- Durable safe audit events for administrative secret changes and runtime secret access.

### Out of scope for this slice

- New `Lemming Type` or template entity.
- Multi-user access control.
- Login/session management.
- Per-user secret permissions.
- Approval workflows for secret access.
- External secret managers such as Vault, Infisical, AWS Secrets Manager, etc.
- Secret rotation automation.
- Full connection object UI.
- Showing, copying, exporting, previewing, hashing, or partially revealing secret values.

---

## 4. User

The only user for this MVP is the local admin.

The local admin can:

- configure env fallback mappings through application config;
- create Secret Bank keys at World, City, Department, and Lemming scope;
- replace local secret values;
- delete local secrets;
- see which effective secret applies at a scope;
- see where that effective secret comes from;
- monitor durable safe secret activity without exposing values.

The admin cannot:

- read a previously saved secret value;
- copy a secret value;
- export a secret value;
- see masked previews such as first/last characters;
- see hashes derived from a secret value;
- delete inherited secrets from child scopes;
- use the Secret Bank as a user-authentication credential store.

---

## 5. Key and Tool Reference Model

The Secret Bank stores convention-based Bank keys. Tools reference secrets with `$secrets.<provider>.<name>` placeholders in tool configuration.

Runtime normalization:

```text
Tool config reference: $secrets.github.token
Secret Bank key:       github.token
Env fallback name:     GITHUB_TOKEN
```

The Secret Bank resolves the normalized Bank key for the relevant runtime scope. The raw value is injected only inside the trusted Tool Runtime path.

Tools and Lemmings must not receive arbitrary Bank key inventory. Tool execution may only resolve secret references present in the tool configuration being executed.

The process environment is never treated as an open keyspace. Env fallback is allowed only for configured Secret Bank keys. If a configured key has no explicit env var override, the env var name is derived by convention from the normalized key.

Example config shape:

```elixir
config :lemmings_os, :secret_bank,
  env_fallbacks: [
    "github.token",
    {"openrouter.default", "OPENROUTER_API_KEY"}
  ]
```

This allows `github.token` to read `GITHUB_TOKEN` by convention and `openrouter.default` to read `OPENROUTER_API_KEY` by explicit override.

---

## 6. Hierarchy and Resolution Model

Secrets resolve through hierarchical override semantics.

Resolution order from least specific to most specific:

```text
env allowlist -> world -> city -> department -> lemming
```

Runtime lookup order from most specific to least specific:

```text
lemming -> department -> city -> world -> env allowlist
```

Effective value rule:

```text
The most specific configured value for a Secret Bank key wins.
```

For example:

```text
env allowlist:
  openrouter.default = configured from OPENROUTER_API_KEY

world_main:
  openrouter.default = configured

city_a:
  openrouter.default = configured

this_department:
  no local value
```

At `this_department`, the effective secret is inherited from `city_a`.

If `this_department` creates a local secret with the same Secret Bank key, the Department value becomes effective and the City value is hidden from the effective view.

If the Department value is deleted, the City value becomes effective again.

---

## 7. Secret Scope Levels

### 7.1 Env Allowlist

`env allowlist` is the top-level fallback source.

Allowlisted env secrets are configured as safe metadata that maps a Secret Bank key to an environment variable name. They are shown in the UI as inherited source `(env)` when they are the effective value for a scope.

Env values are not created, replaced, deleted, displayed, copied, exported, or previewed from World/City/Department/Lemming secret surfaces.

Expected display:

```text
openrouter.default  (env)  [configured]
```

### 7.2 World

World secrets are configured from the existing World detail experience, exposed as a `Secrets` surface/tab alongside current World sections.

A World secret overrides the env allowlist source for the same Secret Bank key.

Expected display on the World page:

```text
openrouter.default  (this_world)  [configured]
```

If the World has no local value but env has one:

```text
openrouter.default  (env)  [configured]
```

### 7.3 City

City secrets are configured from the existing City detail experience. The implementation should add a `Secrets` surface that fits the current City UI rather than assuming a separate resource page shape.

A City secret overrides World and env values for the same Secret Bank key.

Expected display on a City detail surface:

```text
openrouter.default  (this_city)  [configured]
```

If inherited from World:

```text
openrouter.default  (world_main)  [configured]
```

If inherited from env:

```text
openrouter.default  (env)  [configured]
```

### 7.4 Department

Department secrets are configured from the existing Department detail experience, exposed as a `Secrets` tab/surface alongside current Department sections.

A Department secret overrides City, World, and env values for the same Secret Bank key.

Expected display before local override:

```text
github.token  (city_a)  [configured]
```

The inherited secret cannot be deleted from the Department page.

The admin may create a local Department secret using the same Secret Bank key:

```text
github.token  (this_department)  [configured]
```

After the local override exists, the inherited City secret stops appearing as the effective value.

If the local Department secret is deleted, the inherited City value appears again if it still exists.

### 7.5 Lemming

Lemming secrets are configured from the existing Lemming detail experience, exposed as a `Secrets` tab/surface alongside current Lemming overview/edit sections.

A Lemming secret overrides Department, City, World, and env values for the same Secret Bank key.

Expected display before local override:

```text
openrouter.default  (this_department)  [configured]
```

Expected display after local Lemming override:

```text
openrouter.default  (this_lemming)  [configured]
```

---

## 8. UI Model

Each relevant entity detail experience must expose a `Secrets` surface:

- World detail -> `Secrets`
- City detail -> `Secrets`
- Department detail -> `Secrets`
- Lemming detail -> `Secrets`

The exact LiveView/component structure should fit the current app. The product requirement is the operator capability, not identical tab mechanics across every page.

The `Secrets` surface shows effective Secret Bank keys available at that scope.

The UI must show:

- Secret Bank key;
- effective source;
- configured state;
- safe metadata such as last updated timestamp when available;
- actions allowed for the current scope;
- recent durable safe audit activity relevant to the current scope when available.

The UI must never show:

- raw secret value;
- copied secret value;
- exported secret value;
- first characters;
- last characters;
- hashes derived from the value;
- previews;
- masked text that implies the value can be revealed.

Preferred visual value indicator:

```text
[configured]
```

Do not use:

```text
********
```

unless the UI design requires a conventional masked placeholder. Product language must remain clear that the value is not recoverable or revealable.

---

## 9. Effective Source Display

The UI must show where the effective secret comes from.

Examples:

```text
github.token  (env)              [configured]
github.token  (world_main)       [configured]
github.token  (city_a)           [configured]
github.token  (this_department)  [configured]
github.token  (this_lemming)     [configured]
```

For inherited secrets:

- the source is the parent scope that currently provides the effective value;
- the secret is visible in the child scope;
- the secret cannot be deleted from the child scope;
- the admin can create a local secret with the same Secret Bank key to override it.

For local secrets:

- the source is the current scope;
- the secret can be replaced;
- the secret can be deleted;
- deleting it reveals the next inherited value if one exists.

---

## 10. Create, Replace, and Delete Behavior

### 10.1 Create

The admin can create a local secret by entering:

```text
BANK_KEY
VALUE
```

After creation:

- the key appears in the effective list;
- the value is never shown again;
- the source is the current scope;
- a durable safe audit event is recorded.

If the same key exists only in a parent scope, creating a local key overrides the inherited value.

### 10.2 Replace

Editing a secret means replacing its value.

The previous value is never shown.

Replace flow:

```text
BANK_KEY: github.token
New value: [input]
Confirm replace
```

If the key already exists locally, the UI should treat the action as `Replace existing secret`, not as a validation error.

### 10.3 Delete

Delete is real delete.

No soft delete.
No disabled state.
No feature flag behavior.

Rules:

- only local secrets can be deleted from the current scope;
- inherited secrets cannot be deleted from child scopes;
- env allowlist values cannot be deleted from child scopes;
- deleting a local secret permanently removes it from that scope;
- if a parent scope has the same key, that parent value becomes effective again;
- if no parent scope or env allowlist fallback has the key, the key becomes unresolved for that scope.

---

## 11. Runtime Access Model

The Secret Bank exists so runtime services and tools can resolve credentials safely.

Runtime/tool execution resolves secrets through this flow:

```text
Tool config contains $secrets.github.token
  -> Tool Runtime normalizes it to github.token
  -> Secret Bank resolves github.token for runtime scope
  -> Raw value is injected only inside trusted Tool Runtime execution
```

The Secret Bank resolves the effective Secret Bank key using:

```text
lemming -> department -> city -> world -> env allowlist
```

The runtime receives the raw value only inside the trusted execution path that needs it.

Lemmings and LLMs must never receive raw secret values.

Lemmings may only receive safe references or error states such as:

```text
secret_ref: github.token
status: configured
```

or:

```text
{:error, :missing_secret}
```

They must not receive:

- value;
- partial value;
- hash;
- preview;
- decrypted representation;
- provider-specific token material;
- Secret Bank key inventory unrelated to the secret reference.

---

## 12. Error Behavior

Errors must be safe and operationally useful.

Expected safe error categories:

- `missing_secret`
- `invalid_key`
- `invalid_scope`
- `provider_unavailable`
- `master_key_missing`
- `decrypt_failed`
- `not_found`
- `inherited_secret_not_deletable`
- `local_secret_required_for_replace`

Error messages must identify the safe metadata needed for troubleshooting:

- secret reference or normalized Bank key, when safe and relevant;
- requested scope;
- operation;
- source/provider if safe;
- reason.

Error messages must never include secret values or derived previews.

---

## 13. Durable Audit, Logs, and Runtime Traces

Secret Bank operations must be observable from day one through durable safe audit events.

The MVP must implement or reuse the canonical durable event store described by ADR-0018. In-memory-only activity logging is not sufficient for Secret Bank auditability.

The system must record safe events for:

- administrative changes;
- runtime resolution;
- runtime/tool usage;
- failed access or failed resolution.

### 13.1 Minimum event set

Event names should be canonicalized during implementation against ADR-0018, but the MVP must cover these product events:

| Event | Trigger | Must include | Must never include |
|---|---|---|---|
| `secret.created` | A local key/value is created | key, scope, source, timestamp | value |
| `secret.replaced` | A local value is replaced | key, scope, timestamp | old value, new value |
| `secret.deleted` | A local key is deleted | key, scope, timestamp | value |
| `secret.accessed` | Runtime resolves an effective secret for tool execution | secret reference, normalized key, requested_scope, resolved_source, tool_name when applicable | value |
| `secret.access_failed` | Runtime cannot resolve a secret reference | secret reference or normalized key, requested_scope, reason | value |

### 13.2 Non-negotiable safety rule

Logs, audit events, traces, telemetry, exceptions, LiveView assigns rendered to the client, runtime snapshots, checkpoints, and UI errors must never include secret values.

This includes:

- full values;
- partial values;
- first characters;
- last characters;
- masked previews containing real data;
- hashes of the value;
- copied material derived from the value.

### 13.3 UI monitoring

The `Secrets` surface should expose recent durable safe activity for the current scope.

Example:

```text
2026-04-28 10:15  secret.replaced       github.token  this_department
2026-04-28 10:18  secret.accessed       github.token             github_issue_creator
2026-04-28 10:21  secret.access_failed  stripe.token             missing_secret
```

This monitoring is intended for local admin troubleshooting, not advanced compliance reporting.

---

## 14. Functional Acceptance Criteria

### 14.1 Secret configuration

- An admin can configure env allowlist fallback entries.
- An admin can create a secret in World scope.
- An admin can create a secret in City scope.
- An admin can create a secret in Department scope.
- An admin can create a secret in Lemming scope.

### 14.2 Write-only values

- After a secret is created, its value cannot be read from the UI.
- After a secret is created, its value cannot be copied from the UI.
- After a secret is created, its value cannot be exported from the UI.
- Replacing a secret does not reveal the old value.
- Listing secrets never shows raw values, partial values, previews, or hashes.

### 14.3 Effective source display

- The `Secrets` surface shows the effective Secret Bank key available at the current scope.
- The `Secrets` surface shows whether the effective key comes from env allowlist, world, city, department, or current scope.
- Inherited secrets are visible but not deletable from child scopes.
- Local secrets are replaceable and deletable from their own scope.

### 14.4 Override behavior

- A World secret overrides an env allowlist fallback with the same Secret Bank key.
- A City secret overrides a World or env allowlist secret with the same Secret Bank key.
- A Department secret overrides a City, World, or env allowlist secret with the same Secret Bank key.
- A Lemming secret overrides a Department, City, World, or env allowlist secret with the same Secret Bank key.
- Creating a local secret with an inherited key makes the local value effective.
- Once overridden locally, the inherited value no longer appears as the effective value for that key.

### 14.5 Delete behavior

- Deleting a local secret removes it permanently from that scope.
- Deleting a local override reveals the next inherited value if one exists.
- Deleting a local secret with no parent or env allowlist fallback makes the key unresolved.
- The UI prevents deleting inherited secrets from child scopes.

### 14.6 Runtime resolution

- Runtime services normalize `$secrets.*` references to Secret Bank keys.
- Runtime services can resolve a normalized Secret Bank key for a given scope.
- The Secret Bank returns the most specific effective raw value only inside the trusted runtime/tool path.
- If no secret exists in the chain, runtime receives a safe error.
- Lemmings and LLM prompts never receive raw secret values.

### 14.7 Observability

- Creating a secret records a durable safe audit event.
- Replacing a secret records a durable safe audit event.
- Deleting a secret records a durable safe audit event.
- Successful runtime secret access records a durable safe audit event.
- Failed secret resolution records a durable safe audit event.
- No audit/log/trace/telemetry event contains secret values or derived previews.

---

## 15. Non-Functional Requirements

### 15.1 Safety

Secret values must be treated as sensitive write-only material.

They must not leak through:

- UI;
- logs;
- durable audit events;
- traces;
- telemetry;
- exceptions;
- LiveView assigns rendered to the client;
- prompts;
- Lemming context;
- checkpoints;
- runtime snapshots;
- tool execution summaries or previews.

### 15.2 Simplicity

This MVP should remain small and local-admin oriented.

Do not introduce user management, authentication, RBAC, external secret managers, approval workflows, or full connection management as part of this slice.

### 15.3 Operational clarity

The admin must be able to answer these questions from the UI:

- Which Secret Bank keys are effective here?
- Where does each effective secret come from?
- Which secrets are local to this scope?
- Which secrets are inherited?
- Can I replace or delete this secret here?
- Has runtime/tool access recently succeeded or failed?

### 15.4 Documentation and ADR alignment

This slice must include documentation work as a non-functional requirement.

Before the implementation is considered complete, existing ADRs must be reviewed and updated where the implemented MVP behavior differs from the current architecture text.

At minimum, review:

- `docs/adr/0008-lemming-persistence-model.md`
- `docs/adr/0009-secret-bank-hierarchical-secret-management.md`
- `docs/adr/0010-control-plane-authentication-admin-access.md`
- `docs/adr/0011-control-plane-authorization-model.md`
- `docs/adr/0017-runtime-topology-city-execution-model.md`
- `docs/adr/0018-audit-log-event-model.md`
- `docs/adr/0020-hierarchical-configuration-model.md`
- relevant operator-facing docs

The review must ensure documentation clearly describes:

- MVP secret scope chain: `env allowlist -> world -> city -> department -> lemming`;
- convention-based `$secrets.*` tool references and normalized Secret Bank keys;
- write-only secret values;
- source visibility in the UI;
- inherited vs local secret behavior;
- local override semantics;
- real delete behavior;
- durable safe audit requirements;
- current MVP assumption: local self-hosted admin, no users, no auth yet;
- future compatibility with control-plane authentication and authorization ADRs.

If an ADR already defines the intended long-term architecture, the update should not erase that direction. Instead, distinguish:

- current MVP behavior;
- intended future behavior;
- implementation sequencing constraints.

Operator-facing documentation must explain how a local admin configures, replaces, deletes, and monitors secrets.

---

## 16. Product Examples

### 16.1 Inherited City secret visible in Department

Given:

```text
city_a:
  github.token = configured

this_department:
  no github.token
```

The Department `Secrets` surface shows:

```text
github.token  (city_a)  [configured]
```

The admin cannot delete it from Department.

The admin may create a local Department secret with the same Secret Bank key.

### 16.2 Department override hides City value

Given:

```text
city_a:
  github.token = configured

this_department:
  github.token = configured
```

The Department `Secrets` surface shows:

```text
github.token  (this_department)  [configured]
```

The inherited City value no longer appears as the effective secret for that key.

The admin can replace or delete the Department value.

### 16.3 Deleting Department override restores City inheritance

Given:

```text
city_a:
  github.token = configured

this_department:
  github.token = configured
```

When the admin deletes `github.token` from `this_department`, the Department `Secrets` surface shows:

```text
github.token  (city_a)  [configured]
```

### 16.4 Env allowlist fallback

Given:

```text
env allowlist:
  openrouter.default -> OPENROUTER_API_KEY = configured

world:
  no openrouter.default

city:
  no openrouter.default

department:
  no openrouter.default
```

The Department `Secrets` surface shows:

```text
openrouter.default  (env)  [configured]
```

The admin cannot delete it from Department.

The admin can override it locally by creating `openrouter.default` in Department.

### 16.5 Tool secret reference and runtime access

Given:

```text
Tool config reference:
  $secrets.github.token

Lemming scope effective secret:
  github.token = configured from Department
```

When the tool runs, the runtime resolves `github.token` at the Lemming scope and injects the raw value only into the trusted Tool Runtime execution.

The Lemming and LLM may see only safe state such as:

```text
github.token = configured
```

They must not see the raw value or Secret Bank key inventory.

---

## 17. Architecture Handoff

This plan defines product behavior. The implementation design must decide the technical details.

Architecture/implementation should define:

- storage schema;
- encryption approach;
- master key handling;
- env allowlist configuration shape;
- persisted encrypted storage provider shape;
- exact context APIs;
- `$secrets.*` parsing and normalization path;
- LiveView structure that fits current pages;
- read-model shape for effective secrets;
- durable audit event persistence;
- canonical event names aligned with ADR-0018;
- safe error contracts;
- test strategy;
- documentation updates.

The implementation must preserve these product guarantees:

1. Values are write-only after submission.
2. Effective source is visible.
3. Inherited secrets are not editable or deletable from child scopes.
4. Local overrides are allowed by creating the same key at a more specific scope.
5. Delete is real delete.
6. Tools access secrets only through `$secrets.*` references in tool configuration.
7. Runtime can resolve effective values internally.
8. Lemmings and LLMs never see raw values.
9. Logs, audit, traces, telemetry, snapshots, checkpoints, and errors never leak values or derived previews.
10. Durable audit events exist for secret changes and runtime access.
11. Documentation and ADRs are updated to reflect MVP sequencing and behavior.

---

## 18. Suggested Slice Boundary

The preferred scope for this issue is:

- implement the Secret Bank foundation;
- support configured env allowlist fallback;
- support encrypted persisted secrets for World/City/Department/Lemming;
- expose a `Secrets` surface on each relevant current detail experience;
- show effective secrets and their source;
- allow create/replace/delete for local secrets;
- prevent delete for inherited secrets;
- support convention-based `$secrets.*` references for runtime access;
- record durable safe audit events;
- add/update docs and ADRs.

Do not expand this issue into:

- a new Lemming Type/template entity;
- full connection management;
- real third-party integrations;
- auth/RBAC;
- approval workflows;
- external secret manager support;
- advanced compliance reporting.
