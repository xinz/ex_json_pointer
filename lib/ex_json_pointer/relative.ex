defmodule ExJSONPointer.Relative do
  @moduledoc false

  @error_not_found {:error, "not found"}
  @error_syntax {:error, "invalid relative JSON pointer syntax"}

  def valid_relative_json_pointer?(pointer) do
    case Regex.named_captures(relative_json_pointer_regex(), pointer) do
      %{"json_pointer" => "/" <> _ = json_pointer} ->
        ExJSONPointer.RFC6901.valid_json_pointer?(json_pointer)

      %{} ->
        true

      nil ->
        false
    end
  end

  def resolve(_docoument, "", _relative) do
    # Refer https://datatracker.ietf.org/doc/html/draft-bhutton-relative-json-pointer-00#section-4
    # If the current referenced value is the root of the document, then evaluation fails.
    @error_not_found
  end

  def resolve(document, start_json_pointer, relative_pointer) do
    document
    |> ExJSONPointer.RFC6901.resolve_while(start_json_pointer, {[], []}, &handler_resolve/3)
    |> continue_find_relative_value(relative_pointer)
  end

  defp handler_resolve(value_of_ref_token, ref_token, {document, {levels_acc, ref_tokens_acc}}) do
    {:cont, {value_of_ref_token, {[document | levels_acc], [ref_token | ref_tokens_acc]}}}
  end

  defp continue_find_relative_value({:error, _} = error, _relative_pointer), do: error
  defp continue_find_relative_value({value_of_start, {levels, ref_tokens}}, relative_pointer) do
    relative_pointer
    |> parse_relative_json_pointer()
    |> find_value(value_of_start, levels, ref_tokens)
  end

  defp parse_relative_json_pointer(pointer) do
    relative_json_pointer_regex()
    |> Regex.named_captures(pointer)
    |> format_regex()
  end

  defp relative_json_pointer_regex() do
    ~r/^(?<prefix>0|[1-9][0-9]*)(?<index_manip>[+-](?:0|[1-9][0-9]*))?(?:(?<json_pointer>\/(?:[^#].*)?)|(?<hash_ending>#))?$/
  end

  defp format_regex(nil), do: @error_syntax
  defp format_regex(%{"prefix" => non_negative_int_prefix, "index_manip" => <<char::bitstring-size(8)>> <> index} = data)
    when char == "+" or char == "-" do
    prefix = String.to_integer(non_negative_int_prefix)
    index = String.to_integer(index)
    Map.merge(data, %{"prefix" => prefix, "index_manip" => {char, index}})
  end
  defp format_regex(%{"prefix" => non_negative_int_prefix} = data) do
    prefix = String.to_integer(non_negative_int_prefix)
    Map.put(data, "prefix", prefix)
  end

  defp find_value({:error, _} = error, _value_of_start, _levels, _ref_tokens), do: error
  defp find_value(%{"prefix" => prefix, "index_manip" => "", "hash_ending" => "#"}, _value_of_start, levels, ref_tokens) do
    target_level = Enum.at(levels, prefix)
    cond do
      is_list(target_level) ->
        index = Enum.at(ref_tokens, prefix)
        if index != nil, do: {:ok, String.to_integer(index)}, else: @error_not_found
      target_level == nil ->
        @error_not_found
      true ->
        key = Enum.at(ref_tokens, prefix)
        if key != nil, do: {:ok, key}, else: @error_not_found
    end
  end

  defp find_value(%{"prefix" => prefix, "index_manip" => {char, index}, "hash_ending" => "#"}, _value_of_start, levels, ref_tokens) do
    with {:ok, target_level} <- expect_level_of_prefix_as_list_when_with_index_manip(levels, prefix),
         {:ok, prefix_index} <- get_index_of_prefix(ref_tokens, prefix),
         {:ok, new_index} <- calculate_new_index(prefix_index, char, index) do
      if Enum.at(target_level, new_index)!= nil, do: {:ok, new_index}, else: @error_not_found
    else
      {:error, _} = error ->
        error
    end
  end

  defp find_value(%{"prefix" => prefix, "index_manip" => {char, index}, "json_pointer" => json_pointer}, _value_of_start, levels, ref_tokens) do
    with {:ok, target_level} <- expect_level_of_prefix_as_list_when_with_index_manip(levels, prefix),
         {:ok, prefix_index} <- get_index_of_prefix(ref_tokens, prefix),
         {:ok, new_index} <- calculate_new_index(prefix_index, char, index) do
      value = Enum.at(target_level, new_index)
      cond do
        json_pointer == "" and value != nil ->
          {:ok, value}
        json_pointer != "" and value != nil ->
          ExJSONPointer.RFC6901.resolve(value, json_pointer)
        true ->
          @error_not_found
      end
    else
      {:error, _} = error ->
        error
    end
  end

  defp find_value(%{"prefix" => prefix, "json_pointer" => ""}, value_of_start, levels, _ref_tokens) do
    value = Enum.at([value_of_start | levels], prefix)
    if value != nil, do: {:ok, value}, else: @error_not_found
  end

  defp find_value(%{"prefix" => prefix, "json_pointer" => json_pointer}, value_of_start, levels, _ref_tokens) do
    value = Enum.at([value_of_start | levels], prefix)
    if value != nil, do: ExJSONPointer.RFC6901.resolve(value, json_pointer), else: @error_not_found
  end

  defp calculate_new_index(prefix, "+", index), do: {:ok, prefix + index}
  defp calculate_new_index(prefix, "-", index) when prefix >= index, do: {:ok, prefix - index}
  defp calculate_new_index(_prefix, "-", _index), do: @error_syntax # Array indices are expressed as non-negative integers

  defp expect_level_of_prefix_as_list_when_with_index_manip(levels, prefix) do
    # The index manipulation (+ or - followed by a non-negative integer) in a Relative JSON Pointer is only meaningful when
    # the referenced value after moving up levels is an element within an array, the starting value is an element within an array.
    level = Enum.at(levels, prefix)
    if is_list(level), do: {:ok, level}, else: @error_syntax
  end

  defp get_index_of_prefix(ref_tokens, prefix) do
    index = Enum.at(ref_tokens, prefix)
    if index != nil do
      {:ok, String.to_integer(index)}
    else
      @error_not_found
    end
  rescue
    ArgumentError ->
      @error_syntax
  end
end
