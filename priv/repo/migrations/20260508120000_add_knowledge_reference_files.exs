defmodule LemmingsOs.Repo.Migrations.AddKnowledgeReferenceFiles do
  use Ecto.Migration

  def change do
    create table(:knowledge_reference_files, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :knowledge_item_id,
          references(:knowledge_items, type: :binary_id, on_delete: :delete_all),
          null: false

      add :reference_ref, :string, null: false
      add :reference_file_type, :string, null: false
      add :original_filename, :string, null: false
      add :content_type, :string, null: false
      add :size_bytes, :bigint, null: false
      add :checksum, :string
      add :storage_ref, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:knowledge_reference_files, [:knowledge_item_id])
    create unique_index(:knowledge_reference_files, [:reference_ref])
    create index(:knowledge_reference_files, [:reference_file_type, :inserted_at, :id])

    create index(
             :knowledge_items,
             [:world_id, :status, :updated_at, :id],
             where: "kind = 'reference_file'",
             name: :knowledge_items_reference_file_world_status_updated_at_index
           )

    create index(
             :knowledge_items,
             [:world_id, :city_id, :department_id, :lemming_id, :status, :updated_at, :id],
             where: "kind = 'reference_file'",
             name: :knowledge_items_reference_file_scope_status_updated_at_index
           )

    create index(
             :knowledge_items,
             [:tags],
             using: :gin,
             where: "kind = 'reference_file'",
             name: :knowledge_items_reference_file_tags_gin_index
           )
  end
end
