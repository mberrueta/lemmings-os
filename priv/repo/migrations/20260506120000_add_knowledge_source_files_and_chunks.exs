defmodule LemmingsOs.Repo.Migrations.AddKnowledgeSourceFilesAndChunks do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS vector")

    create table(:knowledge_source_files, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :knowledge_item_id,
          references(:knowledge_items, type: :binary_id, on_delete: :delete_all),
          null: false

      add :source_file_type, :string, null: false
      add :original_filename, :string, null: false
      add :content_type, :string, null: false
      add :size_bytes, :bigint, null: false
      add :checksum, :string
      add :storage_ref, :string, null: false
      add :extraction_status, :string, null: false
      add :indexing_status, :string, null: false
      add :failure_reason, :string
      add :extracted_at, :utc_datetime
      add :indexed_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:knowledge_source_files, [:knowledge_item_id])
    create index(:knowledge_source_files, [:source_file_type])
    create index(:knowledge_source_files, [:extraction_status])
    create index(:knowledge_source_files, [:indexing_status])

    create constraint(
             :knowledge_source_files,
             :knowledge_source_files_extraction_status_check,
             check:
               "extraction_status in ('pending', 'extracting', 'ready', 'needs_ocr', 'failed', 'no_content')"
           )

    create constraint(
             :knowledge_source_files,
             :knowledge_source_files_indexing_status_check,
             check:
               "indexing_status in ('pending', 'chunking', 'embedding', 'ready', 'needs_ocr', 'failed', 'archived', 'deleted')"
           )

    create table(:knowledge_source_file_chunks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :knowledge_item_id,
          references(:knowledge_items, type: :binary_id, on_delete: :delete_all),
          null: false

      add :knowledge_source_file_id,
          references(:knowledge_source_files, type: :binary_id, on_delete: :delete_all),
          null: false

      add :chunk_index, :integer, null: false
      add :chunk_ref, :string, null: false
      add :content, :text, null: false
      add :content_hash, :string, null: false
      add :token_count, :integer
      add :char_count, :integer, null: false
      add :embedding, :vector, size: 1536
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:knowledge_source_file_chunks, [:knowledge_source_file_id, :chunk_index],
             name: :knowledge_source_file_chunks_source_file_chunk_index_index
           )

    create index(:knowledge_source_file_chunks, [:chunk_ref])
    create index(:knowledge_source_file_chunks, [:knowledge_item_id])
    create index(:knowledge_source_file_chunks, [:knowledge_source_file_id, :chunk_index, :id])

    create index(
             :knowledge_source_file_chunks,
             ["embedding vector_cosine_ops"],
             using: :hnsw,
             where: "embedding IS NOT NULL",
             name: :knowledge_source_file_chunks_embedding_hnsw_index
           )

    create index(
             :knowledge_items,
             [:world_id, :status, :updated_at, :id],
             where: "kind = 'source_file'",
             name: :knowledge_items_source_file_world_status_updated_at_index
           )

    create index(
             :knowledge_items,
             [:world_id, :city_id, :department_id, :lemming_id, :status, :updated_at, :id],
             where: "kind = 'source_file'",
             name: :knowledge_items_source_file_scope_status_updated_at_index
           )
  end

  def down do
    drop index(:knowledge_items, [],
           name: :knowledge_items_source_file_scope_status_updated_at_index
         )

    drop index(:knowledge_items, [],
           name: :knowledge_items_source_file_world_status_updated_at_index
         )

    drop index(:knowledge_source_file_chunks, [],
           name: :knowledge_source_file_chunks_embedding_hnsw_index
         )

    drop index(:knowledge_source_file_chunks, [:knowledge_source_file_id, :chunk_index, :id])
    drop index(:knowledge_source_file_chunks, [:knowledge_item_id])
    drop index(:knowledge_source_file_chunks, [:chunk_ref])

    drop index(:knowledge_source_file_chunks, [:knowledge_source_file_id, :chunk_index],
           name: :knowledge_source_file_chunks_source_file_chunk_index_index
         )

    drop table(:knowledge_source_file_chunks)

    drop constraint(:knowledge_source_files, :knowledge_source_files_indexing_status_check)
    drop constraint(:knowledge_source_files, :knowledge_source_files_extraction_status_check)

    drop index(:knowledge_source_files, [:indexing_status])
    drop index(:knowledge_source_files, [:extraction_status])
    drop index(:knowledge_source_files, [:source_file_type])
    drop index(:knowledge_source_files, [:knowledge_item_id])
    drop table(:knowledge_source_files)
  end
end
