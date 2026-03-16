defmodule LemmingsOs.Repo.Migrations.CreateWorlds do
  use Ecto.Migration

  def change do
    create table(:worlds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "unknown"
      add :bootstrap_source, :string
      add :bootstrap_path, :string
      add :last_bootstrap_hash, :string
      add :last_import_status, :string, null: false, default: "unknown"
      add :last_imported_at, :utc_datetime

      # World-level declarative config stays split into scoped JSONB columns so
      # future editing, validation, and ownership remain explicit. This task
      # intentionally avoids a single catch-all `config_jsonb` blob.
      add :limits_config, :map, null: false, default: %{}
      add :runtime_config, :map, null: false, default: %{}
      add :costs_config, :map, null: false, default: %{}
      add :models_config, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:worlds, [:slug])
    create unique_index(:worlds, [:bootstrap_path], where: "bootstrap_path IS NOT NULL")
  end
end
