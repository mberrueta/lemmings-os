defmodule LemmingsOs.Connections.TypeRegistryTest do
  use LemmingsOs.DataCase, async: true

  doctest LemmingsOs.Connections.TypeRegistry

  alias LemmingsOs.Connections.TypeRegistry

  test "registers gmail type and keeps mock" do
    types = TypeRegistry.list_types()
    type_ids = Enum.map(types, & &1.id)

    assert "mock" in type_ids
    assert "gmail" in type_ids
    assert TypeRegistry.module_for_type("gmail") == LemmingsOs.Connections.Providers.GmailCaller
  end
end
