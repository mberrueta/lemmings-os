defmodule LemmingsOs.Tools.CatalogTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.Tools.Catalog
  alias LemmingsOs.Tools.DefaultRuntimeFetcher

  describe "list_tools/0" do
    test "returns only the approved first-party tools" do
      assert [
               %{id: "fs.read_text_file"},
               %{id: "fs.write_text_file"},
               %{id: "web.search"},
               %{id: "web.fetch"},
               %{id: "knowledge.search"},
               %{id: "knowledge.read"},
               %{id: "knowledge.store"},
               %{id: "documents.markdown_to_html"},
               %{id: "documents.print_to_pdf"},
               %{id: "email.create_draft"}
             ] = Catalog.list_tools()
    end

    test "exposes only draft creation for Gmail/email behavior" do
      tool_ids = Catalog.list_tools() |> Enum.map(& &1.id)

      assert "email.create_draft" in tool_ids

      gmail_or_email_tool_ids =
        Enum.filter(tool_ids, fn tool_id ->
          String.starts_with?(tool_id, ["email.", "gmail."])
        end)

      refute Enum.any?(gmail_or_email_tool_ids, fn tool_id ->
               String.contains?(tool_id, ["send", "read", "sync", "list", "delete"])
             end)

      for unsupported <- unsupported_gmail_tools() do
        refute unsupported in tool_ids
      end
    end
  end

  describe "supported_tool?/1" do
    test "returns true for approved tools and false otherwise" do
      assert Catalog.supported_tool?("fs.read_text_file")
      assert Catalog.supported_tool?("fs.write_text_file")
      assert Catalog.supported_tool?("web.search")
      assert Catalog.supported_tool?("web.fetch")
      assert Catalog.supported_tool?("knowledge.search")
      assert Catalog.supported_tool?("knowledge.read")
      assert Catalog.supported_tool?("knowledge.store")
      assert Catalog.supported_tool?("documents.markdown_to_html")
      assert Catalog.supported_tool?("documents.print_to_pdf")
      assert Catalog.supported_tool?("email.create_draft")
      refute Catalog.supported_tool?("exec.run")
    end

    test "does not support Gmail send, read, list, sync, or delete tools" do
      for unsupported <- unsupported_gmail_tools() do
        refute Catalog.supported_tool?(unsupported)
      end
    end
  end

  describe "DefaultRuntimeFetcher.fetch/0" do
    test "returns the fixed runtime catalog" do
      assert {:ok, runtime_tools} = DefaultRuntimeFetcher.fetch()
      assert runtime_tools == Catalog.list_tools()
    end
  end

  defp unsupported_gmail_tools do
    ~w(
      email.send
      email.send_approved
      email.read
      email.list
      email.sync
      email.delete
      gmail.send
      gmail.read
      gmail.list
      gmail.sync
      gmail.delete
      gmail.messages.list
      gmail.messages.read
      gmail.messages.send
    )
  end
end
