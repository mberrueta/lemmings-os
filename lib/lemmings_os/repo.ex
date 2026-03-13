defmodule LemmingsOs.Repo do
  use Ecto.Repo,
    otp_app: :lemmings_os,
    adapter: Ecto.Adapters.Postgres
end
