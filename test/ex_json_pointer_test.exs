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
               {:ok,
                %{
                  "c" => [1, 2, 3],
                  "" => "empty string",
                  "d" => nil
                }}

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

  test "invalid syntax" do
    assert ExJSONPointer.resolve(@nesting_data, "a/b") ==
             {:error, "invalid JSON pointer syntax"}
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
