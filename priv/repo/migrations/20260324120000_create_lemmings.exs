defmodule LemmingsOs.Repo.Migrations.CreateLemmings do
  use Ecto.Migration

  def change do
    create table(:lemmings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false
      add :city_id, references(:cities, type: :binary_id, on_delete: :delete_all), null: false

      add :department_id, references(:departments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :instructions, :text
      add :status, :string, null: false, default: "draft"

      # Lemming-level declarative config keeps the existing split JSONB bucket
      # model and adds `tools_config` as the fifth bucket unique to this issue.
      add :limits_config, :map, null: false, default: %{}
      add :runtime_config, :map, null: false, default: %{}
      add :costs_config, :map, null: false, default: %{}
      add :models_config, :map, null: false, default: %{}
      add :tools_config, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:lemmings, [:world_id])
    create index(:lemmings, [:city_id])
    create index(:lemmings, [:department_id])
    create unique_index(:lemmings, [:department_id, :slug])
    create index(:lemmings, [:world_id, :city_id, :department_id, :status])
  end
end
