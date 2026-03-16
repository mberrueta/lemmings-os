defmodule LemmingsOsWeb.LemmingsLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.MockData

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:lemmings, dgettext("layout", ".page_title_lemmings"))
     |> assign(:lemmings, MockData.lemmings())
     |> assign(:selected_lemming, nil)}
  end

  def handle_params(params, _uri, socket) do
    selected_lemming = MockData.find_lemming(params["lemming"])

    breadcrumb =
      case selected_lemming do
        %{id: lemming_id, department_id: department_id} ->
          department = MockData.find_department(department_id)
          city = department && MockData.find_city(department.city_id)

          [
            city && shell_item(:cities, "/cities"),
            city && shell_item(city.id, "/cities?city=#{city.id}"),
            city && shell_item(:departments, "/departments?city=#{city.id}"),
            department &&
              shell_item(
                department.id,
                "/departments?city=#{city.id}&dept=#{department.id}"
              ),
            shell_item(lemming_id, "/lemmings?lemming=#{lemming_id}")
          ]
          |> Enum.reject(&is_nil/1)

        _ ->
          default_shell_breadcrumb(:lemmings)
      end

    {:noreply,
     socket
     |> assign(:selected_lemming, selected_lemming)
     |> put_shell_breadcrumb(breadcrumb)}
  end
end
