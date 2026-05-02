# Task 02: Documents Config And Dependency Contract

## Status
- **Status**: PENDING
- **Approved**: [ ]

## Assigned Agent
`dev-backend-elixir-engineer` - Senior backend engineer for Elixir/Phoenix contexts, adapters, runtime configuration, and tests.

## Agent Invocation
Act as `dev-backend-elixir-engineer`. Establish the documents dependency and runtime configuration contract without implementing document conversion behavior yet.

## Objective
Add the Earmark dependency version approved in `plan.md` and define safe runtime configuration for the documents adapter: Gotenberg URL, timeouts, retries, source/PDF/fallback size limits, and optional fallback asset paths.

## Inputs Required
- [ ] `llms/tasks/0012_print_to_pdf/plan.md`
- [ ] Task 01 scenario matrix
- [ ] `llms/coding_styles/elixir.md`
- [ ] `llms/coding_styles/elixir_tests.md`
- [ ] `mix.exs`
- [ ] `config/runtime.exs`
- [ ] `config/test.exs`

## Expected Outputs
- [ ] Earmark is added using the dependency version approved in `plan.md`.
- [ ] `:lemmings_os, :documents` runtime config populated from documented env vars.
- [ ] Numeric env parsing fails startup clearly for invalid values.
- [ ] Empty fallback env values are treated as unset.
- [ ] Test config has deterministic defaults suitable for Bypass-based PDF backend tests.
- [ ] Focused config tests or equivalent coverage for defaults, overrides, invalid numerics, and unset fallbacks.

## Acceptance Criteria
- [ ] No unapproved dependencies are added.
- [ ] The agent never controls `LEMMINGS_GOTENBERG_URL`; only runtime config does.
- [ ] Safety limits default to the values in `plan.md`.
- [ ] Fallback paths are stored as config values only; validation of existence, location, symlink status, extension, and size is left to the adapter task.
- [ ] Existing tool runtime config behavior remains unchanged.
- [ ] Tests that mutate application env restore previous values in `on_exit`.

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
- [ ] To be completed by the executing agent.

### Outputs Created
- [ ] To be completed by the executing agent.

### Assumptions Made
- [ ] To be completed by the executing agent.

### Decisions Made
- [ ] To be completed by the executing agent.

### Blockers
- [ ] To be completed by the executing agent.

### Questions for Human
- [ ] To be completed by the executing agent.

### Ready for Next Task
- [ ] Yes
- [ ] No

## Human Review
Human reviewer confirms env names, defaults, failure behavior, and dependency choice before Task 03 begins.
