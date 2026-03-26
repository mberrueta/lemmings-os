defmodule LemmingsOsWeb.ImportLemmingLive do
  @moduledoc """
  LiveView for importing one or more Lemming definitions from a JSON file into a
  target department.

  ## Assigns
  - `:world` - The resolved `%World{}` owning the target department
  - `:city` - The resolved `%City{}` owning the target department
  - `:department` - The target `%Department{}`
  - `:step` - `:upload | :confirm` — controls which UI panel is rendered
  - `:upload_error` - `nil` or a human-readable error string for the upload step
  - `:conflicts` - list of `%{name: String.t(), slug: String.t(), id: String.t()}` for clashing records
  - `:pending_records` - decoded JSON records waiting for user confirmation
  - `:existing_by_slug` - map of `slug => %Lemming{}` for the current department (used in confirm step)
  - `:confirm_error` - nil or error string shown on the confirm step without bouncing back to upload
  """

  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Departments
  alias LemmingsOs.Lemmings
  alias LemmingsOs.Lemmings.ImportExport

  @max_file_size 512_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_shell(:lemmings, dgettext("lemmings", ".page_title_import_lemming"))
      |> assign(:world, nil)
      |> assign(:city, nil)
      |> assign(:department, nil)
      |> assign(:step, :upload)
      |> assign(:upload_error, nil)
      |> assign(:conflicts, [])
      |> assign(:pending_records, [])
      |> assign(:existing_by_slug, %{})
      |> assign(:confirm_error, nil)
      |> allow_upload(:json_file,
        accept: ~w(.json),
        max_entries: 1,
        max_file_size: @max_file_size
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, params)}
  end

  @impl true
  def handle_event("validate_file", _params, socket) do
    {:noreply, assign(socket, :upload_error, nil)}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :json_file, ref)}
  end

  @impl true
  def handle_event("process_file", _params, socket) do
    case read_uploaded_json(socket) do
      {:ok, json_bytes} ->
        handle_decoded_json(socket, json_bytes)

      {:error, :no_file} ->
        {:noreply,
         assign(socket, :upload_error, dgettext("lemmings", ".error_import_no_file_selected"))}

      {:error, :too_large} ->
        {:noreply,
         assign(socket, :upload_error, dgettext("lemmings", ".error_import_file_too_large"))}
    end
  end

  @impl true
  def handle_event("confirm_import", _params, socket) do
    %{
      world: world,
      city: city,
      department: department,
      pending_records: records,
      existing_by_slug: existing_by_slug
    } = socket.assigns

    conflict_slugs = Map.keys(existing_by_slug)
    {to_update, to_create} = Enum.split_with(records, &(Map.get(&1, "slug") in conflict_slugs))

    update_results =
      Enum.map(to_update, fn record ->
        existing = Map.get(existing_by_slug, Map.get(record, "slug"))
        Lemmings.update_lemming(existing, record)
      end)

    update_errors = Enum.filter(update_results, &match?({:error, _}, &1))

    if update_errors != [] do
      {:error, cs} = hd(update_errors)
      {:noreply, assign(socket, :confirm_error, changeset_error_summary(cs))}
    else
      case ImportExport.import_lemmings(world, city, department, to_create) do
        {:ok, created} ->
          updated = Enum.flat_map(update_results, fn {:ok, l} -> [l] end)
          total = length(created) + length(updated)

          {:noreply,
           socket
           |> put_flash(:info, dgettext("lemmings", ".flash_import_success", count: total))
           |> push_navigate(
             to: ~p"/departments?#{%{city: city.id, dept: department.id, tab: "lemmings"}}"
           )}

        {:error, :unsupported_schema_version} ->
          {:noreply,
           assign(
             socket,
             :confirm_error,
             dgettext("lemmings", ".error_import_unsupported_version")
           )}

        {:error, errors} when is_list(errors) ->
          {:noreply, assign(socket, :confirm_error, import_changeset_error_message(errors))}

        {:error, _} ->
          {:noreply, assign(socket, :confirm_error, dgettext("lemmings", ".error_import_failed"))}
      end
    end
  end

  @impl true
  def handle_event("cancel_import", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :upload)
     |> assign(:pending_records, [])
     |> assign(:conflicts, [])
     |> assign(:existing_by_slug, %{})
     |> assign(:confirm_error, nil)
     |> assign(:upload_error, nil)}
  end

  defp load_page(socket, %{"dept" => department_id}) when is_binary(department_id) do
    case Departments.get_department(department_id, preload: [:city, :world]) do
      nil ->
        socket
        |> put_flash(:error, dgettext("lemmings", ".flash_create_scope_invalid"))
        |> push_navigate(to: ~p"/lemmings")

      department ->
        socket
        |> assign(:world, department.world)
        |> assign(:city, department.city)
        |> assign(:department, department)
        |> put_shell_breadcrumb([
          shell_item(:cities, "/cities"),
          shell_item(
            department.city.name || department.city.id,
            "/cities?city=#{department.city.id}"
          ),
          shell_item(:departments, "/departments?city=#{department.city.id}"),
          shell_item(
            department.name || department.id,
            "/departments?city=#{department.city.id}&dept=#{department.id}&tab=lemmings"
          ),
          shell_item("import", "/lemmings/import?dept=#{department.id}")
        ])
    end
  end

  defp load_page(socket, _params) do
    socket
    |> put_flash(:error, dgettext("lemmings", ".flash_create_scope_invalid"))
    |> push_navigate(to: ~p"/lemmings")
  end

  defp read_uploaded_json(socket) do
    case socket.assigns.uploads.json_file.entries do
      [] -> {:error, :no_file}
      [%{valid?: false} | _] -> {:error, :too_large}
      [entry | _] -> {:ok, consume_uploaded_entry(socket, entry, &read_path/1)}
    end
  end

  defp read_path(%{path: path}), do: {:ok, File.read!(path)}

  defp handle_decoded_json(socket, json_bytes) do
    with {:ok, decoded} <- Jason.decode(json_bytes),
         {:ok, records} <- normalize_records(decoded) do
      existing_lemmings = Lemmings.list_lemmings(socket.assigns.department)
      existing_by_slug = Map.new(existing_lemmings, &{&1.slug, &1})

      conflicts =
        records
        |> Enum.filter(fn r -> Map.get(r, "slug") in Map.keys(existing_by_slug) end)
        |> Enum.map(fn r ->
          existing = Map.get(existing_by_slug, Map.get(r, "slug"))
          %{name: existing.name, slug: existing.slug, id: existing.id}
        end)

      if conflicts == [] do
        do_import(socket, records)
      else
        {:noreply,
         socket
         |> assign(:step, :confirm)
         |> assign(:pending_records, records)
         |> assign(:existing_by_slug, existing_by_slug)
         |> assign(:conflicts, conflicts)}
      end
    else
      {:error, %Jason.DecodeError{}} ->
        {:noreply,
         assign(socket, :upload_error, dgettext("lemmings", ".error_import_invalid_json"))}

      {:error, :invalid_payload} ->
        {:noreply,
         assign(socket, :upload_error, dgettext("lemmings", ".error_import_invalid_json"))}
    end
  end

  defp do_import(socket, records) do
    %{world: world, city: city, department: department} = socket.assigns

    case ImportExport.import_lemmings(world, city, department, records) do
      {:ok, lemmings} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           dgettext("lemmings", ".flash_import_success", count: length(lemmings))
         )
         |> push_navigate(
           to: ~p"/departments?#{%{city: city.id, dept: department.id, tab: "lemmings"}}"
         )}

      {:error, :unsupported_schema_version} ->
        {:noreply,
         assign(
           socket,
           :upload_error,
           dgettext("lemmings", ".error_import_unsupported_version")
         )}

      {:error, errors} when is_list(errors) ->
        {:noreply, assign(socket, :upload_error, import_changeset_error_message(errors))}

      {:error, _reason} ->
        {:noreply, assign(socket, :upload_error, dgettext("lemmings", ".error_import_failed"))}
    end
  end

  defp normalize_records(decoded) when is_list(decoded) do
    if Enum.all?(decoded, &is_map/1) do
      {:ok, decoded}
    else
      {:error, :invalid_payload}
    end
  end

  defp normalize_records(decoded) when is_map(decoded), do: {:ok, [decoded]}
  defp normalize_records(_decoded), do: {:error, :invalid_payload}

  defp changeset_error_summary(%Ecto.Changeset{} = cs) do
    errors =
      Ecto.Changeset.traverse_errors(cs, fn {msg, _opts} -> msg end)
      |> Enum.map_join(", ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)

    dgettext("lemmings", ".error_import_record_invalid", index: 1, errors: errors)
  end

  defp import_changeset_error_message([%{index: index, error: %Ecto.Changeset{} = cs} | _rest]) do
    errors =
      Ecto.Changeset.traverse_errors(cs, fn {msg, _opts} -> msg end)
      |> Enum.map_join(", ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)

    dgettext("lemmings", ".error_import_record_invalid",
      index: (index || 0) + 1,
      errors: errors
    )
  end

  defp import_changeset_error_message([%{index: index, error: _} | _rest]) do
    dgettext("lemmings", ".error_import_record_invalid",
      index: (index || 0) + 1,
      errors: dgettext("lemmings", ".error_import_failed")
    )
  end

  defp import_changeset_error_message(_errors) do
    dgettext("lemmings", ".error_import_failed")
  end
end
