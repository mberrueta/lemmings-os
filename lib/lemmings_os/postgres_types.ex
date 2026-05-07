# Extends Postgrex types with pgvector support so `vector` columns (for
# source-file chunk embeddings) can be encoded/decoded by Repo queries.
# Repo config uses this module via `types: LemmingsOs.PostgresTypes`.

Postgrex.Types.define(
  LemmingsOs.PostgresTypes,
  Pgvector.extensions() ++ Ecto.Adapters.Postgres.extensions(),
  []
)
