# LemmingsOS — Elixir & Phoenix (LiveView) Guidelines

> Minimal, idiomatic, maintainable. All UI strings in English via Gettext.

## 0) Scope & Goals

- Prefer small, pure functions; explicit typed returns (`{:ok, t} | {:error, reason}`).
- Encapsulate DB and side-effects in context boundaries.
- LiveView first: components, assigns hygiene, i18n, a11y.
- Keep diffs minimal; remove dead/experimental code before merge.
- OTP correctness is first-class: supervision strategy, process naming, and restart semantics
  must be deliberate and testable.

## 1) Project Structure & Modules

- **Contexts** expose stable public APIs (`LemmingsOs.World`, `LemmingsOs.City`, etc.).
- **Schemas** live under their context (not a global `Schemas` bucket).
- **Web** layer only depends on contexts, not vice-versa.
- Module names: `LemmingsOsWeb.*` (web), `LemmingsOs.*` (core). One module per file.
- Context APIs for World-scoped resources MUST accept `world_id` or `%World{}` explicitly.

```elixir
# good
defmodule LemmingsOs.Department do
  alias LemmingsOs.Repo
  alias LemmingsOs.Department.{Schema, Manager}

  @spec create(map(), String.t()) :: {:ok, Schema.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs, world_id) do
    %Schema{}
    |> Schema.changeset(Map.put(attrs, :world_id, world_id))
    |> Repo.insert()
  end
end
```

## 2) Code Style

- `alias/require/import/use` grouped and alphabetized; one alias per line.
- Add `@moduledoc false` only for trivial modules; otherwise write a short `@moduledoc`.
- Document public functions with `@doc` and typespecs (`@spec`) when behavior is non-trivial.
- Pipe for data transformation only. Do **not** pipe into `case`/`with`; return tuples and branch at the end.
- **Pattern matching in function heads is the first and default choice.** `if`, `cond`, and `case` are secondary tools for when pattern matching is genuinely insufficient or would be less readable.
- Avoid `case` branches with only two simple outcomes when pattern matching in separate clauses keeps the flow flatter.
- Prefer `with` for linear happy-path flows that would otherwise become nested branching.
- Never use `if list == []` — use a pattern-matched clause for the empty case instead.

```elixir
# bad — reaches for `if` instead of matching
defp rotate(list, seed) do
  if list == [] do
    a
  else
	b
  end
end

# good — empty case is a separate clause, logic is flat
defp rotate([], _seed), do: a
defp rotate(list, seed) do: b
```

```elixir
# good
def start_lemming(attrs) do
  with {:ok, lemming} <- create_lemming(attrs),
       {:ok, _pid} <- Executor.start(lemming) do
    {:ok, lemming}
  end
end
```

## 3) Error Handling

- Return tuples; reserve `raise` for programmer errors or non-recoverable boundaries (startup, mix tasks).
- Normalize external errors to domain atoms/structs before bubbling up.
- Never swallow errors; attach context in logs with hierarchy metadata.

```elixir
with {:ok, resp} <- Req.get(url),
     {:ok, data} <- Jason.decode(resp.body) do
  {:ok, data}
else
  {:error, %Req.TransportError{reason: r}} -> {:error, {:http_error, r}}
  {:error, %Jason.DecodeError{} = e} -> {:error, {:invalid_json, e.position}}
end
```

## 4) Ecto

- Use `changeset/2` for validation; use `unique_constraint/3` instead of prechecks.
- Prefer `Ecto.Multi` for multi-step writes; return final typed tuples.
- Keep queries composable; expose filter functions rather than many `list_by_*` variants.
- Only preload what you render/use; avoid N+1 with explicit `preload`.
- All World-scoped tables MUST be filtered by `world_id` in every query.

```elixir
# composable World-scoped query
def list_departments(world_id, opts \\ []) do
  from(d in Department, where: d.world_id == ^world_id)
  |> filter_query(opts)
  |> Repo.all()
end

defp filter_query(q, [{:city_id, city_id} | rest]),
  do: filter_query(from(d in q, where: d.city_id == ^city_id), rest)
defp filter_query(q, [_ | rest]), do: filter_query(q, rest)
defp filter_query(q, []), do: q
```

## 5) OTP & Process Management

- Lemmings and Department Managers are supervised processes. Always start them via
  `DynamicSupervisor.start_child/2` or `start_supervised/1` in tests.
- Process names MUST be derived from stable DB UUIDs, not runtime-generated atoms.
- Restart strategies must be documented in the module `@moduledoc` when non-obvious.
- Do NOT use `String.to_atom/1` on external input. Use `via_tuple/1` with the Registry.

```elixir
# good: stable process name via Registry
def via_tuple(lemming_id), do: {:via, Registry, {LemmingsOs.Registry, lemming_id}}

# good: start child with stable name
DynamicSupervisor.start_child(
  LemmingsOs.Department.Supervisor,
  {LemmingsOs.Lemming.Executor, lemming}
)
```

## 6) Phoenix LiveView & HEEx

- Use **verified routes** (`~p"/path"`) and `push_navigate/2`.
- Set default assigns in `mount/3` (guard with `connected?/1` for side-effects).
- Prefer **function components** with `attr/3` and `slot/3`; validate assigns.
- Use `:if`, `:for`, and `{}` in HEEx; avoid raw `<% %>`.
- Use `phx-update="stream|append|prepend|replace"` intentionally.
- All user-facing text via Gettext (`dgettext("context", ".key")`). No literals.
- Follow basic a11y: labels, roles, keyboard support.

## 7) Logging & Telemetry

- Use `Logger` macros with hierarchy metadata: `world_id`, `city_id`, `department_id`, `lemming_id`.
- Avoid logging agent payloads (they may contain sensitive data from LLM calls).
- Emit `:telemetry` events for agent lifecycle actions:
  `[:lemmings_os, :lemming, :started]`, `[:lemmings_os, :lemming, :crashed]`, etc.
- Include hierarchy metadata in all telemetry event metadata maps.

```elixir
Logger.info("lemming started", world_id: w.id, city_id: c.id, lemming_id: l.id)

:telemetry.execute(
  [:lemmings_os, :lemming, :started],
  %{count: 1},
  %{world_id: w.id, city_id: c.id, department_id: d.id, lemming_id: l.id}
)
```

## 8) Config & Secrets

- Runtime config in `config/runtime.exs`; no secrets in repo.
- Agent configuration (LLM API keys, model identifiers) MUST come from env vars.
- Avoid compile-time app URLs; use env/ENV vars.

## 9) Credo & Formatter

- Enforce `mix format` (no diffs on CI).
- Credo: enable `Consistency`, `Readability`, `Refactoring`, `Warning` checks.

```bash
mix format --check-formatted
mix credo --strict
```

## 10) Performance

- Batch queries; prefer `Repo.insert_all` for bulk inserts when validations are elsewhere.
- ETS/caches only with eviction strategy; document TTL.
- For high-throughput Lemming event processing, prefer `Task.async_stream/3` with
  `max_concurrency` rather than unbounded spawning.
