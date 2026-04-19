defmodule LemmingsOs.LemmingToolsTest do
  use LemmingsOs.DataCase, async: true

  alias LemmingsOs.LemmingTools
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.Repo

  describe "create_tool_execution/3 and list_tool_executions/3" do
    test "S01: persists durable tool executions and lists them chronologically" do
      %{world: world, instance: instance} = spawn_instance_fixture()
      started_at = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, first_execution} =
               LemmingTools.create_tool_execution(world, instance, %{
                 tool_name: "fs.read_text_file",
                 status: "running",
                 args: %{"path" => "notes-a.txt"},
                 started_at: started_at
               })

      assert {:ok, second_execution} =
               LemmingTools.create_tool_execution(world, instance, %{
                 tool_name: "web.search",
                 status: "running",
                 args: %{"query" => "phoenix"},
                 started_at: started_at
               })

      older_inserted_at =
        DateTime.add(DateTime.utc_now(), -5, :second) |> DateTime.truncate(:second)

      {1, _} =
        ToolExecution
        |> where([tool_execution], tool_execution.id == ^first_execution.id)
        |> Repo.update_all(set: [inserted_at: older_inserted_at])

      assert [listed_first, listed_second] = LemmingTools.list_tool_executions(world, instance)
      assert listed_first.id == first_execution.id
      assert listed_second.id == second_execution.id
      assert listed_first.status == "running"
      assert listed_second.tool_name == "web.search"
    end

    test "S02: supports status and tool filters in world-scoped listing" do
      %{world: world, instance: instance} = spawn_instance_fixture()

      assert {:ok, ok_execution} =
               LemmingTools.create_tool_execution(world, instance, %{
                 tool_name: "fs.read_text_file",
                 status: "ok",
                 args: %{"path" => "notes-a.txt"},
                 result: %{"bytes" => 10}
               })

      assert {:ok, error_execution} =
               LemmingTools.create_tool_execution(world, instance, %{
                 tool_name: "web.fetch",
                 status: "error",
                 args: %{"url" => "https://example.com"},
                 error: %{"code" => "tool.web.request_failed"}
               })

      assert [%ToolExecution{id: id}] =
               LemmingTools.list_tool_executions(world, instance, status: "ok")

      assert id == ok_execution.id

      assert [%ToolExecution{id: id}] =
               LemmingTools.list_tool_executions(world, instance,
                 statuses: ["error"],
                 tool_name: "web.fetch"
               )

      assert id == error_execution.id
    end
  end

  describe "get_tool_execution/4 and update_tool_execution/4" do
    test "S03: updates persisted completion fields for a running execution" do
      %{world: world, instance: instance} = spawn_instance_fixture()

      assert {:ok, tool_execution} =
               LemmingTools.create_tool_execution(world, instance, %{
                 tool_name: "fs.write_text_file",
                 status: "running",
                 args: %{"path" => "report.md", "content" => "done"}
               })

      completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, updated_execution} =
               LemmingTools.update_tool_execution(world, instance, tool_execution, %{
                 status: "ok",
                 summary: "Wrote file /workspace/report.md",
                 preview: "done",
                 result: %{"path" => "/workspace/report.md", "bytes" => 4},
                 completed_at: completed_at,
                 duration_ms: 19
               })

      assert updated_execution.status == "ok"
      assert updated_execution.duration_ms == 19
      assert updated_execution.result == %{"path" => "/workspace/report.md", "bytes" => 4}

      assert {:ok, fetched_execution} =
               LemmingTools.get_tool_execution(world, instance, tool_execution.id)

      assert fetched_execution.status == "ok"
      assert fetched_execution.summary == "Wrote file /workspace/report.md"
      assert fetched_execution.completed_at == completed_at
    end

    test "S04: enforces world scope across create, list, get, and update APIs" do
      %{world: world, instance: instance} = spawn_instance_fixture()
      other_world = insert(:world)

      assert {:ok, tool_execution} =
               LemmingTools.create_tool_execution(world, instance, %{
                 tool_name: "fs.read_text_file",
                 status: "running",
                 args: %{"path" => "notes.txt"}
               })

      assert [] = LemmingTools.list_tool_executions(other_world, instance)

      assert {:error, :not_found} =
               LemmingTools.get_tool_execution(other_world, instance, tool_execution.id)

      assert {:error, :not_found} =
               LemmingTools.create_tool_execution(other_world, instance, %{
                 tool_name: "fs.read_text_file",
                 status: "running",
                 args: %{"path" => "notes.txt"}
               })

      assert {:error, :not_found} =
               LemmingTools.update_tool_execution(other_world, instance, tool_execution, %{
                 status: "error",
                 error: %{"code" => "tool.invalid_scope"}
               })
    end
  end

  defp spawn_instance_fixture do
    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        status: "active"
      )

    {:ok, instance} = LemmingInstances.spawn_instance(lemming, "Run task")

    %{world: world, instance: instance}
  end
end
