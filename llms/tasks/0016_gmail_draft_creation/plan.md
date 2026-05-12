# Gmail Connection Onboarding And Draft Creation Tool - Implementation Plan

## Goal

Implement Gmail connection onboarding plus the first Gmail outbound slice for
the demo workflow:

```text
Connections -> Gmail -> Connect
  -> Google OAuth consent
  -> OAuth callback
  -> store refresh token through Secret Bank
  -> create or update Gmail Connection

prepared email content + artifact_ids + Gmail connection_ref
  -> email.create_draft
  -> reviewable Gmail draft with attachments
```

This PR lets an admin/operator connect a Gmail account, then lets a Lemming
create a Gmail draft that a human reviews and sends manually in Gmail.

This issue must not implement sending email, reading Gmail, or mailbox sync.

## Current Architecture Alignment

The app already has the foundations this slice should reuse:

| Foundation | Existing pattern | Gmail draft alignment |
|---|---|---|
| Tool catalog | Fixed first-party catalog in `LemmingsOs.Tools.Catalog` | Add `email.create_draft` as a fixed tool |
| Tool runtime | `LemmingsOs.Tools.Runtime` normalizes adapter output | Keep existing `summary`, `preview`, `result` envelope |
| Connections | Hierarchical, nearest-wins resolution by `type` | Add Gmail onboarding that creates/updates a `gmail` Connection |
| Secret Bank | Runtime-only secret resolution through `$KEY` refs | Store OAuth refresh token through Secret Bank and resolve refs only inside adapters |
| Artifacts | Managed storage and scoped download boundary | Attach existing Artifacts by ID, not paths |
| Timeline | Tool executions render summaries/results | Use safe summary/result data; no special timeline table |
| Events | Generic durable `Events.record_event/4` | Attempt best-effort safe onboarding and draft events |

The issue text recommends `type=email` and `provider=gmail`, but the current
Connection model has only `type` and no `provider` column or slug/ref field.
For this MVP, use:

```text
type: gmail
provider: gmail
```

where `provider` is safe metadata inside the Connection config and tool result.
The tool input `connection_ref` maps to the current Connection `type`, so the
supported value for this slice is `"gmail"`.

For this MVP, `connection_ref` maps to the current Connection type because the
current Connection model has no separate slug/ref. This means the effective
Gmail Connection is selected by hierarchical resolution for type `gmail`, and
there is only one effective Gmail account per scope.

This is an MVP compatibility choice with the current Connection schema. It does
not introduce the final multi-provider email model. A future migration may add
`type=email`, `provider=gmail`, or a dedicated connection slug/ref if multiple
Gmail accounts per scope become necessary.

## Gmail OAuth Onboarding

This PR includes a basic control-plane flow for connecting a Gmail account.

Admin/operator flow:

```text
Connections -> Gmail -> Connect
  -> Google OAuth consent
  -> OAuth callback
  -> store refresh token through Secret Bank
  -> create or update Gmail Connection
```

The connected Gmail account is then available to `email.create_draft` through
`connection_ref`.

This onboarding flow is intentionally narrow:

- Gmail only.
- Draft creation scope only.
- No Gmail read scopes.
- No mailbox sync.
- No send flow.
- No generic OAuth provider framework.
- No multi-account management beyond what the existing Connection model can represent.

OAuth client id and client secret may remain environment/admin configured.
The OAuth callback stores the generated refresh token through Secret Bank and
stores only the resulting Secret Bank ref in Connection config.

## External Setup Dependency

This issue requires a Google Cloud project configured with:

- Gmail API enabled
- OAuth consent screen
- OAuth Web Client credentials
- Authorized redirect URI pointing to the LemmingsOS OAuth callback

Each deployment must provide application-level OAuth config:

```text
GOOGLE_OAUTH_CLIENT_ID
GOOGLE_OAUTH_CLIENT_SECRET
GOOGLE_OAUTH_REDIRECT_URI
```

This PR does not automate Google Cloud project setup. Each self-hosted
deployment must provide a Google OAuth client configuration once. After that,
LemmingsOS users/admins can connect Gmail accounts through the control-plane
Connect Gmail flow.

## OAuth Security Requirements

The Gmail OAuth onboarding flow must:

- generate and validate OAuth `state`
- bind the OAuth flow to the authenticated control-plane user/session
- prevent CSRF on the callback
- reject callbacks with missing, invalid, expired, or mismatched state
- request only the Gmail compose scope
- store refresh tokens only through Secret Bank
- never expose refresh tokens or access tokens after callback handling
- store only safe metadata in Connection config
- show a safe success/failure result in the UI

## New Tool

Add a first-party runtime tool:

```text
email.create_draft
```

Catalog metadata:

| Field | Value |
|---|---|
| `id` | `email.create_draft` |
| `name` | `Create Gmail Draft` |
| `category` | `email` |
| `risk` | `medium` |
| `description` | Create a Gmail draft from prepared email content and optional Artifact attachments. |

### Input

```json
{
  "connection_ref": "gmail",
  "to": ["customer@example.com"],
  "cc": [],
  "bcc": [],
  "subject": "Quotation for requested service",
  "body": "Prepared email body",
  "body_format": "text/plain",
  "artifact_ids": ["artifact-id-1"]
}
```

| Field | Required? | Rules |
|---|---:|---|
| `connection_ref` | Yes | Must be `"gmail"` for this MVP |
| `to` | Yes | Non-empty list of simple valid email recipients |
| `cc` | No | List of simple valid email recipients; default `[]` |
| `bcc` | No | List of simple valid email recipients; default `[]` |
| `subject` | Yes | Non-empty string |
| `body` | Yes | String email body prepared by the Lemming |
| `body_format` | Yes | `text/plain` or `text/html` |
| `artifact_ids` | No | List of Artifact IDs; default `[]` |

Markdown-to-HTML conversion is out of scope. If a Lemming wants HTML email, it
must provide HTML body content and `body_format: "text/html"`.

### Success Result

Adapter result before runtime normalization:

```elixir
{:ok,
 %{
   summary: "Created Gmail draft for customer@example.com with 1 attachment",
   preview: "Subject: Quotation for requested service",
   result: %{
     "status" => "draft_created",
     "provider" => "gmail",
     "connection_ref" => "gmail",
     "draft_id" => "gmail-draft-id",
     "message_id" => "gmail-message-id-if-available",
     "to" => ["customer@example.com"],
     "cc" => [],
     "bcc" => [],
     "subject" => "Quotation for requested service",
     "artifact_ids" => ["artifact-id-1"]
   }
 }}
```

Runtime result must preserve the existing runtime envelope:

```elixir
{:ok,
 %{
   tool_name: "email.create_draft",
   args: args,
   summary: "Created Gmail draft for customer@example.com with 1 attachment",
   preview: "Subject: Quotation for requested service",
   result: %{...}
 }}
```

Do not return raw Gmail API responses.

## Gmail Connection

Add a registered Connection type:

```text
gmail
```

For this PR, the primary supported path is the control-plane Gmail OAuth
onboarding flow:

```text
Connections -> Gmail -> Connect
  -> Google OAuth consent
  -> OAuth callback
  -> Secret Bank refresh token storage
  -> Gmail Connection created or updated
```

Manual/admin-created Gmail Connections may exist for tests or local
development, but they are not the normal product flow. If manually configured,
the config may contain secret refs like this:

```json
{
  "provider": "gmail",
  "account_email": "sales@example.com",
  "scopes": ["https://www.googleapis.com/auth/gmail.compose"],
  "client_id": "$GMAIL_CLIENT_ID",
  "client_secret": "$GMAIL_CLIENT_SECRET",
  "refresh_token": "$GMAIL_REFRESH_TOKEN"
}
```

After onboarding, the preferred config shape is:

```json
{
  "provider": "gmail",
  "account_email": "sales@example.com",
  "scopes": ["https://www.googleapis.com/auth/gmail.compose"],
  "client_id": "$GMAIL_CLIENT_ID",
  "client_secret": "$GMAIL_CLIENT_SECRET",
  "refresh_token": "$GMAIL_REFRESH_TOKEN_GENERATED_FOR_THIS_CONNECTION"
}
```

Meaning:

- `client_id` and `client_secret` can remain environment/admin configured.
- `refresh_token` is generated by the OAuth callback and stored as a Secret Bank entry.
- Connection config stores the secret ref, not the token value.

Rules:

- `provider` must be `"gmail"`.
- `account_email` is safe display metadata.
- `scopes` must include only the minimum draft-composition scope for this issue.
- Credential fields must be Secret Bank refs.
- Raw OAuth tokens, refresh tokens, access tokens, client secrets, or passwords are invalid config.
- Runtime Connection resolution returns a safe descriptor only.
- Secret refs are resolved only by the Gmail adapter during tool execution.

Minimum Gmail scope:

```text
https://www.googleapis.com/auth/gmail.compose
```

Do not request Gmail read scopes. Do not implement or expose a send path even if
the scope technically permits later send operations.

## Gmail Adapter

Add a narrow Gmail adapter for `email.create_draft`.

Responsibilities:

- Validate tool input.
- Resolve `connection_ref` through the existing Connection runtime boundary.
- Resolve Secret Bank refs only inside the adapter execution boundary.
- Exchange the configured refresh token for an access token.
- Build a MIME email payload for `text/plain` or `text/html`.
- Attach existing Artifacts loaded through the Artifact boundary.
- Call Gmail draft creation.
- Return only a safe draft descriptor.
- Sanitize all provider and credential failures.

Use existing `Req` for HTTP calls. Do not add a Google client dependency unless
explicitly approved in a later implementation decision.

Keep the adapter provider-specific. Do not introduce a generic email provider
framework in this issue.

## Artifact Attachments

The tool accepts Artifact identifiers only:

```json
{"artifact_ids": ["artifact-id-1"]}
```

Rules:

- Raw local file paths are never accepted.
- Attachments are opened through `LemmingsOs.Artifacts` trusted APIs.
- Each Artifact must exist, be ready, and be accessible from the invoking
  `LemmingInstance` scope.
- Attachment MIME parts use the Artifact filename and content type.
- Filenames are sanitized before MIME use.
- Artifact storage refs and local filesystem paths are never included in tool
  inputs, results, logs, events, timeline entries, or raw context pages.
- Attachment errors return safe categories such as `artifact_not_found`,
  `artifact_not_allowed`, or `gmail_draft_create_failed`.

The expected demo attachment is a generated quotation, contract, or report PDF,
but the implementation should not be hardcoded to PDF if the Artifact metadata
already has a safe content type.

## Error Handling

Use the existing tool error envelope:

```elixir
{:error, %{code: binary(), message: binary(), details: map()}}
```

Safe error categories:

| Code | Meaning |
|---|---|
| `tool.email.connection_not_found` | No visible Gmail Connection |
| `tool.email.connection_not_allowed` | Connection exists but is not usable in scope |
| `tool.email.connection_auth_failed` | Secret resolution or OAuth refresh failed |
| `tool.email.artifact_not_found` | Attachment Artifact is missing or not ready |
| `tool.email.artifact_not_allowed` | Attachment is outside the invoking scope |
| `tool.email.invalid_recipient` | Recipient validation failed |
| `tool.email.invalid_body_format` | Unsupported `body_format` |
| `tool.email.draft_create_failed` | Gmail draft creation failed safely |
| `tool.validation.invalid_args` | Missing or malformed arguments |

Provider errors must be sanitized before returning to the Lemming or showing in
the UI. Never expose raw Google responses, authorization headers, tokens,
credential refs resolved values, storage refs, or local paths.

## Observability

Draft creation should follow existing tool execution and event patterns.

Attempt to record safe events through the existing `Events.record_event/4`
pattern. Event recording is best-effort and must not fail Gmail draft creation
if event persistence fails.

```text
email.draft_requested
email.draft_created
email.draft_failed
```

Safe metadata may include:

- `world_id`
- `city_id`
- `department_id`
- `lemming_id`
- `lemming_instance_id`
- `tool_name`
- `provider`
- `connection_ref`
- `connection_id`
- `recipient_count`
- `attachment_count`
- `artifact_ids`
- `draft_id`
- `status`

Events must not include:

- OAuth tokens
- refresh tokens
- access tokens
- client secrets
- authorization headers
- raw Gmail API responses
- local file paths
- Artifact storage refs

The existing instance timeline should show a readable tool result using the
tool execution summary/preview/result. It should show subject, recipient
summary, and Artifact IDs. It should not expose provider auth data or storage
internals.

## Non-goals

Do not implement:

- SMTP
- email sending
- `email.send_approved`
- approval records or approval workflow
- inbound Gmail reading
- Gmail mailbox sync
- Gmail watch/push notifications
- Gmail thread ingestion
- automatic reply processing
- generic multi-provider email abstraction
- email template management
- Markdown-to-HTML email rendering
- new outbound email domain model
- persisted `outbound_email_drafts` table
- billing-grade or compliance-grade audit storage

## Acceptance Criteria

### Gmail OAuth onboarding

- A control-plane user can start Gmail connection from the Connections UI.
- The app redirects to Google OAuth consent with the Gmail compose scope.
- The OAuth callback validates state/session before continuing.
- The callback exchanges the authorization code for tokens.
- The refresh token is stored through Secret Bank / Secret Provider.
- The Connection is created or updated with safe Gmail metadata.
- The Connection stores only secret refs, never token values.
- OAuth failures are shown as safe UI errors.
- No token value appears in logs, events, tool results, raw context pages, or artifacts.

### Connection and secrets

- A Gmail account can be represented using the existing Connection model with
  `type=gmail` and safe provider metadata.
- Manual Secret Bank/Connection setup is not required for the normal product flow.
- Gmail credentials are referenced through Secret Bank refs.
- No raw Gmail credential material is accepted in Connection config or tool input.
- No Gmail credential material appears in tool results, events, logs, raw
  context pages, artifacts, ETS, DETS, or checkpoints.

### Tool behavior

- `email.create_draft` is available in the fixed runtime catalog.
- The tool accepts `connection_ref`, recipients, subject, body, body format, and
  optional `artifact_ids`.
- The tool creates a Gmail draft and does not send email.
- The implementation contains no exposed send path.
- The tool supports `text/plain` and `text/html`.
- The tool performs simple recipient validation.
- The tool rejects unsupported body formats.
- Runtime output uses the existing tool result envelope.

### Attachments

- The tool can attach one or more existing Artifacts.
- The tool uses Artifact identifiers, not raw local paths.
- The tool verifies Artifact existence and scope access.
- The tool uses safe filenames and content types for MIME attachments.
- Attachment failures return safe errors.

### Gmail adapter

- Gmail API calls are isolated behind a small adapter/wrapper.
- The adapter resolves credentials only inside the execution boundary.
- The adapter builds the MIME draft payload.
- The adapter sanitizes Gmail/provider failures.
- Tests can use a fake Gmail client without calling Gmail.

### Observability

- Draft creation emits best-effort safe events.
- Successful draft creation is visible in the Lemming timeline.
- Failure events are safe and actionable.
- Events do not leak credentials, raw provider auth data, or local storage paths.

### Demo readiness

- A Lemming can create a Gmail draft with a prepared email body.
- A Lemming can attach an existing quotation, contract, or report Artifact.
- The user can review the created draft in Gmail.
- No send action is available from this issue.

## Test Plan

Backend tests:

- Catalog includes `email.create_draft`.
- Runtime dispatch normalizes success and failure.
- Gmail Connection type validates required safe config.
- Gmail Connection type rejects raw credential values.
- Missing, disabled, invalid, or inaccessible Gmail Connections fail safely.
- Tool validation covers required fields, recipient validation, body format, and
  invalid `artifact_ids`.
- Secret refs resolve only inside adapter execution.
- Fake Gmail client covers OAuth refresh success/failure.
- Fake Gmail client covers draft creation success/failure.
- MIME construction works with no attachments.
- MIME construction works with one or more Artifact attachments.
- Missing, non-ready, inaccessible, or broken Artifact attachments fail safely.
- Provider errors are sanitized.
- Tool result and events do not leak credentials, raw provider responses,
  storage refs, or local paths.

OAuth onboarding tests:

- start connect flow generates OAuth state
- callback rejects missing state
- callback rejects invalid state
- callback rejects expired state
- callback rejects mismatched state/session
- callback exchanges code through a fake Google OAuth client
- callback stores refresh token through a fake Secret Provider or Secret Bank boundary
- callback creates or updates Gmail Connection with safe metadata
- callback does not expose tokens in UI, events, logs, or safe results
- OAuth provider failure returns safe errors

Documentation checks:

- Update `docs/features/tools.md` for `email.create_draft`.
- Update `docs/features/connections.md` for Gmail Connection config.
- Update `docs/features/secret_bank.md` only as needed for Gmail secret refs.
- Document Gmail OAuth onboarding, OAuth scope, and explicit no-send/no-read/non-sync boundaries.
- Add a how-to for configuring and linking Google OAuth:
  Google Cloud project setup, Gmail API enablement, OAuth consent screen,
  OAuth Web Client creation, authorized redirect URI, deployment env vars
  (`GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`,
  `GOOGLE_OAUTH_REDIRECT_URI`), and the in-app `Connections -> Gmail -> Connect`
  flow.

Final validation:

```bash
mix test test/lemmings_os/connections test/lemmings_os/tools
mix precommit
```

## Involved Roles

Recommended implementation/review roles from `llms/agents/agent_catalog.md`:

- `po-analyst` for specification validation.
- `dev-backend-elixir-engineer` for tool, adapter, Connection, Secret Bank, and
  Artifact integration.
- `qa-test-scenarios` for acceptance and edge-case coverage.
- `qa-elixir-test-author` for ExUnit coverage.
- `docs-feature-documentation-author` for feature docs.
- `audit-security` for credential, provider, and attachment safety review.
- `audit-pr-elixir` for final Elixir/Phoenix code review.

## Generated Implementation Task Plan

### Metadata

- **Source plan**: `llms/tasks/0016_gmail_draft_creation/plan.md`
- **Generated**: 2026-05-09
- **Status**: PLANNING
- **Operating role**: `tl-architect`

This generated sequence converts the Gmail connection onboarding and draft
creation plan into grouped, sequential, human-approved implementation tasks.
The source plan is ready for task decomposition because it defines current
architecture alignment, OAuth security requirements, tool input/output
contracts, error taxonomy, attachment rules, observability expectations,
non-goals, acceptance criteria, and a test plan.

### Codebase Findings

- Connections already use `LemmingsOs.Connections`, `Connection`,
  `TypeRegistry`, and `Connections.Runtime` with nearest-wins resolution by
  `type`.
- The only registered Connection type today is `mock`, implemented by
  `LemmingsOs.Connections.Providers.MockCaller`.
- Connection config can store Secret Bank refs, and provider callers resolve
  refs just in time through `LemmingsOs.SecretBank`.
- `LemmingsOs.Tools.Catalog` and `LemmingsOs.Tools.Runtime` are fixed
  first-party boundaries. Runtime normalizes adapter outputs into the existing
  `summary`, `preview`, and `result` envelope.
- Artifact access already has trusted scoped APIs and safe public descriptors.
  The Gmail adapter should open attachment bytes only through `LemmingsOs.Artifacts`.
- The control plane currently runs in local-admin mode without implemented
  per-user authentication. OAuth state must still be session-bound and CSRF
  protected, and the sequencing gap must be documented.
- Connections UI is shared through `LemmingsOsWeb.ConnectionsSurface` and is
  embedded on World, City, and Department LiveViews.

### Technical Summary

- **New files anticipated**: Gmail connection provider, Gmail OAuth/controller
  boundary, Gmail tool adapter/client helpers, tests, and documentation updates.
- **Modified files anticipated**: Connection type registry, Connections context
  or helper APIs as needed, Secret Bank env fallback config, Tool catalog/runtime,
  router, Connections UI surfaces, instance timeline rendering only if existing
  cards are insufficient, factories, and docs.
- **Database migrations**: Not expected for the MVP. OAuth state should prefer
  session-bound state unless implementation discovers a reviewed need for a
  server-side state store.
- **External dependencies**: None. Use existing `Req`; do not add a Google
  client dependency.

### Assumptions For Human Review

- `connection_ref = "gmail"` maps to the current Connection `type = "gmail"`.
- Only one effective Gmail account per scope is supported through existing
  nearest-wins Connection resolution.
- Authenticated-user binding in the plan maps to the current browser/session
  boundary until ADR-0010 is implemented. This feature must not invent a full
  user/RBAC subsystem.
- Gmail OAuth requests only the compose scope. If implementation discovers that
  displaying `account_email` requires an additional Google scope, it must stop
  for human approval before broadening scopes.
- OAuth client id and client secret are deployment configuration. Refresh
  tokens generated by callback handling are stored through Secret Bank.
- Public backend APIs introduced by these tasks must include `@doc`, clear
  parameter descriptions, `@spec`, and executable examples/doctests where
  behavior is non-trivial.

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| OAuth state/session handling is implemented too loosely | Medium | High | Make OAuth state validation the first task and require callback rejection tests for missing, invalid, expired, and mismatched state. |
| Credential material leaks into Connection config, logs, events, tool results, or UI | Medium | High | Secret refs only in config; raw token sentinel tests; dedicated security and final PR audits. |
| Gmail adapter accidentally exposes send/read behavior | Low | High | Restrict catalog to `email.create_draft`; tests assert no send tool/path and compose-only scope. |
| Attachment access bypasses Artifact scope checks | Medium | High | Adapter must use Artifact APIs by ID only; tests cover missing, non-ready, cross-scope, and broken storage cases. |
| UI changes regress existing generic Connection forms | Medium | Medium | Keep shared `ConnectionsSurface` behavior intact and include LiveView tests for existing create/edit/test/delete flow plus Gmail connect controls. |

### Roles

#### Human Reviewer

- Approves each task before the next begins.
- Executes all git operations.
- Can reject a task and request revisions before the sequence continues.
- Performs final sign-off after security, observability, accessibility, coding
  style, and PR-readiness audits.

#### Executing Agents

Each task names exactly one assigned agent from
`llms/agents/agent_catalog.md`.

### Task Sequence

1. `01_gmail_connection_oauth_and_secret_storage.md` - `dev-backend-elixir-engineer`
2. `02_email_create_draft_backend_tool.md` - `dev-backend-elixir-engineer`
3. `03_gmail_connection_ui_and_documentation.md` - `dev-frontend-ui-engineer`
4. `04_gmail_security_observability_audit.md` - `audit-security`
5. `05_gmail_accessibility_audit.md` - `audit-accessibility`
6. `06_gmail_final_pr_audit.md` - `audit-pr-elixir`

### Human Approval Gates

After each task, the human reviewer must validate the task file acceptance
criteria and approve before the next task starts. Each implementation task must
run the narrowest relevant checks first, then `mix precommit` when the task is
complete and the branch is ready for the next approval gate.
