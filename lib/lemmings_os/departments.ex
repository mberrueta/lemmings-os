defmodule LemmingsOs.Departments do
  @moduledoc """
  Department domain boundary.

  This context owns persisted Department retrieval, explicit World/City-scoped
  CRUD APIs, and lifecycle transitions.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.DeleteDeniedError
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @doc """
  Returns persisted departments for the given World and City scope.

  Accepts an optional keyword list for filtering and explicit preloads.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> LemmingsOs.Factory.insert(:department, world: world, city: city, status: "active")
      iex> [%LemmingsOs.Departments.Department{}] = LemmingsOs.Departments.list_departments(world, city)
  """
  @spec list_departments(World.t() | Ecto.UUID.t(), City.t() | Ecto.UUID.t(), keyword()) :: [
          Department.t()
        ]
  def list_departments(world_or_world_id, city_or_city_id, opts \\ []) do
    world_or_world_id
    |> departments_query(city_or_city_id, opts)
    |> Repo.all()
  end

  @doc """
  Fetches a Department by World/City-scoped persisted ID.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> {:ok, %LemmingsOs.Departments.Department{id: id}} =
      ...>   LemmingsOs.Departments.fetch_department(world, city, department.id)
      iex> id
      department.id
  """
  @spec fetch_department(World.t() | Ecto.UUID.t(), City.t() | Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Department.t()} | {:error, :not_found}
  def fetch_department(world_or_world_id, city_or_city_id, id)

  def fetch_department(%World{id: world_id}, %City{id: city_id}, id),
    do: fetch_department(world_id, city_id, id)

  def fetch_department(%World{id: world_id}, city_id, id) when is_binary(city_id),
    do: fetch_department(world_id, city_id, id)

  def fetch_department(world_id, %City{id: city_id}, id) when is_binary(world_id),
    do: fetch_department(world_id, city_id, id)

  def fetch_department(world_id, city_id, id)
      when is_binary(world_id) and is_binary(city_id) and is_binary(id) do
    Department
    |> where(
      [department],
      department.world_id == ^world_id and department.city_id == ^city_id and department.id == ^id
    )
    |> Repo.one()
    |> fetch_department_result()
  end

  @doc """
  Returns the Department for the given World/City-scoped persisted ID.

  Raises `Ecto.NoResultsError` if no Department exists in that scope.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> %LemmingsOs.Departments.Department{id: id} =
      ...>   LemmingsOs.Departments.get_department!(world, city, department.id)
      iex> id
      department.id
  """
  @spec get_department!(World.t() | Ecto.UUID.t(), City.t() | Ecto.UUID.t(), Ecto.UUID.t()) ::
          Department.t()
  def get_department!(world_or_world_id, city_or_city_id, id) do
    case fetch_department(world_or_world_id, city_or_city_id, id) do
      {:ok, department} -> department
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: Department
    end
  end

  @doc """
  Fetches a Department by City-scoped slug.

  ## Examples

      iex> city = LemmingsOs.Factory.insert(:city)
      iex> department = LemmingsOs.Factory.insert(:department, world: city.world, city: city, slug: "support")
      iex> {:ok, %LemmingsOs.Departments.Department{slug: "support", id: id}} =
      ...>   LemmingsOs.Departments.fetch_department_by_slug(city, "support")
      iex> id
      department.id
  """
  @spec fetch_department_by_slug(City.t() | Ecto.UUID.t(), String.t()) ::
          {:ok, Department.t()} | {:error, :not_found}
  def fetch_department_by_slug(city_or_city_id, slug)

  def fetch_department_by_slug(%City{id: city_id}, slug),
    do: fetch_department_by_slug(city_id, slug)

  def fetch_department_by_slug(city_id, slug) when is_binary(city_id) and is_binary(slug) do
    Department
    |> where([department], department.city_id == ^city_id and department.slug == ^slug)
    |> Repo.one()
    |> fetch_department_result()
  end

  @doc """
  Returns the Department for the given City-scoped slug.

  Raises `Ecto.NoResultsError` if no Department exists in that City scope.

  ## Examples

      iex> city = LemmingsOs.Factory.insert(:city)
      iex> department = LemmingsOs.Factory.insert(:department, world: city.world, city: city, slug: "support")
      iex> %LemmingsOs.Departments.Department{slug: "support", id: id} =
      ...>   LemmingsOs.Departments.get_department_by_slug!(city, "support")
      iex> id
      department.id
  """
  @spec get_department_by_slug!(City.t() | Ecto.UUID.t(), String.t()) :: Department.t()
  def get_department_by_slug!(city_or_city_id, slug) do
    case fetch_department_by_slug(city_or_city_id, slug) do
      {:ok, department} -> department
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: Department
    end
  end

  @doc """
  Creates a Department scoped to the given World and City.

  Returns `{:error, :city_not_in_world}` when the supplied City does not belong
  to the supplied World scope.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> {:ok, %LemmingsOs.Departments.Department{slug: "support", world_id: world_id, city_id: city_id}} =
      ...>   LemmingsOs.Departments.create_department(world, city, %{slug: "support", name: "Support", status: "active"})
      iex> {world_id, city_id}
      {world.id, city.id}
  """
  @spec create_department(World.t() | Ecto.UUID.t(), City.t() | Ecto.UUID.t(), map()) ::
          {:ok, Department.t()} | {:error, Ecto.Changeset.t() | :city_not_in_world}
  def create_department(world_or_world_id, city_or_city_id, attrs) when is_map(attrs) do
    with {:ok, world_id} <- normalize_world_id(world_or_world_id),
         {:ok, %City{id: city_id}} <- fetch_city_in_world(world_id, city_or_city_id) do
      %Department{world_id: world_id, city_id: city_id}
      |> Department.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Updates a persisted Department through the operator-facing CRUD contract.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city, name: "Before")
      iex> {:ok, %LemmingsOs.Departments.Department{name: name}} =
      ...>   LemmingsOs.Departments.update_department(department, %{name: "After"})
      iex> name
      "After"
  """
  @spec update_department(Department.t(), map()) ::
          {:ok, Department.t()} | {:error, Ecto.Changeset.t()}
  def update_department(%Department{} = department, attrs) when is_map(attrs) do
    department
    |> Department.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Transitions a Department to a new administrative status.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city, status: "disabled")
      iex> {:ok, %LemmingsOs.Departments.Department{status: status}} =
      ...>   LemmingsOs.Departments.set_department_status(department, "active")
      iex> status
      "active"
  """
  @spec set_department_status(Department.t(), String.t()) ::
          {:ok, Department.t()} | {:error, Ecto.Changeset.t()}
  def set_department_status(%Department{} = department, status) when is_binary(status) do
    update_department(department, %{status: status})
  end

  @doc """
  Transitions a Department to `active`.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city, status: "disabled")
      iex> {:ok, %LemmingsOs.Departments.Department{status: status}} =
      ...>   LemmingsOs.Departments.activate_department(department)
      iex> status
      "active"
  """
  @spec activate_department(Department.t()) ::
          {:ok, Department.t()} | {:error, Ecto.Changeset.t()}
  def activate_department(%Department{} = department),
    do: set_department_status(department, "active")

  @doc """
  Transitions a Department to `draining`.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city, status: "active")
      iex> {:ok, %LemmingsOs.Departments.Department{status: status}} =
      ...>   LemmingsOs.Departments.drain_department(department)
      iex> status
      "draining"
  """
  @spec drain_department(Department.t()) :: {:ok, Department.t()} | {:error, Ecto.Changeset.t()}
  def drain_department(%Department{} = department),
    do: set_department_status(department, "draining")

  @doc """
  Transitions a Department to `disabled`.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city, status: "draining")
      iex> {:ok, %LemmingsOs.Departments.Department{status: status}} =
      ...>   LemmingsOs.Departments.disable_department(department)
      iex> status
      "disabled"
  """
  @spec disable_department(Department.t()) :: {:ok, Department.t()} | {:error, Ecto.Changeset.t()}
  def disable_department(%Department{} = department),
    do: set_department_status(department, "disabled")

  @doc """
  Deletes a persisted Department record when safe removal can be proven.

  This implementation is intentionally conservative. In the current project
  slice there is no runtime-backed signal that can prove the Department has no
  active work, so hard deletion remains denied even after the Department is
  administratively disabled.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city, status: "disabled")
      iex> {:error, %LemmingsOs.Departments.DeleteDeniedError{reason: :safety_indeterminate}} =
      ...>   LemmingsOs.Departments.delete_department(department)
  """
  @spec delete_department(Department.t()) ::
          {:ok, Department.t()} | {:error, DeleteDeniedError.t()}
  def delete_department(%Department{} = department) do
    with :ok <- ensure_department_disabled_for_delete(department),
         :ok <- ensure_department_safe_to_delete(department) do
      Repo.delete(department)
    end
  end

  defp departments_query(%World{id: world_id}, %City{id: city_id}, opts),
    do: departments_query(world_id, city_id, opts)

  defp departments_query(%World{id: world_id}, city_id, opts) when is_binary(city_id),
    do: departments_query(world_id, city_id, opts)

  defp departments_query(world_id, %City{id: city_id}, opts) when is_binary(world_id),
    do: departments_query(world_id, city_id, opts)

  defp departments_query(world_id, city_id, opts)
       when is_binary(world_id) and is_binary(city_id) do
    Department
    |> where([department], department.world_id == ^world_id and department.city_id == ^city_id)
    |> filter_query(opts)
    |> order_by([department], asc: department.inserted_at, asc: department.id)
  end

  defp fetch_department_result(%Department{} = department), do: {:ok, department}
  defp fetch_department_result(nil), do: {:error, :not_found}

  defp normalize_world_id(%World{id: world_id}) when is_binary(world_id), do: {:ok, world_id}
  defp normalize_world_id(world_id) when is_binary(world_id), do: {:ok, world_id}

  defp fetch_city_in_world(world_id, %City{id: city_id, world_id: world_id} = city)
       when is_binary(city_id),
       do: {:ok, city}

  defp fetch_city_in_world(_world_id, %City{}), do: {:error, :city_not_in_world}

  defp fetch_city_in_world(world_id, city_id)
       when is_binary(world_id) and is_binary(city_id) do
    City
    |> where([city], city.world_id == ^world_id and city.id == ^city_id)
    |> Repo.one()
    |> fetch_scoped_city_result()
  end

  defp fetch_scoped_city_result(%City{} = city), do: {:ok, city}
  defp fetch_scoped_city_result(nil), do: {:error, :city_not_in_world}

  defp ensure_department_disabled_for_delete(%Department{id: _id, status: "disabled"}), do: :ok

  defp ensure_department_disabled_for_delete(%Department{id: id}) do
    {:error, %DeleteDeniedError{department_id: id, reason: :not_disabled}}
  end

  defp ensure_department_safe_to_delete(%Department{id: id}) do
    {:error, %DeleteDeniedError{department_id: id, reason: :safety_indeterminate}}
  end

  defp filter_query(query, [{:status, status} | rest]),
    do: filter_query(from(department in query, where: department.status == ^status), rest)

  defp filter_query(query, [{:ids, ids} | rest]) when is_list(ids),
    do: filter_query(from(department in query, where: department.id in ^ids), rest)

  defp filter_query(query, [{:slug, slug} | rest]),
    do: filter_query(from(department in query, where: department.slug == ^slug), rest)

  defp filter_query(query, [{:preload, preloads} | rest]),
    do: filter_query(preload(query, ^preloads), rest)

  defp filter_query(query, [_ | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query
end
