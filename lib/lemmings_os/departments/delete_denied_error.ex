defmodule LemmingsOs.Departments.DeleteDeniedError do
  @moduledoc """
  Domain error returned when a Department hard delete is unsafe or indeterminate.
  """

  use Gettext, backend: LemmingsOs.Gettext

  @enforce_keys [:department_id, :reason]
  defexception [:department_id, :reason]

  @type reason :: :not_disabled | :safety_indeterminate

  @type t :: %__MODULE__{
          department_id: Ecto.UUID.t(),
          reason: reason()
        }

  @impl true
  def message(%__MODULE__{reason: :not_disabled}) do
    dgettext("errors", ".department_delete_denied_not_disabled")
  end

  def message(%__MODULE__{reason: :safety_indeterminate}) do
    dgettext("errors", ".department_delete_denied_safety_indeterminate")
  end
end
