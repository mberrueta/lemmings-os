defmodule LemmingsOsWeb.PageData.CitiesMockChildrenSnapshot do
  @moduledoc """
  Explicit mock-backed child preview data for the Cities page.

  The Cities slice still shows department and lemming previews, but they are
  clearly marked as mock-backed and are not treated as persisted authority.
  """

  use Gettext, backend: LemmingsOs.Gettext

  alias LemmingsOs.MockData

  @type department_preview :: %{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          task_count: non_neg_integer(),
          first_task: String.t() | nil
        }

  @type lemming_preview :: %{
          id: String.t(),
          name: String.t(),
          role: String.t() | nil,
          current_task: String.t() | nil,
          status: String.t() | atom()
        }

  @type t :: %__MODULE__{
          source: String.t(),
          label: String.t(),
          departments: [department_preview()],
          lemmings: [lemming_preview()]
        }

  defstruct [:source, :label, :departments, :lemmings]

  @doc """
  Builds a mock-backed preview for the selected city.

  The selected city only influences the preview rotation so the UI feels tied
  to the current selection without implying persisted membership.
  """
  @spec build(map() | nil) :: t()
  def build(city \\ nil)

  def build(nil), do: preview_snapshot([], [])

  def build(%{} = city) do
    seed = preview_seed(city)

    departments =
      MockData.departments()
      |> rotate(seed)
      |> Enum.take(3)
      |> Enum.map(&department_preview/1)

    lemmings =
      MockData.lemmings()
      |> rotate(seed)
      |> Enum.take(4)
      |> Enum.map(&lemming_preview/1)

    preview_snapshot(departments, lemmings)
  end

  defp preview_snapshot(departments, lemmings) do
    %__MODULE__{
      source: "mock",
      label: Gettext.dgettext(LemmingsOs.Gettext, "world", ".label_mock_backed_preview"),
      departments: departments,
      lemmings: lemmings
    }
  end

  defp department_preview(%{} = department) do
    %{
      id: Map.fetch!(department, :id),
      name: Map.fetch!(department, :name),
      description: Map.get(department, :description),
      task_count: department |> Map.get(:tasks_queue, []) |> length(),
      first_task: department |> Map.get(:tasks_queue, []) |> List.first()
    }
  end

  defp lemming_preview(%{} = lemming) do
    %{
      id: Map.fetch!(lemming, :id),
      name: Map.fetch!(lemming, :name),
      role: Map.get(lemming, :role),
      current_task: Map.get(lemming, :current_task),
      status: Map.get(lemming, :status)
    }
  end

  defp preview_seed(%{id: id}) when is_binary(id) and id != "", do: :erlang.phash2(id)
  defp preview_seed(%{slug: slug}) when is_binary(slug) and slug != "", do: :erlang.phash2(slug)
  defp preview_seed(%{name: name}) when is_binary(name) and name != "", do: :erlang.phash2(name)
  defp preview_seed(_city), do: 0

  defp rotate(list, seed) do
    split_at = rem(seed, length(list))
    {head, tail} = Enum.split(list, split_at)
    tail ++ head
  end
end
