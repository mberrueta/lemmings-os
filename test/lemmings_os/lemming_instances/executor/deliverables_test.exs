defmodule LemmingsOs.LemmingInstances.Executor.DeliverablesTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.LemmingInstances.Executor.Deliverables
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.Tools.WorkArea

  doctest Deliverables

  setup do
    old_path = Application.get_env(:lemmings_os, :work_areas_path)
    path = Path.join(System.tmp_dir!(), "lemmings_deliverables_test_#{System.unique_integer()}")

    Application.put_env(:lemmings_os, :work_areas_path, path)

    on_exit(fn ->
      File.rm_rf!(path)

      if old_path do
        Application.put_env(:lemmings_os, :work_areas_path, old_path)
      else
        Application.delete_env(:lemmings_os, :work_areas_path)
      end
    end)

    work_area_ref = "work-area-1"
    :ok = WorkArea.ensure(work_area_ref)

    %{work_area_ref: work_area_ref}
  end

  test "fs.write_text_file output becomes a verified markdown deliverable", %{
    work_area_ref: work_area_ref
  } do
    write_work_area_file!(work_area_ref, "quotation_joao_silva.md", "# Quote")

    payload =
      Deliverables.completion_fields(
        %{id: "instance-1"},
        [
          %ToolExecution{
            id: "tool-md",
            status: "ok",
            tool_name: "fs.write_text_file",
            args: %{"path" => "quotation_joao_silva.md"},
            result: %{"path" => "quotation_joao_silva.md", "bytes" => 7}
          }
        ],
        "Markdown quotation saved.",
        work_area_ref: work_area_ref,
        artifacts: []
      )

    assert [
             %{
               "kind" => "markdown",
               "path" => "quotation_joao_silva.md",
               "tool_execution_id" => "tool-md",
               "exists" => true
             }
           ] = payload.deliverables["files"]

    assert payload.missing_deliverables == []
  end

  test "document tools output html and pdf deliverables with tool execution ids", %{
    work_area_ref: work_area_ref
  } do
    write_work_area_file!(work_area_ref, "quotation_joao_silva.html", "<h1>Quote</h1>")
    write_work_area_file!(work_area_ref, "quotation_joao_silva.pdf", "%PDF-1.7")

    payload =
      Deliverables.completion_fields(
        %{id: "instance-1"},
        [
          %ToolExecution{
            id: "tool-html",
            status: "ok",
            tool_name: "documents.markdown_to_html",
            args: %{"output_path" => "quotation_joao_silva.html"},
            result: %{"output_path" => "quotation_joao_silva.html"}
          },
          %ToolExecution{
            id: "tool-pdf",
            status: "ok",
            tool_name: "documents.print_to_pdf",
            args: %{"output_path" => "quotation_joao_silva.pdf"},
            result: %{"output_path" => "quotation_joao_silva.pdf"}
          }
        ],
        "HTML and PDF created.",
        work_area_ref: work_area_ref,
        artifacts: []
      )

    assert %{
             "kind" => "html",
             "path" => "quotation_joao_silva.html",
             "tool_execution_id" => "tool-html",
             "exists" => true
           } in payload.deliverables["files"]

    assert %{
             "kind" => "pdf",
             "path" => "quotation_joao_silva.pdf",
             "tool_execution_id" => "tool-pdf",
             "exists" => true
           } in payload.deliverables["files"]
  end

  test "email.create_draft output becomes a verified email draft deliverable" do
    payload =
      Deliverables.completion_fields(
        %{id: "instance-1"},
        [
          %ToolExecution{
            id: "tool-email",
            status: "ok",
            tool_name: "email.create_draft",
            result: %{
              "provider" => "gmail",
              "connection_ref" => "gmail",
              "draft_id" => "draft-123",
              "status" => "created"
            }
          }
        ],
        "Gmail draft created.",
        work_area_ref: "work-area-1",
        artifacts: []
      )

    assert [
             %{
               "provider" => "gmail",
               "connection_ref" => "gmail",
               "draft_id" => "draft-123",
               "tool_execution_id" => "tool-email",
               "status" => "created"
             }
           ] = payload.deliverables["email_drafts"]
  end

  test "free-text deliverable claims without matching tool results are unverified" do
    payload =
      Deliverables.completion_fields(
        %{id: "instance-1"},
        [],
        "Markdown quotation saved, PDF generated, HTML version created, and Gmail draft created.",
        work_area_ref: "work-area-1",
        artifacts: []
      )

    assert payload.deliverables == %{"files" => [], "email_drafts" => []}

    assert Enum.any?(
             payload.warnings,
             &(Map.get(&1, "code") == "deliverable.claim_unverified" and
                 String.contains?(Map.get(&1, "message"), "PDF"))
           )

    assert Enum.any?(
             payload.warnings,
             &(Map.get(&1, "code") == "deliverable.claim_unverified" and
                 String.contains?(Map.get(&1, "message"), "Gmail draft"))
           )
  end

  defp write_work_area_file!(work_area_ref, relative_path, content) do
    {:ok, resolved} = WorkArea.resolve(work_area_ref, relative_path)
    :ok = File.mkdir_p(Path.dirname(resolved.absolute_path))
    :ok = File.write(resolved.absolute_path, content)
  end
end
