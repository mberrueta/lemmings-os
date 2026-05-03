defmodule LemmingsOs.HelpersTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.Helpers
  doctest LemmingsOs.Helpers

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

  describe "take_existing/2" do
    test "takes allowed atom and string keys into atom-keyed output" do
      assert Helpers.take_existing(
               %{:age => 42, "name" => "Ada", "ignored" => true},
               [:name, :age]
             ) == %{name: "Ada", age: 42}
    end

    test "omits missing and nil values" do
      assert Helpers.take_existing(%{"name" => nil, "role" => "manager"}, [:name, :role]) == %{
               role: "manager"
             }
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

  describe "env_or_default/2" do
    test "returns fallback when env is not set" do
      with_env("__LEMMINGS_OS_HELPERS_ENV_OR_DEFAULT_NOT_SET__", nil, fn ->
        assert Helpers.env_or_default(
                 "__LEMMINGS_OS_HELPERS_ENV_OR_DEFAULT_NOT_SET__",
                 "fallback"
               ) ==
                 "fallback"
      end)
    end

    test "returns env value when set" do
      with_env("__LEMMINGS_OS_HELPERS_ENV_OR_DEFAULT_SET__", "value", fn ->
        assert Helpers.env_or_default("__LEMMINGS_OS_HELPERS_ENV_OR_DEFAULT_SET__", "fallback") ==
                 "value"
      end)
    end
  end

  describe "env_optional_path_or_default/2" do
    test "returns fallback when env is not set" do
      with_env("__LEMMINGS_OS_HELPERS_OPTIONAL_PATH_NOT_SET__", nil, fn ->
        assert Helpers.env_optional_path_or_default(
                 "__LEMMINGS_OS_HELPERS_OPTIONAL_PATH_NOT_SET__",
                 "fallback"
               ) == "fallback"
      end)
    end

    test "maps empty env to nil" do
      with_env("__LEMMINGS_OS_HELPERS_OPTIONAL_PATH_EMPTY__", "", fn ->
        assert Helpers.env_optional_path_or_default(
                 "__LEMMINGS_OS_HELPERS_OPTIONAL_PATH_EMPTY__",
                 "fallback"
               ) == nil
      end)
    end

    test "returns env value when set" do
      with_env("__LEMMINGS_OS_HELPERS_OPTIONAL_PATH_SET__", "priv/documents/header.html", fn ->
        assert Helpers.env_optional_path_or_default(
                 "__LEMMINGS_OS_HELPERS_OPTIONAL_PATH_SET__",
                 "fallback"
               ) == "priv/documents/header.html"
      end)
    end
  end

  describe "parse_positive_integer/1" do
    test "accepts positive integers and integer strings" do
      assert Helpers.parse_positive_integer(7) == {:ok, 7}
      assert Helpers.parse_positive_integer("42") == {:ok, 42}
    end

    test "rejects zero, negatives, and invalid values" do
      assert Helpers.parse_positive_integer(0) == :error
      assert Helpers.parse_positive_integer("-1") == :error
      assert Helpers.parse_positive_integer("3.14") == :error
      assert Helpers.parse_positive_integer("abc") == :error
      assert Helpers.parse_positive_integer(nil) == :error
    end
  end

  describe "parse_non_negative_integer/1" do
    test "accepts zero and positive integers and integer strings" do
      assert Helpers.parse_non_negative_integer(0) == {:ok, 0}
      assert Helpers.parse_non_negative_integer(7) == {:ok, 7}
      assert Helpers.parse_non_negative_integer("0") == {:ok, 0}
      assert Helpers.parse_non_negative_integer("42") == {:ok, 42}
    end

    test "rejects negatives and invalid values" do
      assert Helpers.parse_non_negative_integer(-1) == :error
      assert Helpers.parse_non_negative_integer("-1") == :error
      assert Helpers.parse_non_negative_integer("abc") == :error
      assert Helpers.parse_non_negative_integer(nil) == :error
    end
  end

  defp with_env(key, value, fun) do
    previous = System.get_env(key)

    try do
      case value do
        nil -> System.delete_env(key)
        _ -> System.put_env(key, value)
      end

      fun.()
    after
      case previous do
        nil -> System.delete_env(key)
        _ -> System.put_env(key, previous)
      end
    end
  end
end
