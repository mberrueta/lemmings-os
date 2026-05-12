# Task 02: Email Create Draft Backend Tool

## Status

- **Status**: COMPLETED
- **Approved**: [x] Human sign-off

## Assigned Agent

`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix tool runtime, external HTTP integrations, artifacts, observability, and tests.

## Agent Invocation

Act as `dev-backend-elixir-engineer`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/coding_styles/elixir.md`, `llms/coding_styles/elixir_tests.md`, `llms/tasks/0016_gmail_draft_creation/plan.md`, Task 01, and this task. Implement only the `email.create_draft` backend tool, Gmail adapter/client boundary, attachment handling, observability, and tests.

## Objective

Add the first Gmail outbound runtime slice:

```text
prepared email content + artifact_ids + connection_ref
  -> email.create_draft
  -> Gmail draft descriptor
```

The tool creates a Gmail draft and never sends email.

## Expected Outputs

- `email.create_draft` entry in `LemmingsOs.Tools.Catalog` with category `email` and risk `medium`.
- Runtime dispatch in `LemmingsOs.Tools.Runtime` that preserves the existing tool result envelope.
- Gmail draft adapter/client modules using `Req`, with tests using Bypass or an injected fake client.
- Input validation for:
  - `connection_ref == "gmail"`
  - non-empty `to`
  - optional `cc` and `bcc`
  - simple recipient validation
  - non-empty `subject`
  - string `body`
  - `body_format` in `text/plain` or `text/html`
  - optional `artifact_ids`
- Scoped Connection resolution using the current LemmingInstance hierarchy and existing Connections runtime boundary.
- Secret ref resolution only inside the adapter execution boundary.
- Refresh-token to access-token exchange.
- MIME payload construction for text/plain, text/html, and attachments.
- Attachment loading only through `LemmingsOs.Artifacts` trusted APIs by Artifact ID.
- Safe draft result containing only `status`, `provider`, `connection_ref`, `draft_id`, optional `message_id`, recipients, subject, and `artifact_ids`.
- Best-effort safe events:
  - `email.draft_requested`
  - `email.draft_created`
  - `email.draft_failed`
- Public API docs, parameter descriptions, specs, and executable examples/doctests for non-trivial new public functions.

## Implementation Checklist

- [x] `email.create_draft` added to `LemmingsOs.Tools.Catalog` (`category: email`, `risk: medium`).
- [x] Runtime dispatch wired in `LemmingsOs.Tools.Runtime` with existing normalized envelope.
- [x] Added `LemmingsOs.Tools.Adapters.Email` and `LemmingsOs.Tools.Adapters.Email.GmailClient` (Req boundary).
- [x] Input validation for recipients, body format, connection ref, and artifact ID contract.
- [x] Scoped Connection resolution via `LemmingsOs.Connections.Runtime`.
- [x] Secret ref resolution kept inside adapter execution (`LemmingsOs.SecretBank.resolve_runtime_secret/3`).
- [x] Refresh-token exchange and Gmail draft create HTTP flow implemented.
- [x] MIME construction supports `text/plain`, `text/html`, and multipart attachments.
- [x] Attachment loading uses `LemmingsOs.Artifacts` APIs by Artifact ID only.
- [x] Safe draft result contract implemented (no raw provider responses).
- [x] Best-effort safe events added: `email.draft_requested`, `email.draft_created`, `email.draft_failed`.
- [x] Public docs/specs/examples added for new public APIs (adapter + Gmail client).
- [x] Tests added/updated for catalog/runtime, adapter validation/errors, MIME/attachments, provider failures, and no-leak assertions.
- [x] Validation run complete: targeted tests + `mix precommit` passing.

## Backend Safety Rules

- Do not return raw Gmail API responses.
- Do not log or emit OAuth tokens, refresh tokens, access tokens, client secrets, authorization headers, Secret Bank resolved values, Artifact storage refs, or local paths.
- Do not accept raw file paths in tool input.
- Do not expose a send path, `email.send_approved`, mailbox read, sync, watch, or reply processing.
- Provider errors must be normalized to the safe error taxonomy from `plan.md`.
- Event persistence is best-effort and must not fail a successful draft creation.

## Testing Requirements

- Catalog test proves `email.create_draft` is listed and supported.
- Runtime test proves success normalization preserves `tool_name`, `args`, `summary`, `preview`, and `result`.
- Runtime and adapter tests cover missing/disabled/invalid/inaccessible Gmail Connections.
- Validation tests cover missing required fields, invalid recipients, unsupported body format, unsupported `connection_ref`, malformed `artifact_ids`, and unsupported raw path fields.
- Secret resolution tests prove refs resolve only inside adapter execution, not in catalog/runtime/Connection resolution.
- Gmail HTTP tests cover refresh success/failure and draft creation success/failure with fake endpoints.
- MIME tests cover no attachments, one attachment, multiple attachments, text/plain, and text/html.
- Artifact tests cover missing, non-ready, cross-scope, inaccessible, and broken-storage attachments.
- No-leak tests use sentinel tokens, secret refs, storage refs, local paths, and raw provider bodies and assert they are absent from tool results, events, logs, and persisted tool execution output.
- Tests assert no send tool or send HTTP path is exposed.

## Suggested Checks

```bash
mix test test/lemmings_os/tools test/lemmings_os/artifacts test/lemmings_os/connections
mix test test/lemmings_os/lemming_instances
mix format
```

When the task is complete and ready for human approval, run `mix precommit` if the task changes are stable enough for a full gate.

## Acceptance Criteria

- `email.create_draft` can create a Gmail draft through the runtime with the existing normalized envelope.
- The adapter supports text/plain and text/html bodies.
- Attachments are loaded by Artifact ID through scope-checked Artifact APIs.
- All specified safe error codes are returned where applicable.
- Successful and failed draft events are safe and best-effort.
- No raw credential, provider response, storage ref, or local path leaks through any tested backend surface.
- Public backend APIs added in this task include docs, specs, parameter descriptions, and examples/doctests.
- Human reviewer can approve Task 03 after reviewing backend test evidence.

## Human Approval Gate

Human reviewer validates tool behavior, attachment safety, no-send boundary, no-leak evidence, and API documentation before UI work begins.
