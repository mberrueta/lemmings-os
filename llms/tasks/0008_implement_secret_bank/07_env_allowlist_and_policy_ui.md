# Task 07: Env Fallback Display

## Status
- **Status**: PENDING
- **Approved**: [ ] Human sign-off

## Assigned Agent
`dev-frontend-ui-engineer`

## Agent Invocation
Act as `dev-frontend-ui-engineer`. Add read-only visibility into configured/convention-based env fallback behavior where it helps operators understand effective Secret Bank sources.

## Objective
Expose read-only safe metadata for env fallback behavior. Tool secret references are convention-based (`$secrets.github.token -> github.token -> GITHUB_TOKEN`) and do not have a policy binding UI. Env fallback is available only for configured allowlist entries.

## Expected Outputs
- Settings, Tools, or Secret surface UI updates under `lib/lemmings_os_web/**`, matched to existing page structure.
- Stable DOM IDs for any read-only env fallback display.

## Acceptance Criteria
- UI can show configured env fallback mappings as read-only safe metadata when helpful.
- UI distinguishes convention-derived entries such as `github.token -> GITHUB_TOKEN` from explicit overrides such as `openrouter.default -> OPENROUTER_API_KEY`.
- UI does not create, replace, or delete env fallback mappings because those live in application config.
- UI does not create, replace, or delete tool secret bindings because bindings do not exist in this MVP.
- UI explains convention with safe examples such as `$secrets.github.token -> GITHUB_TOKEN` if explanatory text is needed.
- Env fallback UI never treats all environment variables as discoverable or browsable.
- Validation errors use safe messages and do not echo secret values.
- UI fits existing Settings/Tools information architecture.

## Review Notes
Reject if the UI lists process environment values, adds env fallback CRUD, adds tool binding CRUD, or leaks provider credential material.
