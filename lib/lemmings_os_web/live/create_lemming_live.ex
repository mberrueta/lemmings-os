defmodule LemmingsOsWeb.CreateLemmingLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Cities
  alias LemmingsOs.Departments
  alias LemmingsOs.Helpers
  alias LemmingsOs.Lemmings
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Worlds

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:lemmings, dgettext("lemmings", ".page_title_create_lemming"))
     |> assign(:world, nil)
     |> assign(:city, nil)
     |> assign(:department, nil)
     |> assign(:cities, [])
     |> assign(:departments, [])
     |> assign(:slug_manual?, false)
     |> assign(:scope_form, build_scope_form(%{}))
     |> assign(:form, build_form(base_changeset(%{})))}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, params)}
  end

  def handle_event("change_scope", %{"scope" => params}, socket) do
    {:noreply, push_patch(socket, to: create_scope_path(params))}
  end

  def handle_event("validate", %{"_target" => target, "lemming" => params}, socket) do
    slug_manual? = slug_manual?(socket.assigns.slug_manual?, target, params)
    normalized_params = normalize_params(params, slug_manual?)

    changeset =
      normalized_params
      |> base_changeset()
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:slug_manual?, slug_manual?)
     |> assign(:form, build_form(changeset))}
  end

  def handle_event("save", %{"lemming" => params}, socket) do
    attrs = normalize_params(params, socket.assigns.slug_manual?)

    case Lemmings.create_lemming(
           socket.assigns.world,
           socket.assigns.city,
           socket.assigns.department,
           attrs
         ) do
      {:ok, lemming} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("lemmings", ".flash_lemming_created"))
         |> push_navigate(
           to:
             ~p"/lemmings/#{lemming.id}?#{%{city: socket.assigns.city.id, dept: socket.assigns.department.id}}"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, build_form(Map.put(changeset, :action, :validate)))}

      {:error, :department_not_in_city_world} ->
        {:noreply, put_flash(socket, :error, dgettext("lemmings", ".flash_create_scope_invalid"))}
    end
  end

  defp load_page(socket, %{"dept" => department_id}) when is_binary(department_id) do
    case Departments.get_department(department_id, preload: [:city, :world]) do
      nil ->
        load_page(socket, %{})

      department ->
        cities = Cities.list_cities(department.world)
        departments = Departments.list_departments(department.city)

        socket
        |> assign(:world, department.world)
        |> assign(:city, department.city)
        |> assign(:department, department)
        |> assign(:cities, cities)
        |> assign(:departments, departments)
        |> assign(
          :scope_form,
          build_scope_form(%{"city_id" => department.city.id, "department_id" => department.id})
        )
        |> assign(:form, build_form(base_changeset(form_params(socket.assigns.form))))
        |> put_shell_breadcrumb([
          shell_item(:cities, "/cities"),
          shell_item(
            department.city.name || department.city.id,
            "/cities?city=#{department.city.id}"
          ),
          shell_item(:departments, "/departments?city=#{department.city.id}"),
          shell_item(
            department.name || department.id,
            "/departments?city=#{department.city.id}&dept=#{department.id}"
          ),
          shell_item("new", "/lemmings/new?dept=#{department.id}")
        ])
    end
  end

  defp load_page(socket, %{"city" => city_id}) when is_binary(city_id) do
    case Worlds.get_default_world() do
      %Worlds.World{} = world ->
        cities = Cities.list_cities(world)
        city = Enum.find(cities, &(&1.id == city_id))
        departments = if city, do: Departments.list_departments(city), else: []

        socket
        |> assign(:world, world)
        |> assign(:city, city)
        |> assign(:department, nil)
        |> assign(:cities, cities)
        |> assign(:departments, departments)
        |> assign(
          :scope_form,
          build_scope_form(%{"city_id" => city && city.id, "department_id" => nil})
        )
        |> assign(:slug_manual?, false)
        |> assign(:form, build_form(base_changeset(%{})))
        |> put_shell_breadcrumb([
          shell_item(:lemmings, "/lemmings"),
          shell_item("new", "/lemmings/new")
        ])

      nil ->
        load_page_without_scope(socket)
    end
  end

  defp load_page(socket, _params) do
    case Worlds.get_default_world() do
      %Worlds.World{} = world ->
        socket
        |> assign(:world, world)
        |> assign(:city, nil)
        |> assign(:department, nil)
        |> assign(:cities, Cities.list_cities(world))
        |> assign(:departments, [])
        |> assign(:slug_manual?, false)
        |> assign(:scope_form, build_scope_form(%{}))
        |> assign(:form, build_form(base_changeset(%{})))
        |> put_shell_breadcrumb([
          shell_item(:lemmings, "/lemmings"),
          shell_item("new", "/lemmings/new")
        ])

      nil ->
        load_page_without_scope(socket)
    end
  end

  defp base_changeset(attrs) do
    %Lemming{}
    |> Lemming.changeset(Map.put_new(attrs, "status", "draft"))
  end

  defp build_form(changeset), do: to_form(changeset, as: :lemming)
  defp build_scope_form(params), do: to_form(params, as: :scope)

  defp form_params(nil), do: %{}
  defp form_params(%Phoenix.HTML.Form{params: params}) when is_map(params), do: params
  defp form_params(_form), do: %{}

  defp normalize_params(params, slug_manual?) do
    slug =
      if slug_manual? do
        params["slug"]
      else
        Helpers.slugify(params["name"] || "")
      end

    params
    |> Map.put("slug", slug || "")
    |> Map.put_new("status", "draft")
  end

  defp slug_manual?(_current?, ["lemming", "slug"], %{"slug" => slug}) do
    !Helpers.blank?(slug)
  end

  defp slug_manual?(current?, ["lemming", "name"], %{"slug" => slug}) do
    current? and !Helpers.blank?(slug)
  end

  defp slug_manual?(current?, _target, _params), do: current?

  defp create_scope_path(%{"department_id" => department_id})
       when is_binary(department_id) and department_id != "" do
    ~p"/lemmings/new?#{%{dept: department_id}}"
  end

  defp create_scope_path(%{"city_id" => city_id}) when is_binary(city_id) and city_id != "" do
    ~p"/lemmings/new?#{%{city: city_id}}"
  end

  defp create_scope_path(_params), do: ~p"/lemmings/new"

  defp load_page_without_scope(socket) do
    socket
    |> assign(:world, nil)
    |> assign(:city, nil)
    |> assign(:department, nil)
    |> assign(:cities, [])
    |> assign(:departments, [])
    |> assign(:slug_manual?, false)
    |> assign(:scope_form, build_scope_form(%{}))
    |> assign(:form, build_form(base_changeset(%{})))
    |> put_shell_breadcrumb([
      shell_item(:lemmings, "/lemmings"),
      shell_item("new", "/lemmings/new")
    ])
  end
end
