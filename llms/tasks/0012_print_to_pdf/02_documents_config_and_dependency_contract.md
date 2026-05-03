# Task 02: Documents Config And Dependency Contract

## Status
- **Status**: COMPLETE
- **Approved**: [X]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix contexts, adapters, runtime configuration, and tests.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Establish the documents dependency and runtime configuration contract without implementing document conversion behavior yet.

## Objective
Add the Earmark dependency version approved in `plan.md` and define safe runtime configuration for the documents adapter: Gotenberg URL, timeouts, retries, source/PDF/fallback size limits, and optional fallback asset paths.

## Inputs Required
- [X] `llms/tasks/0012_print_to_pdf/plan.md`
- [X] Task 01 scenario matrix
- [X] `llms/coding_styles/elixir.md`
- [X] `llms/coding_styles/elixir_tests.md`
- [X] `mix.exs`
- [X] `config/runtime.exs`
- [X] `config/test.exs`

## Expected Outputs
- [X] Earmark is added using the dependency version approved in `plan.md`.
- [X] `:lemmings_os, :documents` runtime config populated from documented env vars.
- [X] Numeric env parsing fails startup clearly for invalid values.
- [X] Empty fallback env values are treated as unset.
- [X] Test config has deterministic defaults suitable for Bypass-based PDF backend tests.
- [X] Focused config tests or equivalent coverage for defaults, overrides, invalid numerics, and unset fallbacks.

## Acceptance Criteria
- [X] No unapproved dependencies are added.
- [X] The agent never controls `LEMMINGS_GOTENBERG_URL`; only runtime config does.
- [X] Safety limits default to the values in `plan.md`.
- [X] Fallback paths are stored as config values only; validation of existence, location, symlink status, extension, and size is left to the adapter task.
- [X] Existing tool runtime config behavior remains unchanged.
- [X] Tests that mutate application env restore previous values.

## Technical Notes
- Existing `runtime.exs` already has a local `parse_optional_integer` helper pattern. Reuse or extend it conservatively.
- Runtime config is deployment adapter configuration, not hierarchy policy and not Lemming-controlled input.
- Keep implementation small enough that later adapter tasks can consume `Application.get_env(:lemmings_os, :documents, [])`.
- Current default candidate from `plan.md` is `{:earmark, "~> 1.4"}`; use a different version only if `plan.md` is updated before execution.

## Execution Instructions
1. Read style docs and existing runtime config first.
2. Add the dependency and config contract.
3. Add focused tests for config behavior using the repo's existing patterns.
4. Run the narrowest relevant tests, then `mix format` for changed files.
5. Record commands and results in this task file.

## Execution Summary

### Work Performed
- [X] Added `{:earmark, "~> 1.4"}` dependency to `mix.exs`.
- [X] Extended `config/runtime.exs` with `:lemmings_os, :documents` runtime config (Gotenberg URL, timeouts, retries, source/PDF/fallback size limits, optional fallback paths).
- [X] Hardened numeric env parsing in `config/runtime.exs` so invalid integers raise with env-var-specific errors.
- [X] Added optional-string parsing so empty fallback path env vars are treated as unset.
- [X] Added deterministic test defaults for `:documents` in `config/test.exs` for Bypass-based tests.
- [X] Added focused config coverage in `test/lemmings_os/config/runtime_documents_config_test.exs`.
- [X] Ran format, focused tests, and full `mix precommit`.

### Outputs Created
- [X] Updated `mix.exs`
- [X] Updated `config/runtime.exs`
- [X] Updated `config/test.exs`
- [X] Added `test/lemmings_os/config/runtime_documents_config_test.exs`

### Assumptions Made
- [X] Runtime `:documents` config should remain environment-controlled deployment config and not world/city/department/lemming-scoped config.
- [X] Fallback path trust and filesystem validation remain out of scope for this task and will be implemented in adapter tasks.

### Decisions Made
- [X] Reused and strengthened the existing `parse_optional_integer` runtime helper pattern instead of introducing a separate parser module.
- [X] Used `Application.get_env(:lemmings_os, :documents, [])` as conservative fallback for runtime defaults.
- [X] Isolated runtime config tests from preloaded app env by temporarily clearing `:documents` app env when asserting defaults/overrides.

### Blockers
- [X] None.

### Questions for Human
- [X] None.

### Ready for Next Task
- [X] Yes
- [ ] No

### Commands Run And Results
- `mix deps.get` (success; added `earmark 1.4.48` to lockfile)
- `mix format mix.exs config/runtime.exs config/test.exs test/lemmings_os/config/runtime_documents_config_test.exs` (success)
- `mix test test/lemmings_os/config/runtime_artifact_storage_config_test.exs test/lemmings_os/config/runtime_documents_config_test.exs` (success; 6 tests, 0 failures)
- `mix precommit` (success; format/compile/dialyzer/credo all passed)

## Human Review
Human reviewer confirms env names, defaults, failure behavior, and dependency choice before Task 03 begins.
