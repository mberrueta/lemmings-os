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
               %{id: "knowledge.store"},
               %{id: "documents.markdown_to_html"},
               %{id: "documents.print_to_pdf"}
             ] = Catalog.list_tools()
    end
  end

  describe "supported_tool?/1" do
    test "returns true for approved tools and false otherwise" do
      assert Catalog.supported_tool?("fs.read_text_file")
      assert Catalog.supported_tool?("fs.write_text_file")
      assert Catalog.supported_tool?("web.search")
      assert Catalog.supported_tool?("web.fetch")
      assert Catalog.supported_tool?("knowledge.store")
      assert Catalog.supported_tool?("documents.markdown_to_html")
      assert Catalog.supported_tool?("documents.print_to_pdf")
      refute Catalog.supported_tool?("exec.run")
    end
  end

  describe "DefaultRuntimeFetcher.fetch/0" do
    test "returns the fixed runtime catalog" do
      assert {:ok, runtime_tools} = DefaultRuntimeFetcher.fetch()
      assert runtime_tools == Catalog.list_tools()
    end
  end
end
