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

  def decode_path(""), do: {:ok, []}
  def decode_path("#"), do: {:ok, []}

  def decode_path("/" <> _ = pointer) do
    if valid_json_pointer?(pointer) do
      {:ok,
       pointer
       |> String.split("/")
       |> remove_first_item_if_empty_str()
       |> Enum.map(&unescape/1)}
    else
      @error_invalid_syntax
    end
  end

  def decode_path("#/" <> _ = pointer) do
    case URI.new(pointer) do
      {:ok, %URI{fragment: fragment}} ->
        decoded_pointer = URI.decode(fragment)

        if valid_json_pointer?(decoded_pointer) do
          {:ok,
           decoded_pointer
           |> String.split("/")
           |> remove_first_item_if_empty_str()
           |> Enum.map(&unescape/1)}
        else
          @error_invalid_syntax
        end

      {:error, _} ->
        @error_invalid_syntax
    end
  end

  def decode_path(_pointer), do: @error_invalid_syntax

  def encode_path(tokens) when is_list(tokens) do
    case Enum.map(tokens, &escape_token/1) do
      [] -> ""
      escaped_tokens -> "/" <> Enum.join(escaped_tokens, "/")
    end
  end

  def valid_json_pointer?(""), do: true
  def valid_json_pointer?("/"), do: true
  def valid_json_pointer?("/" <> _ = pointer) do
    not Regex.match?(~r/~[^01]|~$/, pointer)
  end
  def valid_json_pointer?(_), do: false

  def batch_resolve(document, pointers) when is_list(pointers) do
    batch_resolve_reduce(document, pointers, %{}, fn pointer, result, acc ->
      Map.put(acc, pointer, result)
    end)
  end

  def batch_resolve_reduce(document, pointers, acc, reduce_fun)
      when is_list(pointers) and is_function(reduce_fun, 3) do
    with false <- should_prefer_fallback?(pointers),
         {acc, groups, total, unique_first_tokens} <-
           classify_batch_pointers(document, pointers, {acc, %{}, 0, 0}, reduce_fun) do
      if should_use_grouped_batch?(total, unique_first_tokens) do
        batch_process_groups(document, groups, acc, reduce_fun)
      else
        fallback_batch_to_resolve(document, groups, acc, reduce_fun)
      end
    else
      _ ->
        fallback_batch_to_resolve(document, pointers, acc, reduce_fun)
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
    calc_unique_to_fallback?(pointers, length(pointers), 16)
  end

  defp calc_unique_to_fallback?(_pointers, pointers_size, _sample_size)
       when pointers_size <= 8, do: false

  defp calc_unique_to_fallback?(pointers, pointers_size, sample_size) do
    sample_size = min(pointers_size, sample_size)
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

  defp classify_batch_pointers(_document, [], acc, _reduce_fun), do: acc
  defp classify_batch_pointers(document, [pointer | rest], acc, reduce_fun) do
    result = classify_batch_pointer(document, pointer, acc, reduce_fun)
    classify_batch_pointers(document, rest, result, reduce_fun)
  end

  defp classify_batch_pointer(document, pointer, {acc, groups, total, unique_count}, reduce_fun) do
    case split_json_pointer(pointer) do
      [] ->
        {reduce_fun.(pointer, {:ok, document}, acc), groups, total + 1, unique_count}

      {:error, _} = error ->
        {reduce_fun.(pointer, error, acc), groups, total + 1, unique_count}

      [first] ->
        case value_to_token(document, first) do
          {:ok, _value} = result ->
            {reduce_fun.(pointer, result, acc), groups, total + 1, unique_count}

          {:error, _} = error ->
            {reduce_fun.(pointer, error, acc), groups, total + 1, unique_count}
        end

      [first | rest] ->
        entries = Map.get(groups, first, nil)

        if entries != nil do
          {acc, %{groups | first => [{pointer, rest} | entries]}, total + 1, unique_count}
        else
          {acc, Map.put(groups, first, [{pointer, rest}]), total + 1, unique_count + 1}
        end
    end
  end

  defp fallback_batch_to_resolve(document, pointers, acc, reduce_fun) when is_list(pointers) do
    do_fallback_batch_to_resolve(document, pointers, acc, reduce_fun)
  end

  defp fallback_batch_to_resolve(document, groups, acc, reduce_fun) when is_map(groups) do
    do_fallback_batch_groups_to_resolve(document, Map.to_list(groups), acc, reduce_fun)
  end

  defp do_fallback_batch_to_resolve(_doc, [], acc, _reduce_fun), do: acc
  defp do_fallback_batch_to_resolve(document, [pointer | rest], acc, reduce_fun) do
    acc = reduce_fun.(pointer, resolve(document, pointer), acc)
    do_fallback_batch_to_resolve(document, rest, acc, reduce_fun)
  end

  defp do_fallback_batch_groups_to_resolve(_document, [], acc, _reduce_fun), do: acc
  defp do_fallback_batch_groups_to_resolve(document, [{first_token, items} | rest], acc, reduce_fun) do
    acc = do_fallback_batch_tokens_to_resolve(document, first_token, items, acc, reduce_fun)
    do_fallback_batch_groups_to_resolve(document, rest, acc, reduce_fun)
  end

  defp do_fallback_batch_tokens_to_resolve(_document, _first_token, [], acc, _reduce_fun), do: acc
  defp do_fallback_batch_tokens_to_resolve(document, first_token, [{pointer, rest_tokens} | rest], acc, reduce_fun) do
    value = process(document, [first_token | rest_tokens])
    acc = reduce_fun.(pointer, value, acc)
    do_fallback_batch_tokens_to_resolve(document, first_token, rest, acc, reduce_fun)
  end

  defp batch_process_groups(_document, [], acc, _reduce_fun), do: acc

  defp batch_process_groups(document, groups, acc, reduce_fun) do
    batch_process_group(document, Map.to_list(groups), acc, reduce_fun)
  end

  defp batch_process_group(_document, [], acc, _reduce_fun), do: acc

  defp batch_process_group(document, [{token, entries} | rest], acc, reduce_fun) do
    acc = handle_batch_group(document, token, entries, acc, reduce_fun)
    batch_process_group(document, rest, acc, reduce_fun)
  end

  defp handle_batch_group(document, token, entries, acc, reduce_fun) do
    case value_to_token(document, token) do
      {:ok, next_document} ->
        {acc, next_groups} = batch_partition(next_document, entries, acc, reduce_fun)
        batch_process_groups(next_document, next_groups, acc, reduce_fun)

      {:error, _} = error ->
        fail_entries(entries, error, acc, reduce_fun)
    end
  end

  defp batch_partition(document, entries, acc, reduce_fun) do
    batch_partition_entry(document, entries, {acc, %{}}, reduce_fun)
  end

  defp batch_partition_entry(_document, [], result, _reduce_fun), do: result

  defp batch_partition_entry(document, [{pointer, [next]} | rest_entry], {acc, acc_groups}, reduce_fun) do
    acc = reduce_fun.(pointer, value_to_token(document, next), acc)
    batch_partition_entry(document, rest_entry, {acc, acc_groups}, reduce_fun)
  end

  defp batch_partition_entry(document, [{pointer, [next | other_tokens]} | rest_entry], {acc, acc_groups}, reduce_fun) do
    batch_partition_entry(
      document,
      rest_entry,
      {acc, prepend_group_entry(acc_groups, next, {pointer, other_tokens})},
      reduce_fun
    )
  end

  defp prepend_group_entry(groups, key, entry) do
    case groups do
      %{^key => entries} -> %{groups | key => [entry | entries]}
      %{} -> Map.put(groups, key, [entry])
    end
  end

  defp fail_entries(entries, error, acc, reduce_fun) do
    Enum.reduce(entries, acc, fn {pointer, _rest}, inner_acc ->
      reduce_fun.(pointer, error, inner_acc)
    end)
  end

  defp unescape(pointer) do
    String.replace(pointer, ["~1", "~0"], fn
      "~1" -> "/"
      "~0" -> "~"
    end)
  end

  defp escape_token(token) when is_binary(token) do
    token
    |> String.replace("~", "~0")
    |> String.replace("/", "~1")
  end

  defp escape_token(token) when is_integer(token) do
    token
    |> Integer.to_string()
    |> escape_token()
  end

  defp escape_token(token) do
    raise ArgumentError, "path tokens must be strings or integers, got: #{inspect(token)}"
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
        uri.fragment |> URI.decode() |> String.split("/", opts) |> remove_first_item_if_empty_str()

      {:error, _} ->
        @error_invalid_syntax
    end
  end
  defp split_json_pointer(_pointer, _opts), do: @error_invalid_syntax

  defp remove_first_item_if_empty_str(["" | ref_tokens]), do: ref_tokens
  defp remove_first_item_if_empty_str(ref_tokens), do: ref_tokens
end
