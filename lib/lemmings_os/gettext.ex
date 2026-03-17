defmodule LemmingsOs.Gettext do
  @moduledoc """
  Single Gettext backend for the entire LemmingsOS application.

  Both domain modules (`LemmingsOs.*`) and web modules (`LemmingsOsWeb.*`)
  use this backend. This ensures `mix gettext.extract` only runs once and
  all translations live in a single `priv/gettext` tree.

      use Gettext, backend: LemmingsOs.Gettext
  """
  use Gettext.Backend, otp_app: :lemmings_os
end
