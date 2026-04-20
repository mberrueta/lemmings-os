defmodule LemmingsOs.Tools.RuntimeTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Tools.Runtime
  alias LemmingsOs.Worlds.World

  setup do
    old_workspace_root = Application.get_env(:lemmings_os, :runtime_workspace_root)

    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "lemmings_tools_runtime_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:lemmings_os, :runtime_workspace_root, workspace_root)
    File.mkdir_p!(workspace_root)

    on_exit(fn ->
      if old_workspace_root do
        Application.put_env(:lemmings_os, :runtime_workspace_root, old_workspace_root)
      else
        Application.delete_env(:lemmings_os, :runtime_workspace_root)
      end

      File.rm_rf(workspace_root)
    end)

    world = %World{id: Ecto.UUID.generate()}

    instance = %LemmingInstance{
      id: Ecto.UUID.generate(),
      world_id: world.id,
      department_id: Ecto.UUID.generate(),
      lemming_id: Ecto.UUID.generate()
    }

    File.mkdir_p!(Path.join([workspace_root, instance.department_id, instance.lemming_id]))

    {:ok, world: world, instance: instance}
  end

  describe "execute/4 with filesystem tools" do
    test "writes and reads a file inside the instance work area", %{
      world: world,
      instance: instance
    } do
      assert {:ok, write_result} =
               Runtime.execute(world, instance, "fs.write_text_file", %{
                 "path" => "reports/result.md",
                 "content" => "hello from tools runtime"
               })

      assert write_result.tool_name == "fs.write_text_file"
      assert write_result.summary == "Wrote file reports/result.md"
      assert write_result.result.path == "reports/result.md"

      assert write_result.result.workspace_path ==
               "/workspace/#{instance.department_id}/#{instance.lemming_id}/reports/result.md"

      assert {:ok, read_result} =
               Runtime.execute(world, instance, "fs.read_text_file", %{
                 "path" => "reports/result.md"
               })

      assert read_result.tool_name == "fs.read_text_file"
      assert read_result.summary == "Read file reports/result.md"
      assert read_result.result.path == "reports/result.md"
      assert read_result.result.content == "hello from tools runtime"
    end

    test "rejects absolute and escaping paths", %{world: world, instance: instance} do
      assert {:error, %{code: "tool.fs.path_must_be_relative"}} =
               Runtime.execute(world, instance, "fs.write_text_file", %{
                 "path" => "/etc/passwd",
                 "content" => "nope"
               })

      assert {:error, %{code: "tool.fs.path_outside_workspace"}} =
               Runtime.execute(world, instance, "fs.read_text_file", %{"path" => "../secret.txt"})
    end
  end

  describe "execute/4 with web tools" do
    test "uses Req for web.search and returns normalized data", %{
      world: world,
      instance: instance
    } do
      bypass = Bypass.open()
      old_endpoint = Application.get_env(:lemmings_os, :tools_web_search_endpoint)

      Application.put_env(
        :lemmings_os,
        :tools_web_search_endpoint,
        "http://localhost:#{bypass.port}/search"
      )

      on_exit(fn ->
        if old_endpoint do
          Application.put_env(:lemmings_os, :tools_web_search_endpoint, old_endpoint)
        else
          Application.delete_env(:lemmings_os, :tools_web_search_endpoint)
        end
      end)

      Bypass.expect(bypass, fn conn ->
        conn = Plug.Conn.put_resp_content_type(conn, "application/json")

        Plug.Conn.resp(
          conn,
          200,
          ~s({"RelatedTopics":[{"Text":"Phoenix Framework","FirstURL":"https://www.phoenixframework.org"}]})
        )
      end)

      assert {:ok, result} =
               Runtime.execute(world, instance, "web.search", %{"query" => "phoenix"})

      assert result.tool_name == "web.search"
      assert [%{title: "Phoenix Framework"}] = result.result.results
    end

    test "fetches HTTP content with normalized response", %{world: world, instance: instance} do
      bypass = Bypass.open()

      Bypass.expect(bypass, fn conn ->
        Plug.Conn.resp(conn, 200, "runtime tools fetch payload")
      end)

      assert {:ok, result} =
               Runtime.execute(world, instance, "web.fetch", %{
                 "url" => "http://localhost:#{bypass.port}/content"
               })

      assert result.tool_name == "web.fetch"
      assert result.result.status == 200
      assert result.result.body == "runtime tools fetch payload"
    end
  end

  describe "execute/4 failures" do
    test "rejects tools outside the fixed catalog", %{world: world, instance: instance} do
      assert {:error, %{code: "tool.unsupported", tool_name: "exec.run"}} =
               Runtime.execute(world, instance, "exec.run", %{})
    end

    test "enforces explicit world scope", %{instance: instance} do
      world = %World{id: Ecto.UUID.generate()}

      assert {:error, %{code: "tool.invalid_scope"}} =
               Runtime.execute(world, instance, "web.fetch", %{"url" => "https://example.com"})
    end
  end
end
