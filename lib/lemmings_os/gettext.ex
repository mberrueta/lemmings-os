defmodule LemmingsOs.Gettext do
  @moduledoc """
  Domain-level Gettext backend for LemmingsOS.

  Domain modules under `LemmingsOs.*` use this backend directly so that the
  core application layer does not depend on `LemmingsOsWeb.*`. Web modules
  may continue to use `LemmingsOsWeb.Gettext`, which shares the same
  `priv/gettext` translation files compiled under the `:lemmings_os` OTP app.
  """
  use Gettext.Backend, otp_app: :lemmings_os
end
