# Core backend rules

- Keep contexts explicit and world-scoped where relevant.
- Prefer `{:ok, value} | {:error, reason}` APIs.
- Avoid bang APIs for domain actions.
- Use `Ecto.Multi` for multi-step durable changes.
- Keep pure resolver modules free of database access.
- Do not mix runtime orchestration, persistence, model calls, and PubSub in one module unless intentionally documented.
- Public modules should include useful `@moduledoc`, `@doc`, and doctest-friendly examples.
