defmodule LemmingsOs.Repo.Migrations.CreateConnections do
  use Ecto.Migration

  def change do
    create table(:connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false
      add :city_id, references(:cities, type: :binary_id, on_delete: :delete_all)
      add :department_id, references(:departments, type: :binary_id, on_delete: :delete_all)

      add :slug, :string, null: false
      add :name, :string, null: false
      add :type, :string, null: false
      add :provider, :string, null: false
      add :status, :string, null: false
      add :config, :map, null: false, default: %{}
      add :secret_refs, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :last_tested_at, :utc_datetime
      add :last_test_status, :string
      add :last_test_error, :string

      timestamps(type: :utc_datetime)
    end

    create index(:connections, [:world_id])
    create index(:connections, [:city_id])
    create index(:connections, [:department_id])

    create index(:connections, [:world_id, :slug])
    create index(:connections, [:world_id, :city_id, :slug])
    create index(:connections, [:world_id, :city_id, :department_id, :slug])

    create unique_index(
             :connections,
             [:world_id, :slug],
             name: :connections_unique_world_scope_slug_index,
             where: "city_id IS NULL AND department_id IS NULL"
           )

    create unique_index(
             :connections,
             [:world_id, :city_id, :slug],
             name: :connections_unique_city_scope_slug_index,
             where: "city_id IS NOT NULL AND department_id IS NULL"
           )

    create unique_index(
             :connections,
             [:world_id, :city_id, :department_id, :slug],
             name: :connections_unique_department_scope_slug_index,
             where: "city_id IS NOT NULL AND department_id IS NOT NULL"
           )
  end
end
