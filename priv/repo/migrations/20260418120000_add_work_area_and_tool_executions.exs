defmodule LemmingsOs.Repo.Migrations.AddWorkAreaAndToolExecutions do
  use Ecto.Migration

  def up do
    create table(:lemming_instance_tool_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :lemming_instance_id,
          references(:lemming_instances, type: :binary_id, on_delete: :delete_all),
          null: false

      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false
      add :tool_name, :string, null: false
      add :status, :string, null: false, default: "running"
      add :args, :map, null: false
      add :result, :map
      add :error, :map
      add :summary, :text
      add :preview, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :duration_ms, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:lemming_instance_tool_executions, [:lemming_instance_id])
    create index(:lemming_instance_tool_executions, [:world_id])
    create index(:lemming_instance_tool_executions, [:tool_name])
    create index(:lemming_instance_tool_executions, [:status])

    create index(
             :lemming_instance_tool_executions,
             [:lemming_instance_id, :inserted_at],
             name: :lemming_instance_tool_executions_instance_inserted_at_index
           )
  end

  def down do
    drop table(:lemming_instance_tool_executions)
  end
end
