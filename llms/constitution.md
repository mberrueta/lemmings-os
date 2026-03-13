# LemmingsOS Constitution

## Core Principles

### Agent Tooling Restrictions (NON-NEGOTIABLE)

- Agents MUST NOT use git commands that modify repository state (`git add`, `git commit`,
  `git stash`, `git revert`, `git push`).
- Agents MUST only propose changes via file edits and leave version control actions to the user.

### Test Discipline & Quality Gates (NON-NEGOTIABLE)

- All changes that touch executable logic MUST include ExUnit tests.
- `mix test` and `mix precommit` MUST pass with zero warnings/errors before merge.
- Tests MUST run under the DB sandbox and be deterministic (no timing or ordering dependence).
- For OTP/process tests, use `start_supervised/1` and assert process state cleanly.
- For substantive changes, a coverage report via `mix coveralls.html` MUST be generated
  and linked in the PR.
- Debug prints and log noise MUST NOT be committed.

Rationale: Strong testing and zero-warning gating keep the runtime reliable, enable safe
refactoring, and ensure CI readiness.

### Context APIs & Query Patterns

- Context `list_*` functions MUST accept an `opts` keyword list for filtering.
- Core filtering MUST live in a private, multi-clause `filter_query/2` that pattern matches
  on filter keys.
- Complex retrievals SHOULD expose a reusable `list_*_query/1` for composition.
- Functions that can fail MUST return `{:ok, data}` or `{:error, reason}` tuples.
- Web layers MUST call through contexts, not schemas or repos directly.
- Context APIs for World-scoped resources MUST require an explicit `world_id` (or `%World{}`
  struct) as a parameter. No implicit global queries.
- Public functions that define important backend behavior MUST have `@doc` documentation.
- Important public backend functions SHOULD include executable examples in their `@doc` blocks
  when behavior is non-trivial or reused across contexts.

Rationale: Consistent, composable APIs and explicit World scoping enforce isolation
guarantees at the API layer, not just at the DB layer.

### Coding Style Baselines for Elixir Work

- Any agent changing Elixir production code MUST read `llms/coding_styles/elixir.md` before editing.
- Any agent changing Elixir tests MUST read `llms/coding_styles/elixir_tests.md` before editing.
- Agents MUST prefer pattern matching in function heads and small helpers over simple `if`/`case`
  branching whenever that keeps the flow flatter.
- Agents SHOULD prefer `with` for linear happy-path flows instead of nested `case` chains.
- Tests MUST use factories as the default test-data mechanism and MUST NOT introduce
  fixture-style helpers or `*_fixture` naming.
- Public backend functions added or materially changed MUST include `@doc` documentation with
  executable-style examples when behavior is non-trivial.

Rationale: Explicit style baselines reduce repeated review churn and keep agent output
aligned with the project's expected Elixir and OTP conventions.

### Schema Changesets & Validation

- Schemas MUST declare `@required` and `@optional` field lists.
- `changeset/2` MUST `cast(attrs, @required ++ @optional)` and validate with those lists.
- All validation messages MUST be internationalized using `dgettext("errors", "some_key")`.
- HEEx templates MUST use `{}` interpolation and `:if`/`:for` attributes and MUST NOT use
  `<% %>` or `<%= %>` blocks.

Rationale: Declarative changesets and localized messages ensure consistent, translatable
validation and predictable UI behavior.

### Security & Configuration Hygiene

- Secrets, salts, keys, and credentials MUST NEVER be hardcoded in source code.
  All such values MUST come from environment variables (via `runtime.exs` or direnv),
  with dev/test defaults clearly labelled (e.g., `"dev_only_signing_salt"`).
  Agents MUST NOT generate random secrets and embed them in source files.
- Data access MUST use Ecto with parameterized queries; logging MUST avoid sensitive data.
- PRs that add configuration MUST document required env vars.
- Agent configuration (LLM API keys, model identifiers) MUST come from env vars, never from
  source code or database plain-text fields.

Rationale: Protecting secrets and enforcing secure defaults mitigates risk and accelerates
compliant deployments. Agent runtimes are high-value targets.

### OTP & Process Safety

- Lemmings (and any supervised processes) MUST be started via `start_supervised/1` in tests.
- Dynamic supervisors MUST NOT be started without a named registration strategy that prevents
  duplicate registrations.
- Process names MUST be derived from stable identities (e.g., UUIDs from DB records), not from
  runtime-generated atoms (atom table overflow risk).
- Agents MUST NOT use `String.to_atom/1` on external input.

Rationale: OTP process management is the core of LemmingsOS. Process safety violations can
cause silent failures, atom table exhaustion, or cascading supervisor restarts.

### Build Parity & Operational Readiness

- The repo MUST be bootstrappable via `mix setup` and runnable locally via `mix phx.server`
  at http://localhost:4000.
- All PRs MUST pass `mix precommit` (format, Credo, test).
- Migrations MUST live under `priv/repo/migrations/` with seeds in `priv/repo/seeds.exs`.
- Tests MUST use the provided DB sandbox configuration.

Rationale: Reproducible builds and consistent runbooks reduce onboarding time and ensure
CI/CD parity.

## Project Structure & Tooling

- Source in `lib/`: domain contexts under `lib/lemmings_os/**`, web layer under
  `lib/lemmings_os_web/**`.
- Tests in `test/**`; mirror source paths.
- Config in `config/*.exs`; secrets via direnv / runtime.exs.
- Assets in `assets/` (Tailwind/esbuild); compiled/static in `priv/static`.
- Data/DB in `priv/repo/**` (migrations, seeds).

Stack and tools:

- Elixir/Erlang via ASDF; PostgreSQL 14+; Node.js for assets.
- ExUnit, ExMachina, ExCoveralls; Credo for style.

## Development Workflow & Quality Gates

- Development
  - `mix setup` to bootstrap; `mix phx.server` to run locally.
  - Follow Elixir style: 2-space indent; snake_case functions/files; PascalCase modules.
  - HEEx-only templating (no raw EEx in LiveView templates).
- Testing
  - Use ExUnit with DB sandbox; group tests with `describe` blocks.
  - Use `Test.Support.Factory` (e.g., `insert(:world)`).
  - Use `start_supervised/1` for OTP process tests.
- Reviews & PRs
  - Commits: small, imperative subject; logically scoped.
  - PRs MUST include summary, linked issues/ADR, screenshots (UI), migration notes,
    and a test plan; run `mix precommit` before pushing.

## Governance

Authority:

- This constitution supersedes other practice documents in case of conflict.

Amendments:

- Amendments MUST be proposed via PR updating this file and any affected templates.
  Each amendment MUST include:
  - Rationale, scope, and migration/transition guidance.
  - List of updated artifacts (templates, scripts, docs).
- Approval by maintainers is required.

Compliance & Review:

- All PRs MUST state how the change satisfies the relevant MUST rules.
- Exceptions REQUIRE a written waiver in the PR with an expiration date.
- Non-compliant merges MAY be reverted immediately.
- This constitution SHOULD be reviewed at least quarterly.
