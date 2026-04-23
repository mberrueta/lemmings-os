defmodule LemmingsOsWeb.PageData.DepartmentCollaborationSnapshot do
  @moduledoc """
  Collaboration-focused read model for the Departments page.
  """

  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Lemmings
  alias LemmingsOs.Lemmings.Lemming

  @type lemming_type :: %{
          id: String.t(),
          name: String.t(),
          slug: String.t(),
          status: String.t(),
          role: String.t(),
          role_label: String.t(),
          primary_manager?: boolean(),
          path: String.t(),
          description: String.t() | nil
        }

  @type t :: %__MODULE__{
          primary_manager: lemming_type() | nil,
          lemming_types: [lemming_type()]
        }

  defstruct primary_manager: nil, lemming_types: []

  @doc """
  Builds collaboration metadata for a Department detail surface.
  """
  @spec build(Department.t()) :: t()
  def build(%Department{} = department) do
    lemming_types =
      department
      |> Lemmings.list_lemmings()
      |> Enum.map(&lemming_type(&1, department))

    primary_manager = primary_manager(lemming_types)

    %__MODULE__{
      primary_manager: primary_manager,
      lemming_types: mark_primary_manager(lemming_types, primary_manager)
    }
  end

  def build(_department), do: %__MODULE__{}

  defp primary_manager(lemming_types) do
    Enum.find(lemming_types, &(&1.role == "manager" and &1.status == "active")) ||
      Enum.find(lemming_types, &(&1.role == "manager"))
  end

  defp mark_primary_manager(lemming_types, %{id: primary_manager_id}) do
    Enum.map(lemming_types, fn lemming_type ->
      Map.put(lemming_type, :primary_manager?, lemming_type.id == primary_manager_id)
    end)
  end

  defp mark_primary_manager(lemming_types, _primary_manager), do: lemming_types

  defp lemming_type(%Lemming{} = lemming, %Department{} = department) do
    %{
      id: lemming.id,
      name: lemming.name,
      slug: lemming.slug,
      status: lemming.status,
      role: lemming.collaboration_role || "worker",
      role_label: role_label(lemming.collaboration_role),
      primary_manager?: false,
      path: "/lemmings/#{lemming.id}?city=#{department.city_id}&dept=#{department.id}",
      description: lemming.description
    }
  end

  defp role_label("manager"), do: "Manager"
  defp role_label("worker"), do: "Worker"
  defp role_label(role) when is_binary(role), do: String.capitalize(role)
  defp role_label(_role), do: "Worker"
end
