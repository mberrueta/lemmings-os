defmodule LemmingsOs.Tools.PolicyFetcherBehaviour do
  @moduledoc """
  Behaviour for fetching tool policy reconciliation state.

  Implement this behaviour to supply policy status per tool ID to the Tools
  page snapshot. The default implementation returns `:deferred`. In tests,
  use the `LemmingsOs.Tools.MockPolicyFetcher` Mox mock.
  """

  @callback fetch() :: :deferred | {:ok, %{String.t() => String.t()}} | {:error, atom()}
end
