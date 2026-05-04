defmodule LemmingsOs.Repo.Migrations.CreateKnowledgeItems do
  use Ecto.Migration

  def change do
    create table(:knowledge_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :world_id, references(:worlds, type: :binary_id, on_delete: :delete_all), null: false
      add :city_id, references(:cities, type: :binary_id, on_delete: :delete_all)

      add :department_id,
          references(:departments, type: :binary_id, on_delete: :delete_all)

      add :lemming_id, references(:lemmings, type: :binary_id, on_delete: :delete_all)
      add :artifact_id, references(:artifacts, type: :binary_id, on_delete: :nilify_all)

      add :kind, :string, null: false
      add :title, :string, null: false
      add :content, :string, null: false
      add :tags, {:array, :string}, null: false, default: []
      add :source, :string, null: false
      add :status, :string, null: false

      add :creator_type, :string
      add :creator_id, :string

      add :creator_lemming_id,
          references(:lemmings, type: :binary_id, on_delete: :nilify_all)

      add :creator_lemming_instance_id,
          references(:lemming_instances, type: :binary_id, on_delete: :nilify_all)

      add :creator_tool_execution_id,
          references(:lemming_instance_tool_executions, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create constraint(
             :knowledge_items,
             :knowledge_items_scope_shape_check,
             check:
               "(city_id IS NULL AND department_id IS NULL AND lemming_id IS NULL) OR " <>
                 "(city_id IS NOT NULL AND department_id IS NULL AND lemming_id IS NULL) OR " <>
                 "(city_id IS NOT NULL AND department_id IS NOT NULL AND lemming_id IS NULL) OR " <>
                 "(city_id IS NOT NULL AND department_id IS NOT NULL AND lemming_id IS NOT NULL)"
           )

    create index(:knowledge_items, [:world_id])
    create index(:knowledge_items, [:city_id])
    create index(:knowledge_items, [:department_id])
    create index(:knowledge_items, [:lemming_id])
    create index(:knowledge_items, [:artifact_id])
    create index(:knowledge_items, [:creator_lemming_id])
    create index(:knowledge_items, [:creator_lemming_instance_id])
    create index(:knowledge_items, [:creator_tool_execution_id])

    create index(
             :knowledge_items,
             [:world_id, :source, :status, :inserted_at, :id],
             name: :knowledge_items_world_source_status_inserted_at_index
           )

    create index(
             :knowledge_items,
             [:world_id, :inserted_at, :id],
             name: :knowledge_items_world_scope_inserted_at_index,
             where: "city_id IS NULL AND department_id IS NULL AND lemming_id IS NULL"
           )

    create index(
             :knowledge_items,
             [:world_id, :city_id, :inserted_at, :id],
             name: :knowledge_items_city_scope_inserted_at_index,
             where: "city_id IS NOT NULL AND department_id IS NULL AND lemming_id IS NULL"
           )

    create index(
             :knowledge_items,
             [:world_id, :city_id, :department_id, :inserted_at, :id],
             name: :knowledge_items_department_scope_inserted_at_index,
             where: "city_id IS NOT NULL AND department_id IS NOT NULL AND lemming_id IS NULL"
           )

    create index(
             :knowledge_items,
             [:world_id, :city_id, :department_id, :lemming_id, :inserted_at, :id],
             name: :knowledge_items_lemming_scope_inserted_at_index,
             where: "city_id IS NOT NULL AND department_id IS NOT NULL AND lemming_id IS NOT NULL"
           )
  end
end
