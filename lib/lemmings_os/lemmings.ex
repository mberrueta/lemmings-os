defmodule LemmingsOs.Lemmings do
  @moduledoc """
  Lemming domain boundary.

  This context owns persisted Lemming retrieval, hierarchy-scoped collection
  APIs, lifecycle transitions, and delete guardrails.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Helpers
  alias LemmingsOs.Lemmings.DeleteDeniedError
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @doc """
  Returns persisted lemmings for the given hierarchy scope.

  Accepts `%World{}`, `%City{}`, or `%Department{}` and an optional keyword list
  for filtering and explicit preloads.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> LemmingsOs.Factory.insert(:lemming, world: world, city: city, department: department, status: "active")
      iex> [%LemmingsOs.Lemmings.Lemming{}] = LemmingsOs.Lemmings.list_lemmings(department)
  """
  @spec list_lemmings(World.t() | City.t() | Department.t(), keyword()) :: [Lemming.t()]
  def list_lemmings(scope, opts \\ [])

  def list_lemmings(%World{id: world_id}, opts) when is_binary(world_id) and is_list(opts) do
    Lemming
    |> filter_query([{:world_id, world_id} | opts])
    |> order_by([lemming], asc: lemming.name, asc: lemming.slug)
    |> Repo.all()
  end

  def list_lemmings(%City{id: city_id}, opts) when is_binary(city_id) and is_list(opts) do
    Lemming
    |> filter_query([{:city_id, city_id} | opts])
    |> order_by([lemming], asc: lemming.name, asc: lemming.slug)
    |> Repo.all()
  end

  def list_lemmings(%Department{id: department_id}, opts)
      when is_binary(department_id) and is_list(opts) do
    Lemming
    |> filter_query([{:department_id, department_id} | opts])
    |> order_by([lemming], asc: lemming.name, asc: lemming.slug)
    |> Repo.all()
  end

  @doc """
  Returns the Lemming for the given persisted ID, or `nil`.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> lemming = LemmingsOs.Factory.insert(:lemming, world: world, city: city, department: department)
      iex> %LemmingsOs.Lemmings.Lemming{id: id} = LemmingsOs.Lemmings.get_lemming(lemming.id)
      iex> id
      lemming.id
  """
  @spec get_lemming(Ecto.UUID.t(), keyword()) :: Lemming.t() | nil
  def get_lemming(id, opts \\ [])

  def get_lemming(id, opts) when is_binary(id) and is_list(opts) do
    Lemming
    |> where([lemming], lemming.id == ^id)
    |> filter_query(opts)
    |> Repo.one()
  end

  @doc """
  Returns the Department-scoped Lemming for the given slug, or `nil`.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> lemming = LemmingsOs.Factory.insert(:lemming, world: department.world, city: department.city, department: department, slug: "code-reviewer")
      iex> %LemmingsOs.Lemmings.Lemming{id: id, slug: "code-reviewer"} =
      ...>   LemmingsOs.Lemmings.get_lemming_by_slug(department, "code-reviewer")
      iex> id
      lemming.id
  """
  @spec get_lemming_by_slug(Department.t(), String.t()) :: Lemming.t() | nil
  def get_lemming_by_slug(%Department{id: department_id}, slug)
      when is_binary(department_id) and is_binary(slug) do
    Lemming
    |> where([lemming], lemming.department_id == ^department_id and lemming.slug == ^slug)
    |> Repo.one()
  end

  @doc """
  Creates a Lemming scoped to the given World, City, and Department.

  Returns `{:error, :department_not_in_city_world}` when the supplied
  Department does not belong to the supplied City and World scope.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> {:ok, %LemmingsOs.Lemmings.Lemming{world_id: world_id, city_id: city_id, department_id: department_id}} =
      ...>   LemmingsOs.Lemmings.create_lemming(world, city, department, %{slug: "code-reviewer", name: "Code Reviewer", status: "draft"})
      iex> {world_id, city_id, department_id}
      {world.id, city.id, department.id}
  """
  @spec create_lemming(
          World.t(),
          City.t(),
          Department.t(),
          map()
        ) ::
          {:ok, Lemming.t()} | {:error, Ecto.Changeset.t() | :department_not_in_city_world}
  def create_lemming(
        %World{id: world_id},
        %City{id: city_id} = city,
        %Department{id: department_id} = department,
        attrs
      )
      when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
             is_map(attrs) do
    with :ok <- validate_city_in_world(world_id, city),
         :ok <- validate_department_in_city_world(world_id, city_id, department) do
      %Lemming{world_id: world_id, city_id: city_id, department_id: department_id}
      |> Lemming.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates a persisted Lemming through the operator-facing CRUD contract.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> lemming = LemmingsOs.Factory.insert(:lemming, world: world, city: city, department: department, name: "Before")
      iex> {:ok, %LemmingsOs.Lemmings.Lemming{name: name}} =
      ...>   LemmingsOs.Lemmings.update_lemming(lemming, %{name: "After"})
      iex> name
      "After"
  """
  @spec update_lemming(Lemming.t(), map()) :: {:ok, Lemming.t()} | {:error, Ecto.Changeset.t()}
  def update_lemming(%Lemming{} = lemming, attrs) when is_map(attrs) do
    lemming
    |> Lemming.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a persisted Lemming record when safe removal can be proven.

  This implementation is intentionally conservative. In the current project
  slice there is no runtime-backed signal that can prove the Lemming definition
  is safe to remove, so hard deletion is always denied.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> lemming = LemmingsOs.Factory.insert(:lemming, world: world, city: city, department: department)
      iex> {:error, %LemmingsOs.Lemmings.DeleteDeniedError{reason: :safety_indeterminate}} =
      ...>   LemmingsOs.Lemmings.delete_lemming(lemming)
  """
  @spec delete_lemming(Lemming.t()) :: {:ok, Lemming.t()} | {:error, DeleteDeniedError.t()}
  def delete_lemming(%Lemming{id: id}) do
    {:error, %DeleteDeniedError{lemming_id: id, reason: :safety_indeterminate}}
  end

  @doc """
  Transitions a Lemming to a new lifecycle status.

  Returns `{:error, :instructions_required}` when the target status is `active`
  and `instructions` is nil or blank.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> lemming = LemmingsOs.Factory.insert(:lemming, world: world, city: city, department: department, status: "draft")
      iex> {:ok, %LemmingsOs.Lemmings.Lemming{status: status}} = LemmingsOs.Lemmings.set_lemming_status(lemming, "archived")
      iex> status
      "archived"
  """
  @spec set_lemming_status(Lemming.t(), String.t()) ::
          {:ok, Lemming.t()} | {:error, :instructions_required | Ecto.Changeset.t()}
  def set_lemming_status(%Lemming{instructions: nil}, "active"),
    do: {:error, :instructions_required}

  def set_lemming_status(%Lemming{instructions: ""}, "active"),
    do: {:error, :instructions_required}

  def set_lemming_status(%Lemming{instructions: instructions} = lemming, "active")
      when is_binary(instructions) do
    if Helpers.blank?(instructions) do
      {:error, :instructions_required}
    else
      update_lemming(lemming, %{status: "active"})
    end
  end

  def set_lemming_status(%Lemming{} = lemming, status) when is_binary(status) do
    update_lemming(lemming, %{status: status})
  end

  @doc """
  Returns aggregate persisted Lemming counts for a World.

  The summary is intentionally narrow and query-efficient for operator-facing
  topology cards.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> LemmingsOs.Factory.insert(:lemming, world: world, city: city, department: department, status: "active")
      iex> summary = LemmingsOs.Lemmings.topology_summary(world)
      iex> summary.active_lemming_count
      1
  """
  @spec topology_summary(World.t()) :: %{
          lemming_count: non_neg_integer(),
          active_lemming_count: non_neg_integer()
        }
  def topology_summary(%World{id: world_id}) when is_binary(world_id) do
    Lemming
    |> where([lemming], lemming.world_id == ^world_id)
    |> select([lemming], %{
      lemming_count: count(lemming.id),
      active_lemming_count:
        sum(fragment("CASE WHEN ? = 'active' THEN 1 ELSE 0 END", lemming.status))
    })
    |> Repo.one()
    |> normalize_topology_summary()
  end

  defp validate_city_in_world(world_id, %City{world_id: world_id}), do: :ok
  defp validate_city_in_world(_world_id, %City{}), do: {:error, :department_not_in_city_world}

  defp validate_department_in_city_world(
         world_id,
         city_id,
         %Department{world_id: world_id, city_id: city_id}
       ),
       do: :ok

  defp validate_department_in_city_world(_world_id, _city_id, %Department{}),
    do: {:error, :department_not_in_city_world}

  defp normalize_topology_summary(nil), do: %{lemming_count: 0, active_lemming_count: 0}

  defp normalize_topology_summary(summary) do
    %{
      lemming_count: summary.lemming_count || 0,
      active_lemming_count: summary.active_lemming_count || 0
    }
  end

  defp filter_query(query, [{:world_id, world_id} | rest]),
    do: filter_query(from(lemming in query, where: lemming.world_id == ^world_id), rest)

  defp filter_query(query, [{:city_id, city_id} | rest]),
    do: filter_query(from(lemming in query, where: lemming.city_id == ^city_id), rest)

  defp filter_query(query, [{:department_id, department_id} | rest]),
    do: filter_query(from(lemming in query, where: lemming.department_id == ^department_id), rest)

  defp filter_query(query, [{:status, status} | rest]),
    do: filter_query(from(lemming in query, where: lemming.status == ^status), rest)

  defp filter_query(query, [{:ids, ids} | rest]) when is_list(ids),
    do: filter_query(from(lemming in query, where: lemming.id in ^ids), rest)

  defp filter_query(query, [{:slug, slug} | rest]),
    do: filter_query(from(lemming in query, where: lemming.slug == ^slug), rest)

  defp filter_query(query, [{:preload, preloads} | rest]),
    do: filter_query(preload(query, ^preloads), rest)

  defp filter_query(query, [_ | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query
end
