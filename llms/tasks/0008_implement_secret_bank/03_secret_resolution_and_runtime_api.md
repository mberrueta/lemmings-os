# Task 03: Secret Resolution and Runtime API

## Status
- **Status**: COMPLETED
- **Approved**: [X] Human sign-off

## Assigned Agent
`dev-backend-elixir-engineer`

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Implement hierarchical resolution and trusted runtime access APIs using the context from Task 02.

## Objective
Resolve normalized Secret Bank keys through `lemming -> department -> city -> world -> env fallback`. Tool config references use `$secrets.<provider>.<name>` and normalize to `<provider>.<name>` before resolution.

## Expected Outputs
- Backend resolution API(s) under `lib/lemmings_os/**`.
- Safe result structs/maps for UI metadata.
- Trusted runtime result shape that returns raw values only inside the runtime API boundary.

## Acceptance Criteria
- Effective metadata resolution shows only the most specific configured value for each Secret Bank key.
- Resolution source labels distinguish env, world, city, department, and current lemming sources.
- Runtime resolution accepts a normalized key such as `github.token` or a `$secrets.github.token` reference that is normalized before lookup.
- `$secrets.github.token` normalizes to `github.token`.
- Env fallback is attempted only when the normalized Secret Bank key is present in the configured env fallback allowlist.
- Env fallback derives `GITHUB_TOKEN` from configured key `github.token` when no explicit env var override is present.
- Env fallback uses explicit overrides such as `{"openrouter.default", "OPENROUTER_API_KEY"}` when configured.
- Missing configured value returns `:missing_secret`.
- Env fallback never scans the process environment as an open keyspace.
- Decryption failures return `:decrypt_failed` without raising value-bearing exceptions.
- Runtime API has tests or task handoff notes showing raw values are not suitable for UI, logs, Lemming context, snapshots, or prompts.

## Review Notes
Reject if this task introduces a tool binding table, policy binding layer, or arbitrary process-environment lookup.
