defmodule LemmingsOs.Tools.Adapters.EmailTest do
  use LemmingsOs.DataCase, async: false

  import ExUnit.CaptureLog

  alias LemmingsOs.Artifacts.LocalStorage
  alias LemmingsOs.Connections.Providers.GmailCaller
  alias LemmingsOs.Events
  alias LemmingsOs.SecretBank
  alias LemmingsOs.Tools.Adapters.Email

  doctest Email

  setup do
    old_storage = Application.get_env(:lemmings_os, :artifact_storage)
    old_email_draft = Application.get_env(:lemmings_os, :email_draft)

    storage_root =
      Path.join(
        System.tmp_dir!(),
        "lemmings_email_adapter_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:lemmings_os, :artifact_storage, backend: :local, root_path: storage_root)
    File.mkdir_p!(storage_root)

    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)
    lemming = insert(:lemming, world: world, city: city, department: department)

    instance =
      insert(:lemming_instance,
        world: world,
        city: city,
        department: department,
        lemming: lemming
      )

    on_exit(fn ->
      if old_storage do
        Application.put_env(:lemmings_os, :artifact_storage, old_storage)
      else
        Application.delete_env(:lemmings_os, :artifact_storage)
      end

      if old_email_draft do
        Application.put_env(:lemmings_os, :email_draft, old_email_draft)
      else
        Application.delete_env(:lemmings_os, :email_draft)
      end

      File.rm_rf(storage_root)
    end)

    {:ok,
     world: world,
     city: city,
     department: department,
     lemming: lemming,
     instance: instance,
     storage_root: storage_root}
  end

  test "creates a Gmail draft with text/plain body and no attachments", context do
    put_gmail_runtime_config!(context)

    assert {:ok, result} =
             Email.create_draft(
               context.instance,
               %{
                 "connection_ref" => "gmail",
                 "to" => ["customer@example.com"],
                 "subject" => "Plain text draft",
                 "body" => "Hello from LemmingsOS",
                 "body_format" => "text/plain"
               },
               %{},
               success_config(self())
             )

    assert result.summary == "Created Gmail draft for 1 recipient(s) with 0 attachments"
    assert result.preview == "Subject: Plain text draft"
    assert result.result["status"] == "draft_created"
    assert result.result["provider"] == "gmail"
    assert result.result["connection_ref"] == "gmail"
    assert result.result["draft_id"] == "draft-abc"
    assert result.result["message_id"] == "message-abc"
    assert result.result["to_count"] == 1
    assert result.result["cc_count"] == 0
    assert result.result["bcc_count"] == 0
    assert result.result["subject_preview"] == "Plain text draft"
    assert result.result["artifact_count"] == 0
    assert result.result["artifact_ids"] == []
    refute Map.has_key?(result.result, "to")
    refute Map.has_key?(result.result, "subject")

    assert_receive {:email_draft_create_called, "access-token", raw_message}
    assert {:ok, mime} = Base.url_decode64(raw_message, padding: false)
    assert mime =~ "Content-Type: text/plain; charset=\"UTF-8\""
    assert mime =~ "To: customer@example.com"
    assert mime =~ "Subject: Plain text draft"
  end

  test "normalizes string recipients, blank optional recipients, and default body format",
       context do
    put_gmail_runtime_config!(context)

    assert {:ok, result} =
             Email.create_draft(
               context.instance,
               %{
                 "connection_ref" => "gmail",
                 "to" => "first@example.com, second@example.com",
                 "cc" => "",
                 "bcc" => nil,
                 "subject" => "Default format draft",
                 "body" => "Hello from LemmingsOS"
               },
               %{},
               success_config(self())
             )

    assert result.result["to_count"] == 2
    assert result.result["cc_count"] == 0
    assert result.result["bcc_count"] == 0

    assert_receive {:email_draft_create_called, "access-token", raw_message}
    assert {:ok, mime} = Base.url_decode64(raw_message, padding: false)
    assert mime =~ "Content-Type: text/plain; charset=\"UTF-8\""
    assert mime =~ "To: first@example.com, second@example.com"
    refute mime =~ "\r\nCc:"
    refute mime =~ "\r\nBcc:"
  end

  test "normalizes comma-separated cc and bcc recipient strings", context do
    put_gmail_runtime_config!(context)

    assert {:ok, result} =
             Email.create_draft(
               context.instance,
               %{
                 "connection_ref" => "gmail",
                 "to" => ["customer@example.com"],
                 "cc" => "ops@example.com, sales@example.com",
                 "bcc" => "audit@example.com",
                 "subject" => "Recipient draft",
                 "body" => "Hello",
                 "body_format" => ""
               },
               %{},
               success_config(self())
             )

    assert result.result["cc_count"] == 2
    assert result.result["bcc_count"] == 1

    assert_receive {:email_draft_create_called, "access-token", raw_message}
    assert {:ok, mime} = Base.url_decode64(raw_message, padding: false)
    assert mime =~ "Cc: ops@example.com, sales@example.com"
    assert mime =~ "Bcc: audit@example.com"
    assert mime =~ "Content-Type: text/plain; charset=\"UTF-8\""
  end

  test "creates a Gmail draft with text/html body and one attachment", context do
    put_gmail_runtime_config!(context)
    artifact = insert_ready_artifact!(context, "quote.pdf", "application/pdf", "%PDF-1.4 body")

    assert {:ok, result} =
             Email.create_draft(
               context.instance,
               %{
                 "connection_ref" => "gmail",
                 "to" => ["sales@example.com"],
                 "cc" => ["team@example.com"],
                 "subject" => "Quote draft",
                 "body" => "<p>Quote attached</p>",
                 "body_format" => "text/html",
                 "artifact_ids" => [artifact.id]
               },
               %{},
               success_config(self())
             )

    assert result.result["artifact_ids"] == [artifact.id]
    assert result.result["cc_count"] == 1
    assert result.result["artifact_count"] == 1

    assert_receive {:email_draft_create_called, "access-token", raw_message}
    assert {:ok, mime} = Base.url_decode64(raw_message, padding: false)
    assert mime =~ "Content-Type: multipart/mixed"
    assert mime =~ "Content-Type: text/html; charset=\"UTF-8\""
    assert mime =~ "Content-Type: application/pdf; name=\"quote.pdf\""
    assert mime =~ "Content-Disposition: attachment; filename=\"quote.pdf\""
  end

  test "creates a Gmail draft with multiple attachments", context do
    put_gmail_runtime_config!(context)
    first = insert_ready_artifact!(context, "a.txt", "text/plain", "A content")
    second = insert_ready_artifact!(context, "b.txt", "text/plain", "B content")

    assert {:ok, result} =
             Email.create_draft(
               context.instance,
               %{
                 "connection_ref" => "gmail",
                 "to" => ["ops@example.com"],
                 "subject" => "Multi attachment draft",
                 "body" => "See files",
                 "body_format" => "text/plain",
                 "artifact_ids" => [first.id, second.id]
               },
               %{},
               success_config(self())
             )

    assert result.result["artifact_ids"] == [first.id, second.id]
    assert_receive {:email_draft_create_called, "access-token", raw_message}
    assert {:ok, mime} = Base.url_decode64(raw_message, padding: false)
    assert mime =~ "filename=\"a.txt\""
    assert mime =~ "filename=\"b.txt\""
  end

  test "returns connection_not_found when Gmail connection is missing", context do
    assert {:error, error} =
             Email.create_draft(
               context.instance,
               %{
                 "connection_ref" => "gmail",
                 "to" => ["ops@example.com"],
                 "subject" => "Missing connection",
                 "body" => "Body",
                 "body_format" => "text/plain"
               },
               %{},
               success_config(self())
             )

    assert error.code == "tool.email.connection_not_found"
  end

  test "returns connection_not_allowed for disabled or invalid Gmail connection", context do
    put_gmail_runtime_config!(context)
    connection = LemmingsOs.Connections.get_connection_by_type(context.world, "gmail")

    assert {:ok, _} =
             LemmingsOs.Connections.update_connection(context.world, connection, %{
               status: "disabled"
             })

    assert {:error, %{code: "tool.email.connection_not_allowed"}} =
             Email.create_draft(
               context.instance,
               valid_args(),
               %{},
               success_config(self())
             )

    assert {:ok, _} =
             LemmingsOs.Connections.update_connection(context.world, connection, %{
               status: "invalid"
             })

    assert {:error, %{code: "tool.email.connection_not_allowed"}} =
             Email.create_draft(
               context.instance,
               valid_args(),
               %{},
               success_config(self())
             )
  end

  test "returns connection_auth_failed when refresh token exchange fails", context do
    put_gmail_runtime_config!(context)

    assert {:error, error} =
             Email.create_draft(
               context.instance,
               valid_args(),
               %{},
               %{
                 "gmail_client" => LemmingsOs.TestSupport.EmailDraftGmailClientAuthFailure
               }
             )

    assert error.code == "tool.email.connection_auth_failed"
  end

  test "returns draft_create_failed when provider draft call fails", context do
    put_gmail_runtime_config!(context)

    assert {:error, error} =
             Email.create_draft(
               context.instance,
               valid_args(),
               %{},
               %{
                 "gmail_client" => LemmingsOs.TestSupport.EmailDraftGmailClientDraftFailure
               }
             )

    assert error.code == "tool.email.draft_create_failed"
  end

  test "falls back to default Gmail client when trusted gmail_client is nil", context do
    put_gmail_runtime_config!(context)

    assert {:ok, result} =
             Email.create_draft(
               context.instance,
               valid_args(),
               %{},
               %{
                 "gmail_client" => nil,
                 "gmail_client_opts" => %{
                   "req" => LemmingsOs.TestSupport.EmailDraftReqSuccess
                 }
               }
             )

    assert result.result["status"] == "draft_created"
    assert result.result["draft_id"] == "draft-123"
    assert result.result["message_id"] == "message-123"
  end

  test "validates recipients, body format, and rejects raw path fields", context do
    put_gmail_runtime_config!(context)

    assert {:error, %{code: "tool.email.invalid_recipient", details: %{field: "to"}}} =
             Email.create_draft(
               context.instance,
               %{
                 "connection_ref" => "gmail",
                 "to" => ["not-an-email"],
                 "subject" => "Invalid",
                 "body" => "Body",
                 "body_format" => "text/plain"
               },
               %{},
               success_config(self())
             )

    assert {:error, %{code: "tool.email.invalid_body_format"}} =
             Email.create_draft(
               context.instance,
               %{
                 "connection_ref" => "gmail",
                 "to" => ["valid@example.com"],
                 "subject" => "Invalid format",
                 "body" => "Body",
                 "body_format" => "text/markdown"
               },
               %{},
               success_config(self())
             )

    assert {:error,
            %{code: "tool.validation.invalid_args", details: %{unsupported_fields: fields}}} =
             Email.create_draft(
               context.instance,
               %{
                 "connection_ref" => "gmail",
                 "to" => ["valid@example.com"],
                 "subject" => "Invalid field",
                 "body" => "Body",
                 "body_format" => "text/plain",
                 "attachment_paths" => ["/tmp/secret.pdf"]
               },
               %{},
               success_config(self())
             )

    assert "attachment_paths" in fields
  end

  test "invalid arguments emit safe draft_failed event without raw input values", context do
    put_gmail_runtime_config!(context)

    raw_body = "sentinel body should not be observed"
    raw_subject = "sentinel subject should not be observed"
    raw_recipient = "raw-recipient@example.com"
    raw_path = "/tmp/sentinel-secret.pdf"
    raw_token = "sentinel-access-token"

    assert {:error, %{code: "tool.validation.invalid_args"} = error} =
             Email.create_draft(
               context.instance,
               %{
                 "connection_ref" => "gmail",
                 "to" => [raw_recipient],
                 "subject" => raw_subject,
                 "body" => raw_body,
                 "body_format" => "text/plain",
                 "attachment_paths" => [raw_path],
                 "access_token" => raw_token
               },
               %{},
               success_config(self())
             )

    assert error.details.unsupported_fields == ["access_token", "attachment_paths"]

    [event] =
      Events.list_recent_events(
        %{
          world_id: context.world.id,
          city_id: context.city.id,
          department_id: context.department.id,
          lemming_id: context.lemming.id
        },
        event_types: ["email.draft_failed"],
        limit: 1
      )

    assert event.payload["world_id"] == context.world.id
    assert event.payload["city_id"] == context.city.id
    assert event.payload["department_id"] == context.department.id
    assert event.payload["lemming_instance_id"] == context.instance.id
    assert event.payload["tool_name"] == "email.create_draft"
    assert event.payload["status"] == "failed"
    assert event.payload["error_code"] == "invalid_args"

    inspected_payload = inspect(event.payload)
    refute inspected_payload =~ raw_body
    refute inspected_payload =~ raw_subject
    refute inspected_payload =~ raw_recipient
    refute inspected_payload =~ raw_path
    refute inspected_payload =~ raw_token
    refute inspected_payload =~ "attachment_paths"
    refute inspected_payload =~ "access_token"
  end

  test "returns safe artifact errors for missing, non-ready, not-allowed, and broken storage",
       context do
    put_gmail_runtime_config!(context)

    missing_id = Ecto.UUID.generate()

    assert {:error, %{code: "tool.email.artifact_not_found"}} =
             Email.create_draft(
               context.instance,
               Map.put(valid_args(), "artifact_ids", [missing_id]),
               %{},
               success_config(self())
             )

    non_ready =
      insert_ready_artifact!(context, "archived.txt", "text/plain", "archived",
        status: "archived"
      )

    assert {:error, %{code: "tool.email.artifact_not_found"}} =
             Email.create_draft(
               context.instance,
               Map.put(valid_args(), "artifact_ids", [non_ready.id]),
               %{},
               success_config(self())
             )

    other_lemming =
      insert(:lemming,
        world: context.world,
        city: context.city,
        department: context.department
      )

    not_allowed =
      insert_ready_artifact!(
        context,
        "other-owner.txt",
        "text/plain",
        "content",
        lemming: other_lemming
      )

    assert {:error, %{code: "tool.email.artifact_not_allowed"}} =
             Email.create_draft(
               context.instance,
               Map.put(valid_args(), "artifact_ids", [not_allowed.id]),
               %{},
               success_config(self())
             )

    broken = insert_broken_ready_artifact!(context, "broken.txt", "text/plain")

    assert {:error, %{code: "tool.email.artifact_not_found"}} =
             Email.create_draft(
               context.instance,
               Map.put(valid_args(), "artifact_ids", [broken.id]),
               %{},
               success_config(self())
             )
  end

  test "rejects an individual attachment larger than configured megabyte limit", context do
    put_gmail_runtime_config!(context)
    put_email_draft_config!(max_attachment_megabytes: 0.000001)

    artifact =
      insert_metadata_only_artifact!(context,
        filename: "large-secret-name.pdf",
        storage_ref: "local://private/storage/ref.pdf",
        size_bytes: 2
      )

    assert {:error, error} =
             Email.create_draft(
               context.instance,
               Map.put(valid_args(), "artifact_ids", [artifact.id]),
               %{},
               success_config(self())
             )

    assert error == %{
             code: "tool.email.attachment_too_large",
             message: "Attachment exceeds configured draft limit",
             details: %{artifact_id: artifact.id}
           }

    refute_receive {:email_draft_exchange_called, _access_token}
    refute_receive {:email_draft_create_called, _access_token, _raw_message}

    [event] = recent_email_failed_events(context)
    assert event.payload["error_code"] == "tool.email.attachment_too_large"
    assert event.payload["artifact_ids"] == [artifact.id]

    inspected_payload = inspect(event.payload)
    refute inspected_payload =~ "large-secret-name.pdf"
    refute inspected_payload =~ "local://private/storage/ref.pdf"
  end

  test "rejects attachments whose total size exceeds configured megabyte limit", context do
    put_gmail_runtime_config!(context)

    put_email_draft_config!(
      max_attachment_megabytes: 1,
      max_total_attachment_megabytes: 0.000003
    )

    first = insert_metadata_only_artifact!(context, size_bytes: 2)
    second = insert_metadata_only_artifact!(context, size_bytes: 2)

    assert {:error, error} =
             Email.create_draft(
               context.instance,
               Map.put(valid_args(), "artifact_ids", [first.id, second.id]),
               %{},
               success_config(self())
             )

    assert error.code == "tool.email.attachment_too_large"
    assert error.message == "Attachment exceeds configured draft limit"
    assert error.details == %{artifact_id: second.id}

    refute_receive {:email_draft_exchange_called, _access_token}
    refute_receive {:email_draft_create_called, _access_token, _raw_message}
  end

  test "rejects too many attachments before calling Gmail client", context do
    put_gmail_runtime_config!(context)
    put_email_draft_config!(max_attachment_count: 1)

    first_id = Ecto.UUID.generate()
    second_id = Ecto.UUID.generate()

    assert {:error, error} =
             Email.create_draft(
               context.instance,
               Map.put(valid_args(), "artifact_ids", [first_id, second_id]),
               %{},
               success_config(self())
             )

    assert error == %{
             code: "tool.email.attachment_too_large",
             message: "Attachment exceeds configured draft limit",
             details: %{}
           }

    refute_receive {:email_draft_exchange_called, _access_token}
    refute_receive {:email_draft_create_called, _access_token, _raw_message}
  end

  test "events are emitted and payload/result do not leak secrets or provider tokens", context do
    raw_client_secret = "sentinel-client-secret"
    raw_refresh_token = "sentinel-refresh-token"
    raw_access_token = "sentinel-access-token"
    raw_auth_code = "sentinel-auth-code"

    put_gmail_runtime_config!(context,
      client_secret_value: raw_client_secret,
      refresh_token_value: raw_refresh_token
    )

    log =
      capture_log(fn ->
        assert {:ok, result} =
                 Email.create_draft(
                   context.instance,
                   valid_args(),
                   %{},
                   success_config(self(), access_token: raw_access_token)
                 )

        assert inspect(result) =~ "draft_created"
        refute inspect(result) =~ raw_client_secret
        refute inspect(result) =~ raw_refresh_token
        refute inspect(result) =~ raw_access_token
        refute inspect(result) =~ raw_auth_code
      end)

    refute log =~ raw_client_secret
    refute log =~ raw_refresh_token
    refute log =~ raw_access_token
    refute log =~ raw_auth_code

    events =
      Events.list_recent_events(
        %{
          world_id: context.world.id,
          city_id: context.city.id,
          department_id: context.department.id,
          lemming_id: context.lemming.id
        },
        event_types: ["email.draft_requested", "email.draft_created"],
        limit: 10
      )

    assert Enum.any?(events, &(&1.event_type == "email.draft_requested"))
    assert Enum.any?(events, &(&1.event_type == "email.draft_created"))

    inspected_payloads = Enum.map_join(events, "\n", &inspect(&1.payload))
    refute inspected_payloads =~ raw_client_secret
    refute inspected_payloads =~ raw_refresh_token
    refute inspected_payloads =~ raw_access_token
    refute inspected_payloads =~ raw_auth_code

    connection = LemmingsOs.Connections.get_connection_by_type(context.world, "gmail")
    assert connection.config["client_id"] == "$GMAIL_CLIENT_ID"
    assert connection.config["client_secret"] == "$GMAIL_CLIENT_SECRET"
    assert connection.config["refresh_token"] == "$GMAIL_REFRESH_TOKEN"
    refute inspect(connection.config) =~ raw_client_secret
    refute inspect(connection.config) =~ raw_refresh_token
  end

  defp valid_args do
    %{
      "connection_ref" => "gmail",
      "to" => ["ops@example.com"],
      "subject" => "Test draft",
      "body" => "Hello",
      "body_format" => "text/plain"
    }
  end

  defp success_config(pid, opts \\ []) do
    %{
      "gmail_client" => LemmingsOs.TestSupport.EmailDraftGmailClientSuccess,
      "gmail_client_opts" => %{
        "test_pid" => pid,
        "access_token" => Keyword.get(opts, :access_token, "access-token")
      }
    }
  end

  defp put_email_draft_config!(overrides) do
    config =
      Keyword.merge(
        [
          max_attachment_count: 5,
          max_attachment_megabytes: 10,
          max_total_attachment_megabytes: 20,
          max_body_megabytes: 0.2
        ],
        overrides
      )

    Application.put_env(:lemmings_os, :email_draft, config)
  end

  defp put_gmail_runtime_config!(context, opts \\ []) do
    client_id_value = Keyword.get(opts, :client_id_value, "client-id-value")
    client_secret_value = Keyword.get(opts, :client_secret_value, "client-secret-value")
    refresh_token_value = Keyword.get(opts, :refresh_token_value, "refresh-token-value")

    assert {:ok, _} = SecretBank.upsert_secret(context.world, "GMAIL_CLIENT_ID", client_id_value)

    assert {:ok, _} =
             SecretBank.upsert_secret(context.world, "GMAIL_CLIENT_SECRET", client_secret_value)

    assert {:ok, _} =
             SecretBank.upsert_secret(context.world, "GMAIL_REFRESH_TOKEN", refresh_token_value)

    config = %{
      "provider" => "gmail",
      "account_email" => "ops@example.com",
      "scopes" => [GmailCaller.compose_scope()],
      "client_id" => "$GMAIL_CLIENT_ID",
      "client_secret" => "$GMAIL_CLIENT_SECRET",
      "refresh_token" => "$GMAIL_REFRESH_TOKEN"
    }

    case LemmingsOs.Connections.get_connection_by_type(context.world, "gmail") do
      nil ->
        insert(:world_connection,
          world: context.world,
          type: "gmail",
          status: "enabled",
          config: config
        )

      connection ->
        assert {:ok, _} =
                 LemmingsOs.Connections.update_connection(context.world, connection, %{
                   status: "enabled",
                   config: config
                 })
    end
  end

  defp insert_ready_artifact!(context, filename, content_type, content, opts \\ []) do
    artifact_id = Ecto.UUID.generate()
    source_path = Path.join(context.storage_root, "source_#{artifact_id}")
    lemming = Keyword.get(opts, :lemming, context.lemming)
    status = Keyword.get(opts, :status, "ready")
    File.write!(source_path, content)

    {:ok, stored} = LocalStorage.store_copy(context.world.id, artifact_id, source_path, filename)

    insert(:artifact,
      id: artifact_id,
      world: context.world,
      city: context.city,
      department: context.department,
      lemming: lemming,
      lemming_instance: nil,
      type: "other",
      filename: filename,
      content_type: content_type,
      storage_ref: stored.storage_ref,
      size_bytes: stored.size_bytes,
      checksum: stored.checksum,
      status: status,
      metadata: %{"source" => "manual_promotion"}
    )
  end

  defp insert_broken_ready_artifact!(context, filename, content_type) do
    artifact_id = Ecto.UUID.generate()
    {:ok, storage_ref} = LocalStorage.build_storage_ref(context.world.id, artifact_id, filename)

    insert(:artifact,
      id: artifact_id,
      world: context.world,
      city: context.city,
      department: context.department,
      lemming: context.lemming,
      lemming_instance: nil,
      type: "other",
      filename: filename,
      content_type: content_type,
      storage_ref: storage_ref,
      size_bytes: 100,
      checksum: String.duplicate("a", 64),
      status: "ready",
      metadata: %{"source" => "manual_promotion"}
    )
  end

  defp insert_metadata_only_artifact!(context, opts) do
    artifact_id = Ecto.UUID.generate()

    insert(:artifact,
      id: artifact_id,
      world: context.world,
      city: context.city,
      department: context.department,
      lemming: context.lemming,
      lemming_instance: nil,
      type: "other",
      filename: Keyword.get(opts, :filename, "attachment.bin"),
      content_type: Keyword.get(opts, :content_type, "application/octet-stream"),
      storage_ref:
        Keyword.get(
          opts,
          :storage_ref,
          "local://artifacts/#{context.world.id}/#{artifact_id}/attachment.bin"
        ),
      size_bytes: Keyword.get(opts, :size_bytes, 1),
      checksum: String.duplicate("c", 64),
      status: "ready",
      metadata: %{"source" => "manual_promotion"}
    )
  end

  defp recent_email_failed_events(context) do
    Events.list_recent_events(
      %{
        world_id: context.world.id,
        city_id: context.city.id,
        department_id: context.department.id,
        lemming_id: context.lemming.id
      },
      event_types: ["email.draft_failed"],
      limit: 1
    )
  end
end
