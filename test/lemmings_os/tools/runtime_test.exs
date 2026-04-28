defmodule LemmingsOs.Tools.RuntimeTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Tools.Runtime
  alias LemmingsOs.Worlds.World

  setup do
    old_work_areas_path = Application.get_env(:lemmings_os, :work_areas_path)
    old_allow_private_hosts = Application.fetch_env(:lemmings_os, :tools_web_allow_private_hosts)
    old_trusted_tool_config = Application.fetch_env(:lemmings_os, :tools_runtime_trusted_config)
    old_github_token = System.get_env("GITHUB_TOKEN")

    work_areas_path =
      Path.join(
        System.tmp_dir!(),
        "lemmings_tools_runtime_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:lemmings_os, :work_areas_path, work_areas_path)
    Application.put_env(:lemmings_os, :tools_web_allow_private_hosts, true)
    File.mkdir_p!(work_areas_path)

    on_exit(fn ->
      if old_work_areas_path do
        Application.put_env(:lemmings_os, :work_areas_path, old_work_areas_path)
      else
        Application.delete_env(:lemmings_os, :work_areas_path)
      end

      restore_env(:tools_web_allow_private_hosts, old_allow_private_hosts)
      restore_env(:tools_runtime_trusted_config, old_trusted_tool_config)
      restore_system_env("GITHUB_TOKEN", old_github_token)

      File.rm_rf(work_areas_path)
    end)

    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)
    lemming = insert(:lemming, world: world, city: city, department: department)

    instance = %LemmingInstance{
      id: Ecto.UUID.generate(),
      world_id: world.id,
      city_id: city.id,
      department_id: department.id,
      lemming_id: lemming.id
    }

    File.mkdir_p!(Path.join(work_areas_path, instance.id))

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

      refute Map.has_key?(write_result.result, :workspace_path)

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
      assert {:error, %{code: "tool.validation.invalid_path"}} =
               Runtime.execute(world, instance, "fs.write_text_file", %{
                 "path" => "/etc/passwd",
                 "content" => "nope"
               })

      assert {:error, %{code: "tool.validation.invalid_path"}} =
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

    test "resolves trusted secret references from tool config and injects raw value only in adapter request",
         %{world: world, instance: instance} do
      bypass = Bypass.open()
      System.put_env("GITHUB_TOKEN", "dev_only_runtime_secret_token")

      Application.put_env(
        :lemmings_os,
        :tools_runtime_trusted_config,
        %{
          "web.fetch" => %{
            "headers" => %{"authorization" => "$secrets.github.token"}
          }
        }
      )

      Bypass.expect_once(bypass, "GET", "/with-secret", fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == [
                 "dev_only_runtime_secret_token"
               ]

        Plug.Conn.resp(conn, 200, "runtime tools fetch payload")
      end)

      assert {:ok, result} =
               Runtime.execute(world, instance, "web.fetch", %{
                 "url" => "http://localhost:#{bypass.port}/with-secret"
               })

      assert result.tool_name == "web.fetch"
      assert result.result.status == 200
    end

    test "does not execute adapter when trusted secret resolution fails", %{
      world: world,
      instance: instance
    } do
      bypass = Bypass.open()
      parent = self()
      System.delete_env("GITHUB_TOKEN")

      Application.put_env(
        :lemmings_os,
        :tools_runtime_trusted_config,
        %{
          "web.fetch" => %{
            "headers" => %{"authorization" => "$secrets.github.token"}
          }
        }
      )

      Bypass.stub(bypass, "GET", "/missing-secret", fn conn ->
        send(parent, :adapter_called)
        Plug.Conn.resp(conn, 200, "should not execute")
      end)

      assert {:error, %{code: "tool.secret.missing", details: details}} =
               Runtime.execute(world, instance, "web.fetch", %{
                 "url" => "http://localhost:#{bypass.port}/missing-secret"
               })

      assert details.secret_ref == "$secrets.github.token"
      assert details.bank_key == "github.token"
      refute_received :adapter_called
    end

    test "does not resolve secret references from tool args", %{world: world, instance: instance} do
      Application.put_env(:lemmings_os, :tools_runtime_trusted_config, %{})
      System.put_env("GITHUB_TOKEN", "dev_only_runtime_secret_token")

      assert {:error, %{code: "tool.web.invalid_url", details: %{url: "$secrets.github.token"}}} =
               Runtime.execute(world, instance, "web.fetch", %{"url" => "$secrets.github.token"})
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

  defp restore_env(key, {:ok, value}), do: Application.put_env(:lemmings_os, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:lemmings_os, key)

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)
end
