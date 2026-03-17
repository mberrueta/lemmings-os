defmodule LemmingsOs.Tools.DefaultPolicyFetcher do
  @moduledoc """
  Default policy fetcher. Returns `:deferred` until the hierarchical policy
  engine is implemented.
  """

  @behaviour LemmingsOs.Tools.PolicyFetcherBehaviour

  @impl true
  def fetch, do: :deferred
end
