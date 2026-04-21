defmodule LemmingsOs.Runtime.StatusTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingTools
  alias LemmingsOs.Runtime.Status

  test "dashboard_snapshot/1 includes recent persisted tool executions" do
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

    {:ok, instance} = LemmingInstances.spawn_instance(lemming, "Generate an artifact")

    {:ok, tool_execution} =
      LemmingTools.create_tool_execution(world, instance, %{
        tool_name: "fs.write_text_file",
        status: "ok",
        args: %{"path" => "reports/result.md", "content" => "content"},
        summary: "Wrote file",
        duration_ms: 12,
        started_at: DateTime.utc_now() |> DateTime.truncate(:second),
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    snapshot = Status.dashboard_snapshot(recent_limit: 10)

    assert is_list(snapshot.tool_executions)

    assert Enum.any?(snapshot.tool_executions, fn entry ->
             entry.id == tool_execution.id and
               entry.instance_id == instance.id and
               entry.tool_name == "fs.write_text_file" and
               entry.status == "ok" and
               entry.duration_ms == 12
           end)
  end
end
