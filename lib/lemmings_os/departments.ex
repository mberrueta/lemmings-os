defmodule LemmingsOs.Departments do
  @moduledoc """
  Department domain boundary.

  This context owns persisted Department retrieval, scope-based list APIs, and
  lifecycle transitions.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.DeleteDeniedError
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @doc """
  Returns persisted departments scoped by World or City.

  Accepts an optional keyword list for filtering and explicit preloads.
  """
  @spec list_departments(World.t() | City.t(), keyword()) :: [Department.t()]
  def list_departments(scope, opts \\ [])

  def list_departments(%World{id: world_id}, opts) do
    Department
    |> filter_query(Keyword.merge([world_id: world_id], opts))
    |> order_by([department], asc: department.inserted_at, asc: department.id)
    |> Repo.all()
  end

  def list_departments(%City{id: city_id}, opts) do
    Department
    |> filter_query(Keyword.merge([city_id: city_id], opts))
    |> order_by([department], asc: department.inserted_at, asc: department.id)
    |> Repo.all()
  end

  @doc """
  Returns the Department for the given persisted ID, or `nil`.
  """
  @spec get_department(Ecto.UUID.t(), keyword()) :: Department.t() | nil
  def get_department(id, opts \\ []) when is_binary(id) do
    Department
    |> filter_query(Keyword.merge([id: id], opts))
    |> Repo.one()
  end

  @doc """
  Returns the Department for the given City-scoped slug, or `nil`.
  """
  @spec get_department_by_slug(City.t(), String.t(), keyword()) :: Department.t() | nil
  def get_department_by_slug(%City{id: city_id}, slug, opts \\ []) when is_binary(slug) do
    Department
    |> filter_query(Keyword.merge([city_id: city_id, slug: slug], opts))
    |> Repo.one()
  end

  @doc """
  Creates a Department scoped to the given City.
  """
  @spec create_department(City.t(), map()) :: {:ok, Department.t()} | {:error, Ecto.Changeset.t()}
  def create_department(%City{id: city_id, world_id: world_id}, attrs) when is_map(attrs) do
    %Department{world_id: world_id, city_id: city_id}
    |> Department.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a persisted Department through the operator-facing CRUD contract.
  """
  @spec update_department(Department.t(), map()) ::
          {:ok, Department.t()} | {:error, Ecto.Changeset.t()}
  def update_department(%Department{} = department, attrs) when is_map(attrs) do
    department
    |> Department.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns aggregate persisted Department counts for a World.
  """
  @spec topology_summary(World.t()) :: %{
          department_count: non_neg_integer(),
          active_department_count: non_neg_integer()
        }
  def topology_summary(%World{id: world_id}) do
    Department
    |> where([department], department.world_id == ^world_id)
    |> select([department], %{
      department_count: count(department.id),
      active_department_count:
        sum(fragment("CASE WHEN ? = 'active' THEN 1 ELSE 0 END", department.status))
    })
    |> Repo.one()
    |> normalize_topology_summary()
  end

  @doc """
  Returns persisted Department counts keyed by City id for a World.
  """
  @spec department_counts_by_city(World.t()) :: %{Ecto.UUID.t() => non_neg_integer()}
  def department_counts_by_city(%World{id: world_id}) when is_binary(world_id) do
    Department
    |> where([department], department.world_id == ^world_id)
    |> group_by([department], department.city_id)
    |> select([department], {department.city_id, count(department.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Transitions a Department to a new administrative status.
  """
  @spec set_department_status(Department.t(), String.t()) ::
          {:ok, Department.t()} | {:error, Ecto.Changeset.t()}
  def set_department_status(%Department{} = department, status) when is_binary(status) do
    update_department(department, %{status: status})
  end

  @doc """
  Deletes a persisted Department record when safe removal can be proven.
  """
  @spec delete_department(Department.t()) ::
          {:ok, Department.t()} | {:error, DeleteDeniedError.t()}
  def delete_department(%Department{} = department) do
    with :ok <- ensure_department_disabled_for_delete(department),
         :ok <- ensure_department_safe_to_delete(department) do
      Repo.delete(department)
    end
  end

  defp normalize_topology_summary(nil), do: %{department_count: 0, active_department_count: 0}

  defp normalize_topology_summary(summary) do
    %{
      department_count: summary.department_count || 0,
      active_department_count: summary.active_department_count || 0
    }
  end

  defp ensure_department_disabled_for_delete(%Department{id: _id, status: "disabled"}), do: :ok

  defp ensure_department_disabled_for_delete(%Department{id: id}) do
    {:error, %DeleteDeniedError{department_id: id, reason: :not_disabled}}
  end

  defp ensure_department_safe_to_delete(%Department{id: id}) do
    {:error, %DeleteDeniedError{department_id: id, reason: :safety_indeterminate}}
  end

  defp filter_query(query, [{:id, id} | rest]),
    do: filter_query(from(department in query, where: department.id == ^id), rest)

  defp filter_query(query, [{:world_id, world_id} | rest]),
    do: filter_query(from(department in query, where: department.world_id == ^world_id), rest)

  defp filter_query(query, [{:city_id, city_id} | rest]),
    do: filter_query(from(department in query, where: department.city_id == ^city_id), rest)

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
