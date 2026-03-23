defmodule LemmingsOs.HelpersTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.Helpers

  describe "blank?/1" do
    test "returns true for nil and blank strings" do
      assert Helpers.blank?(nil)
      assert Helpers.blank?("")
      assert Helpers.blank?("   ")
    end

    test "returns false for present values" do
      refute Helpers.blank?("text")
      refute Helpers.blank?(123)
      refute Helpers.blank?(%{})
    end
  end

  describe "slugify/1" do
    test "converts string to slug format" do
      assert Helpers.slugify("This is an example") == "this-is-an-example"
    end

    test "handles special characters" do
      assert Helpers.slugify("Another Example with Special Characters!@#$%") ==
               "another-example-with-special-characters"
    end

    test "handles multiple spaces" do
      assert Helpers.slugify("  Multiple   Spaces  ") == "multiple-spaces"
    end
  end

  describe "normalize_tags/1" do
    test "returns an empty list for nil and non-list inputs" do
      assert Helpers.normalize_tags(nil) == []
      assert Helpers.normalize_tags("ops") == []
    end

    test "normalizes tags with hyphen separators" do
      assert Helpers.normalize_tags([" Customer Support ", "High-Priority"]) == [
               "customer-support",
               "high-priority"
             ]
    end

    test "collapses repeated separators, removes blanks, and preserves first-seen order" do
      assert Helpers.normalize_tags(["---", "Ops__Desk", "ops desk", "QA", "qa"]) == [
               "ops-desk",
               "qa"
             ]
    end
  end

  describe "display_value/2" do
    test "returns translated fallback for blank values" do
      assert Helpers.display_value(nil) == "Not available"
      assert Helpers.display_value("") == "Not available"
    end

    test "formats booleans and strings" do
      assert Helpers.display_value(true) == "true"
      assert Helpers.display_value(false) == "false"
      assert Helpers.display_value("local") == "local"
    end
  end

  describe "truncate_value/2" do
    test "returns fallback for blank values" do
      assert Helpers.truncate_value(nil) == "Not available"
    end

    test "truncates long binary values with configured length" do
      assert Helpers.truncate_value("abcdefghijklmnopqrstuvwxyz", max_length: 10) ==
               "abcdefghij..."
    end

    test "returns original short values" do
      assert Helpers.truncate_value("local", max_length: 10) == "local"
    end
  end

  describe "format_datetime/2" do
    test "returns translated nil label for nil" do
      assert Helpers.format_datetime(nil) == "Not imported yet"
    end

    test "formats datetimes with the default format" do
      assert Helpers.format_datetime(~U[2026-03-17 11:03:00Z]) == "2026-03-17 11:03:00 UTC"
    end

    test "supports custom strftime formats" do
      assert Helpers.format_datetime(~U[2026-03-17 11:03:00Z], format: "%Y-%m-%d") ==
               "2026-03-17"
    end
  end
end
