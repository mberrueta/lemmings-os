defmodule LemmingsOs.LemmingInstances.MessageTest do
  use LemmingsOs.DataCase, async: true

  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.Repo

  test "changeset/2 accepts user and assistant messages with nullable metadata fields" do
    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)
    lemming = insert(:lemming, world: world, city: city, department: department, status: "active")
    {:ok, instance} = LemmingsOs.LemmingInstances.spawn_instance(lemming, "Initial request")

    user_changeset =
      Message.changeset(%Message{}, %{
        lemming_instance_id: instance.id,
        world_id: world.id,
        role: "user",
        content: "Follow-up request"
      })

    assistant_changeset =
      Message.changeset(%Message{}, %{
        lemming_instance_id: instance.id,
        world_id: world.id,
        role: "assistant",
        content: "Processed",
        provider: "ollama",
        model: "llama3.2",
        input_tokens: nil,
        output_tokens: nil,
        total_tokens: nil,
        usage: nil
      })

    assert user_changeset.valid?
    assert assistant_changeset.valid?
  end

  test "changeset/2 validates required fields and role inclusion" do
    changeset =
      Message.changeset(%Message{}, %{
        role: "bogus"
      })

    refute changeset.valid?

    errors = errors_on(changeset)

    assert errors.lemming_instance_id == [".required"]
    assert errors.world_id == [".required"]
    assert errors.content == [".required"]
    assert {".invalid_choice", _details} = Keyword.fetch!(changeset.errors, :role)
  end

  test "changeset/2 enforces foreign-key constraints" do
    attrs = %{
      lemming_instance_id: Ecto.UUID.generate(),
      world_id: Ecto.UUID.generate(),
      role: "user",
      content: "Missing relations"
    }

    assert {:error, changeset} =
             %Message{}
             |> Message.changeset(attrs)
             |> Repo.insert()

    refute changeset.valid?
    assert changeset.constraints != []
  end
end
