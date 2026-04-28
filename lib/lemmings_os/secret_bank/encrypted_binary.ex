defmodule LemmingsOs.SecretBank.EncryptedBinary do
  @moduledoc """
  Cloak-backed encrypted binary Ecto type for Secret Bank values.
  """

  use Cloak.Ecto.Binary, vault: LemmingsOs.Vault
end
