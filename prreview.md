# PR Review — `feature/world-management`

**Branch:** `feature/world-management` → `main`
**Plan:** `llms/tasks/0001_implement_world_management/plan.md`
**Date:** 2026-03-17

---

## Summary

- Introduces the first persisted domain layer: `World` schema, `Worlds` context, bootstrap YAML ingestion pipeline (`PathResolver` → `Loader` → `ShapeValidator` → `Importer`), and a Cachex-backed `WorldCache`.
- Adds four read-model snapshots (`WorldPageSnapshot`, `HomeDashboardSnapshot`, `ToolsPageSnapshot`, `SettingsPageSnapshot`) that compose persisted state, bootstrap declarations, and runtime checks into LiveView-ready structs.
- Desmokes the World, Home, Tools, and Settings LiveView pages from mock data to real persisted data, while keeping remaining mock data (cities, departments, lemmings) explicitly annotated with TODOs.
- Updates ADRs 0020, 0021, and `docs/architecture.md` to document the intentional departure from single `config_jsonb` to split JSONB columns.
- Adds comprehensive test coverage: context tests, bootstrap pipeline tests, snapshot tests, and LiveView integration tests using factories.

## Risk Assessment

**Medium** — This is the foundational domain layer. Naming and boundary decisions here are load-bearing. The implementation is solid overall but has several constitution compliance gaps (missing `@required`/`@optional`, domain-layer Gettext dependency inversion), a caching bug that can poison the cache with `:not_found` errors, and a missing `list_worlds/1` context function. None are catastrophic but all should be addressed before this sets the pattern for Cities/Departments.

---

## BLOCKER

### B1: `WorldCache` caches `{:error, :not_found}` permanently — cache poisoning

- **Where:** `lib/lemmings_os/world_cache.ex`, `fetch/2`
- **Why it matters:** If there is a cache miss and the loader returns `{:error, :not_found}`, that error is stored in the cache permanently until explicit invalidation. If the snapshot is consulted before the bootstrap import finishes (which it can be — the cache starts before the import in `application.ex`), the error gets cached. Any subsequent lookup for that key serves the error response.
- **Suggested fix:** Only cache successful results:

  ```elixir
  defp fetch(key, loader) do
    case Cachex.get(@cache_name, key) do
      {:ok, nil} ->
        result = loader.()
        case result do
          {:ok, _} -> put_and_return(key, result)
          _ -> result
        end
      {:ok, value} -> value
    end
  end
  ```

---

## MAJOR

### M1: `World` schema missing `@required` and `@optional` — constitution violation

- **Where:** `lib/lemmings_os/world.ex`, `changeset/2`
- **Why it matters:** The constitution (section "Schema Changesets & Validation") states: _"Schemas MUST declare `@required` and `@optional` field lists. `changeset/2` MUST `cast(attrs, @required ++ @optional)` and validate with those lists."_ The current implementation inlines the field lists directly in `cast/3` and `validate_required/2`.
- **Suggested fix:**

  ```elixir
  @required ~w(slug name status last_import_status)a
  @optional ~w(bootstrap_source bootstrap_path last_bootstrap_hash
               last_imported_at limits_config runtime_config costs_config models_config)a

  def changeset(world, attrs) do
    world
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    # ...
  end
  ```

### M2: Domain modules depend on `LemmingsOsWeb.Gettext` — inverted dependency

- **Where:** `lib/lemmings_os/helpers.ex`, `lib/lemmings_os/world_bootstrap/importer.ex`, `lib/lemmings_os/world_bootstrap/loader.ex`, `lib/lemmings_os/world.ex`
- **Why it matters:** The Elixir style guide says _"Web layer only depends on contexts, not vice-versa."_ Domain modules under `lib/lemmings_os/` importing `LemmingsOsWeb.Gettext` creates an inverted dependency and couples domain logic to the UI translation layer.
- **Suggested fix:** Either (a) create `LemmingsOs.Gettext` as the backend and have `LemmingsOsWeb.Gettext` delegate to it, or (b) move translation calls to the snapshot/component layer and keep domain modules returning atoms or plain strings. Option (b) is cleaner: `World.translate_status/1` belongs in the snapshot or component layer, not in the schema module.

### M3: `Worlds` context missing `list_worlds/1` with keyword opts

- **Where:** `lib/lemmings_os/worlds.ex`
- **Why it matters:** The constitution says _"Context `list_*` functions MUST accept an `opts` keyword list for filtering."_ There is no `list_worlds/1` function at all. This is the first context and sets the pattern for all future ones.
- **Suggested fix:**

  ```elixir
  @spec list_worlds(keyword()) :: [World.t()]
  def list_worlds(opts \\ []) do
    World
    |> filter_query(opts)
    |> order_by([w], asc: w.inserted_at)
    |> Repo.all()
  end

  defp filter_query(query, [{:status, status} | rest]),
    do: filter_query(from(w in query, where: w.status == ^status), rest)
  defp filter_query(query, [_ | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query
  ```

### M4: `failure_attrs/2` in `Importer` without `slug` or `name` — upsert silently fails on fresh DB

- **Where:** `lib/lemmings_os/world_bootstrap/importer.ex`, `failure_attrs/2`
- **Why it matters:** When called on first boot with a missing YAML file, `failure_attrs/2` builds a map without `slug` or `name`. These are required by `validate_required/2`. The upsert fails with a changeset error, `persisted_world_or_nil/1` returns `nil` silently, and the operator has no persisted record to inspect.
- **Suggested fix:** Either (a) skip the persistence attempt when there is no existing world and the YAML failed to load (only update existing records on failure), or (b) provide fallback values like `slug: "unknown"` in the failure attrs. Document the chosen semantics explicitly.

### M5: `@spec` on `Loader.load/1` placed after default-arg head — compiler warning risk

- **Where:** `lib/lemmings_os/world_bootstrap/loader.ex`
- **Why it matters:** The `@spec` annotation appears after the `def load(input \\ [])` head. In Elixir, the spec must be placed before the first definition head. This may produce a compiler warning or confuse documentation tools.
- **Suggested fix:** Move the `@spec` above `def load(input \\ [])`.

---

## MINOR

- **`WorldPageSnapshot` at ~628 lines is doing too much.** Composing bootstrap loading, shape validation, runtime checks, and snapshot normalization in one file will be hard to maintain as the hierarchy grows. Consider extracting `RuntimeChecks` into a separate module.
- **`ShapeValidator` uses hardcoded English strings** instead of `dgettext`. The constitution says MUST. Can be deferred with an explicit waiver.
- **`ToolsLive` injects fetchers via `Application.get_env`** — process-level global state that prevents `async: true` tests and does not scale well. Consider a behaviour + Mox pattern.
- **`upsert_world/1` can issue up to 3 sequential DB queries** in the lookup chain (by id → by bootstrap_path → by slug). Acceptable for now but worth documenting.

---

## NITS

- Temp files created in `test/support/world_bootstrap_test_helpers.ex` (`write_temp_file!/2`) are not cleaned up with `on_exit`. They accumulate in `/tmp` across runs.
- `WorldLive` still aliases `LemmingsOs.MockData` without a comment marking it as temporary (the TODO on the function is there but not on the alias).
- `accent_style/1` in `WorldComponents` interpolates CSS from data (`"background-color: #{color};"`). Low risk now but a potential XSS vector if city data ever comes from untrusted input.
- `get_world!/1` goes through the cache but has no `@doc` note indicating this — callers may not realize they are getting a cached result.

---

## Test Coverage Notes

**Good coverage areas:**
- `Worlds` context: CRUD, upsert idempotency, lookup priority chain
- Bootstrap pipeline: valid, invalid, missing, and warning cases across `Loader`, `ShapeValidator`, and `Importer`
- `WorldCache`: cache hit and invalidation after upsert
- LiveView integration: all four pages have meaningful render and interaction tests
- `WorldPageSnapshot`: strongest snapshot coverage

**Missing or thin areas:**
- No test for the cache poisoning bug (B1): fetch a missing ID, insert the world, verify the cache does not serve the stale error.
- `ShapeValidator` tests cover ~4 of ~15 distinct validation paths. Missing: integer/boolean type validation, cost budget validation, runtime section validation, profile fallback validation.
- No test for `Loader.load/0` (zero-arg default path resolution through env var).
- No test for `SettingsPageSnapshot.build/0` when no world exists.
- `HomeLive` test does not cover the `:not_found` state.

---

## Observability Notes

- **Good:** `application.ex` logs bootstrap results with structured metadata (`event`, `status`, `bootstrap_path`, `issue_count`, `world_id`).
- **Missing:** No `:telemetry` events emitted. A `[:lemmings_os, :world, :bootstrap_synced]` event would be valuable for metrics.
- **Missing:** No structured logging in `Worlds.upsert_world/1` or cache invalidation paths.
- **Missing:** No debug-level logging in `WorldCache` on miss/hit/invalidation.

---

## Merge Recommendation

**REQUEST_CHANGES**

Fix **B1** (cache poisoning) and **M1** (`@required`/`@optional`) before merge. **M2**, **M3**, and **M4** must be addressed or carry an explicit waiver with an expiration date in the PR description. **M5** is a quick fix worth including in the same pass.
