defmodule LemmingsOs.Knowledge.SourceFiles.EmbeddingProvider do
  @moduledoc """
  Behaviour for source-file embedding providers.
  """

  @type vector :: [float()]
  @type embed_result :: {:ok, [vector()]} | {:error, atom()}

  @callback embed_texts([String.t()], keyword()) :: embed_result()
end
