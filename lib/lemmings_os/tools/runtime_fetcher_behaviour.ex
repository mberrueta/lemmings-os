defmodule LemmingsOs.Tools.RuntimeFetcherBehaviour do
  @moduledoc """
  Behaviour for fetching runtime tool capability data.

  Implement this behaviour to provide the runtime tool list to the Tools page
  snapshot. The default implementation returns `{:error, :not_implemented}`.
  In tests, use the `MockRuntimeFetcher` Mox mock defined in `test/support/mocks.ex`.
  """

  @callback fetch() :: {:ok, [map()]} | {:error, atom()}
end
