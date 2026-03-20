defmodule LemmingsOs.Repo.Migrations.CreateCities do
  use Ecto.Migration

  def change do
    create table(:cities, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false

      add :slug, :string, null: false
      add :name, :string, null: false

      # `node_name` stores the full BEAM runtime identity (`name@host`) used by
      # city registration and heartbeats.
      add :node_name, :string, null: false

      # Connectivity hints are optional and intentionally non-authoritative for
      # liveness.
      add :host, :string
      add :distribution_port, :integer
      add :epmd_port, :integer

      add :status, :string, null: false, default: "active"
      add :last_seen_at, :utc_datetime

      # City-level declarative config mirrors World's split JSONB buckets and
      # stores local overrides only. This intentionally avoids a single
      # catch-all blob and keeps each ownership boundary explicit.
      add :limits_config, :map, null: false, default: %{}
      add :runtime_config, :map, null: false, default: %{}
      add :costs_config, :map, null: false, default: %{}
      add :models_config, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:cities, [:world_id])
    create unique_index(:cities, [:world_id, :slug])
    create unique_index(:cities, [:world_id, :node_name])
    create index(:cities, [:world_id, :status])
    create index(:cities, [:world_id, :last_seen_at])
  end
end
