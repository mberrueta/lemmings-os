# Task 04: Gmail Security And Observability Audit

## Status

- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Audit Result (2026-05-12)

### Scope

Reviewed Gmail OAuth onboarding, Gmail Connection config validation, Secret Bank
token storage, `email.create_draft`, Gmail HTTP boundaries, Artifact attachment
loading, timeline-facing result payloads, durable events, and related tests.

Assumption: the current control plane is still local-admin mode with no
implemented per-user auth/RBAC. OAuth state is therefore browser-session-bound,
not user-id-bound.

### Threat Model Snapshot

- Actors: local operator/admin, same-browser attacker attempting OAuth CSRF or
  callback replay, Lemming/tool runtime attempting unsafe draft or attachment
  input, Google/Gmail provider failure surfaces.
- Assets: OAuth refresh tokens, temporary access tokens, OAuth client secret,
  Secret Bank refs, Gmail draft content, Artifact bytes, Artifact storage refs,
  local filesystem paths, event/timeline payloads.
- Entrypoints: `/connections/gmail/oauth/start`,
  `/connections/gmail/oauth/callback`, `email.create_draft`, Artifact download
  boundary, Gmail token/draft/profile HTTP calls.

### Findings Table

| ID | Severity | Category | Location | Risk | Evidence | Recommendation |
|---|---|---|---|---|---|---|
| GMAIL-AUD-001 | Medium | Session / CSRF | `LemmingsOs.Connections.GmailOAuth.complete/4` | Public OAuth completion boundary validated nonce/expiry but did not independently compare the passed scope to the session-bound scope. The controller derived scope from session, so browser flow was protected, but the backend boundary was weaker than the documented contract. | Fixed in this audit by adding `validate_session_scope/2` before code exchange or secret resolution. Added `test/lemmings_os/connections/gmail_oauth_test.exs` coverage proving mismatched scope fails before token exchange. | Fixed. Keep this direct boundary test. |
| GMAIL-AUD-002 | Medium | Config / Browser Session | `LemmingsOsWeb.Endpoint` session config | Phoenix session cookie is signed but not encrypted, so OAuth session metadata such as selected scope and Secret Bank ref names is readable by the browser. No raw token/client secret values are stored there. | Endpoint comments explicitly state signed-only cookie storage. OAuth state contains refs and safe metadata only. | Accept for current local-admin MVP, or add `:encryption_salt` if ref names are considered sensitive in deployment threat model. |
| GMAIL-AUD-003 | Medium | Auth / Access Control | Control-plane routes | There is no implemented per-user control-plane auth/RBAC, so any party with browser access to the local admin plane can start Gmail onboarding or create/update scope-local Gmail Connections. | Project plan explicitly documents local-admin mode and ADR-0010 sequencing gap. | Human reviewer must explicitly accept this residual risk before broader deployment. Re-audit when per-user auth lands. |
| GMAIL-AUD-004 | Low | Logging / Observability | `email.create_draft` validation path | Draft requested/created/failed events are safe for parsed execution paths, but malformed argument validation failures return safe tool errors without an `email.draft_failed` event because no parsed args exist yet. | Event payloads include safe IDs/counts/status/error code; validation happens before event recording. | Accept for MVP or add a minimal invalid-args event using only instance scope, tool name, and error code. |
| GMAIL-AUD-005 | Low | Supply Chain / Web Config | `mix sobelow` global findings | Sobelow reports global missing CSP and HTTPS/HSTS hardening, plus existing low-confidence file/path findings. These are app-wide findings, not introduced by this Gmail slice. | `mix sobelow` reported `Config.CSP` and `Config.HTTPS` high-confidence findings and low/medium-confidence path/XSS findings in existing storage/download code. Gmail attachment file read is behind `Artifacts.open_artifact_download/2` scope/status checks. | Track as platform hardening. Do not block this Gmail task unless the release target is non-local production. |

### Observability Findings

- OAuth events are present and safe:
  `connection.gmail.oauth_started`, `connection.gmail.oauth_succeeded`,
  `connection.gmail.oauth_failed`, plus profile lookup failure.
- Draft events are present and safe:
  `email.draft_requested`, `email.draft_created`, `email.draft_failed`.
- Draft event payloads include hierarchy IDs, tool/provider identifiers,
  connection ID where available, recipient/attachment counts, Artifact IDs,
  status, draft ID on success, and safe error code on failure.
- No reviewed event/result path includes raw refresh tokens, access tokens,
  OAuth codes, authorization headers, raw Google response bodies, Artifact
  storage refs, or local paths.

### Remediation Completed

- Added backend scope/session comparison in `GmailOAuth.complete/4`.
- Added direct ExUnit coverage proving mismatched session scope rejects before
  OAuth exchange.
- Follow-up remediation added Phoenix session cookie encryption while preserving
  signed session behavior.
- Follow-up remediation added regression coverage that the app exposes Gmail
  draft creation only, with no registered, routed, or callable Gmail
  send/read/list/sync/delete tool paths.
- Follow-up remediation emits a minimal safe `email.draft_failed` event for
  invalid `email.create_draft` arguments without recording raw args.

### Residual Risks

- No per-user control-plane auth/RBAC is implemented yet; current safety depends
  on local-admin deployment boundaries.
- Gmail `gmail.compose` is the minimum Gmail compose scope, but Google grants
  capabilities beyond this app's exposed draft-only path. Regression tests now
  assert no send/read/list/sync/delete path is exposed by the catalog, runtime,
  router, or Gmail client surface.
- Global CSP/HTTPS hardening remains outside this Gmail task.

### Recommendation

Proceed to human review for Task 04 after accepting the documented local-admin
and signed-session residual risks. Re-audit before production/non-local
deployment or after control-plane authentication is implemented.

## Assigned Agent

`audit-security` - Security reviewer for authentication, authorization, input validation, secrets management, OWASP risks, and PII safety.

## Agent Invocation

Act as `audit-security`. Read `llms/constitution.md`, `llms/project_context.md`, `llms/tasks/0016_gmail_draft_creation/plan.md`, Tasks 01-03, and the implementation diff. Perform a security and observability audit of the Gmail OAuth onboarding and `email.create_draft` implementation.

## Objective

Verify that the implementation is safe for credentials, OAuth state handling, attachment boundaries, provider errors, and operational visibility.

## Audit Scope

- OAuth state generation, expiry, session binding, and callback validation.
- CSRF and browser-session assumptions under current local-admin control-plane mode.
- Gmail compose-only scope and absence of read/send/sync functionality.
- Secret Bank storage of refresh tokens and runtime-only resolution.
- Connection config containing refs and safe metadata only.
- Gmail adapter credential exchange and authorization header handling.
- Artifact attachment access by ID through scope-checked APIs only.
- Sanitized tool errors, provider failures, events, logs, raw context pages, and timeline payloads.
- Best-effort event recording that cannot fail successful draft creation.
- No token, credential, storage ref, local path, or raw provider body leakage.

## Expected Outputs

- Security findings ordered by severity.
- Observability findings about event/log completeness and safety.
- Targeted remediation requirements for confirmed defects.
- Explicit residual risks, including the current absence of implemented per-user control-plane auth.
- Recommendation to proceed, block, or re-audit.

## Suggested Checks

```bash
mix test test/lemmings_os/connections test/lemmings_os/tools test/lemmings_os/artifacts
mix sobelow # if already available in the project
```

## Acceptance Criteria

- OAuth callback cannot be replayed or completed with missing, invalid, expired, or mismatched state.
- No credential material is persisted outside Secret Bank or emitted to unsafe surfaces.
- No Gmail read/send/sync capability is reachable.
- Attachment scope enforcement is server-side and tested.
- Events include useful safe metadata for success and failure without raw payload leakage.
- Confirmed high and medium security findings are fixed or explicitly waived by the human reviewer.

## Human Approval Gate

Human reviewer validates security and observability findings before the accessibility audit begins.
