defmodule ExJSONPointerResolveWhileTest do
  use ExUnit.Case, async: true

  test "empty paths reference the root without invoking the callback" do
    for document <- [%{}, [], %{"key" => 1}, [1, 2]], path <- [[], "", "#"] do
      assert ExJSONPointer.resolve_while(document, path, :unchanged, fn _, _, _ ->
               flunk("the callback must not be invoked for the root path")
             end) == {document, :unchanged}
    end
  end

  test "empty tokens select empty map keys rather than the root" do
    document = %{"" => %{"" => 42}}

    assert ExJSONPointer.resolve_while(document, ["", ""], [], &collect_tokens/3) ==
             {42, ["", ""]}
  end

  test "walks decode_path output without unescaping tokens again" do
    document = %{"a/b" => %{"~1" => 42, "/" => :wrong_target}}
    assert {:ok, path} = ExJSONPointer.decode_path("#/a~1b/~01")
    assert path == ["a/b", "~1"]

    assert ExJSONPointer.resolve_while(document, path, [], &collect_tokens/3) ==
             {42, ["~1", "a/b"]}
  end

  test "decoded tokens are used literally for lookup and callbacks" do
    for token <- ["a/b", "~0", "~1", "~2", "~", "#", "key#"] do
      assert ExJSONPointer.resolve_while(%{token => 42}, [token], [], &collect_tokens/3) ==
               {42, [token]}
    end
  end

  test "does not URI-decode percent sequences or plus signs in decoded tokens" do
    for token <- ["%2F", "%7E1", "%25", "%20", "%", "a+b"] do
      assert ExJSONPointer.resolve_while(%{token => 42}, [token], [], &collect_tokens/3) ==
               {42, [token]}
    end
  end

  test "numeric-looking map keys remain strings when mixed with array indices" do
    document = %{
      "0" => %{"01" => [%{"1" => 42}]},
      "01" => :leading_zero_key,
      "-1" => :negative_key,
      0 => :integer_key
    }

    assert ExJSONPointer.resolve_while(document, ["0", "01", "0", "1"], [], &collect_tokens/3) ==
             {42, ["1", "0", "01", "0"]}

    assert ExJSONPointer.resolve_while(document, ["01"], [], &collect_tokens/3) ==
             {:leading_zero_key, ["01"]}

    assert ExJSONPointer.resolve_while(document, ["-1"], [], &collect_tokens/3) ==
             {:negative_key, ["-1"]}
  end

  test "preserves existing array-index handling and passes index tokens unchanged" do
    document = [%{"name" => "first"}, %{"name" => "last"}]

    for {token, expected} <- [
          {"0", "first"},
          {"1", "last"},
          {"01", "last"},
          {"+1", "last"},
          {"-1", "last"},
          {"-2", "first"}
        ] do
      assert ExJSONPointer.resolve_while(document, [token, "name"], [], &collect_tokens/3) ==
               {expected, ["name", token]}

      assert ExJSONPointer.resolve_while(document, "/#{token}/name", [], &collect_tokens/3) ==
               {expected, ["name", token]}
    end
  end

  test "passes parent context and continues with the value returned by the callback" do
    document = %{"a" => %{"b" => 1}}

    callback = fn
      value, "a", {parent, 0} ->
        assert value == %{"b" => 1}
        assert parent == document
        {:cont, {%{"b" => 42}, 1}}

      value, "b", {parent, 1} ->
        assert value == 42
        assert parent == %{"b" => 42}
        {:cont, {value, 2}}
    end

    assert ExJSONPointer.resolve_while(document, ["a", "b"], 0, callback) == {42, 2}
  end

  test "early termination returns the callback result without visiting remaining tokens" do
    document = %{"a" => %{"b" => 42}}

    callback = fn value, token, {parent, count} ->
      assert token == "a"
      assert parent == document
      {:halt, {:stopped, value, count + 1}}
    end

    assert ExJSONPointer.resolve_while(document, ["a", "missing"], 0, callback) ==
             {:stopped, %{"b" => 42}, 1}
  end

  test "returns not found for missing keys, invalid indices, and traversal through scalars" do
    document = %{"items" => [1, nil]}

    for path <- [
          ["missing"],
          ["items", "2"],
          ["items", "-3"],
          ["items", "0a"],
          ["items", "-"],
          ["items", ""],
          ["items", "1#"],
          ["items", "0", "missing"],
          ["items", "1", "missing"]
        ] do
      assert ExJSONPointer.resolve_while(document, path, [], &collect_tokens/3) ==
               {:error, "not found"}
    end

    assert ExJSONPointer.resolve_while(document, ["items", "1"], [], &collect_tokens/3) ==
             {nil, ["1", "items"]}
  end

  test "keeps string-pointer decoding and callback tokens unchanged" do
    document = %{"a/b" => %{"~1" => 42}, "c%d" => %{"%2F" => 43}, "a+b" => 44, "~2" => 45}

    for pointer <- ["/a~1b/~01", "#/a~1b/~01"] do
      assert ExJSONPointer.resolve_while(document, pointer, [], &collect_tokens/3) ==
               {42, ["~01", "a~1b"]}
    end

    for pointer <- ["/c%d/%2F", "#/c%25d/%252F"] do
      assert ExJSONPointer.resolve_while(document, pointer, [], &collect_tokens/3) ==
               {43, ["%2F", "c%d"]}
    end

    assert ExJSONPointer.resolve_while(document, "#/a+b", [], &collect_tokens/3) ==
             {44, ["a+b"]}

    for pointer <- ["/~2", "#/~2"] do
      assert ExJSONPointer.resolve_while(document, pointer, [], &collect_tokens/3) ==
               {45, ["~2"]}
    end
  end

  test "preserves invalid string-pointer syntax errors" do
    for pointer <- ["plain", "#plain", "##/a"] do
      assert ExJSONPointer.resolve_while(%{}, pointer, [], &collect_tokens/3) ==
               {:error, "invalid JSON pointer syntax"}
    end
  end

  defp collect_tokens(value, token, {_parent, tokens}) do
    {:cont, {value, [token | tokens]}}
  end
end
