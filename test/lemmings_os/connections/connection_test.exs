defmodule LemmingsOs.Connections.ConnectionTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Connections.Connection

  describe "changeset/2" do
    test "S01: requires world scope base fields" do
      changeset = Connection.changeset(%Connection{}, %{})

      refute changeset.valid?

      errors = errors_on(changeset)

      assert ".required" in errors.world_id
      assert ".required" in errors.slug
      assert ".required" in errors.name
      assert ".required" in errors.type
      assert ".required" in errors.provider
    end

    test "S02: accepts mock provider pair and enabled status" do
      changeset =
        Connection.changeset(%Connection{}, %{
          world_id: Ecto.UUID.generate(),
          slug: "mock-primary",
          name: "Mock Primary",
          type: "mock",
          provider: "mock",
          status: "enabled",
          config: %{},
          secret_refs: %{"api_key" => "$GITHUB_TOKEN"},
          metadata: %{}
        })

      assert changeset.valid?
    end

    test "S03: rejects unknown status values" do
      changeset =
        Connection.changeset(%Connection{}, %{
          world_id: Ecto.UUID.generate(),
          slug: "mock-primary",
          name: "Mock Primary",
          type: "mock",
          provider: "mock",
          status: "paused",
          config: %{},
          secret_refs: %{"api_key" => "$GITHUB_TOKEN"},
          metadata: %{}
        })

      refute changeset.valid?
      assert ".invalid_choice" in errors_on(changeset).status
    end

    test "S04: rejects invalid scope shape when department_id is set without city_id" do
      changeset =
        Connection.changeset(%Connection{}, %{
          world_id: Ecto.UUID.generate(),
          department_id: Ecto.UUID.generate(),
          slug: "mock-primary",
          name: "Mock Primary",
          type: "mock",
          provider: "mock",
          status: "enabled",
          config: %{},
          secret_refs: %{"api_key" => "$GITHUB_TOKEN"},
          metadata: %{}
        })

      refute changeset.valid?
      assert ".invalid_value" in errors_on(changeset).city_id
    end

    test "S05: validates map fields as maps" do
      changeset =
        Connection.changeset(%Connection{}, %{
          world_id: Ecto.UUID.generate(),
          slug: "mock-primary",
          name: "Mock Primary",
          type: "mock",
          provider: "mock",
          status: "enabled",
          config: "bad",
          secret_refs: %{"api_key" => "$GITHUB_TOKEN"},
          metadata: []
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).config
      assert "is invalid" in errors_on(changeset).metadata
    end

    test "S06: requires secret refs values to be Secret Bank-compatible references" do
      changeset =
        Connection.changeset(%Connection{}, %{
          world_id: Ecto.UUID.generate(),
          slug: "mock-primary",
          name: "Mock Primary",
          type: "mock",
          provider: "mock",
          status: "enabled",
          config: %{},
          secret_refs: %{"api_key" => "raw-secret-value"},
          metadata: %{}
        })

      refute changeset.valid?
      assert ".invalid_value" in errors_on(changeset).secret_refs
    end

    test "S07: enforces logical secret names in secret refs map" do
      changeset =
        Connection.changeset(%Connection{}, %{
          world_id: Ecto.UUID.generate(),
          slug: "mock-primary",
          name: "Mock Primary",
          type: "mock",
          provider: "mock",
          status: "enabled",
          config: %{},
          secret_refs: %{"API_KEY" => "$GITHUB_TOKEN"},
          metadata: %{}
        })

      refute changeset.valid?
      assert ".invalid_value" in errors_on(changeset).secret_refs
    end

    test "S08: exposes canonical statuses helper" do
      assert Connection.statuses() == ~w(enabled disabled invalid)
    end
  end

  describe "database constraints" do
    test "S09: enforces unique slug per world scope" do
      world = insert(:world)

      insert(:world_connection, world: world, slug: "github-main")

      changeset =
        %Connection{}
        |> Connection.changeset(%{
          world_id: world.id,
          slug: "github-main",
          name: "GitHub Main",
          type: "mock",
          provider: "mock",
          status: "enabled",
          config: %{},
          secret_refs: %{"api_key" => "$GITHUB_TOKEN"},
          metadata: %{}
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).slug
    end

    test "S10: allows same slug in child city scope" do
      world = insert(:world)
      city = insert(:city, world: world)

      insert(:world_connection, world: world, slug: "github-main")

      changeset =
        %Connection{}
        |> Connection.changeset(%{
          world_id: world.id,
          city_id: city.id,
          slug: "github-main",
          name: "GitHub City",
          type: "mock",
          provider: "mock",
          status: "enabled",
          config: %{},
          secret_refs: %{"api_key" => "$GITHUB_TOKEN"},
          metadata: %{}
        })

      assert {:ok, connection} = Repo.insert(changeset)
      assert connection.slug == "github-main"
      assert connection.city_id == city.id
    end

    test "S11: enforces associated world existence" do
      changeset =
        %Connection{}
        |> Connection.changeset(%{
          world_id: Ecto.UUID.generate(),
          slug: "github-main",
          name: "GitHub Main",
          type: "mock",
          provider: "mock",
          status: "enabled",
          config: %{},
          secret_refs: %{"api_key" => "$GITHUB_TOKEN"},
          metadata: %{}
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).world
    end
  end

  describe "factory support" do
    test "S12: builds world scoped connection structs" do
      connection = build(:world_connection)

      assert is_nil(connection.city)
      assert is_nil(connection.department)
      assert connection.type == "mock"
      assert connection.provider == "mock"
    end

    test "S13: builds city scoped connection structs" do
      connection = build(:city_connection)

      assert connection.city
      assert is_nil(connection.department)
      assert connection.world
    end

    test "S14: builds department scoped connection structs" do
      connection = build(:department_connection)

      assert connection.department
      assert connection.city
      assert connection.world
    end
  end
end
