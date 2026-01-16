defmodule ExJSONPointerValidRelativeJsonPointerTest do
  use ExUnit.Case, async: true

  describe "valid_relative_json_pointer?/1" do
    test "a valid upwards RJP" do
      assert ExJSONPointer.valid_relative_json_pointer?("1")
    end

    test "a valid downwards RJP" do
      assert ExJSONPointer.valid_relative_json_pointer?("0/foo/bar")
    end

    test "a valid up and then down RJP, with array index" do
      assert ExJSONPointer.valid_relative_json_pointer?("2/0/baz/1/zip")
    end

    test "a valid RJP taking the member or index name" do
      assert ExJSONPointer.valid_relative_json_pointer?("0#")
    end

    test "an invalid RJP that is a valid JSON Pointer" do
      refute ExJSONPointer.valid_relative_json_pointer?("/foo/bar")
    end

    test "negative prefix" do
      refute ExJSONPointer.valid_relative_json_pointer?("-1/foo/bar")
    end

    test "explicit positive prefix" do
      refute ExJSONPointer.valid_relative_json_pointer?("+1/foo/bar")
    end

    test "## is not a valid json-pointer" do
      refute ExJSONPointer.valid_relative_json_pointer?("0##")
    end

    test "zero cannot be followed by other digits, plus json-pointer" do
      refute ExJSONPointer.valid_relative_json_pointer?("01/a")
    end

    test "zero cannot be followed by other digits, plus octothorpe" do
      refute ExJSONPointer.valid_relative_json_pointer?("01#")
    end

    test "empty string" do
      refute ExJSONPointer.valid_relative_json_pointer?("")
    end

    test "multi-digit integer prefix" do
      assert ExJSONPointer.valid_relative_json_pointer?("120/foo/bar")
    end
  end
end