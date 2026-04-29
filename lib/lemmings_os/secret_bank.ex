defmodule LemmingsOs.SecretBank do
  @moduledoc """
  Minimal boundary for encrypted local secrets and safe metadata.

  Public API:
  - `upsert_secret/3`
  - `delete_secret/2`
  - `list_effective_metadata/2`
  - `resolve_runtime_secret/2`
  """

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Events
  alias LemmingsOs.Events.Event
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.SecretBank.Secret
  alias LemmingsOs.Worlds.World

  @secret_ref_prefix "$"
  @bank_key_pattern ~r/^[A-Z_][A-Z0-9_]*$/
  @secret_event_types ~w(
    secret.created
    secret.replaced
    secret.deleted
    secret.resolved
    secret.resolve_failed
    secret.used_by_tool
  )

  @type metadata :: %{
          required(:bank_key) => String.t(),
          required(:scope) => String.t(),
          required(:source) => String.t(),
          required(:configured) => boolean(),
          required(:inserted_at) => DateTime.t() | nil,
          required(:updated_at) => DateTime.t() | nil,
          required(:allowed_actions) => [String.t()]
        }

  @type activity :: %{
          required(:id) => Ecto.UUID.t(),
          required(:event_type) => String.t(),
          required(:occurred_at) => DateTime.t(),
          required(:message) => String.t(),
          required(:scope) => String.t(),
          required(:payload) => map()
        }

  @type runtime_secret :: %{
          required(:bank_key) => String.t(),
          required(:value) => String.t(),
          required(:scope) => String.t(),
          required(:source) => String.t()
        }

  @type env_fallback_policy :: %{
          required(:bank_key) => String.t(),
          required(:env_var) => String.t(),
          required(:mapping_kind) => String.t(),
          required(:allowlisted) => boolean()
        }

  @doc """
  Creates or updates a local encrypted secret at the exact scope.

  ## Examples

      iex> world = %LemmingsOs.Worlds.World{id: "world-1"}
      iex> LemmingsOs.SecretBank.upsert_secret(world, "", "x")
      {:error, :invalid_key}
  """
  @spec upsert_secret(World.t() | City.t() | Department.t() | Lemming.t(), String.t(), String.t()) ::
          {:ok, metadata()} | {:error, Ecto.Changeset.t() | atom()}
  def upsert_secret(scope, key_or_ref, value) do
    with {:ok, scope_data} <- raw_scope_data(scope),
         {:ok, bank_key} <- normalize_key(key_or_ref),
         {:ok, value} <- normalize_string(value),
         :ok <- validate_scope_consistency(scope_data) do
      case get_local_secret(scope_data, bank_key) do
        {:ok, %Secret{} = secret} ->
          secret
          |> Secret.changeset(%{bank_key: bank_key, value: value})
          |> audited_secret_write(scope_data, "secret.replaced")

        {:error, :not_found} ->
          %Secret{}
          |> struct(scope_data)
          |> Secret.changeset(%{bank_key: bank_key, value: value})
          |> audited_secret_write(scope_data, "secret.created")
      end
    end
  end

  @doc """
  Deletes a local secret at the exact scope.

  Returns `{:error, :inherited_secret_not_deletable}` when the effective key is
  inherited from parent scope or environment fallback.

  ## Examples

      iex> world = %LemmingsOs.Worlds.World{id: "world-1"}
      iex> LemmingsOs.SecretBank.delete_secret(world, "")
      {:error, :invalid_key}
  """
  @spec delete_secret(World.t() | City.t() | Department.t() | Lemming.t(), String.t()) ::
          {:ok, metadata()} | {:error, atom()}
  def delete_secret(scope, key_or_ref) do
    with {:ok, scope_data} <- raw_scope_data(scope),
         {:ok, bank_key} <- normalize_key(key_or_ref),
         :ok <- validate_scope_consistency(scope_data) do
      delete_local_secret(scope, scope_data, bank_key)
    end
  end

  @doc """
  Lists safe effective metadata for the given scope.

  Optionally accepts `bank_key:` in `opts`.

  ## Examples

      iex> LemmingsOs.SecretBank.list_effective_metadata(%{})
      {:error, :invalid_scope}
  """
  @spec list_effective_metadata(World.t() | City.t() | Department.t() | Lemming.t(), keyword()) ::
          [metadata()] | {:error, :invalid_scope | :scope_mismatch}
  def list_effective_metadata(scope, opts \\ []) when is_list(opts) do
    case scope_chain(scope) do
      {:ok, chain} ->
        key_filter = key_filter(opts)
        locals = effective_local_metadata(chain, key_filter)
        env = effective_env_metadata(locals, key_filter)

        (locals ++ env)
        |> Enum.sort_by(& &1.bank_key)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists recent durable Secret Bank activity relevant to a scope.

  Options:
  - `:event_types` defaults to Secret Bank event types
  - `:limit` defaults to `25`
  """
  @spec list_recent_activity(World.t() | City.t() | Department.t() | Lemming.t(), keyword()) ::
          [activity()] | {:error, :invalid_scope | :scope_mismatch}
  def list_recent_activity(scope, opts \\ []) when is_list(opts) do
    event_types = Keyword.get(opts, :event_types, @secret_event_types)
    limit = Keyword.get(opts, :limit, 25)

    case scope_data(scope) do
      {:ok, scope_data} ->
        scope_data
        |> Events.list_recent_events(event_types: event_types, limit: limit)
        |> Enum.map(&to_activity/1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists configured environment fallback mappings as read-only safe metadata.

  Entries distinguish convention-derived mappings from explicit overrides and
  indicate whether each env var is present in `allowed_env_vars`.
  """
  @spec list_env_fallback_policy() :: [env_fallback_policy()]
  def list_env_fallback_policy do
    env_fallback_entries()
    |> Enum.sort_by(& &1.bank_key)
  end

  @doc """
  Resolves one secret key for trusted runtime usage.

  Accepts either a normalized key (for example `"GITHUB_TOKEN"`) or a secret
  reference (for example `"$GITHUB_TOKEN"`). Resolution order is:
  `lemming -> department -> city -> world -> env`.

  ## Examples

      iex> LemmingsOs.SecretBank.resolve_runtime_secret(%{}, "$UNKNOWN_KEY")
      {:error, :invalid_scope}
  """
  @spec resolve_runtime_secret(
          World.t() | City.t() | Department.t() | Lemming.t(),
          String.t(),
          keyword()
        ) ::
          {:ok, runtime_secret()}
          | {:error,
             :invalid_scope | :scope_mismatch | :invalid_key | :missing_secret | :decrypt_failed}
  def resolve_runtime_secret(scope, key_or_ref, opts \\ []) when is_list(opts) do
    with {:ok, chain} <- scope_chain(scope),
         {:ok, bank_key} <- normalize_key(key_or_ref) do
      resolve_runtime_secret_from_chain(chain, bank_key, key_or_ref, opts)
    else
      {:error, :invalid_key} = error ->
        maybe_record_access_failed(scope, key_or_ref, :invalid_key, opts)
        error

      {:error, reason} = error ->
        maybe_record_access_failed(scope, key_or_ref, reason, opts)
        error
    end
  end

  defp resolve_runtime_secret_from_chain(chain, bank_key, key_or_ref, opts) do
    with {:error, :not_found} <- resolve_local_runtime_secret(chain, bank_key),
         {:ok, env_var} <- configured_env_var(bank_key),
         {:ok, value} <- env_value(env_var) do
      runtime_secret = %{bank_key: bank_key, value: value, scope: "env", source: "env"}
      record_resolved_event(chain, runtime_secret)
      {:ok, runtime_secret}
    else
      {:ok, %{} = runtime_secret} ->
        record_resolved_event(chain, runtime_secret)
        {:ok, runtime_secret}

      {:error, :not_found} ->
        record_access_failed_event(chain, bank_key, key_or_ref, :missing_secret, opts)
        {:error, :missing_secret}

      {:error, reason} ->
        record_access_failed_event(chain, bank_key, key_or_ref, reason, opts)
        {:error, reason}
    end
  end

  defp resolve_local_runtime_secret([], _bank_key), do: {:error, :not_found}

  defp resolve_local_runtime_secret([scope_data | rest], bank_key) do
    with {:ok, %Secret{} = secret} <- get_runtime_local_secret(scope_data, bank_key),
         {:ok, %{} = runtime_secret} <- local_runtime_secret(secret, scope_data) do
      {:ok, runtime_secret}
    else
      {:error, :not_found} ->
        resolve_local_runtime_secret(rest, bank_key)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp local_runtime_secret(%Secret{bank_key: bank_key, value: value}, scope_data) do
    with {:ok, runtime_value} <- local_runtime_value(value) do
      {:ok,
       %{
         bank_key: bank_key,
         value: runtime_value,
         scope: scope_name(scope_data),
         source: "local"
       }}
    end
  end

  defp get_runtime_local_secret(scope_data, bank_key) do
    scope_data
    |> local_secret_query(bank_key)
    |> Repo.one()
    |> normalize_runtime_local_secret()
  rescue
    _error -> {:error, :decrypt_failed}
  end

  defp normalize_runtime_local_secret(%Secret{} = secret), do: {:ok, secret}
  defp normalize_runtime_local_secret(nil), do: {:error, :not_found}

  defp env_value(env_var) when is_binary(env_var) do
    case System.get_env(env_var) do
      nil -> {:error, :not_found}
      "" -> {:error, :not_found}
      value -> {:ok, value}
    end
  end

  defp local_runtime_value(value) when is_binary(value) and value != "", do: {:ok, value}
  defp local_runtime_value(_value), do: {:error, :decrypt_failed}

  defp audited_secret_write(changeset, scope_data, event_type) do
    Repo.transaction(fn ->
      changeset
      |> Repo.insert_or_update()
      |> metadata_write_result(scope_data, event_type)
      |> case do
        {:ok, metadata} -> metadata
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> transaction_result()
  end

  defp metadata_write_result({:ok, %Secret{} = secret}, scope_data, event_type) do
    metadata = to_local_metadata(secret, scope_data)

    case record_secret_event(
           event_type,
           scope_data,
           secret_message(secret.bank_key, event_type),
           %{
             secret_ref: to_secret_ref(secret.bank_key),
             bank_key: secret.bank_key,
             scope: metadata.scope,
             source: metadata.source
           }
         ) do
      {:ok, _event} -> {:ok, metadata}
      {:error, reason} -> {:error, {:audit_event_failed, reason}}
    end
  end

  defp metadata_write_result({:error, %Changeset{} = changeset}, _scope_data, _event_type),
    do: {:error, changeset}

  defp delete_local_secret(scope, scope_data, bank_key),
    do:
      delete_local_secret(
        scope,
        scope_data,
        bank_key,
        local_metadata_for_scope(scope_data, bank_key)
      )

  defp delete_local_secret(_scope, scope_data, bank_key, metadata) when not is_nil(metadata) do
    Repo.transaction(fn ->
      Secret
      |> filter_query(scope_filters(scope_data, bank_key))
      |> Repo.delete_all()
      |> audited_secret_delete_result(scope_data, bank_key, metadata)
    end)
    |> transaction_result()
  end

  defp delete_local_secret(scope, _scope_data, bank_key, nil),
    do: delete_missing_local_secret(list_effective_metadata(scope, bank_key: bank_key))

  defp delete_missing_local_secret({:error, reason}), do: {:error, reason}

  defp delete_missing_local_secret([]), do: {:error, :not_found}

  defp delete_missing_local_secret([_metadata | _rest]),
    do: {:error, :inherited_secret_not_deletable}

  defp audited_secret_delete_result({1, _rows}, scope_data, bank_key, metadata) do
    case record_secret_event(
           "secret.deleted",
           scope_data,
           secret_message(bank_key, "secret.deleted"),
           %{
             secret_ref: to_secret_ref(bank_key),
             bank_key: bank_key,
             scope: metadata.scope,
             source: metadata.source
           }
         ) do
      {:ok, _event} -> metadata
      {:error, reason} -> Repo.rollback({:audit_event_failed, reason})
    end
  end

  defp audited_secret_delete_result({_count, _rows}, _scope_data, _bank_key, _metadata),
    do: Repo.rollback(:not_found)

  defp local_metadata_for_scope(scope_data, bank_key) do
    Secret
    |> filter_query(scope_filters(scope_data, bank_key))
    |> select_metadata_rows()
    |> Repo.one()
    |> row_to_metadata(scope_data)
  end

  defp get_local_secret(scope_data, bank_key) do
    scope_data
    |> local_secret_query(bank_key)
    |> Repo.one()
    |> case do
      %Secret{} = secret -> {:ok, secret}
      nil -> {:error, :not_found}
    end
  end

  defp local_secret_query(scope_data, bank_key) do
    Secret
    |> filter_query(scope_filters(scope_data, bank_key))
  end

  defp effective_local_metadata([%{world_id: world_id} | _] = chain, key_filter) do
    Secret
    |> filter_query([{:world_id, world_id}])
    |> filter_query(key_filter)
    |> select_metadata_rows()
    |> Repo.all()
    |> pick_effective_rows(chain, List.first(chain), [])
  end

  defp pick_effective_rows(_rows, [], _requested_scope, picked), do: Enum.reverse(picked)

  defp pick_effective_rows(rows, [scope_data | rest], requested_scope, picked) do
    existing_keys = MapSet.new(picked, & &1.bank_key)

    new_rows =
      rows
      |> Enum.filter(&row_matches_scope?(&1, scope_data))
      |> Enum.reject(&MapSet.member?(existing_keys, &1.bank_key))
      |> Enum.map(&row_to_metadata(&1, requested_scope))

    pick_effective_rows(rows, rest, requested_scope, new_rows ++ picked)
  end

  defp effective_env_metadata(locals, [{:bank_key, bank_key}]) do
    if MapSet.member?(MapSet.new(locals, & &1.bank_key), bank_key) do
      []
    else
      case configured_env_var(bank_key) do
        {:ok, env_var} -> [env_metadata(bank_key, env_var)]
        {:error, _reason} -> []
      end
    end
  end

  defp effective_env_metadata(locals, []) do
    local_keys = MapSet.new(locals, & &1.bank_key)

    configured_env_fallbacks()
    |> Enum.reject(fn {bank_key, _env_var} -> MapSet.member?(local_keys, bank_key) end)
    |> Enum.map(fn {bank_key, env_var} -> env_metadata(bank_key, env_var) end)
  end

  defp env_metadata(bank_key, env_var) do
    %{
      bank_key: bank_key,
      scope: "env",
      source: "env",
      configured: env_var_present?(env_var),
      inserted_at: nil,
      updated_at: nil,
      allowed_actions: ["upsert"]
    }
  end

  defp to_local_metadata(%Secret{} = secret, requested_scope) do
    %{
      bank_key: secret.bank_key,
      world_id: secret.world_id,
      city_id: secret.city_id,
      department_id: secret.department_id,
      lemming_id: secret.lemming_id,
      inserted_at: secret.inserted_at,
      updated_at: secret.updated_at
    }
    |> row_to_metadata(requested_scope)
  end

  defp row_to_metadata(nil, _requested_scope), do: nil

  defp row_to_metadata(row, requested_scope) do
    exact? = row_matches_scope?(row, requested_scope)

    %{
      bank_key: row.bank_key,
      scope: scope_name(row),
      source: "local",
      configured: true,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at,
      allowed_actions: if(exact?, do: ["upsert", "delete"], else: ["upsert"])
    }
  end

  defp select_metadata_rows(query) do
    select(query, [secret], %{
      bank_key: secret.bank_key,
      world_id: secret.world_id,
      city_id: secret.city_id,
      department_id: secret.department_id,
      lemming_id: secret.lemming_id,
      inserted_at: secret.inserted_at,
      updated_at: secret.updated_at
    })
  end

  defp scope_data(scope) do
    with {:ok, scope_data} <- raw_scope_data(scope),
         :ok <- validate_scope_consistency(scope_data) do
      {:ok, scope_data}
    end
  end

  defp raw_scope_data(%World{id: world_id}) when is_binary(world_id),
    do: {:ok, %{world_id: world_id, city_id: nil, department_id: nil, lemming_id: nil}}

  defp raw_scope_data(%City{id: city_id, world_id: world_id})
       when is_binary(world_id) and is_binary(city_id),
       do: {:ok, %{world_id: world_id, city_id: city_id, department_id: nil, lemming_id: nil}}

  defp raw_scope_data(%Department{id: department_id, world_id: world_id, city_id: city_id})
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) do
    {:ok,
     %{
       world_id: world_id,
       city_id: city_id,
       department_id: department_id,
       lemming_id: nil
     }}
  end

  defp raw_scope_data(%Lemming{
         id: lemming_id,
         world_id: world_id,
         city_id: city_id,
         department_id: department_id
       })
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
              is_binary(lemming_id) do
    {:ok,
     %{
       world_id: world_id,
       city_id: city_id,
       department_id: department_id,
       lemming_id: lemming_id
     }}
  end

  defp raw_scope_data(_scope), do: {:error, :invalid_scope}

  defp validate_scope_consistency(%{
         world_id: world_id,
         city_id: nil,
         department_id: nil,
         lemming_id: nil
       })
       when is_binary(world_id) do
    World
    |> where([world], world.id == ^world_id)
    |> Repo.exists?()
    |> scope_consistency_result()
  end

  defp validate_scope_consistency(%{
         world_id: world_id,
         city_id: city_id,
         department_id: nil,
         lemming_id: nil
       }) do
    City
    |> where([city], city.id == ^city_id and city.world_id == ^world_id)
    |> Repo.exists?()
    |> scope_consistency_result()
  end

  defp validate_scope_consistency(%{
         world_id: world_id,
         city_id: city_id,
         department_id: department_id,
         lemming_id: nil
       }) do
    Department
    |> join(:inner, [department], city in City, on: city.id == department.city_id)
    |> where(
      [department, city],
      department.id == ^department_id and department.world_id == ^world_id and
        department.city_id == ^city_id and city.world_id == ^world_id
    )
    |> Repo.exists?()
    |> scope_consistency_result()
  end

  defp validate_scope_consistency(%{
         world_id: world_id,
         city_id: city_id,
         department_id: department_id,
         lemming_id: lemming_id
       }) do
    Lemming
    |> join(:inner, [lemming], department in Department,
      on: department.id == lemming.department_id
    )
    |> join(:inner, [lemming, department], city in City, on: city.id == lemming.city_id)
    |> where(
      [lemming, department, city],
      lemming.id == ^lemming_id and lemming.world_id == ^world_id and
        lemming.city_id == ^city_id and lemming.department_id == ^department_id and
        department.world_id == ^world_id and department.city_id == ^city_id and
        city.world_id == ^world_id
    )
    |> Repo.exists?()
    |> scope_consistency_result()
  end

  defp scope_consistency_result(true), do: :ok
  defp scope_consistency_result(false), do: {:error, :scope_mismatch}

  defp scope_chain(scope) do
    case scope_data(scope) do
      {:ok, %{city_id: city_id, department_id: department_id, lemming_id: lemming_id} = data}
      when is_binary(city_id) and is_binary(department_id) and is_binary(lemming_id) ->
        {:ok,
         [
           data,
           %{data | lemming_id: nil},
           %{data | department_id: nil, lemming_id: nil},
           %{data | city_id: nil, department_id: nil, lemming_id: nil}
         ]}

      {:ok, %{city_id: city_id, department_id: department_id, lemming_id: nil} = data}
      when is_binary(city_id) and is_binary(department_id) ->
        {:ok,
         [
           data,
           %{data | department_id: nil},
           %{data | city_id: nil, department_id: nil}
         ]}

      {:ok, %{city_id: city_id, department_id: nil, lemming_id: nil} = data}
      when is_binary(city_id) ->
        {:ok, [data, %{data | city_id: nil}]}

      {:ok, %{city_id: nil, department_id: nil, lemming_id: nil} = data} ->
        {:ok, [data]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp scope_name(%{city_id: nil, department_id: nil, lemming_id: nil}), do: "world"
  defp scope_name(%{department_id: nil, lemming_id: nil}), do: "city"
  defp scope_name(%{lemming_id: nil}), do: "department"
  defp scope_name(_row), do: "lemming"

  defp row_matches_scope?(row, scope_data) do
    row.world_id == scope_data.world_id and row.city_id == scope_data.city_id and
      row.department_id == scope_data.department_id and row.lemming_id == scope_data.lemming_id
  end

  defp scope_filters(scope_data, bank_key) do
    [
      {:world_id, scope_data.world_id},
      {:city_id, scope_data.city_id},
      {:department_id, scope_data.department_id},
      {:lemming_id, scope_data.lemming_id},
      {:bank_key, bank_key}
    ]
  end

  defp key_filter(opts) do
    case Keyword.fetch(opts, :bank_key) do
      {:ok, key_or_ref} ->
        case normalize_key(key_or_ref) do
          {:ok, key} -> [{:bank_key, key}]
          {:error, _reason} -> [{:bank_key, "__missing__"}]
        end

      :error ->
        []
    end
  end

  defp normalize_key(key_or_ref) when is_binary(key_or_ref) do
    key_or_ref
    |> String.trim()
    |> normalize_key_candidate()
    |> valid_bank_key()
  end

  defp normalize_key(_key_or_ref), do: {:error, :invalid_key}

  defp normalize_string(value) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, :invalid_value}
    else
      {:ok, value}
    end
  end

  defp normalize_string(_value), do: {:error, :invalid_value}

  defp normalize_key_candidate("$secrets." <> _legacy), do: "__invalid__"

  defp normalize_key_candidate("$" <> value) do
    case value do
      "{" <> wrapped -> String.trim_trailing(wrapped, "}")
      _other -> value
    end
  end

  defp normalize_key_candidate(value), do: value

  defp valid_bank_key(""), do: {:error, :invalid_key}

  defp valid_bank_key(value) do
    if String.match?(value, @bank_key_pattern), do: {:ok, value}, else: {:error, :invalid_key}
  end

  defp configured_env_var(bank_key) do
    configured_env_fallbacks()
    |> Map.new()
    |> Map.fetch(bank_key)
    |> case do
      {:ok, env_var} -> {:ok, env_var}
      :error -> {:error, :not_found}
    end
  end

  defp configured_env_fallbacks do
    env_fallback_entries()
    |> Enum.filter(& &1.allowlisted)
    |> Enum.map(fn entry -> {entry.bank_key, entry.env_var} end)
  end

  defp env_fallback_entries do
    allowed_envs = allowed_env_vars()

    :lemmings_os
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:env_fallbacks, [])
    |> Enum.reduce(%{}, fn fallback, entries ->
      case normalize_env_fallback_entry(fallback, allowed_envs) do
        {:ok, entry} -> Map.put(entries, entry.bank_key, entry)
        :error -> entries
      end
    end)
    |> Map.values()
  end

  defp normalize_env_fallback_entry({bank_key, env_var}, allowed_envs)
       when is_binary(bank_key) and is_binary(env_var) do
    case normalize_key(bank_key) do
      {:ok, key} ->
        normalized_env_var = normalize_env_name(env_var)

        {:ok,
         %{
           bank_key: key,
           env_var: normalized_env_var,
           mapping_kind: "explicit_override",
           allowlisted: MapSet.member?(allowed_envs, normalized_env_var)
         }}

      {:error, _reason} ->
        :error
    end
  end

  defp normalize_env_fallback_entry(bank_key, allowed_envs) when is_binary(bank_key) do
    case normalize_key(bank_key) do
      {:ok, key} ->
        derived_env_var = derive_env_var(key)

        {:ok,
         %{
           bank_key: key,
           env_var: derived_env_var,
           mapping_kind: "convention",
           allowlisted: MapSet.member?(allowed_envs, derived_env_var)
         }}

      {:error, _reason} ->
        :error
    end
  end

  defp normalize_env_fallback_entry(_fallback, _allowed_envs), do: :error

  # Small string helper for env names:
  # - accepts `GITHUB_TOKEN`, `$GITHUB_TOKEN`, or `${GITHUB_TOKEN}`
  # - stores canonical env var names without `$`
  defp normalize_env_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_leading("$")
    |> String.trim_leading("{")
    |> String.trim_trailing("}")
    |> String.replace(" ", "")
    |> String.upcase()
  end

  defp derive_env_var(bank_key) do
    bank_key
    |> normalize_env_name()
  end

  defp env_var_present?(env_var),
    do: env_var_allowed?(env_var) and System.get_env(env_var) not in [nil, ""]

  defp env_var_allowed?(env_var), do: MapSet.member?(allowed_env_vars(), env_var)

  defp allowed_env_vars do
    :lemmings_os
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:allowed_env_vars, [])
    |> Enum.flat_map(fn
      value when is_binary(value) ->
        [normalize_env_name(value)]

      _other ->
        []
    end)
    |> MapSet.new()
  end

  defp filter_query(query, [{:world_id, world_id} | rest]),
    do: filter_query(from(secret in query, where: secret.world_id == ^world_id), rest)

  defp filter_query(query, [{:city_id, nil} | rest]),
    do: filter_query(from(secret in query, where: is_nil(secret.city_id)), rest)

  defp filter_query(query, [{:city_id, city_id} | rest]),
    do: filter_query(from(secret in query, where: secret.city_id == ^city_id), rest)

  defp filter_query(query, [{:department_id, nil} | rest]),
    do: filter_query(from(secret in query, where: is_nil(secret.department_id)), rest)

  defp filter_query(query, [{:department_id, department_id} | rest]),
    do: filter_query(from(secret in query, where: secret.department_id == ^department_id), rest)

  defp filter_query(query, [{:lemming_id, nil} | rest]),
    do: filter_query(from(secret in query, where: is_nil(secret.lemming_id)), rest)

  defp filter_query(query, [{:lemming_id, lemming_id} | rest]),
    do: filter_query(from(secret in query, where: secret.lemming_id == ^lemming_id), rest)

  defp filter_query(query, [{:bank_key, bank_key} | rest]),
    do: filter_query(from(secret in query, where: secret.bank_key == ^bank_key), rest)

  defp filter_query(query, [_unknown | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query

  defp maybe_record_access_failed(scope, key_or_ref, reason, opts) do
    case scope_data(scope) do
      {:ok, %{world_id: _world_id} = scope_data} ->
        record_access_failed_event([scope_data], nil, key_or_ref, reason, opts)

      {:error, _reason} ->
        :ok
    end
  end

  defp record_resolved_event([requested_scope | _rest], runtime_secret) do
    bank_key = runtime_secret.bank_key

    record_secret_event(
      "secret.resolved",
      requested_scope,
      resolved_message(bank_key),
      resolved_payload(bank_key, requested_scope, runtime_secret.scope)
    )
  end

  defp record_access_failed_event([requested_scope | _rest], bank_key, key_or_ref, reason, _opts) do
    safe_key = bank_key || normalized_key(key_or_ref)

    record_secret_event(
      "secret.resolve_failed",
      requested_scope,
      failed_message(safe_key),
      resolve_failed_payload(safe_key, requested_scope, reason)
    )
  end

  defp resolved_payload(bank_key, requested_scope, resolved_source) do
    %{
      key: bank_key,
      requested_scope: safe_scope_payload(requested_scope),
      resolved_source: resolved_source
    }
  end

  defp resolve_failed_payload(bank_key, requested_scope, reason) do
    %{
      key: bank_key,
      requested_scope: safe_scope_payload(requested_scope),
      reason: safe_reason(reason)
    }
  end

  defp safe_scope_payload(scope_data) when is_map(scope_data) do
    scope_data
    |> Map.take([:world_id, :city_id, :department_id, :lemming_id])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp safe_reason(reason)
       when reason in [
              :invalid_scope,
              :scope_mismatch,
              :invalid_key,
              :missing_secret,
              :decrypt_failed,
              :not_found
            ],
       do: Atom.to_string(reason)

  defp safe_reason(_reason), do: "unknown"

  defp record_secret_event(event_type, scope_data, message, payload) do
    sanitized_payload =
      payload
      |> Map.merge(safe_scope_payload(scope_data))
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Events.record_event(event_type, scope_data, message,
      payload: sanitized_payload,
      event_family: "audit",
      action: event_action(event_type),
      status: event_status(event_type),
      resource_type: "secret",
      resource_id: Map.get(sanitized_payload, :bank_key) || Map.get(sanitized_payload, :key)
    )
  end

  defp transaction_result({:ok, metadata}), do: {:ok, metadata}
  defp transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp transaction_result({:error, {:audit_event_failed, _reason}}),
    do: {:error, :audit_event_failed}

  defp transaction_result({:error, reason}) when is_atom(reason), do: {:error, reason}
  defp transaction_result({:error, _reason}), do: {:error, :audit_event_failed}

  defp event_action("secret.created"), do: "create"
  defp event_action("secret.replaced"), do: "replace"
  defp event_action("secret.deleted"), do: "delete"
  defp event_action("secret.resolved"), do: "resolve"
  defp event_action("secret.resolve_failed"), do: "resolve"

  defp event_status("secret.resolve_failed"), do: "failed"
  defp event_status(_event_type), do: "succeeded"

  defp secret_message(bank_key, "secret.created"), do: "#{bank_key} created"
  defp secret_message(bank_key, "secret.replaced"), do: "#{bank_key} replaced"
  defp secret_message(bank_key, "secret.deleted"), do: "#{bank_key} deleted"

  defp resolved_message(bank_key), do: "#{bank_key} resolved"

  defp failed_message(bank_key) when is_binary(bank_key) and bank_key != "",
    do: "#{bank_key} resolve failed"

  defp failed_message(_bank_key), do: "secret resolve failed"

  defp normalized_key(key_or_ref) when is_binary(key_or_ref) do
    case normalize_key(key_or_ref) do
      {:ok, bank_key} -> bank_key
      {:error, _reason} -> nil
    end
  end

  defp normalized_key(_key_or_ref), do: nil

  defp to_secret_ref(bank_key) when is_binary(bank_key) and bank_key != "",
    do: "#{@secret_ref_prefix}#{bank_key}"

  defp to_activity(%Event{} = event) do
    %{
      id: event.id,
      event_type: event.event_type,
      occurred_at: event.occurred_at,
      message: event.message,
      scope:
        scope_name(%{
          city_id: event.city_id,
          department_id: event.department_id,
          lemming_id: event.lemming_id
        }),
      payload: event.payload || %{}
    }
  end
end
