defmodule LemmingsOs.Connections.ConnectionTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Connections.Connection

  describe "changeset/2" do
    test "requires world scope base fields" do
      changeset = Connection.changeset(%Connection{}, %{})

      refute changeset.valid?

      errors = errors_on(changeset)

      assert ".required" in errors.world_id
      assert ".required" in errors.type
      refute Map.has_key?(errors, :status)
    end

    test "accepts registered mock type and enabled status" do
      changeset =
        Connection.changeset(%Connection{}, %{
          world_id: Ecto.UUID.generate(),
          type: "mock",
          status: "enabled",
          config: %{
            "mode" => "echo",
            "base_url" => "https://example.test/mock",
            "api_key" => "$MOCK_API_KEY"
          }
        })

      assert changeset.valid?
    end

    test "rejects unknown status values" do
      changeset =
        Connection.changeset(%Connection{}, %{
          world_id: Ecto.UUID.generate(),
          type: "mock",
          status: "paused",
          config: %{}
        })

      refute changeset.valid?
      assert ".invalid_choice" in errors_on(changeset).status
    end

    test "rejects invalid scope shape when department_id is set without city_id" do
      changeset =
        Connection.changeset(%Connection{}, %{
          world_id: Ecto.UUID.generate(),
          department_id: Ecto.UUID.generate(),
          type: "mock",
          status: "enabled",
          config: %{}
        })

      refute changeset.valid?
      assert ".invalid_value" in errors_on(changeset).city_id
    end

    test "validates config as map" do
      changeset =
        Connection.changeset(%Connection{}, %{
          world_id: Ecto.UUID.generate(),
          type: "mock",
          status: "enabled",
          config: "bad"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).config
    end

    test "rejects unsupported type" do
      changeset =
        Connection.changeset(%Connection{}, %{
          world_id: Ecto.UUID.generate(),
          type: "github",
          status: "enabled",
          config: %{}
        })

      refute changeset.valid?
      assert ".invalid_choice" in errors_on(changeset).type
    end

    test "exposes canonical statuses helper" do
      assert Connection.statuses() == ~w(enabled disabled invalid)
    end
  end

  describe "database constraints" do
    test "enforces unique type per world scope" do
      world = insert(:world)

      insert(:world_connection, world: world, type: "mock")

      changeset =
        %Connection{}
        |> Connection.changeset(%{
          world_id: world.id,
          type: "mock",
          status: "enabled",
          config: %{
            "mode" => "echo",
            "base_url" => "https://example.test/mock",
            "api_key" => "$MOCK_API_KEY"
          }
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).type
    end

    test "allows same type in child city scope" do
      world = insert(:world)
      city = insert(:city, world: world)

      insert(:world_connection, world: world, type: "mock")

      changeset =
        %Connection{}
        |> Connection.changeset(%{
          world_id: world.id,
          city_id: city.id,
          type: "mock",
          status: "enabled",
          config: %{
            "mode" => "echo",
            "base_url" => "https://example.test/mock",
            "api_key" => "$CITY_MOCK_API_KEY"
          }
        })

      assert {:ok, connection} = Repo.insert(changeset)
      assert connection.type == "mock"
      assert connection.city_id == city.id
    end

    test "enforces associated world existence" do
      changeset =
        %Connection{}
        |> Connection.changeset(%{
          world_id: Ecto.UUID.generate(),
          type: "mock",
          status: "enabled",
          config: %{
            "mode" => "echo",
            "base_url" => "https://example.test/mock",
            "api_key" => "$MOCK_API_KEY"
          }
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).world
    end
  end

  describe "factory support" do
    test "builds world scoped connection structs" do
      connection = build(:world_connection)

      assert is_nil(connection.city)
      assert is_nil(connection.department)
      assert connection.type == "mock"
    end

    test "builds city scoped connection structs" do
      connection = build(:city_connection)

      assert connection.city
      assert is_nil(connection.department)
      assert connection.world
    end

    test "builds department scoped connection structs" do
      connection = build(:department_connection)

      assert connection.department
      assert connection.city
      assert connection.world
    end
  end
end
