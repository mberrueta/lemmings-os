defmodule LemmingsOsWeb.DepartmentsLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.MockData

  def mount(_params, _session, socket) do
    cities = MockData.cities()

    {:ok,
     socket
     |> assign_shell(:departments, dgettext("layout", ".page_title_departments"))
     |> assign(:cities, cities)
     |> assign(:selected_city, List.first(cities))
     |> assign(:departments, [])
     |> assign(:selected_department, nil)}
  end

  def handle_params(params, _uri, socket) do
    selected_department = MockData.find_department(params["dept"])

    selected_city =
      case MockData.find_city(params["city"]) do
        nil ->
          case selected_department do
            %{city_id: city_id} -> MockData.find_city(city_id)
            _ -> List.first(socket.assigns.cities)
          end

        city ->
          city
      end

    departments =
      case selected_city do
        %{id: city_id} -> MockData.departments_for_city(city_id)
        _ -> []
      end

    {:noreply,
     socket
     |> assign(:selected_city, selected_city)
     |> assign(:departments, departments)
     |> assign(:selected_department, selected_department)
     |> put_shell_breadcrumb(build_shell_breadcrumb(selected_city, selected_department))}
  end

  def handle_event("navigate_department", %{"department_id" => department_id}, socket) do
    params =
      case socket.assigns.selected_city do
        %{id: city_id} -> %{city: city_id, dept: department_id}
        _ -> %{dept: department_id}
      end

    {:noreply, push_navigate(socket, to: ~p"/departments?#{params}")}
  end

  defp build_shell_breadcrumb(nil, nil), do: default_shell_breadcrumb(:departments)

  defp build_shell_breadcrumb(city, nil) do
    [
      shell_item(:cities, "/cities"),
      shell_item(city.id, "/cities?city=#{city.id}"),
      shell_item(:departments, "/departments?city=#{city.id}")
    ]
  end

  defp build_shell_breadcrumb(city, department) do
    [
      shell_item(:cities, "/cities"),
      shell_item(city.id, "/cities?city=#{city.id}"),
      shell_item(:departments, "/departments?city=#{city.id}"),
      shell_item(department.id, "/departments?city=#{city.id}&dept=#{department.id}")
    ]
  end
end
