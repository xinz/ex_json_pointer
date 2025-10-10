defmodule ExJSONPointer.RFC6901 do
  @moduledoc false

  @not_found :not_found
  @error_not_found {:error, "not found"}
  @error_invalid_syntax {:error, "invalid JSON pointer syntax"}

  def resolve(document, ""), do: {:ok, document}
  def resolve(document, "#"), do: {:ok, document}

  def resolve(document, pointer)
      when is_map(document) and is_bitstring(pointer)
      when is_list(document) and is_bitstring(pointer) do
    do_resolve(document, pointer)
  end

  # Unescapes the reference token by replacing ~1 with / and ~0 with ~
  defp unescape(pointer) do
    String.replace(pointer, ["~1", "~0"], fn
      "~1" -> "/"
      "~0" -> "~"
    end)
  end

  defp do_resolve(document, "/" <> _pointer_str = pointer) do
    # JSON String Representation
    resolve_json_str(document, pointer)
  end

  defp do_resolve(document, "#" <> _pointer_str = pointer) do
    # URI Fragment Identifier Representation
    resolve_uri_fragment(document, pointer)
  end

  defp do_resolve(_document, _pointer) do
    @error_invalid_syntax
  end

  defp resolve_json_str(document, pointer_str) do
    start_process(document, pointer_str)
  end

  defp resolve_uri_fragment(document, pointer_str) do
    case URI.new(pointer_str) do
      {:ok, uri} ->
        start_process(document, URI.decode_www_form(uri.fragment))

      {:error, _} ->
        @error_invalid_syntax
    end
  end

  # Starts processing the pointer by splitting it into reference tokens
  defp start_process(document, ""), do: document

  defp start_process(document, input) when is_bitstring(input) do
    case String.split(input, "/") do
      ["" | ref_tokens] ->
        process(document, ref_tokens)

      other ->
        process(document, other)
    end
  end

  defp process(value, []) do
    {:ok, value}
  end

  defp process(document, [ref_token]) when is_list(document) and is_bitstring(ref_token) do
    # case that fetch the index of the array when found the value
    if String.last(ref_token) == "#" do
      ref = String.slice(ref_token, 0..-2//1)
      index = String.to_integer(ref)
      value = Enum.at(document, index, @not_found)
      if value != @not_found, do: {:ok, index}, else: @error_not_found
    else
      index = String.to_integer(ref_token)
      value = Enum.at(document, index, @not_found)
      if value != @not_found, do: {:ok, value}, else: @error_not_found
    end
  rescue
    ArgumentError ->
      @error_not_found
  end

  defp process(document, [ref_token | rest]) when is_list(document) do
    with index <- String.to_integer(ref_token),
         value when is_map(value) or is_list(value) <- Enum.at(document, index, @not_found) do
      process(value, rest)
    else
      @not_found ->
        @error_not_found

      value ->
        {:ok, value}
    end
  rescue
    ArgumentError ->
      @error_not_found
  end

  defp process(document, [ref_token]) when is_map(document) do
    if String.last(ref_token) == "#" do
      key = String.slice(ref_token, 0..-2//1)
      value = Map.get(document, unescape(key), @not_found)
      if value != @not_found, do: {:ok, key}, else: @error_not_found
    else
      value = Map.get(document, unescape(ref_token), @not_found)
      if value != @not_found, do: {:ok, value}, else: @error_not_found
    end
  end

  defp process(document, [ref_token | rest]) when is_map(document) do
    inner = Map.get(document, unescape(ref_token), @not_found)
    if inner != @not_found, do: process(inner, rest), else: @error_not_found
  end

  # Handle case when we've reached a leaf node but still have reference tokens
  defp process(value, _ref_tokens)
       when not is_list(value)
       when not is_map(value) do
    @error_not_found
  end

  def resolve_while(document, pointer, acc, resolve_fun)
      when is_map(document) and is_bitstring(pointer)
      when is_list(document) and is_bitstring(pointer) do
    case split_json_pointer(pointer) do
      [] ->
        # Empty pointer, return the original document and accumulated value
        {document, acc}

      ref_tokens when is_list(ref_tokens) ->
        Enum.reduce_while(ref_tokens, {document, acc}, fn ref_token, {doc, acc} ->
          value =
            cond do
              is_list(doc) ->
                index = String.to_integer(ref_token)
                Enum.at(doc, index, @not_found)

              is_map(doc) ->
                Map.get(doc, unescape(ref_token), @not_found)

              true ->
                @not_found
            end

          if value == @not_found do
            {:halt, @error_not_found}
          else
            resolve_fun.(value, ref_token, {doc, acc})
          end
        end)

      {:error, _} = error ->
        error
    end
  rescue
    ArgumentError ->
      @error_not_found
  end

  defp split_json_pointer(""), do: []
  defp split_json_pointer("#"), do: []

  defp split_json_pointer("/" <> _ = pointer) do
    pointer |> String.split("/") |> format_init_ref_tokens()
  end

  defp split_json_pointer("#" <> _ = pointer) do
    case URI.new(pointer) do
      {:ok, uri} ->
        uri.fragment |> String.split("/") |> format_init_ref_tokens()

      {:error, _} ->
        @error_invalid_syntax
    end
  end

  defp format_init_ref_tokens(["" | ref_tokens]), do: ref_tokens
  defp format_init_ref_tokens(ref_tokens), do: ref_tokens
end
