defmodule LemmingsOs.Tools.DefaultRuntimeFetcher do
  @moduledoc """
  Default runtime fetcher backed by the fixed Tool Runtime MVP catalog.
  """

  @behaviour LemmingsOs.Tools.RuntimeFetcherBehaviour

  alias LemmingsOs.Tools.Catalog

  @impl true
  def fetch, do: {:ok, Catalog.list_tools()}
end
