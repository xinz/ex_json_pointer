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
end