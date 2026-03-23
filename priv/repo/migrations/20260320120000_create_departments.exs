defmodule LemmingsOs.Repo.Migrations.CreateDepartments do
  use Ecto.Migration

  def change do
    create table(:departments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false
      add :city_id, references(:cities, type: :binary_id, on_delete: :delete_all), null: false

      add :slug, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :notes, :text
      add :tags, {:array, :string}, null: false, default: []

      # Department-level declarative config follows the same split JSONB bucket
      # model as World and City, storing local overrides only.
      add :limits_config, :map, null: false, default: %{}
      add :runtime_config, :map, null: false, default: %{}
      add :costs_config, :map, null: false, default: %{}
      add :models_config, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:departments, [:world_id])
    create index(:departments, [:city_id])
    create unique_index(:departments, [:city_id, :slug])
    create index(:departments, [:world_id, :city_id, :status])
  end
end
