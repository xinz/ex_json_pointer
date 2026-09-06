defmodule ExJSONPointer.RelativeTest do
  use ExUnit.Case

  # test data from https://datatracker.ietf.org/doc/html/draft-bhutton-relative-json-pointer-00#section-5.1
  @data %{"foo" => ["bar", "baz"], "highly" => %{"nested" => %{"objects" => true}}}

  # test data from https://opis.io/json-schema/2.x/pointers.html
  @data2 %{
    "name" => "some product",
    "price" => 10.5,
    "features" => [
      "easy to use",
      %{
        "name" => "environment friendly",
        "url" => "http://example.com"
      }
    ],
    "info" => %{
      "onStock" => true
    },
    "a/b" => "a"
  }

  test "start from the value is an item within an array" do
    assert ExJSONPointer.Relative.resolve(@data, "/foo/1", "0") == {:ok, "baz"}
    assert ExJSONPointer.Relative.resolve(@data, "/foo/1", "1/0") == {:ok, "bar"}
    assert ExJSONPointer.Relative.resolve(@data, "/foo/1", "0-1") == {:ok, "bar"}
    assert ExJSONPointer.Relative.resolve(@data, "/foo/1", "2/highly/nested/objects") == {:ok, true}
    assert ExJSONPointer.Relative.resolve(@data, "/foo/1", "0#") == {:ok, 1}
    assert ExJSONPointer.Relative.resolve(@data, "/foo/1", "0-1#") == {:ok, 0}
    assert ExJSONPointer.Relative.resolve(@data, "/foo/1", "1#") == {:ok, "foo"}
  end

  test "start from the value is object" do
    assert ExJSONPointer.Relative.resolve(@data, "/highly/nested", "0/objects") == {:ok, true}
    assert ExJSONPointer.Relative.resolve(@data, "/highly/nested", "1/nested/objects") == {:ok, true}
    assert ExJSONPointer.Relative.resolve(@data, "/highly/nested", "2/foo/0") == {:ok, "bar"}
    assert ExJSONPointer.Relative.resolve(@data, "/highly/nested", "0#") == {:ok, "nested"}
    assert ExJSONPointer.Relative.resolve(@data, "/highly/nested", "1#") == {:ok, "highly"}
  end

  test "start from a normal value" do
    assert ExJSONPointer.Relative.resolve(@data2, "/price", "0") == {:ok, 10.5}
    assert ExJSONPointer.Relative.resolve(@data2, "/price", "0#") == {:ok, "price"}
    assert ExJSONPointer.Relative.resolve(@data2, "/price", "1") == {:ok, @data2}
    assert ExJSONPointer.Relative.resolve(@data2, "/price", "1#") == {:error, "not found"}
    assert ExJSONPointer.Relative.resolve(@data2, "/price", "1/name") == {:ok, "some product"}
    assert ExJSONPointer.Relative.resolve(@data2, "/price", "1/info") == {:ok, %{"onStock" => true}}
    assert ExJSONPointer.Relative.resolve(@data2, "/price", "1/info/onStock") == {:ok, true}
    assert ExJSONPointer.Relative.resolve(@data2, "/price", "1/a~1b") == {:ok, "a"}
    assert ExJSONPointer.Relative.resolve(@data2, "/price", "1/inexstent/path") == {:error, "not found"}
    assert ExJSONPointer.Relative.resolve(@data2, "/price", "2") == {:error, "not found"}
  end

  test "start from a value of an object in an array" do
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "0") == {:ok, "http://example.com"}
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "0#") == {:ok, "url"}
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "1#") == {:ok, 1}
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "1/name") == {:ok, "environment friendly"}
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "2#") == {:ok, "features"}
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "2/0") == {:ok, "easy to use"}
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "1-1") == {:ok, "easy to use"}
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "2/0#") == {:ok, 0}
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "3") == {:ok, @data2}
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "3/price") == {:ok, 10.5}
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "3/info/onStock") == {:ok, true}
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "3/info/inexstent2/path") == {:error, "not found"}
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "3#") == {:error, "not found"}
    assert ExJSONPointer.Relative.resolve(@data2, "/features/1/url", "4") == {:error, "not found"}
  end

  test "resolves existing nil values" do
    document = %{"items" => [nil, %{"value" => nil}, nil]}

    assert ExJSONPointer.Relative.resolve(document, "/items/0", "0") == {:ok, nil}
    assert ExJSONPointer.Relative.resolve(document, "/items/1/value", "0") == {:ok, nil}
    assert ExJSONPointer.Relative.resolve(document, "/items/1", "0+1") == {:ok, nil}
    assert ExJSONPointer.Relative.resolve(document, "/items/1", "0+1#") == {:ok, 2}
  end

  test "preserves start-pointer error precedence" do
    document = %{"items" => [1]}

    assert ExJSONPointer.Relative.resolve(document, "/missing", "invalid") ==
             {:error, "not found"}

    assert ExJSONPointer.Relative.resolve(document, "invalid", "invalid") ==
             {:error, "invalid JSON pointer syntax"}

    assert ExJSONPointer.Relative.resolve(document, "/items/0", "invalid") ==
             {:error, "invalid relative JSON pointer syntax"}
  end
end
