defmodule LemmingsOs.Lemmings.DeleteDeniedError do
  @moduledoc """
  Domain error returned when a Lemming hard delete is unsafe or indeterminate.
  """

  use Gettext, backend: LemmingsOs.Gettext

  @enforce_keys [:lemming_id, :reason]
  defexception [:lemming_id, :reason]

  @type reason :: :safety_indeterminate

  @type t :: %__MODULE__{
          lemming_id: Ecto.UUID.t(),
          reason: reason()
        }

  @impl true
  def message(%__MODULE__{reason: :safety_indeterminate}) do
    dgettext("errors", ".lemming_delete_denied_safety_indeterminate")
  end
end
