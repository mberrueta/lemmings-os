defmodule LemmingsOs.WorldsDocTestHelpers do
  @moduledoc false

  alias LemmingsOs.{Repo, World}

  def world_attrs(overrides \\ %{}) do
    unique_value = System.unique_integer([:positive])

    defaults = %{
      slug: "doc-world-#{unique_value}",
      name: "Doc World #{unique_value}",
      bootstrap_path: "/tmp/worlds/doc-world-#{unique_value}.default.world.yaml"
    }

    Map.merge(defaults, overrides)
  end

  def seed_world!(overrides \\ %{}) do
    overrides
    |> world_attrs()
    |> then(fn attrs ->
      %World{}
      |> World.changeset(attrs)
      |> Repo.insert!()
    end)
  end
end
