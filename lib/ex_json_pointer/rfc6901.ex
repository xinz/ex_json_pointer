defmodule ExJSONPointer.RFC6901 do
  @moduledoc false

  @not_found :not_found
  @error_not_found {:error, "not found"}
  @error_invalid_syntax {:error, "invalid JSON pointer syntax"}

  def resolve(document, ""), do: {:ok, document}
  def resolve(document, "#"), do: {:ok, document}

  def resolve(document, pointer)
      when is_map(document) and is_binary(pointer)
      when is_list(document) and is_binary(pointer) do
    do_resolve(document, pointer)
  end

  def valid_json_pointer?(""), do: true
  def valid_json_pointer?("/"), do: true
  def valid_json_pointer?("/" <> _ = pointer) do
    not Regex.match?(~r/~[^01]|~$/, pointer)
  end
  def valid_json_pointer?(_), do: false

  def batch_resolve(document, pointers) when is_list(pointers) do
    if should_prefer_fallback?(pointers) do
      fallback_batch_to_resolve(document, pointers)
    else
      {results, groups, total, unique_first_tokens} =
         classify_batch_pointers(document, pointers, {%{}, %{}, 0, 0})

      if should_use_grouped_batch?(total, unique_first_tokens) do
        batch_process_groups(document, groups, results)
      else
        fallback_batch_to_resolve(document, groups, results)
      end
    end
  end

  defp should_use_grouped_batch?(total, _unique_first_tokens)
       when total <= 8,
       do: true

  defp should_use_grouped_batch?(total, unique_first_tokens)
       when total <= 32 and unique_first_tokens * 2 <= total,
       do: true

  defp should_use_grouped_batch?(total, unique_first_tokens)
       when total > 32 and unique_first_tokens * 3 <= total,
       do: true

  defp should_use_grouped_batch?(_total, _unique_first_tokens), do: false

  defp should_prefer_fallback?(pointers) do
    pointer_count = length(pointers)

    if pointer_count <= 8 do
      false
    else
      sample_size = min(pointer_count, 16)

      unique_first_tokens =
        pointers
        |> Enum.take(sample_size)
        |> Enum.reduce(MapSet.new(), fn pointer, acc ->
          case split_json_pointer(pointer, [parts: 3]) do
            [first | _rest] -> MapSet.put(acc, first)
            _ -> acc
          end
        end)
        |> MapSet.size()

      unique_first_tokens * 4 >= sample_size * 3
    end
  end

  defp classify_batch_pointers(_document, [], acc), do: acc
  defp classify_batch_pointers(document, [pointer | rest], acc) do
    result = classify_batch_pointer(document, pointer, acc)
    classify_batch_pointers(document, rest, result)
  end

  defp classify_batch_pointer(document, pointer, {results, groups, total, unique_count}) do
    case split_json_pointer(pointer) do
      [] ->
        {Map.put(results, pointer, {:ok, document}), groups, total + 1, unique_count}

      {:error, _} = error ->
        {Map.put(results, pointer, error), groups, total + 1, unique_count}

      [first | rest] ->
        entry = {pointer, rest}

        entries = Map.get(groups, first, nil)
        if entries != nil do
          {results, %{groups | first => [entry | entries]}, total + 1, unique_count}
        else
          {results, Map.put(groups, first, [entry]), total + 1, unique_count + 1}
        end
    end
  end

  defp fallback_batch_to_resolve(document, pointers) do
    do_fallback_batch_to_resolve(document, pointers, %{})
  end

  defp do_fallback_batch_to_resolve(_doc, [], result), do: result
  defp do_fallback_batch_to_resolve(document, [pointer | rest], result) do
    result = Map.put(result, pointer, resolve(document, pointer))
    do_fallback_batch_to_resolve(document, rest, result)
  end

  defp fallback_batch_to_resolve(document, groups, init_result) do
    do_fallback_batch_groups_to_resolve(document, Map.to_list(groups), init_result)
  end

  defp do_fallback_batch_groups_to_resolve(_document, [], result), do: result
  defp do_fallback_batch_groups_to_resolve(document, [{first_token, items} | rest], result) do
    result = do_fallback_batch_tokens_to_resolve(document, first_token, items, result)
    do_fallback_batch_groups_to_resolve(document, rest, result)
  end

  defp do_fallback_batch_tokens_to_resolve(_document, _first_token, [], result), do: result
  defp do_fallback_batch_tokens_to_resolve(document, first_token, [{pointer, rest_tokens} | rest], result) do
    value = process(document, [first_token | rest_tokens])
    do_fallback_batch_tokens_to_resolve(document, first_token, rest, Map.put(result, pointer, value))
  end

  defp batch_process_groups(_document, [], results), do: results
  defp batch_process_groups(document, groups, results) do
    batch_process_group(document, Map.to_list(groups), results)
  end

  defp batch_process_group(_document, [], results), do: results
  defp batch_process_group(document, [{token, entries} | rest], results) do
    batch_process_group(document, rest, handle_batch_group(document, token, entries, results))
  end

  defp handle_batch_group(document, token, entries, results) do
    case value_to_token(document, token) do
      {:ok, next_document} ->
        {next_results, next_groups} = batch_partition(next_document, entries, results)
        batch_process_groups(next_document, next_groups, next_results)

      {:error, _} = error ->
        fail_entries(entries, error, results)
    end
  end

  defp batch_partition(document, entries, results) do
    batch_partition_entry(document, entries, {results, %{}})
  end

  defp batch_partition_entry(_document, [], result), do: result
  defp batch_partition_entry(document, [{pointer, []} | rest_entry], {acc_result, acc_groups}) do
    acc_result = Map.put(acc_result, pointer, {:ok, document})
    batch_partition_entry(document, rest_entry, {acc_result, acc_groups})
  end
  defp batch_partition_entry(document, [{pointer, [next | other_tokens]} | rest_entry], {acc_result, acc_groups}) do
    batch_partition_entry(document, rest_entry, {acc_result, prepend_group_entry(acc_groups, next, {pointer, other_tokens})})
  end

  defp prepend_group_entry(groups, key, entry) do
    case groups do
      %{^key => entries} -> %{groups | key => [entry | entries]}
      %{} -> Map.put(groups, key, [entry])
    end
  end

  defp fail_entries(entries, error, results) do
    Enum.reduce(entries, results, fn {pointer, _rest}, acc ->
      Map.put(acc, pointer, error)
    end)
  end

  defp unescape(pointer) do
    String.replace(pointer, ["~1", "~0"], fn
      "~1" -> "/"
      "~0" -> "~"
    end)
  end

  defp do_resolve(document, "/" <> _pointer_str = pointer) do
    start_process(document, pointer)
  end

  defp do_resolve(document, "#/" <> _pointer_str = pointer) do
    start_process(document, pointer)
  end

  defp do_resolve(_document, _pointer) do
    @error_invalid_syntax
  end

  defp start_process(document, ""), do: document
  defp start_process(document, input) when is_binary(input) do
    case split_json_pointer(input) do
      {:error, _} = error ->
        error
      tokens ->
        process(document, tokens)
    end
  end

  defp process(value, []) do
    {:ok, value}
  end

  defp process(document, [ref_token]) when is_list(document) and is_binary(ref_token) do
    value_to_token(document, ref_token)
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
    value_to_token(document, ref_token)
  end

  defp process(document, [ref_token | rest]) when is_map(document) do
    inner = Map.get(document, unescape(ref_token), @not_found)
    if inner != @not_found, do: process(inner, rest), else: @error_not_found
  end

  defp process(value, _ref_tokens)
       when not is_list(value)
       when not is_map(value) do
    @error_not_found
  end

  defp value_to_token(document, "") when is_map(document) do
    find_value_by_token(document, "")
  end
  defp value_to_token(document, token) when is_map(document) do
    if :binary.last(token) == ?# do
      token = binary_part(token, 0, byte_size(token) - 1)
      find_value_by_token(document, token, true)
    else
      find_value_by_token(document, token)
    end
  end

  defp value_to_token(document, "") when is_list(document) do
    find_value_by_index(document, "")
  end
  defp value_to_token(document, token) when is_list(document) do
    if :binary.last(token) == ?# do
      token = binary_part(token, 0, byte_size(token) - 1)
      find_value_by_index(document, token, true)
    else
      find_value_by_index(document, token)
    end
  rescue
    ArgumentError ->
      @error_not_found
  end
  defp value_to_token(_, _), do: @error_not_found

  defp find_value_by_index(document, token, return_index \\ false) do
    case Integer.parse(token) do
      {index, ""} ->
        case Enum.at(document, index, @not_found) do
          @not_found ->
            @error_not_found
          _value when return_index == true ->
            {:ok, index}
          value ->
            {:ok, value}
        end
      _ ->
        @error_not_found
    end
  end

  defp find_value_by_token(document, token, return_token \\ false) do
    case Map.get(document, unescape(token), @not_found) do
      @not_found ->
        @error_not_found
      _value when return_token == true ->
        {:ok, token}
      value ->
        {:ok, value}
    end
  end

  def resolve_while(document, pointer, acc, resolve_fun)
      when is_map(document) and is_binary(pointer)
      when is_list(document) and is_binary(pointer) do
    case split_json_pointer(pointer) do
      [] ->
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

  defp split_json_pointer(pointer, opts \\ [])
  defp split_json_pointer("", _opts), do: []
  defp split_json_pointer("#", _opts), do: []
  defp split_json_pointer("/" <> _ = pointer, opts) do
    pointer |> String.split("/", opts) |> remove_first_item_if_empty_str()
  end
  defp split_json_pointer("#" <> _ = pointer, opts) do
    # URI Fragment Identifier Representation.
    # Follow the syntax specified in [RFC-6901 Section 3], which consists of zero or more reference tokens,
    # each prefixed with a forward slash character "/" (%x2F).
    case URI.new(pointer) do
      {:ok, uri} ->
        uri.fragment |> URI.decode_www_form() |> String.split("/", opts) |> remove_first_item_if_empty_str()

      {:error, _} ->
        @error_invalid_syntax
    end
  end
  defp split_json_pointer(_pointer, _opts), do: @error_invalid_syntax

  defp remove_first_item_if_empty_str(["" | ref_tokens]), do: ref_tokens
  defp remove_first_item_if_empty_str(ref_tokens), do: ref_tokens
end
