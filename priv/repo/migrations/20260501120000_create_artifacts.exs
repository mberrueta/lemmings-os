defmodule LemmingsOs.Repo.Migrations.CreateArtifacts do
  use Ecto.Migration

  def change do
    create table(:artifacts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false
      add :city_id, references(:cities, type: :binary_id, on_delete: :delete_all)

      add :department_id,
          references(:departments, type: :binary_id, on_delete: :delete_all)

      add :lemming_id, references(:lemmings, type: :binary_id, on_delete: :delete_all)

      add :lemming_instance_id,
          references(:lemming_instances, type: :binary_id, on_delete: :nilify_all)

      add :created_by_tool_execution_id,
          references(:lemming_instance_tool_executions, type: :binary_id, on_delete: :nilify_all)

      add :type, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :storage_ref, :text, null: false
      add :size_bytes, :bigint, null: false
      add :checksum, :string, null: false
      add :status, :string, null: false
      add :notes, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:artifacts, [:world_id])
    create index(:artifacts, [:world_id, :city_id, :department_id])
    create index(:artifacts, [:lemming_instance_id])
    create index(:artifacts, [:created_by_tool_execution_id])

    create index(
             :artifacts,
             [:world_id, :city_id, :department_id, :lemming_id, :filename],
             name: :artifacts_scope_filename_lookup_index
           )
  end
end
