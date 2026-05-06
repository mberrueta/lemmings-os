defmodule LemmingsOs.Knowledge.SourceFiles.IndexingWorkerTest do
  use LemmingsOs.DataCase, async: true

  alias Ecto.Changeset
  alias LemmingsOs.Knowledge.SourceFiles.IndexingWorker

  describe "new/2" do
    test "builds jobs for the dedicated knowledge indexing queue" do
      changeset = IndexingWorker.new(%{"source_file_id" => Ecto.UUID.generate()})

      assert Changeset.get_field(changeset, :queue) == "knowledge_indexing"
      assert Changeset.get_field(changeset, :max_attempts) == 3
    end
  end

  describe "perform/1" do
    test "raises until source-file indexing lifecycle is implemented" do
      job = %Oban.Job{args: %{"source_file_id" => Ecto.UUID.generate()}}

      assert_raise RuntimeError, "source-file indexing worker is not implemented yet", fn ->
        IndexingWorker.perform(job)
      end
    end
  end
end
