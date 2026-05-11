defmodule LemmingsOs.Tools.RuntimeTest do
  use LemmingsOs.DataCase, async: false
  @moduletag capture_log: true

  import Ecto.Query, only: [from: 2]

  alias LemmingsOs.Events.Event
  alias LemmingsOs.Knowledge
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Knowledge.SourceFile
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Repo
  alias LemmingsOs.SecretBank
  alias LemmingsOs.Tools.Runtime
  alias LemmingsOs.Tools.WorkArea
  alias LemmingsOs.Worlds.World

  setup do
    old_work_areas_path = Application.get_env(:lemmings_os, :work_areas_path)
    old_allow_private_hosts = Application.fetch_env(:lemmings_os, :tools_web_allow_private_hosts)
    old_trusted_tool_config = Application.fetch_env(:lemmings_os, :tools_runtime_trusted_config)
    old_github_token = System.get_env("GITHUB_TOKEN")
    old_embeddings = Application.get_env(:lemmings_os, :knowledge_embeddings, [])

    work_areas_path =
      Path.join(
        System.tmp_dir!(),
        "lemmings_tools_runtime_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:lemmings_os, :work_areas_path, work_areas_path)
    Application.put_env(:lemmings_os, :tools_web_allow_private_hosts, true)
    Application.put_env(:lemmings_os, :knowledge_embeddings, provider: :fake, dimensions: 1536)
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
      Application.put_env(:lemmings_os, :knowledge_embeddings, old_embeddings)

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

    {:ok, world: world, city: city, department: department, lemming: lemming, instance: instance}
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

  describe "execute/5 with email.create_draft" do
    test "normalizes adapter success with standard runtime envelope", %{
      world: world,
      instance: instance
    } do
      assert {:ok, _} = SecretBank.upsert_secret(world, "GMAIL_CLIENT_ID", "client-id")
      assert {:ok, _} = SecretBank.upsert_secret(world, "GMAIL_CLIENT_SECRET", "client-secret")
      assert {:ok, _} = SecretBank.upsert_secret(world, "GMAIL_REFRESH_TOKEN", "refresh-token")

      insert(:world_connection,
        world: world,
        type: "gmail",
        status: "enabled",
        config: %{
          "provider" => "gmail",
          "account_email" => "ops@example.com",
          "scopes" => ["https://www.googleapis.com/auth/gmail.compose"],
          "client_id" => "$GMAIL_CLIENT_ID",
          "client_secret" => "$GMAIL_CLIENT_SECRET",
          "refresh_token" => "$GMAIL_REFRESH_TOKEN"
        }
      )

      args = %{
        "connection_ref" => "gmail",
        "to" => ["customer@example.com"],
        "subject" => "Runtime envelope draft",
        "body" => "Hello from runtime",
        "body_format" => "text/plain"
      }

      runtime_meta = %{
        trusted_tool_config: %{
          "email.create_draft" => %{
            "gmail_client" => LemmingsOs.TestSupport.EmailDraftGmailClientSuccess,
            "gmail_client_opts" => %{
              "test_pid" => self(),
              "access_token" => "runtime-access-token"
            }
          }
        }
      }

      assert {:ok, result} =
               Runtime.execute(world, instance, "email.create_draft", args, runtime_meta)

      assert result.tool_name == "email.create_draft"
      assert result.args == args
      assert result.summary == "Created Gmail draft for customer@example.com with 0 attachments"
      assert result.preview == "Subject: Runtime envelope draft"
      assert result.result["status"] == "draft_created"
      assert result.result["provider"] == "gmail"
      assert result.result["connection_ref"] == "gmail"
      assert result.result["to"] == ["customer@example.com"]
      assert result.result["subject"] == "Runtime envelope draft"

      assert_receive {:email_draft_create_called, "runtime-access-token", _raw_message}
    end
  end

  describe "execute/4 with knowledge tools" do
    test "stores llm memory with lemming scope by default and minimal result payload", %{
      world: world,
      city: city,
      department: department,
      lemming: lemming,
      instance: instance
    } do
      persisted_instance =
        insert(:lemming_instance,
          world: world,
          city: city,
          department: department,
          lemming: lemming
        )

      assert :ok = PubSub.subscribe_instance_messages(persisted_instance.id)

      assert {:ok, result} =
               Runtime.execute(
                 world,
                 instance,
                 "knowledge.store",
                 %{
                   "title" => "ACME - email summary language",
                   "content" => "Client ACME prefers short email summaries in Portuguese.",
                   "tags" => ["customer:ACME", "language:pt-BR"]
                 },
                 %{actor_instance_id: persisted_instance.id}
               )

      assert result.tool_name == "knowledge.store"
      assert result.result.status == "stored"
      assert result.result.scope == "lemming"
      assert is_binary(result.result.knowledge_item_id)
      assert is_binary(result.summary)
      refute Map.has_key?(result.result, :world_id)
      refute Map.has_key?(result.result, :work_area_ref)

      memory = Repo.get!(KnowledgeItem, result.result.knowledge_item_id)

      assert memory.source == "llm"
      assert memory.status == "active"
      assert memory.kind == "memory"
      assert memory.world_id == instance.world_id
      assert memory.city_id == instance.city_id
      assert memory.department_id == instance.department_id
      assert memory.lemming_id == instance.lemming_id
      assert memory.creator_type == "tool_runtime"
      assert memory.creator_id == "knowledge.store"
      assert memory.creator_lemming_id == instance.lemming_id
      assert memory.creator_lemming_instance_id == persisted_instance.id

      persisted_instance_id = persisted_instance.id

      assert_receive {:message_appended,
                      %{
                        instance_id: ^persisted_instance_id,
                        message_id: message_id,
                        role: "assistant"
                      }}

      notification = Repo.get!(Message, message_id)
      assert notification.lemming_instance_id == persisted_instance.id
      assert String.contains?(notification.content, "Memory added:")
      assert String.contains?(notification.content, "/knowledge?memory_id=#{memory.id}")

      assert Repo.exists?(
               from(e in Event,
                 where:
                   e.event_type == "knowledge.memory.created_by_llm" and
                     e.resource_id == ^memory.id
               )
             )
    end

    test "accepts explicit scope hints within current ancestry", %{
      world: world,
      instance: instance
    } do
      assert {:ok, result} =
               Runtime.execute(
                 world,
                 instance,
                 "knowledge.store",
                 %{
                   "title" => "Language policy",
                   "content" => "Use Portuguese for this city.",
                   "scope" => %{
                     "world_id" => instance.world_id,
                     "city_id" => instance.city_id
                   }
                 }
               )

      assert result.result.scope == "city"
      memory = Repo.get!(KnowledgeItem, result.result.knowledge_item_id)
      assert memory.world_id == instance.world_id
      assert memory.city_id == instance.city_id
      assert is_nil(memory.department_id)
      assert is_nil(memory.lemming_id)
    end

    test "rejects unsupported file/category/type fields safely", %{
      world: world,
      instance: instance
    } do
      assert {:error, error} =
               Runtime.execute(
                 world,
                 instance,
                 "knowledge.store",
                 %{
                   "title" => "Invalid payload",
                   "content" => "Should fail",
                   "category" => "memory",
                   "type" => "client_preference",
                   "artifact_id" => Ecto.UUID.generate(),
                   "source_path" => "docs/file.md"
                 }
               )

      assert error.tool_name == "knowledge.store"
      assert error.code == "tool.knowledge.unsupported_fields"
      assert Enum.sort(error.details.fields) == ["artifact_id", "category", "source_path", "type"]
      assert Repo.aggregate(KnowledgeItem, :count, :id) == 0
    end

    test "rejects scope escalation outside the current execution ancestry", %{
      world: world,
      instance: instance
    } do
      other_city = insert(:city, world: world)

      assert {:error, error} =
               Runtime.execute(
                 world,
                 instance,
                 "knowledge.store",
                 %{
                   "title" => "Cross-scope attempt",
                   "content" => "Should fail",
                   "scope" => %{
                     "world_id" => instance.world_id,
                     "city_id" => other_city.id
                   }
                 }
               )

      assert error.tool_name == "knowledge.store"
      assert error.code == "tool.knowledge.invalid_scope"
      assert Repo.aggregate(KnowledgeItem, :count, :id) == 0
    end

    test "rejects missing required memory fields with safe validation envelope", %{
      world: world,
      instance: instance
    } do
      assert {:error, error} =
               Runtime.execute(
                 world,
                 instance,
                 "knowledge.store",
                 %{
                   "title" => "   ",
                   "content" => ""
                 }
               )

      assert error.tool_name == "knowledge.store"
      assert error.code == "tool.validation.invalid_args"
      assert error.message == "Invalid tool arguments"
      assert "title" in error.details.required
      assert Repo.aggregate(KnowledgeItem, :count, :id) == 0
    end

    test "notification write failures do not roll back a successful memory store", %{
      world: world,
      instance: instance
    } do
      missing_instance_id = Ecto.UUID.generate()

      assert {:ok, result} =
               Runtime.execute(
                 world,
                 instance,
                 "knowledge.store",
                 %{
                   "title" => "Persist even when notification fails",
                   "content" => "Notification is best effort only."
                 },
                 %{actor_instance_id: missing_instance_id}
               )

      assert result.tool_name == "knowledge.store"
      assert result.result.status == "stored"
      assert is_binary(result.result.knowledge_item_id)

      memory = Repo.get!(KnowledgeItem, result.result.knowledge_item_id)
      assert memory.title == "Persist even when notification fails"

      refute Repo.exists?(
               from(message in Message,
                 where:
                   message.lemming_instance_id == ^missing_instance_id and
                     message.world_id == ^world.id
               )
             )
    end

    test "llm memory audit payload excludes content and runtime internals", %{
      world: world,
      city: city,
      department: department,
      lemming: lemming,
      instance: instance
    } do
      persisted_instance =
        insert(:lemming_instance,
          world: world,
          city: city,
          department: department,
          lemming: lemming
        )

      assert {:ok, result} =
               Runtime.execute(
                 world,
                 instance,
                 "knowledge.store",
                 %{
                   "title" => "Safe payload check",
                   "content" =>
                     "SENTINEL_SECRET_TOKEN_MEMORY_001 SENTINEL_RUNTIME_DUMP_{\"raw\":\"state\"}",
                   "tags" => ["sentinel"]
                 },
                 %{actor_instance_id: persisted_instance.id, work_area_ref: "work-area-v1/secret"}
               )

      memory_id = result.result.knowledge_item_id

      event =
        Repo.one!(
          from(e in Event,
            where:
              e.event_type == "knowledge.memory.created_by_llm" and e.resource_id == ^memory_id
          )
        )

      assert event.payload["knowledge_item_id"] == memory_id
      assert event.payload["world_id"] == world.id
      assert event.payload["city_id"] == city.id
      assert event.payload["department_id"] == department.id
      assert event.payload["lemming_id"] == lemming.id
      assert event.payload["creator_id"] == "knowledge.store"
      assert event.payload["actor_instance_id"] == instance.id
      refute Map.has_key?(event.payload, "content")
      refute Map.has_key?(event.payload, "work_area_ref")
      refute Map.has_key?(event.payload, "path")
      refute Map.has_key?(event.payload, "runtime")
    end

    test "searches ready source-file chunks with safe payload", %{
      world: world,
      department: department,
      instance: instance
    } do
      %{chunk_ref: chunk_ref} = create_ready_source_file_chunk!(world, department, "policy")

      assert {:ok, result} =
               Runtime.execute(world, instance, "knowledge.search", %{
                 "query" => "payment terms",
                 "kind" => "source_file",
                 "source_file_type" => "policy",
                 "tags" => ["customer:acme"],
                 "top_k" => 3
               })

      assert result.tool_name == "knowledge.search"
      assert result.result.kind == "source_file"
      assert result.result.scope == "lemming"
      assert result.result.count >= 1
      assert [%{chunk_ref: ^chunk_ref} = first | _] = result.result.results
      assert is_float(first.score)
      assert is_binary(first.snippet)
      refute Map.has_key?(first, :embedding)
      refute Map.has_key?(first, :storage_ref)
    end

    test "reads one chunk with bounded content and returns not_found safely", %{
      world: world,
      department: department,
      instance: instance
    } do
      %{chunk_ref: chunk_ref, content: content} =
        create_ready_source_file_chunk!(
          world,
          department,
          "policy",
          String.duplicate("abc", 2_000)
        )

      assert {:ok, result} =
               Runtime.execute(world, instance, "knowledge.read", %{
                 "chunk_ref" => chunk_ref,
                 "max_chars" => 250
               })

      assert result.tool_name == "knowledge.read"
      assert result.result.chunk_ref == chunk_ref
      assert result.result.content_length == 250
      assert result.result.truncated == true
      assert String.starts_with?(content, result.result.content)

      assert {:error, error} =
               Runtime.execute(world, instance, "knowledge.read", %{
                 "chunk_ref" => "missing-chunk-ref"
               })

      assert error.tool_name == "knowledge.read"
      assert error.code == "tool.knowledge.not_found"
    end

    test "denies cross-scope reads and invalid scope hints safely", %{
      world: world,
      city: city,
      instance: instance
    } do
      sibling_department = insert(:department, world: world, city: city)

      %{chunk_ref: sibling_chunk_ref} =
        create_ready_source_file_chunk!(world, sibling_department, "policy", "Sibling-only chunk")

      assert {:error, read_error} =
               Runtime.execute(world, instance, "knowledge.read", %{
                 "chunk_ref" => sibling_chunk_ref
               })

      assert read_error.tool_name == "knowledge.read"
      assert read_error.code == "tool.knowledge.not_found"

      other_city = insert(:city, world: world)

      assert {:error, search_error} =
               Runtime.execute(world, instance, "knowledge.search", %{
                 "query" => "policy",
                 "kind" => "source_file",
                 "scope" => %{"world_id" => world.id, "city_id" => other_city.id}
               })

      assert search_error.tool_name == "knowledge.search"
      assert search_error.code == "tool.knowledge.invalid_scope"
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
            "allowed_hosts" => ["localhost"],
            "headers" => %{"authorization" => "$GITHUB_TOKEN"}
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

      events =
        Repo.all(
          from(event in Event,
            where:
              event.world_id == ^world.id and
                event.event_type in ^["secret.resolved", "secret.used_by_tool"],
            order_by: [asc: event.inserted_at, asc: event.id]
          )
        )

      assert MapSet.new(Enum.map(events, & &1.event_type)) ==
               MapSet.new(["secret.resolved", "secret.used_by_tool"])

      resolved = Enum.find(events, &(&1.event_type == "secret.resolved"))
      used_by_tool = Enum.find(events, &(&1.event_type == "secret.used_by_tool"))

      assert fetch_map(resolved.payload, :key) == "GITHUB_TOKEN"
      assert fetch_map(resolved.payload, :resolved_source) == "env"

      assert fetch_map(used_by_tool.payload, :key) == "GITHUB_TOKEN"
      assert fetch_map(used_by_tool.payload, :tool_name) == "web.fetch"
      assert fetch_map(used_by_tool.payload, :adapter_name) == "LemmingsOs.Tools.Adapters.Web"
      assert fetch_map(used_by_tool.payload, :lemming_instance_id) == instance.id
      assert fetch_map(used_by_tool.payload, :world_id) == world.id
      assert fetch_map(used_by_tool.payload, :city_id) == instance.city_id
      assert fetch_map(used_by_tool.payload, :department_id) == instance.department_id
      assert fetch_map(used_by_tool.payload, :lemming_id) == instance.lemming_id
      assert fetch_map(used_by_tool.payload, :resolved_source) == "env"
      assert used_by_tool.status == "succeeded"

      refute inspect(Enum.map(events, & &1.payload)) =~ "dev_only_runtime_secret_token"

      refute Repo.exists?(
               from(event in Event,
                 where:
                   event.world_id == ^world.id and
                     event.event_type in ^["secret.accessed", "secret.access_failed"]
               )
             )
    end

    test "redacts reflected resolved secrets before returning adapter output", %{
      world: world,
      instance: instance
    } do
      bypass = Bypass.open()
      System.put_env("GITHUB_TOKEN", "dev_only_runtime_secret_token")

      Application.put_env(
        :lemmings_os,
        :tools_runtime_trusted_config,
        %{
          "web.fetch" => %{
            "allowed_hosts" => ["localhost"],
            "headers" => %{"authorization" => "$GITHUB_TOKEN"}
          }
        }
      )

      Bypass.expect_once(bypass, "GET", "/echo-secret", fn conn ->
        [authorization] = Plug.Conn.get_req_header(conn, "authorization")
        Plug.Conn.resp(conn, 200, "reflected header=#{authorization}")
      end)

      assert {:ok, result} =
               Runtime.execute(world, instance, "web.fetch", %{
                 "url" => "http://localhost:#{bypass.port}/echo-secret"
               })

      assert result.tool_name == "web.fetch"
      assert result.result.body == "reflected header=[REDACTED]"
      assert result.preview == "reflected header=[REDACTED]"
      refute inspect(result) =~ "dev_only_runtime_secret_token"
    end

    test "blocks secret-bearing headers unless the destination host is explicitly allowlisted", %{
      world: world,
      instance: instance
    } do
      bypass = Bypass.open()
      parent = self()
      System.put_env("GITHUB_TOKEN", "dev_only_runtime_secret_token")

      Application.put_env(
        :lemmings_os,
        :tools_runtime_trusted_config,
        %{
          "web.fetch" => %{
            "headers" => %{"authorization" => "$GITHUB_TOKEN"}
          }
        }
      )

      Bypass.stub(bypass, "GET", "/blocked-secret", fn conn ->
        send(parent, :adapter_called)
        Plug.Conn.resp(conn, 200, "should not execute")
      end)

      assert {:error, %{code: "tool.secret.destination_not_allowed", details: details}} =
               Runtime.execute(world, instance, "web.fetch", %{
                 "url" => "http://localhost:#{bypass.port}/blocked-secret"
               })

      assert details.host == "localhost"
      refute_received :adapter_called

      refute Repo.exists?(
               from(event in Event,
                 where: event.world_id == ^world.id and event.event_type == "secret.used_by_tool"
               )
             )
    end

    test "records secret header use as failed when the adapter request fails", %{
      world: world,
      instance: instance
    } do
      bypass = Bypass.open()
      System.put_env("GITHUB_TOKEN", "dev_only_runtime_secret_token")

      Application.put_env(
        :lemmings_os,
        :tools_runtime_trusted_config,
        %{
          "web.fetch" => %{
            "allowed_hosts" => ["localhost"],
            "headers" => %{"authorization" => "$GITHUB_TOKEN"}
          }
        }
      )

      Bypass.expect_once(bypass, "GET", "/server-error", fn conn ->
        Plug.Conn.resp(conn, 500, "upstream failed")
      end)

      assert {:error, %{code: "tool.web.bad_status"}} =
               Runtime.execute(world, instance, "web.fetch", %{
                 "url" => "http://localhost:#{bypass.port}/server-error"
               })

      [used_by_tool] =
        Repo.all(
          from(event in Event,
            where: event.world_id == ^world.id and event.event_type == "secret.used_by_tool"
          )
        )

      assert used_by_tool.status == "failed"
      assert fetch_map(used_by_tool.payload, :key) == "GITHUB_TOKEN"
      refute inspect(used_by_tool.payload) =~ "dev_only_runtime_secret_token"
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
            "headers" => %{"authorization" => "$GITHUB_TOKEN"}
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

      assert details.secret_ref == "$GITHUB_TOKEN"
      assert details.bank_key == "GITHUB_TOKEN"
      refute_received :adapter_called

      [failed] =
        Repo.all(
          from(event in Event,
            where: event.world_id == ^world.id and event.event_type == "secret.resolve_failed"
          )
        )

      assert fetch_map(failed.payload, :key) == "GITHUB_TOKEN"
      assert fetch_map(failed.payload, :reason) == "missing_secret"

      refute Repo.exists?(
               from(event in Event,
                 where:
                   event.world_id == ^world.id and
                     event.event_type in ^[
                       "secret.accessed",
                       "secret.access_failed",
                       "secret.used_by_tool"
                     ]
               )
             )
    end

    test "does not resolve secret references from tool args", %{world: world, instance: instance} do
      Application.put_env(:lemmings_os, :tools_runtime_trusted_config, %{})
      System.put_env("GITHUB_TOKEN", "dev_only_runtime_secret_token")

      assert {:error, %{code: "tool.web.invalid_url", details: %{url: "$GITHUB_TOKEN"}}} =
               Runtime.execute(world, instance, "web.fetch", %{"url" => "$GITHUB_TOKEN"})

      refute Repo.exists?(
               from(event in Event,
                 where:
                   event.world_id == ^world.id and
                     event.event_type in ^["secret.resolved", "secret.used_by_tool"] and
                     fragment("?->>'key' = ?", event.payload, "GITHUB_TOKEN")
               )
             )
    end

    test "rejects legacy $secrets.* references in trusted config", %{
      world: world,
      instance: instance
    } do
      bypass = Bypass.open()
      parent = self()
      System.put_env("GITHUB_TOKEN", "dev_only_runtime_secret_token")

      Application.put_env(
        :lemmings_os,
        :tools_runtime_trusted_config,
        %{
          "web.fetch" => %{
            "headers" => %{"authorization" => "$secrets.GITHUB_TOKEN"}
          }
        }
      )

      Bypass.stub(bypass, "GET", "/legacy-ref", fn conn ->
        send(parent, :adapter_called)
        Plug.Conn.resp(conn, 200, "should not execute")
      end)

      assert {:error, %{code: "tool.secret.invalid_reference", details: details}} =
               Runtime.execute(world, instance, "web.fetch", %{
                 "url" => "http://localhost:#{bypass.port}/legacy-ref"
               })

      assert details.secret_ref == "$secrets.GITHUB_TOKEN"
      assert details.reason == "invalid_key"
      refute_received :adapter_called
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

  describe "execute/5 with documents tools" do
    test "dispatches documents.markdown_to_html with normalized success envelope", %{
      world: world,
      instance: instance
    } do
      work_area = Path.join(Application.fetch_env!(:lemmings_os, :work_areas_path), instance.id)
      File.mkdir_p!(Path.join(work_area, "notes"))
      File.write!(Path.join(work_area, "notes/a.md"), "# Runtime Title")

      assert {:ok, result} =
               Runtime.execute(
                 world,
                 instance,
                 "documents.markdown_to_html",
                 %{"source_path" => "notes/a.md", "output_path" => "notes/a.html"}
               )

      assert result.tool_name == "documents.markdown_to_html"
      assert result.args == %{"source_path" => "notes/a.md", "output_path" => "notes/a.html"}
      assert result.summary == "Converted notes/a.md to notes/a.html"
      assert is_binary(result.preview)
      assert result.result["source_path"] == "notes/a.md"
      assert result.result["output_path"] == "notes/a.html"
      assert result.result["content_type"] == "text/html"
      assert is_integer(result.result["bytes"])
    end

    test "dispatches documents.markdown_to_html with derived output_path when omitted", %{
      world: world,
      instance: instance
    } do
      work_area = Path.join(Application.fetch_env!(:lemmings_os, :work_areas_path), instance.id)
      File.mkdir_p!(Path.join(work_area, "notes"))
      File.write!(Path.join(work_area, "notes/default.md"), "# Runtime Default")

      assert {:ok, result} =
               Runtime.execute(
                 world,
                 instance,
                 "documents.markdown_to_html",
                 %{"source_path" => "notes/default.md"}
               )

      assert result.tool_name == "documents.markdown_to_html"
      assert result.args == %{"source_path" => "notes/default.md"}
      assert result.summary == "Converted notes/default.md to notes/default.html"
      assert result.result["output_path"] == "notes/default.html"
      assert File.exists?(Path.join(work_area, "notes/default.html"))
    end

    test "dispatches documents.markdown_to_html with markdown_path alias", %{
      world: world,
      instance: instance
    } do
      work_area = Path.join(Application.fetch_env!(:lemmings_os, :work_areas_path), instance.id)
      File.mkdir_p!(Path.join(work_area, "notes"))
      File.write!(Path.join(work_area, "notes/alias.md"), "# Runtime Alias")

      assert {:ok, result} =
               Runtime.execute(
                 world,
                 instance,
                 "documents.markdown_to_html",
                 %{"markdown_path" => "notes/alias.md"}
               )

      assert result.tool_name == "documents.markdown_to_html"
      assert result.args == %{"markdown_path" => "notes/alias.md"}
      assert result.summary == "Converted notes/alias.md to notes/alias.html"
      assert result.result["source_path"] == "notes/alias.md"
      assert result.result["output_path"] == "notes/alias.html"
      assert File.exists?(Path.join(work_area, "notes/alias.html"))
    end

    test "dispatches documents.print_to_pdf with normalized validation error", %{
      world: world,
      instance: instance
    } do
      assert {:error, error} =
               Runtime.execute(
                 world,
                 instance,
                 "documents.print_to_pdf",
                 %{"source_path" => "notes/a.md", "output_path" => ""},
                 %{work_area_ref: "work-area-v1"}
               )

      assert error.tool_name == "documents.print_to_pdf"
      assert error.code == "tool.validation.invalid_args"
      assert error.message == "Invalid tool arguments"
      assert error.details == %{field: "output_path"}
    end

    test "dispatches documents.print_to_pdf with normalized success envelope", %{
      world: world,
      instance: instance
    } do
      bypass = Bypass.open()
      old_documents_config = Application.get_env(:lemmings_os, :documents)

      Application.put_env(
        :lemmings_os,
        :documents,
        gotenberg_url: "http://localhost:#{bypass.port}",
        pdf_timeout_ms: 2_000,
        pdf_connect_timeout_ms: 2_000,
        pdf_retries: 0,
        max_source_bytes: 1024 * 1024,
        max_pdf_bytes: 1024 * 1024
      )

      on_exit(fn ->
        if old_documents_config do
          Application.put_env(:lemmings_os, :documents, old_documents_config)
        else
          Application.delete_env(:lemmings_os, :documents)
        end
      end)

      work_area = Path.join(Application.fetch_env!(:lemmings_os, :work_areas_path), instance.id)
      File.mkdir_p!(Path.join(work_area, "notes"))

      File.write!(
        Path.join(work_area, "notes/source.html"),
        "<html><body>Runtime PDF</body></html>"
      )

      Bypass.expect_once(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "Runtime PDF"
        Plug.Conn.resp(conn, 200, "%PDF runtime")
      end)

      assert {:ok, result} =
               Runtime.execute(
                 world,
                 instance,
                 "documents.print_to_pdf",
                 %{"source_path" => "notes/source.html", "output_path" => "notes/source.pdf"}
               )

      assert result.tool_name == "documents.print_to_pdf"

      assert result.args == %{
               "source_path" => "notes/source.html",
               "output_path" => "notes/source.pdf"
             }

      assert result.summary == "Printed notes/source.html to notes/source.pdf"
      assert result.preview == nil
      assert result.result["source_path"] == "notes/source.html"
      assert result.result["output_path"] == "notes/source.pdf"
      assert result.result["content_type"] == "application/pdf"
      assert is_integer(result.result["bytes"])
    end

    test "dispatches documents.print_to_pdf with derived output_path when omitted", %{
      world: world,
      instance: instance
    } do
      bypass = Bypass.open()
      old_documents_config = Application.get_env(:lemmings_os, :documents)

      Application.put_env(
        :lemmings_os,
        :documents,
        gotenberg_url: "http://localhost:#{bypass.port}",
        pdf_timeout_ms: 2_000,
        pdf_connect_timeout_ms: 2_000,
        pdf_retries: 0,
        max_source_bytes: 1024 * 1024,
        max_pdf_bytes: 1024 * 1024
      )

      on_exit(fn ->
        if old_documents_config do
          Application.put_env(:lemmings_os, :documents, old_documents_config)
        else
          Application.delete_env(:lemmings_os, :documents)
        end
      end)

      work_area = Path.join(Application.fetch_env!(:lemmings_os, :work_areas_path), instance.id)
      File.mkdir_p!(Path.join(work_area, "notes"))

      File.write!(
        Path.join(work_area, "notes/default.html"),
        "<html><body>Default PDF</body></html>"
      )

      Bypass.expect_once(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "Default PDF"
        Plug.Conn.resp(conn, 200, "%PDF default")
      end)

      assert {:ok, result} =
               Runtime.execute(
                 world,
                 instance,
                 "documents.print_to_pdf",
                 %{"source_path" => "notes/default.html"}
               )

      assert result.tool_name == "documents.print_to_pdf"
      assert result.args == %{"source_path" => "notes/default.html"}
      assert result.summary == "Printed notes/default.html to notes/default.pdf"
      assert result.result["output_path"] == "notes/default.pdf"
      assert File.read!(Path.join(work_area, "notes/default.pdf")) == "%PDF default"
    end

    test "honors runtime work_area_ref metadata for documents tool execution", %{
      world: world,
      instance: instance
    } do
      work_area_ref = Ecto.UUID.generate()
      assert :ok = WorkArea.ensure(work_area_ref)

      work_area = Path.join(Application.fetch_env!(:lemmings_os, :work_areas_path), work_area_ref)
      File.mkdir_p!(Path.join(work_area, "notes"))
      File.write!(Path.join(work_area, "notes/metadata.md"), "# Metadata Area")

      assert {:ok, result} =
               Runtime.execute(
                 world,
                 instance,
                 "documents.markdown_to_html",
                 %{
                   "source_path" => "notes/metadata.md",
                   "output_path" => "notes/metadata.html"
                 },
                 %{work_area_ref: work_area_ref}
               )

      assert result.tool_name == "documents.markdown_to_html"
      assert result.result["source_path"] == "notes/metadata.md"
      assert File.exists?(Path.join(work_area, "notes/metadata.html"))
    end
  end

  defp restore_env(key, {:ok, value}), do: Application.put_env(:lemmings_os, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:lemmings_os, key)

  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)

  defp create_ready_source_file_chunk!(
         world,
         scope,
         source_file_type,
         content \\ "Policy chunk text"
       ) do
    {:ok, %{source_file: source_file}} =
      Knowledge.create_source_file(scope, %{
        source_file_type: source_file_type,
        original_filename: "#{source_file_type}.md",
        content_type: "text/markdown",
        size_bytes: 1_024,
        storage_ref:
          "local://knowledge_source_files/#{world.id}/#{Ecto.UUID.generate()}/#{source_file_type}.md",
        title: "Source #{source_file_type}",
        tags: ["customer:acme"]
      })

    source_file = Repo.preload(source_file, :knowledge_item)

    source_file.knowledge_item
    |> KnowledgeItem.changeset(%{status: "ready"})
    |> Repo.update!()

    source_file
    |> SourceFile.changeset(%{extraction_status: "ready", indexing_status: "ready"})
    |> Repo.update!()

    chunk =
      insert(:knowledge_source_file_chunk,
        knowledge_item: source_file.knowledge_item,
        knowledge_source_file: source_file,
        chunk_ref: "chunk-#{System.unique_integer([:positive])}",
        content: content,
        content_hash: Base.encode16(:crypto.hash(:sha256, content), case: :lower),
        char_count: String.length(content)
      )

    {:ok, _result} =
      Repo.query(
        "update knowledge_source_file_chunks set embedding = $1 where id = $2::uuid",
        [List.duplicate(0.1, 1536), Ecto.UUID.dump!(chunk.id)]
      )

    %{chunk_ref: chunk.chunk_ref, content: content}
  end

  defp fetch_map(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
