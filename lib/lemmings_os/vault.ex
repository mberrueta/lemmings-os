defmodule LemmingsOs.Vault do
  @moduledoc """
  Cloak vault for application-managed encrypted fields.

  Secret Bank values are encrypted at the Ecto type boundary. Runtime structs may
  contain decrypted values while they are inside trusted Secret Bank code, but
  context metadata APIs must not expose those values.
  """

  use Cloak.Vault, otp_app: :lemmings_os
end
