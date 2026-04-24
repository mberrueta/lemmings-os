defmodule Mix.Tasks.Lemmings.InstanceTrace do
  use Mix.Task

  alias LemmingsOsWeb.PageData.InstanceRawSnapshot

  @shortdoc "Prints instance raw-context trace as Markdown"
  @request_timeout_ms 1_500
  @connect_timeout_ms 500

  @moduledoc """
  Prints the raw-context interaction trace for an instance as Markdown.

      mix lemmings.instance_trace <instance_id>
      mix lemmings.instance_trace <instance_id> --world <world_id>
      mix lemmings.instance_trace <instance_id> --base-url http://localhost:4050

  The task first tries to fetch a live Markdown export from a running Phoenix
  server so it can include the same in-memory executor trace shown by the raw
  context page. If no live server responds, it falls back to local snapshot
  reconstruction.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, invalid} =
      OptionParser.parse(args,
        strict: [world: :string, base_url: :string],
        aliases: [w: :world]
      )

    case {positional, invalid} do
      {[instance_id], []} ->
        snapshot_opts = [instance_id: instance_id] ++ world_opt(opts)

        snapshot_opts
        |> markdown_output(opts)
        |> Mix.shell().info()

      _other ->
        Mix.raise(
          "Usage: mix lemmings.instance_trace <instance_id> [--world <world_id>] [--base-url <url>]"
        )
    end
  end

  defp markdown_output(snapshot_opts, opts) do
    case fetch_live_markdown(snapshot_opts, opts) do
      {:ok, markdown} ->
        markdown

      :error ->
        case InstanceRawSnapshot.build(snapshot_opts) do
          {:ok, snapshot} ->
            InstanceRawSnapshot.to_markdown(snapshot)

          {:error, :not_found} ->
            instance_id = Keyword.fetch!(snapshot_opts, :instance_id)
            Mix.raise("Could not load instance trace for instance_id=#{instance_id}")
        end
    end
  end

  defp world_opt(opts) do
    case Keyword.get(opts, :world) do
      world_id when is_binary(world_id) and world_id != "" -> [world_id: world_id]
      _other -> []
    end
  end

  defp fetch_live_markdown(snapshot_opts, opts) do
    snapshot_opts
    |> live_export_urls(opts)
    |> Enum.find_value(:error, fn url ->
      case Req.get(
             url: url,
             params: live_export_query(snapshot_opts),
             max_retries: 0,
             receive_timeout: @request_timeout_ms,
             connect_options: [timeout: @connect_timeout_ms]
           ) do
        {:ok, %Req.Response{status: status, body: body}}
        when status in 200..299 and is_binary(body) and body != "" ->
          {:ok, body}

        _other ->
          nil
      end
    end)
  end

  defp live_export_urls(snapshot_opts, opts) do
    instance_id = Keyword.fetch!(snapshot_opts, :instance_id)

    live_export_base_urls(opts)
    |> Enum.map(fn base_url -> "#{base_url}/lemmings/instances/#{instance_id}/raw.md" end)
  end

  defp live_export_query(snapshot_opts) do
    case Keyword.get(snapshot_opts, :world_id) do
      world_id when is_binary(world_id) and world_id != "" -> [world: world_id]
      _other -> []
    end
  end

  defp live_export_base_urls(opts) do
    case Keyword.get(opts, :base_url) do
      base_url when is_binary(base_url) and base_url != "" ->
        [normalize_base_url(base_url)]

      _other ->
        [
          endpoint_base_url(),
          "http://127.0.0.1:4050",
          "http://localhost:4050",
          "http://127.0.0.1:4000",
          "http://localhost:4000"
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&normalize_base_url/1)
        |> Enum.uniq()
    end
  end

  defp endpoint_base_url do
    endpoint_config = Application.get_env(:lemmings_os, LemmingsOsWeb.Endpoint, [])
    url_config = Keyword.get(endpoint_config, :url, [])
    http_config = Keyword.get(endpoint_config, :http, [])

    host = Keyword.get(url_config, :host, "localhost")
    scheme = Keyword.get(url_config, :scheme, "http")
    port = Keyword.get(url_config, :port) || Keyword.get(http_config, :port)

    if is_binary(host) and is_integer(port) do
      "#{scheme}://#{host}:#{port}"
    end
  end

  defp normalize_base_url(base_url) do
    String.trim_trailing(base_url, "/")
  end
end
