defmodule LemmingsOs.Knowledge.SourceFiles.Embedders.Fake do
  @moduledoc """
  Deterministic fake embedder for local and test environments.
  """

  @behaviour LemmingsOs.Knowledge.SourceFiles.EmbeddingProvider

  @default_dimensions 1536

  @impl true
  def embed_texts(texts, opts) when is_list(texts) and is_list(opts) do
    dimensions = Keyword.get(opts, :dimensions, @default_dimensions)

    vectors =
      Enum.map(texts, fn text ->
        text
        |> deterministic_bytes()
        |> to_vector(dimensions)
      end)

    {:ok, vectors}
  end

  def embed_texts(_texts, _opts), do: {:error, :invalid_input}

  defp deterministic_bytes(text) when is_binary(text) do
    :crypto.hash(:sha256, text)
  end

  defp deterministic_bytes(_text) do
    :crypto.hash(:sha256, "")
  end

  defp to_vector(bytes, dimensions) do
    0..(dimensions - 1)
    |> Enum.map(fn index ->
      bytes
      |> :binary.at(rem(index, byte_size(bytes)))
      |> Kernel./(255)
    end)
  end
end
