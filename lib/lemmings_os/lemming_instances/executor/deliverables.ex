defmodule LemmingsOs.LemmingInstances.Executor.Deliverables do
  @moduledoc """
  Builds evidence-bound deliverable payloads from persisted tool executions.
  """

  alias LemmingsOs.Artifacts
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.Tools.ToolExecutionOutputs
  alias LemmingsOs.Tools.WorkArea

  @file_tools ~w(fs.write_text_file documents.markdown_to_html documents.print_to_pdf)
  @email_draft_tool "email.create_draft"

  @doc """
  Builds derived deliverable fields for a child completion/callback payload.

  This function does not persist anything. It derives evidence from successful
  tool execution rows and returns the structured fields that can be embedded in
  runtime callback payloads.

  Parameters:

  - `instance` is the child instance as a `%LemmingInstance{}` or a map. Its
    `:id` is used as the default WorkArea reference when `:work_area_ref` is
    not provided.
  - `tool_executions` must be a list of `%ToolExecution{}` structs or maps with
    atom keys such as `:id`, `:status`, `:tool_name`, `:args`, and `:result`.
    Only successful (`status: "ok"`) output tools are considered.
  - `result_summary` is the child free-text summary. It is scanned only to add
    `deliverable.claim_unverified` warnings when the text claims a file/PDF/HTML
    or email draft that no tool result proves.
  - `opts[:work_area_ref]` defaults to `instance.id`. It is used only for the
    best-effort file existence check.
  - `opts[:artifacts]` defaults to promoted artifacts listed for a
    `%LemmingInstance{}`. Pass `artifacts: []` in pure tests or when artifact
    lookup is not needed.

  Returned map keys are:

  - `:deliverables` with `"files"` and `"email_drafts"` lists.
  - `:missing_deliverables` for file deliverables whose relative WorkArea path
    does not currently exist.
  - `:assumptions`, currently an empty list reserved for later structured
    completion notes.
  - `:warnings`, including unverified free-text claims.

  ## Examples

      iex> payload =
      ...>   LemmingsOs.LemmingInstances.Executor.Deliverables.completion_fields(
      ...>     %{id: "worker-1"},
      ...>     [
      ...>       %{
      ...>         id: "tool-email-1",
      ...>         status: "ok",
      ...>         tool_name: "email.create_draft",
      ...>         result: %{
      ...>           "provider" => "gmail",
      ...>           "connection_ref" => "gmail",
      ...>           "draft_id" => "draft-123",
      ...>           "status" => "created"
      ...>         }
      ...>       }
      ...>     ],
      ...>     "Gmail draft created.",
      ...>     artifacts: []
      ...>   )
      iex> [%{"draft_id" => "draft-123", "provider" => "gmail"} = draft] =
      ...>   payload.deliverables["email_drafts"]
      iex> draft["connection_ref"]
      "gmail"
      iex> draft["tool_execution_id"]
      "tool-email-1"

      iex> payload =
      ...>   LemmingsOs.LemmingInstances.Executor.Deliverables.completion_fields(
      ...>     %{id: "worker-1"},
      ...>     [
      ...>       %{
      ...>         id: "tool-file-1",
      ...>         status: "ok",
      ...>         tool_name: "fs.write_text_file",
      ...>         args: %{"path" => "quote.md"},
      ...>         result: %{"path" => "quote.md"}
      ...>       }
      ...>     ],
      ...>     "Markdown quotation saved.",
      ...>     work_area_ref: "missing-work-area",
      ...>     artifacts: []
      ...>   )
      iex> [%{"kind" => "markdown", "path" => "quote.md", "exists" => false}] =
      ...>   payload.deliverables["files"]
      iex> [%{"path" => "quote.md", "reason" => "file_not_found_in_work_area"}] =
      ...>   payload.missing_deliverables
  """
  @spec completion_fields(LemmingInstance.t() | map(), [map()], String.t() | nil, keyword()) ::
          map()
  def completion_fields(instance, tool_executions, result_summary, opts \\ [])

  def completion_fields(instance, tool_executions, result_summary, opts)
      when is_list(tool_executions) and is_list(opts) do
    work_area_ref = Keyword.get(opts, :work_area_ref) || map_value(instance, :id)
    artifacts = Keyword.get_lazy(opts, :artifacts, fn -> promoted_artifacts(instance) end)
    artifact_ids_by_tool_execution_id = artifact_ids_by_tool_execution_id(artifacts)

    files =
      tool_executions
      |> Enum.flat_map(&file_deliverable(&1, work_area_ref, artifact_ids_by_tool_execution_id))
      |> Enum.uniq_by(&{&1["path"], &1["tool_execution_id"]})

    email_drafts =
      tool_executions
      |> Enum.flat_map(&email_draft_deliverable/1)
      |> Enum.uniq_by(&{&1["draft_id"], &1["tool_execution_id"]})

    deliverables = %{"files" => files, "email_drafts" => email_drafts}

    %{
      deliverables: deliverables,
      missing_deliverables: missing_file_deliverables(files),
      assumptions: [],
      warnings: unverified_claim_warnings(result_summary, deliverables)
    }
  end

  def completion_fields(_instance, _tool_executions, result_summary, _opts) do
    deliverables = %{"files" => [], "email_drafts" => []}

    %{
      deliverables: deliverables,
      missing_deliverables: [],
      assumptions: [],
      warnings: unverified_claim_warnings(result_summary, deliverables)
    }
  end

  @doc """
  Returns warnings when free text claims deliverables that no tool result proves.

  Parameters:

  - `result_summary` is the worker's free-text completion summary. Non-binary
    values return an empty warning list.
  - `deliverables` is the derived deliverable payload, normally the
    `:deliverables` value returned by `completion_fields/4`. Both atom and
    string keys are accepted for `"files"` and `"email_drafts"`.

  A warning is emitted only for claimed deliverable kinds that are absent from
  the structured deliverables. Verified structured deliverables suppress the
  corresponding warning.

  ## Examples

      iex> warnings =
      ...>   LemmingsOs.LemmingInstances.Executor.Deliverables.unverified_claim_warnings(
      ...>     "PDF generated and Gmail draft created.",
      ...>     %{"files" => [], "email_drafts" => []}
      ...>   )
      iex> Enum.map(warnings, & &1["code"]) |> Enum.uniq()
      ["deliverable.claim_unverified"]
      iex> Enum.any?(warnings, &String.contains?(&1["message"], "PDF"))
      true
      iex> Enum.any?(warnings, &String.contains?(&1["message"], "Gmail draft"))
      true

      iex> LemmingsOs.LemmingInstances.Executor.Deliverables.unverified_claim_warnings(
      ...>   "PDF generated.",
      ...>   %{"files" => [%{"kind" => "pdf"}], "email_drafts" => []}
      ...> )
      []
  """
  @spec unverified_claim_warnings(String.t() | nil, map()) :: [map()]
  def unverified_claim_warnings(result_summary, deliverables) when is_binary(result_summary) do
    normalized = String.downcase(result_summary)
    files = map_value(deliverables, :files) || []
    email_drafts = map_value(deliverables, :email_drafts) || []

    [
      maybe_unverified_file_claim(normalized, files, "pdf", "a PDF was generated"),
      maybe_unverified_file_claim(normalized, files, "html", "an HTML file was created"),
      maybe_unverified_file_claim(normalized, files, "markdown", "a Markdown file was created"),
      maybe_unverified_generic_file_claim(normalized, files),
      maybe_unverified_email_draft_claim(normalized, email_drafts)
    ]
    |> Enum.reject(&is_nil/1)
  end

  def unverified_claim_warnings(_result_summary, _deliverables), do: []

  defp file_deliverable(
         %ToolExecution{status: "ok", tool_name: tool_name} = execution,
         work_area_ref,
         artifact_ids
       )
       when tool_name in @file_tools do
    file_deliverable(Map.from_struct(execution), work_area_ref, artifact_ids)
  end

  defp file_deliverable(
         %{status: "ok", tool_name: tool_name} = execution,
         work_area_ref,
         artifact_ids
       )
       when tool_name in @file_tools do
    case ToolExecutionOutputs.workspace_output_relative_path(execution) do
      path when is_binary(path) ->
        [
          %{
            "kind" => file_kind(tool_name, path),
            "path" => path,
            "tool_execution_id" => map_value(execution, :id),
            "exists" => file_exists?(work_area_ref, path)
          }
          |> maybe_put_non_empty(
            "artifact_ids",
            Map.get(artifact_ids, map_value(execution, :id), [])
          )
        ]

      _path ->
        []
    end
  end

  defp file_deliverable(_execution, _work_area_ref, _artifact_ids), do: []

  defp email_draft_deliverable(
         %ToolExecution{status: "ok", tool_name: @email_draft_tool} = execution
       ) do
    email_draft_deliverable(Map.from_struct(execution))
  end

  defp email_draft_deliverable(%{status: "ok", tool_name: @email_draft_tool} = execution) do
    result = map_value(execution, :result) || %{}

    case map_value(result, :draft_id) do
      draft_id when is_binary(draft_id) and draft_id != "" ->
        [
          %{
            "provider" => map_value(result, :provider) || "gmail",
            "draft_id" => draft_id,
            "connection_ref" => map_value(result, :connection_ref),
            "tool_execution_id" => map_value(execution, :id),
            "status" => map_value(result, :status) || "created"
          }
          |> reject_nil_values()
        ]

      _draft_id ->
        []
    end
  end

  defp email_draft_deliverable(_execution), do: []

  defp promoted_artifacts(%LemmingInstance{id: instance_id, world_id: world_id})
       when is_binary(instance_id) and is_binary(world_id) do
    case Artifacts.list_artifacts_for_instance(%{world_id: world_id}, instance_id,
           include_non_ready: true
         ) do
      {:ok, artifacts} -> artifacts
      {:error, _reason} -> []
    end
  end

  defp promoted_artifacts(_instance), do: []

  defp artifact_ids_by_tool_execution_id(artifacts) when is_list(artifacts) do
    artifacts
    |> Enum.reduce(%{}, fn artifact, acc ->
      tool_execution_id = map_value(artifact, :created_by_tool_execution_id)
      artifact_id = map_value(artifact, :id)

      if present?(tool_execution_id) and present?(artifact_id) do
        Map.update(acc, tool_execution_id, [artifact_id], &[artifact_id | &1])
      else
        acc
      end
    end)
    |> Map.new(fn {tool_execution_id, ids} -> {tool_execution_id, Enum.reverse(ids)} end)
  end

  defp artifact_ids_by_tool_execution_id(_artifacts), do: %{}

  defp file_kind("documents.markdown_to_html", _path), do: "html"
  defp file_kind("documents.print_to_pdf", _path), do: "pdf"

  defp file_kind(_tool_name, path) when is_binary(path) do
    case String.downcase(Path.extname(path)) do
      ".md" -> "markdown"
      ".markdown" -> "markdown"
      ".html" -> "html"
      ".htm" -> "html"
      ".pdf" -> "pdf"
      ".txt" -> "text"
      _ext -> "file"
    end
  end

  defp file_exists?(work_area_ref, path) when is_binary(work_area_ref) and is_binary(path) do
    case WorkArea.resolve(work_area_ref, path) do
      {:ok, %{absolute_path: absolute_path}} -> File.regular?(absolute_path)
      {:error, _reason} -> false
    end
  end

  defp file_exists?(_work_area_ref, _path), do: false

  defp missing_file_deliverables(files) when is_list(files) do
    files
    |> Enum.reject(&(map_value(&1, :exists) == true))
    |> Enum.map(fn file ->
      %{
        "kind" => map_value(file, :kind),
        "path" => map_value(file, :path),
        "tool_execution_id" => map_value(file, :tool_execution_id),
        "reason" => "file_not_found_in_work_area"
      }
      |> reject_nil_values()
    end)
  end

  defp maybe_unverified_file_claim(summary, files, kind, claim_text) do
    if file_claim?(summary, kind) and not verified_file_kind?(files, kind) do
      unverified_warning(
        "Child result_summary claimed #{claim_text}, but no #{kind} tool result or artifact was recorded."
      )
    end
  end

  defp maybe_unverified_generic_file_claim(summary, files) do
    if Regex.match?(~r/\b(file|document)\b.*\b(created|saved|wrote|written)\b/, summary) and
         files == [] do
      unverified_warning(
        "Child result_summary claimed a file was created, but no file tool result or artifact was recorded."
      )
    end
  end

  defp maybe_unverified_email_draft_claim(summary, email_drafts) do
    if email_draft_claim?(summary) and email_drafts == [] do
      unverified_warning(
        "Child result_summary claimed a Gmail draft was created, but no email draft tool result was recorded."
      )
    end
  end

  defp file_claim?(summary, "pdf"), do: Regex.match?(~r/(\bpdf\b|\.pdf\b)/, summary)
  defp file_claim?(summary, "html"), do: Regex.match?(~r/(\bhtml\b|\.html?\b)/, summary)

  defp file_claim?(summary, "markdown"),
    do: Regex.match?(~r/(\bmarkdown\b|\.md\b|\.markdown\b)/, summary)

  defp verified_file_kind?(files, kind) when is_list(files) do
    Enum.any?(files, &(map_value(&1, :kind) == kind))
  end

  defp email_draft_claim?(summary) do
    Regex.match?(
      ~r/\b(gmail\s+draft|email\s+draft|draft)\b.*\b(created|saved|drafted)\b/,
      summary
    ) or
      Regex.match?(
        ~r/\b(created|saved|drafted)\b.*\b(gmail\s+draft|email\s+draft|draft)\b/,
        summary
      )
  end

  defp unverified_warning(message) do
    %{
      "code" => "deliverable.claim_unverified",
      "message" => message
    }
  end

  defp maybe_put_non_empty(map, _key, []), do: map
  defp maybe_put_non_empty(map, _key, nil), do: map
  defp maybe_put_non_empty(map, key, value), do: Map.put(map, key, value)

  defp reject_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(_map, _key), do: nil
end
