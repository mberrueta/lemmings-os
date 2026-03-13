# Contributing to LemmingsOS

Thanks for your interest in contributing to **LemmingsOS** — an open-source runtime for autonomous AI agent hierarchies.

Because this project deals with process supervision, agent lifecycle, and distributed coordination, contributions should prioritize **correctness, observability, and fault tolerance** over feature surface area.

---

## Quick links

* Code of Conduct: `CODE_OF_CONDUCT.md` (coming soon)
* Security reporting: `SECURITY.md` (coming soon)
* ADRs: `docs/adr/`
* Project context: `llms/project_context.md`
* Contributor + agent guidelines: `AGENTS.md`
* Baseline LLM governance: `llms/constitution.md`
* Elixir/Phoenix guidelines: `llms/coding_styles/elixir.md`
* Testing guidelines: `llms/coding_styles/elixir_tests.md`

---

## Before you start

### 1) Discuss first for non-trivial changes

For anything beyond a small fix, please **open an issue first** to align on:

* scope and design direction
* hierarchy and isolation implications
* OTP supervision strategy
* data model and migration strategy

### 2) Use ADRs for architectural decisions

If a change affects architecture, the agent hierarchy model, data invariants, or long-term direction, write an ADR.

* Location: `docs/adr/`
* Naming: zero-padded sequence + short slug, e.g. `docs/adr/0004-lemming-identity-model.md`

An ADR should include:

* context / problem
* decision drivers
* alternatives considered
* trade-offs
* consequences / follow-ups

See existing ADRs in `docs/adr/` for format reference.

---

## What contributions are most valuable

### Runtime correctness

* agent lifecycle management (spawn, restart, terminate)
* supervision strategy and OTP tree design
* cross-City/Department coordination primitives
* World isolation boundary enforcement

### Observability

* structured telemetry and tracing across hierarchy layers
* Lemming identity propagation in logs and traces
* performance profiling for agent concurrency

### Testing & reliability

* deterministic tests for agent lifecycle edge cases
* supervision tree failure mode coverage
* concurrent agent interaction tests

### Documentation

* architecture docs and diagrams
* operational runbooks
* ADRs for major design decisions

---

## Development setup

### Prerequisites

* Elixir/Erlang (recommended via [ASDF](https://asdf-vm.com/))
* PostgreSQL 14+
* Node.js (for assets)

### Local setup

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

Open: [http://localhost:4000](http://localhost:4000)

### Docker

```bash
docker compose up --build
```

Open: [http://localhost:4000](http://localhost:4000)

---

## Coding standards

Please follow the repository conventions:

* **Elixir / Phoenix / LiveView**: `llms/coding_styles/elixir.md`
* **Testing**: `llms/coding_styles/elixir_tests.md`
* **Project-wide rules** (including security/config hygiene): `llms/constitution.md`

Key expectations:

* Prefer small, explicit, readable functions.
* Supervision trees must be deterministic and testable.
* No cross-boundary coupling without explicit contracts.
* Keep boundaries clean: web layer calls contexts; contexts encapsulate DB and OTP side effects.
* Never hardcode secrets or keys; document required env vars for new config.

---

## Quality gates

Before opening a PR, run:

```bash
mix format
mix test
mix credo --strict
```

When you're done with a complete set of changes, run the full gate:

```bash
mix precommit
```

PRs should keep `main` releasable and CI-green.

---

## Tests

* All executable logic must come with ExUnit tests.
* Keep tests deterministic (no sleeps, no timing assumptions).
* Use the SQL sandbox patterns from `llms/coding_styles/elixir_tests.md`.
* For OTP/process tests, use `start_supervised/1` and clean up after each test.

---

## Branch strategy

| Prefix | Purpose | Example |
|---|---|---|
| `main` | Production-ready, always releasable | — |
| `feature/*` | New features | `feature/rules-runner` |
| `fix/*` | Bug fixes | `fix/import-csv-parser` |
| `chore/*` | Maintenance, deps, config | `chore/update-deps` |
| `docs/*` | Documentation and ADRs | `docs/adr-agent-architecture` |

Use short, lowercase, hyphen-separated slugs.

---

## Pull request process

1. Fork the repo

2. Create a branch following the [branch strategy](#branch-strategy) above

3. Make focused changes (small PRs are easier to review)

4. Add/update tests

5. Ensure quality gates pass

6. Open a PR

### PR checklist

Include in the PR description:

* What changed and why
* How to test (commands + expected outcomes)
* Any migrations and how to roll back (if applicable)
* OTP/supervision implications (if touching lifecycle or process management)
* Security notes (PII, secrets, access patterns)
* Links to issue / ADR (if relevant)

---

## Security

* **Do not** report vulnerabilities via public issues.
* Follow `SECURITY.md` for responsible disclosure (coming soon).

---

## AI / agent-assisted contributions

If you use AI agents (Claude/Codex/Gemini), ensure outputs comply with:

* `llms/constitution.md` (baseline rules)
* `AGENTS.md` (agent workflow and repo-specific constraints)

When in doubt, prefer smaller diffs and explicit reasoning in the PR description.

---

## License

By contributing, you agree that your contributions will be licensed under the project's [Apache License 2.0](LICENSE).
