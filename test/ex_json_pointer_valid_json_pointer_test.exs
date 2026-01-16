defmodule ExJSONPointerValidJsonPointerTest do
  use ExUnit.Case, async: true

  describe "valid_json_pointer?/1" do
    test "a valid JSON-pointer" do
      assert ExJSONPointer.valid_json_pointer?("/foo/bar~0/baz~1/%a")
    end

    test "not a valid JSON-pointer (~ not escaped)" do
      refute ExJSONPointer.valid_json_pointer?("/foo/bar~")
    end

    test "valid JSON-pointer with empty segment" do
      assert ExJSONPointer.valid_json_pointer?("/foo//bar")
    end

    test "valid JSON-pointer with the last empty segment" do
      assert ExJSONPointer.valid_json_pointer?("/foo/bar/")
    end

    test "valid JSON-pointer as stated in RFC 6901 #1" do
      assert ExJSONPointer.valid_json_pointer?("")
    end

    test "valid JSON-pointer as stated in RFC 6901 #2" do
      assert ExJSONPointer.valid_json_pointer?("/foo")
    end

    test "valid JSON-pointer as stated in RFC 6901 #3" do
      assert ExJSONPointer.valid_json_pointer?("/foo/0")
    end

    test "valid JSON-pointer as stated in RFC 6901 #4" do
      assert ExJSONPointer.valid_json_pointer?("/")
    end

    test "valid JSON-pointer as stated in RFC 6901 #5" do
      assert ExJSONPointer.valid_json_pointer?("/a~1b")
    end

    test "valid JSON-pointer as stated in RFC 6901 #6" do
      assert ExJSONPointer.valid_json_pointer?("/c%d")
    end

    test "valid JSON-pointer as stated in RFC 6901 #7" do
      assert ExJSONPointer.valid_json_pointer?("/e^f")
    end

    test "valid JSON-pointer as stated in RFC 6901 #8" do
      assert ExJSONPointer.valid_json_pointer?("/g|h")
    end

    test "valid JSON-pointer as stated in RFC 6901 #9" do
      assert ExJSONPointer.valid_json_pointer?("/i\\j")
    end

    test "valid JSON-pointer as stated in RFC 6901 #10" do
      assert ExJSONPointer.valid_json_pointer?("/k\"l")
    end

    test "valid JSON-pointer as stated in RFC 6901 #11" do
      assert ExJSONPointer.valid_json_pointer?("/ ")
    end

    test "valid JSON-pointer as stated in RFC 6901 #12" do
      assert ExJSONPointer.valid_json_pointer?("/m~0n")
    end

    test "valid JSON-pointer used adding to the last array position" do
      assert ExJSONPointer.valid_json_pointer?("/foo/-")
    end

    test "valid JSON-pointer (- used as object member name)" do
      assert ExJSONPointer.valid_json_pointer?("/foo/-/bar")
    end

    test "valid JSON-pointer (multiple escaped characters)" do
      assert ExJSONPointer.valid_json_pointer?("/~1~0~0~1~1")
    end

    test "valid JSON-pointer (escaped with fraction part) #1" do
      assert ExJSONPointer.valid_json_pointer?("/~1.1")
    end

    test "valid JSON-pointer (escaped with fraction part) #2" do
      assert ExJSONPointer.valid_json_pointer?("/~0.1")
    end

    test "not a valid JSON-pointer (URI Fragment Identifier) #1" do
      refute ExJSONPointer.valid_json_pointer?("#")
    end

    test "not a valid JSON-pointer (URI Fragment Identifier) #2" do
      refute ExJSONPointer.valid_json_pointer?("#/")
    end

    test "not a valid JSON-pointer (URI Fragment Identifier) #3" do
      refute ExJSONPointer.valid_json_pointer?("#a")
    end

    test "not a valid JSON-pointer (some escaped, but not all) #1" do
      refute ExJSONPointer.valid_json_pointer?("/~0~")
    end

    test "not a valid JSON-pointer (some escaped, but not all) #2" do
      refute ExJSONPointer.valid_json_pointer?("/~0/~")
    end

    test "not a valid JSON-pointer (wrong escape character) #1" do
      refute ExJSONPointer.valid_json_pointer?("/~2")
    end

    test "not a valid JSON-pointer (wrong escape character) #2" do
      refute ExJSONPointer.valid_json_pointer?("/~-1")
    end

    test "not a valid JSON-pointer (multiple characters not escaped)" do
      refute ExJSONPointer.valid_json_pointer?("/~~")
    end

    test "not a valid JSON-pointer (isn't empty nor starts with /) #1" do
      refute ExJSONPointer.valid_json_pointer?("a")
    end

    test "not a valid JSON-pointer (isn't empty nor starts with /) #2" do
      refute ExJSONPointer.valid_json_pointer?("0")
    end

    test "not a valid JSON-pointer (isn't empty nor starts with /) #3" do
      refute ExJSONPointer.valid_json_pointer?("a/a")
    end
  end
end