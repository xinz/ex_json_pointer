defmodule ExJSONPointerTest do
  use ExUnit.Case
  doctest ExJSONPointer

  @rfc6901_data %{
    "foo" => ["bar", "baz"],
    "" => 0,
    "a/b" => 1,
    "c%d" => 2,
    "e^f" => 3,
    "g|h" => 4,
    "i\\j" => 5,
    "k\"l" => 6,
    " " => 7,
    "m~n" => 8
  }

  @nesting_data %{
    "" => %{
      "a" => %{
        "b" => %{
          "c" => [1, 2, 3],
          "" => "empty string from empty token"
        }
      }
    },
    "a" => %{
      "b" => %{
        "c" => [1, 2, 3],
        "" => "empty string",
        "d" => nil
      },
      "b2" => %{
        "c2" => [
          %{"d2-1" => [4, 5, 6]},
          %{"d2-2" => "7"}
        ]
      }
    }
  }

  describe "JSON string representation" do
    test "rfc6901 data sample" do
      assert ExJSONPointer.resolve(@rfc6901_data, "") == {:ok, @rfc6901_data}
      assert ExJSONPointer.resolve(@rfc6901_data, "/foo") == {:ok, ["bar", "baz"]}
      assert ExJSONPointer.resolve(@rfc6901_data, "/foo/0") == {:ok, "bar"}
      assert ExJSONPointer.resolve(@rfc6901_data, "/") == {:ok, 0}
      assert ExJSONPointer.resolve(@rfc6901_data, "/a~1b") == {:ok, 1}
      assert ExJSONPointer.resolve(@rfc6901_data, "/c%d") == {:ok, 2}
      assert ExJSONPointer.resolve(@rfc6901_data, "/e^f") == {:ok, 3}
      assert ExJSONPointer.resolve(@rfc6901_data, "/g|h") == {:ok, 4}
      assert ExJSONPointer.resolve(@rfc6901_data, "/i\\j") == {:ok, 5}
      assert ExJSONPointer.resolve(@rfc6901_data, "/k\"l") == {:ok, 6}
      assert ExJSONPointer.resolve(@rfc6901_data, "/ ") == {:ok, 7}
      assert ExJSONPointer.resolve(@rfc6901_data, "/m~0n") == {:ok, 8}
    end

    test "nesting map" do
      assert ExJSONPointer.resolve(@nesting_data, "/") ==
               {:ok,
                %{
                  "a" => %{
                    "b" => %{
                      "c" => [1, 2, 3],
                      "" => "empty string from empty token"
                    }
                  }
                }}

      assert ExJSONPointer.resolve(@nesting_data, "/a/b/4") == {:error, "not found"}
      assert ExJSONPointer.resolve(@nesting_data, "/a/b/c/4") == {:error, "not found"}
      assert ExJSONPointer.resolve(@nesting_data, "/a/b/c/unknown") == {:error, "not found"}
      assert ExJSONPointer.resolve(@nesting_data, "/a/b/c/0") == {:ok, 1}
      assert ExJSONPointer.resolve(@nesting_data, "/a/b/d") == {:ok, nil}

      assert ExJSONPointer.resolve(@nesting_data, "/a/b") ==
               {:ok,
                %{
                  "c" => [1, 2, 3],
                  "" => "empty string",
                  "d" => nil
                }}

      assert ExJSONPointer.resolve(@nesting_data, "//a/b") ==
               {:ok,
                %{
                  "c" => [1, 2, 3],
                  "" => "empty string from empty token"
                }}

      assert ExJSONPointer.resolve(@nesting_data, "/a/b/") == {:ok, "empty string"}
    end

    test "inner map of list" do
      assert ExJSONPointer.resolve(@nesting_data, "/a/b2/c2/0/d2-1/0") == {:ok, 4}
      assert ExJSONPointer.resolve(@nesting_data, "/a/b2/c2/0/d2-1/1") == {:ok, 5}
      assert ExJSONPointer.resolve(@nesting_data, "/a/b2/c2/0/d2-1/2") == {:ok, 6}
      assert ExJSONPointer.resolve(@nesting_data, "/a/b2/c2/1/d2-2") == {:ok, "7"}
    end
  end

  describe "URI fragment identifier representation" do
    test "rfc6901 data sample" do
      assert ExJSONPointer.resolve(@rfc6901_data, "#") == {:ok, @rfc6901_data}
      assert ExJSONPointer.resolve(@rfc6901_data, "#/foo") == {:ok, ["bar", "baz"]}
      assert ExJSONPointer.resolve(@rfc6901_data, "#/foo/0") == {:ok, "bar"}
      assert ExJSONPointer.resolve(@rfc6901_data, "#/") == {:ok, 0}
      assert ExJSONPointer.resolve(@rfc6901_data, "#/a~1b") == {:ok, 1}
      assert ExJSONPointer.resolve(@rfc6901_data, "#/c%25d") == {:ok, 2}
      assert ExJSONPointer.resolve(@rfc6901_data, "#/e%5Ef") == {:ok, 3}
      assert ExJSONPointer.resolve(@rfc6901_data, "#/g%7Ch") == {:ok, 4}
      assert ExJSONPointer.resolve(@rfc6901_data, "#/i%5Cj") == {:ok, 5}
      assert ExJSONPointer.resolve(@rfc6901_data, "#/k%22l") == {:ok, 6}
      assert ExJSONPointer.resolve(@rfc6901_data, "#/%20") == {:ok, 7}
      assert ExJSONPointer.resolve(@rfc6901_data, "#/m~0n") == {:ok, 8}
    end

    test "nesting map" do
      assert ExJSONPointer.resolve(@nesting_data, "#/a/b/4") == {:error, "not found"}
      assert ExJSONPointer.resolve(@nesting_data, "#/a/b/c/4") == {:error, "not found"}
      assert ExJSONPointer.resolve(@nesting_data, "#/a/b/c/0") == {:ok, 1}

      assert ExJSONPointer.resolve(@nesting_data, "#/a/b") ==
               {:ok,
                %{
                  "c" => [1, 2, 3],
                  "" => "empty string",
                  "d" => nil
                }}

      assert ExJSONPointer.resolve(@nesting_data, "#a/b") ==
               {:error, "invalid JSON pointer syntax"}

      assert ExJSONPointer.resolve(@nesting_data, "##/a/b") == {
               :error,
               "invalid JSON pointer syntax"
             }

      assert ExJSONPointer.resolve(@nesting_data, "#//a/b") ==
               {:ok,
                %{
                  "c" => [1, 2, 3],
                  "" => "empty string from empty token"
                }}

      assert ExJSONPointer.resolve(@nesting_data, "#/a/b/") == {:ok, "empty string"}
    end

    test "inner map of list" do
      assert ExJSONPointer.resolve(@nesting_data, "#/a/b2/c2/0/d2-1/0") == {:ok, 4}
      assert ExJSONPointer.resolve(@nesting_data, "#/a/b2/c2/0/d2-1/1") == {:ok, 5}
      assert ExJSONPointer.resolve(@nesting_data, "#/a/b2/c2/0/d2-1/2") == {:ok, 6}
      assert ExJSONPointer.resolve(@nesting_data, "#/a/b2/c2/1/d2-2") == {:ok, "7"}
    end
  end

  describe "decode_path/1" do
    test "decodes JSON string and URI fragment representations" do
      assert ExJSONPointer.decode_path("") == {:ok, []}
      assert ExJSONPointer.decode_path("#") == {:ok, []}
      assert ExJSONPointer.decode_path("/$defs/name") == {:ok, ["$defs", "name"]}
      assert ExJSONPointer.decode_path("#/items/0") == {:ok, ["items", "0"]}
      assert ExJSONPointer.decode_path("/a~1b/m~0n") == {:ok, ["a/b", "m~n"]}
      assert ExJSONPointer.decode_path("#/c%25d/%20") == {:ok, ["c%d", " "]}
      assert ExJSONPointer.decode_path("#/a+b") == {:ok, ["a+b"]}
    end

    test "returns an error for invalid syntax" do
      assert ExJSONPointer.decode_path("foo") == {:error, "invalid JSON pointer syntax"}
      assert ExJSONPointer.decode_path("#foo") == {:error, "invalid JSON pointer syntax"}
      assert ExJSONPointer.decode_path("/foo/~2") == {:error, "invalid JSON pointer syntax"}
      assert ExJSONPointer.decode_path("#/foo/~2") == {:error, "invalid JSON pointer syntax"}
    end
  end

  describe "encode_path/2" do
    test "uses json_string output by default" do
      assert ExJSONPointer.encode_path([]) ==
               ExJSONPointer.encode_path([], format: "json_string")

      assert ExJSONPointer.encode_path(["$defs", "name"]) ==
               ExJSONPointer.encode_path(["$defs", "name"], format: "json_string")

      assert ExJSONPointer.encode_path(["a/b", "c~d", 0], format: "json_string") == "/a~1b/c~0d/0"
      assert ExJSONPointer.encode_path([""], format: "json_string") == "/"
    end

    test "round trips json_string output with decode_path/1" do
      path = ["$defs", "a/b", "c~d", "0"]

      assert path
             |> ExJSONPointer.encode_path(format: "json_string")
             |> ExJSONPointer.decode_path() == {:ok, path}
    end

    test "supports uri_fragment output" do
      assert ExJSONPointer.encode_path([], format: "uri_fragment") == "#"
      assert ExJSONPointer.encode_path(["$defs", "name"], format: "uri_fragment") == "#/$defs/name"
      assert ExJSONPointer.encode_path(["a/b", "c~d", 0], format: "uri_fragment") == "#/a~1b/c~0d/0"
      assert ExJSONPointer.encode_path(["a b", "c%d", "k\"l"], format: "uri_fragment") == "#/a%20b/c%25d/k%22l"
    end

    test "round trips uri_fragment output with decode_path/1" do
      path = ["$defs", "a/b", "c~d", "a b", "c%d", "0"]

      assert path
             |> ExJSONPointer.encode_path(format: "uri_fragment")
             |> ExJSONPointer.decode_path() == {:ok, path}
    end

    test "raises for an unsupported format" do
      assert_raise ArgumentError,
                   ~r/expected :format to be \"json_string\" or \"uri_fragment\"/,
                   fn ->
                     ExJSONPointer.encode_path(["a"], format: "unknown")
                   end
    end
  end

  test "invalid syntax" do
    assert ExJSONPointer.resolve(@nesting_data, "a/b") ==
             {:error, "invalid JSON pointer syntax"}
  end

  test "URI fragment resolution preserves plus characters" do
    assert ExJSONPointer.resolve(%{"a+b" => 1, "a b" => 2}, "#/a+b") == {:ok, 1}
  end

  test "the ref token is exceeded the index of array" do
    assert ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => [1, 2, 3]}}}, "/a/b/c/0") == {:ok, 1}

    assert ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => [1, 2, 3]}}}, "/a/b/c/4") ==
             {:error, "not found"}
  end

  test "the ref token size is exceeded the depth of input json" do
    assert ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => [1, 2, 3]}}}, "/a/b/c///") ==
             {:error, "not found"}
  end

  test "use resolve_while/4 to struct a map with the refer token and value" do
    data = %{"a" => %{"b" => %{"c" => [10, 20, 30]}, "b2" => "b2_value"}}

    init_acc = %{}

    fun = fn current, ref_token, {_document, acc} ->
      if current != nil do
        {:cont, {current, Map.put(acc, ref_token, current)}}
      else
        {:halt, {current, acc}}
      end
    end

    {value, result} = ExJSONPointer.RFC6901.resolve_while(data, "/a/b/c/0", init_acc, fun)
    assert value == 10
    assert result["a"] == %{"b" => %{"c" => [10, 20, 30]}, "b2" => "b2_value"}
    assert result["b"] == %{"c" => [10, 20, 30]}
    assert result["c"] == [10, 20, 30]
    assert result["0"] == 10

    result = ExJSONPointer.RFC6901.resolve_while(data, "/a/b/c/0a", init_acc, fun)
    assert result == {:error, "not found"}

    result = ExJSONPointer.RFC6901.resolve_while(data, "/a/b2/c", init_acc, fun)
    assert result == {:error, "not found"}

    {value, result} = ExJSONPointer.RFC6901.resolve_while(data, "", init_acc, fun)
    assert value == data and result == init_acc
  end

  test "use resolve_while/4 to evaluate relative JSON pointer" do
    data = %{
      "foo" => ["bar", "baz"],
      "highly" => %{
        "nested" => %{
          "values" => ["!@#$%^&*()"],
          "objects" => true
        }
      }
    }

    fun = fn current, ref_token, {document, acc} ->
      {levels, ref_tokens} = acc
      {:cont, {current, {[document | levels], [ref_token | ref_tokens]}}}
    end

    init_acc = {[], []}

    {value, {levels, ref_tokens}} =
      ExJSONPointer.RFC6901.resolve_while(data, "/foo/1", init_acc, fun)

    full_levels = [value | levels]

    assert Enum.at(full_levels, 1) == ["bar", "baz"]
    assert Enum.at(full_levels, 2) == data
    assert ref_tokens == ["1", "foo"]

    {value, {levels, ref_tokens}} =
      ExJSONPointer.RFC6901.resolve_while(data, "/highly/nested", init_acc, fun)

    full_levels = [value | levels]

    assert Enum.at(full_levels, 1) == %{
             "nested" => %{"objects" => true, "values" => ["!@#$%^&*()"]}
           }

    assert Enum.at(full_levels, 2) == data
    assert ref_tokens == ["nested", "highly"]
  end

  test "fetch the key name or index of the item" do
    data = ["a", "b", "c"]
    assert ExJSONPointer.RFC6901.resolve(data, "/2#") == {:ok, 2}
    assert ExJSONPointer.RFC6901.resolve(data, "/3#") == {:error, "not found"}

    data = %{"a" => "b", "c" => %{"d" => ["1", 2, 3]}}
    assert ExJSONPointer.RFC6901.resolve(data, "/c/d#") == {:ok, "d"}
    assert ExJSONPointer.RFC6901.resolve(data, "/c/d/1#") == {:ok, 1}
    assert ExJSONPointer.RFC6901.resolve(data, "/c/d/2#") == {:ok, 2}
    assert ExJSONPointer.RFC6901.resolve(data, "/g#") == {:error, "not found"}
  end
end
