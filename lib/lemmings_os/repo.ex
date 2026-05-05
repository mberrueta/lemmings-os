defmodule LemmingsOs.Repo do
  use Ecto.Repo,
    otp_app: :lemmings_os,
    adapter: Ecto.Adapters.Postgres

  use Scrivener, page_size: 25
end
