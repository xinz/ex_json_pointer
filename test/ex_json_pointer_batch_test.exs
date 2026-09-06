defmodule ExJSONPointerBatchTest do
  use ExUnit.Case

  test "batch_resolve/2" do
    doc = %{"foo" => %{"bar" => "baz", "qux" => "corge"}, "arr" => [1, 2, 3]}

    assert ExJSONPointer.batch_resolve(doc, ["/foo/bar", "/foo/unknown", "/arr/1"]) == %{
             "/foo/bar" => {:ok, "baz"},
             "/foo/unknown" => {:error, "not found"},
             "/arr/1" => {:ok, 2}
           }
  end

  test "batch_resolve/2 resolves shared-prefix pointers" do
    doc = %{
      "users" => %{
        "1" => %{
          "profile" => %{
            "name" => "alice",
            "email" => "alice@example.com"
          },
          "settings" => %{
            "theme" => "dark"
          }
        }
      }
    }

    assert ExJSONPointer.batch_resolve(doc, [
             "/users/1/profile/name",
             "/users/1/profile/email",
             "/users/1/settings/theme"
           ]) == %{
             "/users/1/profile/name" => {:ok, "alice"},
             "/users/1/profile/email" => {:ok, "alice@example.com"},
             "/users/1/settings/theme" => {:ok, "dark"}
           }
  end

  test "batch_resolve/2 handles root pointers and invalid syntax" do
    doc = %{"foo" => "bar"}

    assert ExJSONPointer.batch_resolve(doc, ["", "#", "foo", "##foo"]) == %{
             "" => {:ok, doc},
             "#" => {:ok, doc},
             "foo" => {:error, "invalid JSON pointer syntax"},
             "##foo" => {:error, "invalid JSON pointer syntax"}
           }
  end

  test "batch_resolve/2 supports escaped map keys" do
    doc = %{
      "a/b" => %{
        "m~n" => 1
      }
    }

    assert ExJSONPointer.batch_resolve(doc, ["/a~1b", "/a~1b/m~0n"]) == %{
             "/a~1b" => {:ok, %{"m~n" => 1}},
             "/a~1b/m~0n" => {:ok, 1}
           }
  end

  test "batch_resolve/2 returns not found for missing descendants after terminal hash lookup" do
    doc = %{
      "users" => %{
        "1" => %{
          "profile" => %{"name" => "alice"}
        }
      }
    }

    assert ExJSONPointer.batch_resolve(doc, [
             "/users/1/profile#",
             "/users/1/profile#/name",
             "/users/1/missing#"
           ]) == %{
             "/users/1/profile#" => {:ok, "profile"},
             "/users/1/profile#/name" => {:error, "not found"},
             "/users/1/missing#" => {:error, "not found"}
           }
  end

  test "batch_resolve/2 supports array indexes and index hash lookups" do
    doc = %{
      "items" => [
        %{"name" => "first"},
        %{"name" => "second"}
      ]
    }

    assert ExJSONPointer.batch_resolve(doc, [
             "/items/0/name",
             "/items/1#",
             "/items/3",
             "/items/1#/name"
           ]) == %{
             "/items/0/name" => {:ok, "first"},
             "/items/1#" => {:ok, 1},
             "/items/3" => {:error, "not found"},
             "/items/1#/name" => {:error, "not found"}
           }
  end

  test "batch_resolve_reduce/4 reduces only successful results into a map" do
    doc = %{
      "users" => %{
        "1" => %{
          "profile" => %{
            "name" => "alice",
            "email" => "alice@example.com"
          }
        }
      }
    }

    assert ExJSONPointer.batch_resolve_reduce(
             doc,
             ["/users/1/profile/name", "/users/1/profile/email", "/users/2/profile/name"],
             %{},
             fn pointer, result, acc ->
               case result do
                 {:ok, value} -> Map.put(acc, pointer, value)
                 {:error, _reason} -> acc
               end
             end
           ) == %{
             "/users/1/profile/name" => "alice",
             "/users/1/profile/email" => "alice@example.com"
           }
  end

  test "batch_resolve_reduce/4 can collect all results into a list" do
    doc = %{"foo" => "bar"}

    assert ExJSONPointer.batch_resolve_reduce(
             doc,
             ["", "#", "foo"],
             [],
             fn pointer, result, acc -> [{pointer, result} | acc] end
           )
           |> Enum.reverse() == [
             {"", {:ok, %{"foo" => "bar"}}},
             {"#", {:ok, %{"foo" => "bar"}}},
             {"foo", {:error, "invalid JSON pointer syntax"}}
           ]
  end

  test "batch_resolve_reduce/4 can count successful pointer resolutions" do
    doc = %{
      "items" => [
        %{"name" => "first"},
        %{"name" => "second"}
      ]
    }

    assert ExJSONPointer.batch_resolve_reduce(
             doc,
             ["/items/0/name", "/items/1/name", "/items/2/name", "/items/1#"],
             0,
             fn _pointer, result, acc ->
               case result do
                 {:ok, _value} -> acc + 1
                 {:error, _reason} -> acc
               end
             end
           ) == 3
  end

  test "batch_resolve/2 is equivalent to resolving each unique pointer independently" do
    doc = %{
      "" => %{"" => 1},
      "a/b" => %{"m~n" => nil},
      "a+b" => 2,
      "items" => [1, nil, %{"name" => "third"}],
      "profile#" => %{"name" => "literal hash"}
    }

    pointers = [
      "",
      "#",
      "/",
      "//",
      "/a~1b/m~0n",
      "#/a+b",
      "/items/0",
      "/items/0/missing",
      "/items/1",
      "/items/2/name",
      "/items/2#",
      "/items/9",
      "/profile#/name",
      "#a+b",
      "plain",
      "##/items",
      "/items/2/name"
    ]

    expected = Map.new(pointers, fn pointer -> {pointer, ExJSONPointer.resolve(doc, pointer)} end)

    assert ExJSONPointer.batch_resolve(doc, pointers) == expected
  end

  test "batch_resolve_reduce/4 invokes the reducer once per input occurrence with unspecified order" do
    doc = %{
      "a" => %{"x" => 1, "y" => 2},
      "b" => %{"x" => 3}
    }

    pointers = ["/b/x", "/a/x", "/a/y", "/b/x", "/missing"]

    actual =
      ExJSONPointer.batch_resolve_reduce(doc, pointers, [], fn pointer, result, acc ->
        [{pointer, result} | acc]
      end)

    expected = Enum.map(pointers, fn pointer -> {pointer, ExJSONPointer.resolve(doc, pointer)} end)

    assert Enum.sort(actual) == Enum.sort(expected)
    assert length(actual) == length(pointers)
  end

  test "batch_resolve/2 resolves high canonical sibling indexes" do
    doc = %{
      "items" => Enum.map(0..2_000, fn index -> %{"value" => index} end)
    }

    pointers = [
      "/items/3/value",
      "/items/750/value",
      "/items/1500/value",
      "/items/1999/value",
      "/items/2000/value",
      "/items/2000#",
      "/items/2001/value",
      "/items/9999"
    ]

    expected = Map.new(pointers, fn pointer -> {pointer, ExJSONPointer.resolve(doc, pointer)} end)

    assert ExJSONPointer.batch_resolve(doc, pointers) == expected
  end

  test "batch_resolve/2 preserves noncanonical and negative array index behavior" do
    doc = %{
      "items" => Enum.map(0..12, fn index -> %{"value" => index} end)
    }

    pointers = [
      "/items/01/value",
      "/items/+1/value",
      "/items/-1/value",
      "/items/-2#",
      "/items/01#",
      "/items/+1#",
      "/items/-0/value",
      "/items/13/value"
    ]

    expected = Map.new(pointers, fn pointer -> {pointer, ExJSONPointer.resolve(doc, pointer)} end)

    assert ExJSONPointer.batch_resolve(doc, pointers) == expected
    assert expected["/items/01/value"] == {:ok, 1}
    assert expected["/items/+1/value"] == {:ok, 1}
    assert expected["/items/-1/value"] == {:ok, 12}
    assert expected["/items/-2#"] == {:ok, -2}
  end

  test "batch_resolve/2 preserves nil and terminal versus nonterminal hash semantics" do
    doc = %{
      "object" => %{
        "value" => nil,
        "value#" => %{"nested" => "literal hash"}
      },
      "items" => [nil]
    }

    pointers = [
      "/object/value",
      "/object/value#",
      "/object/value#/nested",
      "/object/missing#",
      "/items/0",
      "/items/0#",
      "/items/0#/missing"
    ]

    assert ExJSONPointer.batch_resolve(doc, pointers) == %{
             "/object/value" => {:ok, nil},
             "/object/value#" => {:ok, "value"},
             "/object/value#/nested" => {:ok, "literal hash"},
             "/object/missing#" => {:error, "not found"},
             "/items/0" => {:ok, nil},
             "/items/0#" => {:ok, 0},
             "/items/0#/missing" => {:error, "not found"}
           }
  end

  test "batch_resolve_reduce/4 preserves duplicate grouped terminal and descendant callbacks" do
    doc = %{
      "items" => Enum.map(0..150, fn index -> %{"value" => index} end)
    }

    pointers = [
      "/items/125/value",
      "/items/125/value",
      "/items/125#",
      "/items/125#",
      "/items/125#",
      "/items/125#/value",
      "/items/125#/value"
    ]

    actual =
      ExJSONPointer.batch_resolve_reduce(doc, pointers, [], fn pointer, result, acc ->
        [{pointer, result} | acc]
      end)

    expected = Enum.map(pointers, fn pointer -> {pointer, ExJSONPointer.resolve(doc, pointer)} end)

    assert Enum.sort(actual) == Enum.sort(expected)
    assert length(actual) == length(pointers)
    assert Enum.frequencies_by(actual, &elem(&1, 0)) == Enum.frequencies(pointers)
  end
end
