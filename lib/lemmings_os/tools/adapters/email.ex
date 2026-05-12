defmodule LemmingsOs.Tools.Adapters.Email do
  @moduledoc """
  Email adapter boundary for Tool Runtime.

  Supported tool:
  - `email.create_draft`

  This adapter currently supports Gmail draft creation only. It validates
  tool input, resolves a scoped Gmail Connection, resolves Secret Bank refs
  only at execution time, builds a MIME message, and creates a Gmail draft.
  It never sends email.
  """

  alias LemmingsOs.Artifacts
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Connections.Providers.GmailCaller
  alias LemmingsOs.Connections.Runtime, as: ConnectionsRuntime
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Events
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.SecretBank
  alias LemmingsOs.Tools.Adapters.Email.GmailClient
  alias LemmingsOs.Worlds.World

  @tool_name "email.create_draft"
  @provider "gmail"
  @connection_ref "gmail"
  @default_body_format "text/plain"
  @allowed_body_formats MapSet.new(["text/plain", "text/html"])
  @allowed_fields MapSet.new([
                    "connection_ref",
                    "to",
                    "cc",
                    "bcc",
                    "subject",
                    "body",
                    "body_format",
                    "artifact_ids"
                  ])
  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @type runtime_meta :: %{
          optional(:actor_instance_id) => String.t(),
          optional(:work_area_ref) => String.t(),
          optional(:world_id) => String.t(),
          optional(:city_id) => String.t(),
          optional(:department_id) => String.t()
        }

  @type success_result :: %{
          summary: String.t(),
          preview: String.t() | nil,
          result: map()
        }

  @type error_result :: %{
          code: String.t(),
          message: String.t(),
          details: map()
        }

  @type trusted_config :: map()

  @type parsed_args :: %{
          connection_ref: String.t(),
          to: [String.t()],
          cc: [String.t()],
          bcc: [String.t()],
          subject: String.t(),
          body: String.t(),
          body_format: String.t(),
          artifact_ids: [Ecto.UUID.t()]
        }

  @doc """
  Creates one Gmail draft from prepared content and optional Artifact attachments.

  ## Parameters

  - `instance`: `%LemmingsOs.LemmingInstances.LemmingInstance{}` execution scope.
  - `args`:
    - `"connection_ref"` (required): must be `"gmail"`.
    - `"to"` (required): non-empty recipient email string, comma-separated
      recipient email string, or list of recipient email strings.
    - `"cc"` (optional): recipient email string, comma-separated recipient
      email string, list of recipient email strings, `nil`, or `""`. Default: `[]`.
    - `"bcc"` (optional): recipient email string, comma-separated recipient
      email string, list of recipient email strings, `nil`, or `""`. Default: `[]`.
    - `"subject"` (required): non-empty string.
    - `"body"` (required): body string.
    - `"body_format"` (optional): `"text/plain"` or `"text/html"`.
      Default: `"text/plain"`.
    - `"artifact_ids"` (optional): list of Artifact IDs. Default: `[]`.
  - `runtime_meta` (optional): runtime metadata map. Default: `%{}`.
  - `trusted_config` (optional): trusted adapter config map. Default: `%{}`.

    Supported trusted config keys:
    - `"gmail_client"` / `:gmail_client` (optional): module implementing Gmail HTTP boundary.
      Default: `LemmingsOs.Tools.Adapters.Email.GmailClient`.
    - `"gmail_client_opts"` / `:gmail_client_opts` (optional): map/keyword forwarded to Gmail client.
      Default: `%{}`.

  ## Examples

      iex> world = insert(:world)
      iex> city = insert(:city, world: world)
      iex> department = insert(:department, world: world, city: city)
      iex> lemming = insert(:lemming, world: world, city: city, department: department)
      iex> instance =
      ...>   insert(:lemming_instance,
      ...>     world: world,
      ...>     city: city,
      ...>     department: department,
      ...>     lemming: lemming
      ...>   )
      iex> {:ok, _} = LemmingsOs.SecretBank.upsert_secret(world, "GMAIL_CLIENT_ID", "client-id")
      iex> {:ok, _} = LemmingsOs.SecretBank.upsert_secret(world, "GMAIL_CLIENT_SECRET", "client-secret")
      iex> {:ok, _} = LemmingsOs.SecretBank.upsert_secret(world, "GMAIL_REFRESH_TOKEN", "refresh-token")
      iex> insert(:world_connection,
      ...>   world: world,
      ...>   type: "gmail",
      ...>   status: "enabled",
      ...>   config: %{
      ...>     "provider" => "gmail",
      ...>     "account_email" => "ops@example.test",
      ...>     "scopes" => [LemmingsOs.Connections.Providers.GmailCaller.compose_scope()],
      ...>     "client_id" => "$GMAIL_CLIENT_ID",
      ...>     "client_secret" => "$GMAIL_CLIENT_SECRET",
      ...>     "refresh_token" => "$GMAIL_REFRESH_TOKEN"
      ...>   }
      ...> )
      iex> {:ok, result} =
      ...>   LemmingsOs.Tools.Adapters.Email.create_draft(
      ...>     instance,
      ...>     %{
      ...>       "connection_ref" => "gmail",
      ...>       "to" => ["customer@example.test"],
      ...>       "subject" => "Quotation",
      ...>       "body" => "Draft body",
      ...>       "body_format" => "text/plain"
      ...>     },
      ...>     %{},
      ...>     %{
      ...>       "gmail_client" => LemmingsOs.TestSupport.EmailDraftGmailClientSuccess,
      ...>       "gmail_client_opts" => %{"access_token" => "test-access-token"}
      ...>     }
      ...>   )
      iex> result.result["status"]
      "draft_created"

      iex> instance = %LemmingsOs.LemmingInstances.LemmingInstance{id: Ecto.UUID.generate()}
      iex> {:error, error} =
      ...>   LemmingsOs.Tools.Adapters.Email.create_draft(
      ...>     instance,
      ...>     %{"to" => ["ops@example.com"]}
      ...>   )
      iex> error.code
      "tool.validation.invalid_args"
  """
  @spec create_draft(LemmingInstance.t(), map(), runtime_meta(), trusted_config()) ::
          {:ok, success_result()} | {:error, error_result()}
  def create_draft(
        %LemmingInstance{} = instance,
        args,
        runtime_meta \\ %{},
        trusted_config \\ %{}
      )
      when is_map(args) and is_map(runtime_meta) and is_map(trusted_config) do
    case validate_args(args) do
      {:ok, parsed_args} ->
        _ = record_requested_event(instance, parsed_args)

        instance
        |> run_create_draft(parsed_args, trusted_config)
        |> finalize_with_events(instance, parsed_args)

      {:error, %{} = error} ->
        _ = record_invalid_args_failed_event(instance)
        {:error, error}
    end
  end

  defp run_create_draft(%LemmingInstance{} = instance, parsed_args, trusted_config) do
    case resolve_gmail_connection(instance, parsed_args.connection_ref) do
      {:ok, connection_scope, descriptor} ->
        connection_id = descriptor.connection_id

        with {:ok, attachments} <- load_attachments(instance, parsed_args.artifact_ids),
             {:ok, resolved_secrets} <-
               resolve_connection_secrets(connection_scope, descriptor.config),
             {:ok, access_token} <- exchange_refresh_token(resolved_secrets, trusted_config),
             raw_message <- build_raw_message(parsed_args, attachments),
             {:ok, draft} <- create_gmail_draft(access_token, raw_message, trusted_config) do
          {:ok, success_payload(parsed_args, draft),
           %{connection_id: connection_id, draft_id: draft.draft_id}}
        else
          {:error, %{} = error} ->
            {:error, error, %{connection_id: connection_id}}
        end

      {:error, %{} = error} ->
        {:error, error, %{connection_id: nil}}
    end
  end

  defp finalize_with_events(
         {:ok, payload, %{connection_id: connection_id, draft_id: draft_id}},
         instance,
         parsed_args
       ) do
    _ = record_created_event(instance, parsed_args, connection_id, draft_id)
    {:ok, payload}
  end

  defp finalize_with_events(
         {:error, error, %{connection_id: connection_id}},
         instance,
         parsed_args
       ) do
    _ = record_failed_event(instance, parsed_args, connection_id, error)
    {:error, error}
  end

  defp validate_args(args) do
    with :ok <- validate_allowed_fields(args),
         {:ok, connection_ref} <- validate_connection_ref(args),
         {:ok, to} <- validate_required_recipients(args, "to"),
         {:ok, cc} <- validate_optional_recipients(args, "cc"),
         {:ok, bcc} <- validate_optional_recipients(args, "bcc"),
         {:ok, subject} <- validate_required_text(args, "subject"),
         {:ok, body} <- validate_required_text(args, "body"),
         {:ok, body_format} <- validate_body_format(args),
         {:ok, artifact_ids} <- validate_artifact_ids(args) do
      {:ok,
       %{
         connection_ref: connection_ref,
         to: to,
         cc: cc,
         bcc: bcc,
         subject: subject,
         body: body,
         body_format: body_format,
         artifact_ids: artifact_ids
       }}
    end
  end

  defp validate_allowed_fields(args) when is_map(args) do
    unsupported_fields =
      args
      |> Map.keys()
      |> Enum.map(&normalize_arg_key/1)
      |> Enum.reject(&MapSet.member?(@allowed_fields, &1))
      |> Enum.uniq()
      |> Enum.sort()

    case unsupported_fields do
      [] ->
        :ok

      _ ->
        {:error,
         %{
           code: "tool.validation.invalid_args",
           message: "Invalid tool arguments",
           details: %{unsupported_fields: unsupported_fields}
         }}
    end
  end

  defp validate_connection_ref(args) do
    case fetch_arg(args, "connection_ref") do
      @connection_ref ->
        {:ok, @connection_ref}

      value when is_binary(value) ->
        {:error,
         %{
           code: "tool.validation.invalid_args",
           message: "Invalid tool arguments",
           details: %{field: "connection_ref", allowed: [@connection_ref]}
         }}

      _missing ->
        {:error,
         %{
           code: "tool.validation.invalid_args",
           message: "Invalid tool arguments",
           details: %{required: ["connection_ref"]}
         }}
    end
  end

  defp validate_required_recipients(args, field) do
    case normalize_recipient_values(fetch_arg(args, field), field) do
      {:ok, []} ->
        required_field_error(field)

      {:ok, recipients} ->
        {:ok, recipients}

      {:error, %{} = error} ->
        {:error, error}
    end
  end

  defp validate_optional_recipients(args, field) do
    case normalize_recipient_values(fetch_arg(args, field), field) do
      {:ok, recipients} ->
        {:ok, recipients}

      {:error, %{} = error} ->
        {:error, error}
    end
  end

  defp normalize_recipient_values(nil, _field), do: {:ok, []}

  defp normalize_recipient_values(value, field) when is_binary(value) do
    value
    |> recipient_candidates()
    |> normalize_recipients(field)
  end

  defp normalize_recipient_values(values, field) when is_list(values) do
    values
    |> Enum.flat_map(&recipient_candidates/1)
    |> normalize_recipients(field)
  end

  defp normalize_recipient_values(_values, field), do: {:error, invalid_args_error(field)}

  defp recipient_candidates(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp recipient_candidates(value), do: [value]

  defp normalize_recipients(values, field) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case normalize_recipient(value) do
        {:ok, recipient} -> {:cont, {:ok, [recipient | acc]}}
        :error -> {:halt, {:error, invalid_recipient_error(field)}}
      end
    end)
    |> case do
      {:ok, recipients} -> {:ok, Enum.reverse(recipients)}
      {:error, %{} = error} -> {:error, error}
    end
  end

  defp normalize_recipient(value) when is_binary(value) do
    normalized = String.trim(value)

    if normalized != "" and Regex.match?(@email_regex, normalized) do
      {:ok, normalized}
    else
      :error
    end
  end

  defp normalize_recipient(_value), do: :error

  defp validate_required_text(args, field) do
    case fetch_arg(args, field) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" ->
            {:error,
             %{
               code: "tool.validation.invalid_args",
               message: "Invalid tool arguments",
               details: %{required: [field]}
             }}

          normalized ->
            {:ok, normalized}
        end

      _other ->
        {:error,
         %{
           code: "tool.validation.invalid_args",
           message: "Invalid tool arguments",
           details: %{required: [field]}
         }}
    end
  end

  defp validate_body_format(args) do
    case fetch_arg(args, "body_format") do
      nil ->
        {:ok, @default_body_format}

      value when is_binary(value) ->
        normalized = String.trim(value)

        cond do
          normalized == "" ->
            {:ok, @default_body_format}

          MapSet.member?(@allowed_body_formats, normalized) ->
            {:ok, normalized}

          true ->
            {:error, invalid_body_format_error(normalized)}
        end

      _other ->
        {:error, invalid_args_error("body_format")}
    end
  end

  defp required_field_error(field) do
    {:error,
     %{
       code: "tool.validation.invalid_args",
       message: "Invalid tool arguments",
       details: %{required: [field]}
     }}
  end

  defp validate_artifact_ids(args) do
    case fetch_arg(args, "artifact_ids") do
      nil ->
        {:ok, []}

      value when is_binary(value) ->
        if String.trim(value) == "" do
          {:ok, []}
        else
          {:error, invalid_args_error("artifact_ids")}
        end

      values when is_list(values) ->
        normalize_artifact_ids(values)

      _other ->
        {:error, invalid_args_error("artifact_ids")}
    end
  end

  defp normalize_artifact_ids(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case Ecto.UUID.cast(value) do
        {:ok, uuid} -> {:cont, {:ok, [uuid | acc]}}
        :error -> {:halt, {:error, invalid_args_error("artifact_ids")}}
      end
    end)
    |> normalize_artifact_ids_result()
  end

  defp normalize_artifact_ids_result({:ok, artifact_ids}), do: {:ok, Enum.reverse(artifact_ids)}
  defp normalize_artifact_ids_result({:error, %{} = error}), do: {:error, error}

  defp resolve_gmail_connection(instance, @connection_ref) do
    with {:ok, connection_scope} <- connection_scope(instance),
         {:ok, descriptor} <- resolve_connection_descriptor(connection_scope),
         :ok <- validate_connection_descriptor(descriptor) do
      {:ok, connection_scope, descriptor}
    end
  end

  defp resolve_connection_descriptor(connection_scope) do
    case ConnectionsRuntime.resolve_connection(connection_scope, @connection_ref) do
      {:ok, descriptor} ->
        {:ok, descriptor}

      {:error, :missing} ->
        {:error, connection_not_found_error()}

      {:error, _reason} ->
        {:error, connection_not_allowed_error()}
    end
  end

  defp validate_connection_descriptor(%ConnectionsRuntime{type: @connection_ref, config: config})
       when is_map(config) do
    case GmailCaller.validate_config(config) do
      :ok -> :ok
      {:error, _reason} -> {:error, connection_not_allowed_error()}
    end
  end

  defp validate_connection_descriptor(_descriptor), do: {:error, connection_not_allowed_error()}

  defp resolve_connection_secrets(connection_scope, config) when is_map(config) do
    with {:ok, client_id_ref} <- fetch_secret_ref(config, "client_id"),
         {:ok, client_secret_ref} <- fetch_secret_ref(config, "client_secret"),
         {:ok, refresh_token_ref} <- fetch_secret_ref(config, "refresh_token"),
         {:ok, client_id} <- resolve_secret_value(connection_scope, client_id_ref),
         {:ok, client_secret} <- resolve_secret_value(connection_scope, client_secret_ref),
         {:ok, refresh_token} <- resolve_secret_value(connection_scope, refresh_token_ref) do
      {:ok,
       %{
         client_id: client_id,
         client_secret: client_secret,
         refresh_token: refresh_token
       }}
    end
  end

  defp fetch_secret_ref(config, key) do
    case Map.get(config, key) do
      "$" <> rest = value when rest != "" -> {:ok, value}
      _other -> {:error, connection_auth_failed_error()}
    end
  end

  defp resolve_secret_value(scope, ref) do
    case SecretBank.resolve_runtime_secret(scope, ref, tool_name: @tool_name) do
      {:ok, %{value: value}} when is_binary(value) and value != "" ->
        {:ok, value}

      {:error, _reason} ->
        {:error, connection_auth_failed_error()}

      _other ->
        {:error, connection_auth_failed_error()}
    end
  end

  defp exchange_refresh_token(resolved_secrets, trusted_config) do
    gmail_client = gmail_client_module(trusted_config)
    gmail_client_opts = gmail_client_opts(trusted_config)

    case gmail_client.exchange_refresh_token(
           resolved_secrets.client_id,
           resolved_secrets.client_secret,
           resolved_secrets.refresh_token,
           gmail_client_opts
         ) do
      {:ok, access_token} when is_binary(access_token) and access_token != "" ->
        {:ok, access_token}

      _other ->
        {:error, connection_auth_failed_error()}
    end
  end

  defp create_gmail_draft(access_token, raw_message, trusted_config) do
    gmail_client = gmail_client_module(trusted_config)
    gmail_client_opts = gmail_client_opts(trusted_config)

    case gmail_client.create_draft(access_token, raw_message, gmail_client_opts) do
      {:ok, %{draft_id: draft_id} = draft} when is_binary(draft_id) and draft_id != "" ->
        {:ok, draft}

      _other ->
        {:error, draft_create_failed_error()}
    end
  end

  defp gmail_client_module(trusted_config) do
    case fetch_trusted(trusted_config, "gmail_client") do
      module when is_atom(module) and not is_nil(module) -> module
      _other -> GmailClient
    end
  end

  defp gmail_client_opts(trusted_config) do
    trusted_config
    |> fetch_trusted("gmail_client_opts")
    |> normalize_client_opts()
  end

  defp normalize_client_opts(opts) when is_list(opts), do: opts

  defp normalize_client_opts(opts) when is_map(opts) do
    []
    |> maybe_put_opt(:req, fetch_trusted(opts, "req"))
    |> maybe_put_opt(:token_url, fetch_trusted(opts, "token_url"))
    |> maybe_put_opt(:drafts_url, fetch_trusted(opts, "drafts_url"))
    |> maybe_put_opt(:test_pid, fetch_trusted(opts, "test_pid"))
    |> maybe_put_opt(:mode, fetch_trusted(opts, "mode"))
    |> maybe_put_opt(:access_token, fetch_trusted(opts, "access_token"))
  end

  defp normalize_client_opts(_opts), do: []

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp load_attachments(_instance, []), do: {:ok, []}

  defp load_attachments(%LemmingInstance{} = instance, artifact_ids) when is_list(artifact_ids) do
    with {:ok, artifact_scope} <- artifact_scope(instance),
         {:ok, world_scope} <- world_scope(instance) do
      load_attachment_list(artifact_ids, artifact_scope, world_scope)
    end
  end

  defp load_attachment_list(artifact_ids, artifact_scope, world_scope) do
    artifact_ids
    |> Enum.reduce_while({:ok, []}, fn artifact_id, {:ok, acc} ->
      case load_attachment(artifact_scope, world_scope, artifact_id) do
        {:ok, attachment} -> {:cont, {:ok, [attachment | acc]}}
        {:error, %{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> normalize_attachment_list_result()
  end

  defp normalize_attachment_list_result({:ok, attachments}), do: {:ok, Enum.reverse(attachments)}
  defp normalize_attachment_list_result({:error, %{} = error}), do: {:error, error}

  defp load_attachment(artifact_scope, world_scope, artifact_id) do
    case Artifacts.get_artifact(artifact_scope, artifact_id, include_non_ready: true) do
      {:ok, artifact} ->
        if artifact.status != "ready" do
          {:error, artifact_not_found_error(artifact_id)}
        else
          open_attachment(artifact_scope, artifact_id)
        end

      {:error, :not_found} ->
        classify_artifact_visibility(world_scope, artifact_id)

      {:error, _reason} ->
        {:error, artifact_not_allowed_error(artifact_id)}
    end
  end

  defp open_attachment(artifact_scope, artifact_id) do
    with {:ok, opened} <- Artifacts.open_artifact_download(artifact_scope, artifact_id),
         {:ok, content} <- File.read(opened.path) do
      {:ok,
       %{
         artifact_id: artifact_id,
         filename: sanitize_filename(opened.filename),
         content_type: sanitize_content_type(opened.content_type),
         content: content
       }}
    else
      _other ->
        {:error, artifact_not_found_error(artifact_id)}
    end
  end

  defp classify_artifact_visibility(world_scope, artifact_id) do
    case Artifacts.get_artifact(world_scope, artifact_id, include_non_ready: true) do
      {:ok, _artifact} -> {:error, artifact_not_allowed_error(artifact_id)}
      {:error, :not_found} -> {:error, artifact_not_found_error(artifact_id)}
      {:error, _reason} -> {:error, artifact_not_found_error(artifact_id)}
    end
  end

  defp success_payload(parsed_args, draft) do
    base_result = %{
      "status" => "draft_created",
      "provider" => @provider,
      "connection_ref" => parsed_args.connection_ref,
      "draft_id" => draft.draft_id,
      "to" => parsed_args.to,
      "cc" => parsed_args.cc,
      "bcc" => parsed_args.bcc,
      "subject" => parsed_args.subject,
      "artifact_ids" => parsed_args.artifact_ids
    }

    result =
      case Map.get(draft, :message_id) do
        message_id when is_binary(message_id) and message_id != "" ->
          Map.put(base_result, "message_id", message_id)

        _other ->
          base_result
      end

    %{
      summary: draft_summary(parsed_args),
      preview: "Subject: #{parsed_args.subject}",
      result: result
    }
  end

  defp draft_summary(parsed_args) do
    recipient = List.first(parsed_args.to)
    attachment_count = length(parsed_args.artifact_ids)

    attachment_label =
      if attachment_count == 1, do: "1 attachment", else: "#{attachment_count} attachments"

    "Created Gmail draft for #{recipient} with #{attachment_label}"
  end

  defp build_raw_message(parsed_args, attachments) do
    parsed_args
    |> mime_message(attachments)
    |> Base.url_encode64(padding: false)
  end

  defp mime_message(parsed_args, []) do
    headers = base_headers(parsed_args)

    [
      headers,
      "Content-Type: #{parsed_args.body_format}; charset=\"UTF-8\"",
      "Content-Transfer-Encoding: base64",
      "",
      encode_base64_lines(parsed_args.body),
      ""
    ]
    |> List.flatten()
    |> Enum.join("\r\n")
  end

  defp mime_message(parsed_args, attachments) do
    headers = base_headers(parsed_args)
    boundary = "lemmings-os-#{Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)}"

    body_part = [
      "Content-Type: #{parsed_args.body_format}; charset=\"UTF-8\"",
      "Content-Transfer-Encoding: base64",
      "",
      encode_base64_lines(parsed_args.body)
    ]

    attachment_parts =
      Enum.map(attachments, fn attachment ->
        [
          "Content-Type: #{attachment.content_type}; name=\"#{attachment.filename}\"",
          "Content-Disposition: attachment; filename=\"#{attachment.filename}\"",
          "Content-Transfer-Encoding: base64",
          "",
          encode_base64_lines(attachment.content)
        ]
      end)

    [
      headers,
      "Content-Type: multipart/mixed; boundary=\"#{boundary}\"",
      "",
      "--#{boundary}",
      body_part,
      Enum.map(attachment_parts, fn part -> ["--#{boundary}", part] end),
      "--#{boundary}--",
      ""
    ]
    |> List.flatten()
    |> Enum.join("\r\n")
  end

  defp base_headers(parsed_args) do
    []
    |> maybe_put_header("To", recipient_header(parsed_args.to))
    |> maybe_put_header("Cc", recipient_header(parsed_args.cc))
    |> maybe_put_header("Bcc", recipient_header(parsed_args.bcc))
    |> maybe_put_header("Subject", sanitize_header_value(parsed_args.subject))
    |> maybe_put_header("MIME-Version", "1.0")
  end

  defp maybe_put_header(headers, _name, nil), do: headers
  defp maybe_put_header(headers, _name, ""), do: headers
  defp maybe_put_header(headers, name, value), do: headers ++ ["#{name}: #{value}"]

  defp recipient_header([]), do: nil

  defp recipient_header(recipients) when is_list(recipients) do
    recipients
    |> Enum.map(&sanitize_header_value/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      values -> Enum.join(values, ", ")
    end
  end

  defp encode_base64_lines(content) when is_binary(content) do
    content
    |> Base.encode64()
    |> String.replace(~r/.{1,76}/, "\\0\r\n")
    |> String.trim_trailing()
  end

  defp sanitize_header_value(value) when is_binary(value) do
    value
    |> String.replace(~r/[\r\n]+/, " ")
    |> String.trim()
  end

  defp sanitize_header_value(_value), do: ""

  defp sanitize_filename(filename) when is_binary(filename) do
    filename
    |> String.replace(~r/[\r\n"]+/, "_")
    |> String.trim()
    |> case do
      "" -> "attachment.bin"
      sanitized -> sanitized
    end
  end

  defp sanitize_content_type(content_type) when is_binary(content_type) do
    normalized = String.trim(content_type)

    if String.contains?(normalized, "/") and not String.contains?(normalized, ["\r", "\n"]) do
      normalized
    else
      "application/octet-stream"
    end
  end

  defp record_requested_event(instance, parsed_args) do
    payload =
      base_event_payload(instance, parsed_args, nil)
      |> Map.put(:status, "requested")

    record_event(instance, "email.draft_requested", "Email draft requested", payload)
  end

  defp record_created_event(instance, parsed_args, connection_id, draft_id) do
    payload =
      base_event_payload(instance, parsed_args, connection_id)
      |> Map.put(:status, "draft_created")
      |> Map.put(:draft_id, draft_id)

    record_event(instance, "email.draft_created", "Email draft created", payload)
  end

  defp record_failed_event(instance, parsed_args, connection_id, error) do
    payload =
      base_event_payload(instance, parsed_args, connection_id)
      |> Map.put(:status, "failed")
      |> Map.put(:error_code, Map.get(error, :code))

    record_event(instance, "email.draft_failed", "Email draft failed", payload)
  end

  defp record_invalid_args_failed_event(instance) do
    payload = %{
      world_id: instance.world_id,
      city_id: instance.city_id,
      department_id: instance.department_id,
      lemming_instance_id: instance.id,
      tool_name: @tool_name,
      status: "failed",
      error_code: "invalid_args"
    }

    record_event(instance, "email.draft_failed", "Email draft failed", payload)
  end

  defp base_event_payload(instance, parsed_args, connection_id) do
    %{
      world_id: instance.world_id,
      city_id: instance.city_id,
      department_id: instance.department_id,
      lemming_id: instance.lemming_id,
      lemming_instance_id: instance.id,
      tool_name: @tool_name,
      provider: @provider,
      connection_ref: parsed_args.connection_ref,
      connection_id: connection_id,
      recipient_count: length(parsed_args.to) + length(parsed_args.cc) + length(parsed_args.bcc),
      attachment_count: length(parsed_args.artifact_ids),
      artifact_ids: parsed_args.artifact_ids
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp record_event(instance, event_type, message, payload) do
    Events.record_event(
      event_type,
      event_scope(instance),
      message,
      payload: payload,
      event_family: "audit"
    )
  end

  defp event_scope(%LemmingInstance{} = instance) do
    %{
      world_id: instance.world_id,
      city_id: instance.city_id,
      department_id: instance.department_id,
      lemming_id: instance.lemming_id
    }
  end

  defp connection_scope(%LemmingInstance{} = instance)
       when is_binary(instance.world_id) and is_binary(instance.city_id) and
              is_binary(instance.department_id) do
    {:ok,
     %Department{
       id: instance.department_id,
       city_id: instance.city_id,
       world_id: instance.world_id
     }}
  end

  defp connection_scope(%LemmingInstance{} = instance)
       when is_binary(instance.world_id) and is_binary(instance.city_id) do
    {:ok, %City{id: instance.city_id, world_id: instance.world_id}}
  end

  defp connection_scope(%LemmingInstance{} = instance) when is_binary(instance.world_id) do
    {:ok, %World{id: instance.world_id}}
  end

  defp connection_scope(_instance), do: {:error, connection_not_allowed_error()}

  defp artifact_scope(%LemmingInstance{} = instance)
       when is_binary(instance.world_id) and is_binary(instance.city_id) and
              is_binary(instance.department_id) and is_binary(instance.lemming_id) do
    {:ok,
     %Lemming{
       id: instance.lemming_id,
       world_id: instance.world_id,
       city_id: instance.city_id,
       department_id: instance.department_id
     }}
  end

  defp artifact_scope(_instance), do: {:error, artifact_not_allowed_error(nil)}

  defp world_scope(%LemmingInstance{} = instance) when is_binary(instance.world_id),
    do: {:ok, %World{id: instance.world_id}}

  defp world_scope(_instance), do: {:error, artifact_not_found_error(nil)}

  defp invalid_recipient_error(field) do
    %{
      code: "tool.email.invalid_recipient",
      message: "Invalid email recipient",
      details: %{field: field}
    }
  end

  defp invalid_body_format_error(body_format) do
    %{
      code: "tool.email.invalid_body_format",
      message: "Unsupported body format",
      details: %{body_format: body_format, allowed: ["text/plain", "text/html"]}
    }
  end

  defp invalid_args_error(field) do
    %{
      code: "tool.validation.invalid_args",
      message: "Invalid tool arguments",
      details: %{field: field}
    }
  end

  defp connection_not_found_error do
    %{
      code: "tool.email.connection_not_found",
      message: "Gmail connection not found",
      details: %{connection_ref: @connection_ref}
    }
  end

  defp connection_not_allowed_error do
    %{
      code: "tool.email.connection_not_allowed",
      message: "Gmail connection is not allowed",
      details: %{connection_ref: @connection_ref}
    }
  end

  defp connection_auth_failed_error do
    %{
      code: "tool.email.connection_auth_failed",
      message: "Gmail connection authentication failed",
      details: %{provider: @provider}
    }
  end

  defp artifact_not_found_error(artifact_id) do
    %{
      code: "tool.email.artifact_not_found",
      message: "Attachment artifact not found",
      details: maybe_put(%{}, :artifact_id, artifact_id)
    }
  end

  defp artifact_not_allowed_error(artifact_id) do
    %{
      code: "tool.email.artifact_not_allowed",
      message: "Attachment artifact is not allowed",
      details: maybe_put(%{}, :artifact_id, artifact_id)
    }
  end

  defp draft_create_failed_error do
    %{
      code: "tool.email.draft_create_failed",
      message: "Failed to create Gmail draft",
      details: %{provider: @provider}
    }
  end

  defp fetch_arg(args, key) when is_map(args) and is_binary(key) do
    case arg_atom_key(key) do
      nil -> Map.get(args, key)
      atom_key -> Map.get(args, key) || Map.get(args, atom_key)
    end
  end

  defp fetch_trusted(map, key) when is_map(map) and is_binary(key) do
    case trusted_atom_key(key) do
      nil -> Map.get(map, key)
      atom_key -> Map.get(map, key) || Map.get(map, atom_key)
    end
  end

  defp normalize_arg_key(key) when is_binary(key), do: key
  defp normalize_arg_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_arg_key(key), do: inspect(key)

  defp arg_atom_key("connection_ref"), do: :connection_ref
  defp arg_atom_key("to"), do: :to
  defp arg_atom_key("cc"), do: :cc
  defp arg_atom_key("bcc"), do: :bcc
  defp arg_atom_key("subject"), do: :subject
  defp arg_atom_key("body"), do: :body
  defp arg_atom_key("body_format"), do: :body_format
  defp arg_atom_key("artifact_ids"), do: :artifact_ids
  defp arg_atom_key(_key), do: nil

  defp trusted_atom_key("gmail_client"), do: :gmail_client
  defp trusted_atom_key("gmail_client_opts"), do: :gmail_client_opts
  defp trusted_atom_key("req"), do: :req
  defp trusted_atom_key("token_url"), do: :token_url
  defp trusted_atom_key("drafts_url"), do: :drafts_url
  defp trusted_atom_key("test_pid"), do: :test_pid
  defp trusted_atom_key("mode"), do: :mode
  defp trusted_atom_key("access_token"), do: :access_token
  defp trusted_atom_key(_key), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
