defmodule LemmingsOs.Repo.Migrations.AddLemmingCollaborationRoleAndCalls do
  use Ecto.Migration

  def change do
    alter table(:lemmings) do
      add :collaboration_role, :string, null: false, default: "worker"
    end

    create table(:lemming_instance_calls, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false
      add :city_id, references(:cities, type: :binary_id, on_delete: :delete_all), null: false

      add :caller_department_id,
          references(:departments, type: :binary_id, on_delete: :restrict),
          null: false

      add :callee_department_id,
          references(:departments, type: :binary_id, on_delete: :restrict),
          null: false

      add :caller_lemming_id,
          references(:lemmings, type: :binary_id, on_delete: :restrict),
          null: false

      add :callee_lemming_id,
          references(:lemmings, type: :binary_id, on_delete: :restrict),
          null: false

      add :caller_instance_id,
          references(:lemming_instances, type: :binary_id, on_delete: :delete_all),
          null: false

      add :callee_instance_id,
          references(:lemming_instances, type: :binary_id, on_delete: :delete_all),
          null: false

      add :root_call_id, :binary_id
      add :previous_call_id, :binary_id

      add :request_text, :text, null: false
      add :status, :string, null: false, default: "accepted"
      add :result_summary, :text
      add :error_summary, :text
      add :recovery_status, :string
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:lemming_instance_calls, [:world_id])
    create index(:lemming_instance_calls, [:city_id])
    create index(:lemming_instance_calls, [:caller_department_id])
    create index(:lemming_instance_calls, [:callee_department_id])
    create index(:lemming_instance_calls, [:caller_instance_id])
    create index(:lemming_instance_calls, [:callee_instance_id])
    create index(:lemming_instance_calls, [:status])
    create index(:lemming_instance_calls, [:root_call_id])
    create index(:lemming_instance_calls, [:previous_call_id])
    create index(:lemming_instance_calls, [:world_id, :status])
    create index(:lemming_instance_calls, [:world_id, :caller_department_id, :status])
    create index(:lemming_instance_calls, [:world_id, :callee_department_id, :status])
  end
end
