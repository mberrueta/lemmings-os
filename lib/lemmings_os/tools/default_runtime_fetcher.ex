defmodule LemmingsOs.Tools.DefaultRuntimeFetcher do
  @moduledoc """
  Default runtime fetcher. Returns `{:error, :not_implemented}` until the
  real runtime capability registry is implemented.
  """

  @behaviour LemmingsOs.Tools.RuntimeFetcherBehaviour

  @impl true
  def fetch, do: {:error, :not_implemented}
end
