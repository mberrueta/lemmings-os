defmodule LemmingsOs.Repo.Migrations.CreateConnections do
  use Ecto.Migration

  def change do
    create table(:connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false
      add :city_id, references(:cities, type: :binary_id, on_delete: :delete_all)
      add :department_id, references(:departments, type: :binary_id, on_delete: :delete_all)

      add :type, :string, null: false
      add :status, :string, null: false, default: "enabled"
      add :config, :map, null: false, default: %{}
      add :last_test, :text

      timestamps(type: :utc_datetime)
    end

    create index(:connections, [:world_id])
    create index(:connections, [:city_id])
    create index(:connections, [:department_id])

    create index(:connections, [:world_id, :type])
    create index(:connections, [:world_id, :city_id, :type])
    create index(:connections, [:world_id, :city_id, :department_id, :type])

    create unique_index(
             :connections,
             [:world_id, :type],
             name: :connections_unique_world_scope_type_index,
             where: "city_id IS NULL AND department_id IS NULL"
           )

    create unique_index(
             :connections,
             [:world_id, :city_id, :type],
             name: :connections_unique_city_scope_type_index,
             where: "city_id IS NOT NULL AND department_id IS NULL"
           )

    create unique_index(
             :connections,
             [:world_id, :city_id, :department_id, :type],
             name: :connections_unique_department_scope_type_index,
             where: "city_id IS NOT NULL AND department_id IS NOT NULL"
           )

    create constraint(
             :connections,
             :connections_scope_shape_check,
             check:
               "(city_id IS NULL AND department_id IS NULL) OR " <>
                 "(city_id IS NOT NULL AND department_id IS NULL) OR " <>
                 "(city_id IS NOT NULL AND department_id IS NOT NULL)"
           )
  end
end
