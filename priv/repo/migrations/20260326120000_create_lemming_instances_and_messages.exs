defmodule LemmingsOs.Repo.Migrations.CreateLemmingInstancesAndMessages do
  use Ecto.Migration

  def change do
    create table(:lemming_instances, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :lemming_id, references(:lemmings, type: :binary_id, on_delete: :delete_all),
        null: false

      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false
      add :city_id, references(:cities, type: :binary_id, on_delete: :delete_all), null: false

      add :department_id, references(:departments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false, default: "created"

      # The runtime snapshot is frozen at spawn time and must be supplied
      # explicitly so the persisted instance never depends on later config
      # resolution.
      add :config_snapshot, :map, null: false

      add :started_at, :utc_datetime
      add :stopped_at, :utc_datetime
      add :last_activity_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create table(:lemming_instance_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :lemming_instance_id,
          references(:lemming_instances, type: :binary_id, on_delete: :delete_all),
          null: false

      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false

      # Transcript rows are immutable and store the durable provider response
      # metadata alongside the rendered content.
      add :role, :string, null: false
      add :content, :text, null: false
      add :provider, :string
      add :model, :string
      add :input_tokens, :integer
      add :output_tokens, :integer
      add :total_tokens, :integer
      add :usage, :map

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:lemming_instances, [:lemming_id])
    create index(:lemming_instances, [:world_id])
    create index(:lemming_instances, [:city_id])
    create index(:lemming_instances, [:department_id])
    create index(:lemming_instances, [:lemming_id, :status])
    create index(:lemming_instances, [:department_id, :status])

    create index(:lemming_instance_messages, [:lemming_instance_id])
    create index(:lemming_instance_messages, [:world_id])
    create index(:lemming_instance_messages, [:lemming_instance_id, :inserted_at])
  end
end
