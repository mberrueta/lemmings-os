defmodule LemmingsOs.Tools.Catalog do
  @moduledoc """
  Fixed Tool Runtime catalog for the MVP.

  This catalog is intentionally limited to the four approved tools.
  """

  @tools [
    %{
      id: "fs.read_text_file",
      name: "Read Text File",
      description: "Read UTF-8 text files from the instance work area.",
      icon: "hero-document-text",
      category: "filesystem",
      risk: "medium"
    },
    %{
      id: "fs.write_text_file",
      name: "Write Text File",
      description: "Write UTF-8 text files inside the instance work area.",
      icon: "hero-pencil-square",
      category: "filesystem",
      risk: "high"
    },
    %{
      id: "web.search",
      name: "Web Search",
      description: "Search the web for short result snippets.",
      icon: "hero-magnifying-glass",
      category: "web",
      risk: "medium"
    },
    %{
      id: "web.fetch",
      name: "Web Fetch",
      description: "Fetch HTTP(S) content from a single URL.",
      icon: "hero-globe-alt",
      category: "web",
      risk: "medium"
    }
  ]

  @tool_ids MapSet.new(Enum.map(@tools, & &1.id))

  @type tool :: %{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          icon: String.t(),
          category: String.t(),
          risk: String.t()
        }

  @doc """
  Returns the fixed catalog in a runtime-ready shape.

  ## Examples

      iex> tools = LemmingsOs.Tools.Catalog.list_tools()
      iex> Enum.map(tools, & &1.id)
      ["fs.read_text_file", "fs.write_text_file", "web.search", "web.fetch"]
  """
  @spec list_tools() :: [tool()]
  def list_tools, do: @tools

  @doc """
  Returns true when `tool_name` belongs to the fixed catalog.

  ## Examples

      iex> LemmingsOs.Tools.Catalog.supported_tool?("web.fetch")
      true
      iex> LemmingsOs.Tools.Catalog.supported_tool?("exec.run")
      false
  """
  @spec supported_tool?(String.t()) :: boolean()
  def supported_tool?(tool_name) when is_binary(tool_name) do
    MapSet.member?(@tool_ids, tool_name)
  end

  def supported_tool?(_tool_name), do: false
end
