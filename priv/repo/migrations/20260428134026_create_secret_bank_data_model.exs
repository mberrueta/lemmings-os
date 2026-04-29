defmodule LemmingsOs.Repo.Migrations.CreateSecretBankDataModel do
  use Ecto.Migration

  def up do
    create table(:secret_bank_secrets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false
      add :city_id, references(:cities, type: :binary_id, on_delete: :delete_all)

      add :department_id, references(:departments, type: :binary_id, on_delete: :delete_all)

      add :lemming_id, references(:lemmings, type: :binary_id, on_delete: :delete_all)

      add :bank_key, :string, null: false
      add :value_encrypted, :binary, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:secret_bank_secrets, [:world_id])
    create index(:secret_bank_secrets, [:city_id])
    create index(:secret_bank_secrets, [:department_id])
    create index(:secret_bank_secrets, [:lemming_id])
    create index(:secret_bank_secrets, [:world_id, :bank_key])

    create index(:secret_bank_secrets, [
             :world_id,
             :city_id,
             :department_id,
             :lemming_id,
             :bank_key
           ])

    create unique_index(
             :secret_bank_secrets,
             [:world_id, :bank_key],
             name: :secret_bank_secrets_unique_world_scope_index,
             where: "city_id IS NULL AND department_id IS NULL AND lemming_id IS NULL"
           )

    create unique_index(
             :secret_bank_secrets,
             [:world_id, :city_id, :bank_key],
             name: :secret_bank_secrets_unique_city_scope_index,
             where: "city_id IS NOT NULL AND department_id IS NULL AND lemming_id IS NULL"
           )

    create unique_index(
             :secret_bank_secrets,
             [:world_id, :city_id, :department_id, :bank_key],
             name: :secret_bank_secrets_unique_department_scope_index,
             where: "city_id IS NOT NULL AND department_id IS NOT NULL AND lemming_id IS NULL"
           )

    create unique_index(
             :secret_bank_secrets,
             [:world_id, :city_id, :department_id, :lemming_id, :bank_key],
             name: :secret_bank_secrets_unique_lemming_scope_index,
             where: "city_id IS NOT NULL AND department_id IS NOT NULL AND lemming_id IS NOT NULL"
           )

    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_family, :string, null: false
      add :event_type, :string, null: false
      add :occurred_at, :utc_datetime, null: false

      add :world_id, references(:worlds, type: :binary_id, on_delete: :nilify_all)
      add :city_id, references(:cities, type: :binary_id, on_delete: :nilify_all)

      add :department_id, references(:departments, type: :binary_id, on_delete: :nilify_all)

      add :lemming_id, references(:lemmings, type: :binary_id, on_delete: :nilify_all)

      add :actor_type, :string
      add :actor_id, :string
      add :actor_role, :string
      add :resource_type, :string
      add :resource_id, :string
      add :correlation_id, :string, null: false
      add :causation_id, :string
      add :request_id, :string
      add :tool_invocation_id, :string
      add :approval_request_id, :string
      add :action, :string
      add :status, :string
      add :message, :text, null: false
      add :payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:events, [:occurred_at])
    create index(:events, [:event_family, :occurred_at])
    create index(:events, [:event_type, :occurred_at])
    create index(:events, [:world_id])
    create index(:events, [:city_id])
    create index(:events, [:department_id])
    create index(:events, [:lemming_id])
    create index(:events, [:world_id, :occurred_at])
    create index(:events, [:world_id, :city_id, :occurred_at])

    create index(
             :events,
             [:world_id, :city_id, :department_id, :occurred_at],
             name: :events_world_city_department_occurred_at_index
           )

    create index(
             :events,
             [:world_id, :city_id, :department_id, :lemming_id, :occurred_at],
             name: :events_full_scope_occurred_at_index
           )

    create index(:events, [:lemming_id, :occurred_at])
    create index(:events, [:actor_type, :actor_id, :occurred_at])
    create index(:events, [:resource_type, :resource_id, :occurred_at])
    create index(:events, [:correlation_id])
    create index(:events, [:tool_invocation_id])
    create index(:events, [:approval_request_id])
  end

  def down do
    drop table(:events)
    drop table(:secret_bank_secrets)
  end
end
