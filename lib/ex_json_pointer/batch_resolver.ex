defmodule ExJSONPointer.BatchResolver do
  @moduledoc false

  alias ExJSONPointer.RFC6901

  import RFC6901,
    only: [
      fetch_child: 2,
      process: 2,
      split_json_pointer: 1,
      split_json_pointer: 2,
      value_to_token: 2
    ]

  @error_not_found {:error, "not found"}

  def resolve(document, pointers) when is_list(pointers) do
    reduce_fun = fn pointer, result, acc -> Map.put(acc, pointer, result) end

    if should_prefer_fallback?(pointers) do
      fallback_batch_to_resolve(document, pointers, %{}, reduce_fun)
    else
      do_batch_resolve_reduce(document, pointers, %{}, reduce_fun)
    end
  end

  def reduce(document, pointers, acc, reduce_fun)
      when is_list(pointers) and is_function(reduce_fun, 3) do
    if should_prefer_fallback?(pointers) do
      fallback_batch_to_resolve(document, pointers, acc, reduce_fun)
    else
      do_batch_resolve_reduce(document, pointers, acc, reduce_fun)
    end
  end

  defp do_batch_resolve_reduce(document, pointers, acc, reduce_fun) do
    {acc, groups, total} =
      classify_batch_pointers(document, pointers, {acc, %{}, 0}, reduce_fun)

    if should_use_grouped_batch?(total, map_size(groups)) do
      batch_process_groups(document, groups, acc, reduce_fun)
    else
      fallback_batch_groups_to_resolve(document, groups, acc, reduce_fun)
    end
  end

  defp should_prefer_fallback?(pointers) do
    sample_sparse_batch?(pointers, 0, %{}, 16)
  end

  defp sample_sparse_batch?([], sample_size, unique_tokens, _limit) do
    sample_size > 8 and sparse_sample?(sample_size, map_size(unique_tokens))
  end

  defp sample_sparse_batch?(_pointers, sample_size, unique_tokens, sample_size) do
    sparse_sample?(sample_size, map_size(unique_tokens))
  end

  defp sample_sparse_batch?([pointer | rest], sample_size, unique_tokens, limit) do
    unique_tokens =
      case split_json_pointer(pointer, [parts: 3]) do
        [first | _rest] -> Map.put(unique_tokens, first, true)
        _ -> unique_tokens
      end

    sample_sparse_batch?(rest, sample_size + 1, unique_tokens, limit)
  end

  defp sparse_sample?(sample_size, unique_count) do
    unique_count * 4 >= sample_size * 3
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

  defp classify_batch_pointers(_document, [], acc, _reduce_fun), do: acc

  defp classify_batch_pointers(document, [pointer | rest], acc, reduce_fun) do
    result = classify_batch_pointer(document, pointer, acc, reduce_fun)
    classify_batch_pointers(document, rest, result, reduce_fun)
  end

  defp classify_batch_pointer(document, pointer, {acc, groups, total}, reduce_fun) do
    case split_json_pointer(pointer) do
      [] ->
        {reduce_fun.(pointer, {:ok, document}, acc), groups, total + 1}

      {:error, _} = error ->
        {reduce_fun.(pointer, error, acc), groups, total + 1}

      [first] ->
        result = value_to_token(document, first)
        {reduce_fun.(pointer, result, acc), groups, total + 1}

      [first | rest] ->
        {acc, prepend_group_entry(groups, first, {pointer, rest}), total + 1}
    end
  end

  defp fallback_batch_to_resolve(document, pointers, acc, reduce_fun) do
    Enum.reduce(pointers, acc, fn pointer, inner_acc ->
      reduce_fun.(pointer, RFC6901.resolve(document, pointer), inner_acc)
    end)
  end

  defp fallback_batch_groups_to_resolve(document, groups, acc, reduce_fun) do
    Enum.reduce(groups, acc, fn {first_token, entries}, inner_acc ->
      fallback_batch_tokens_to_resolve(document, first_token, entries, inner_acc, reduce_fun)
    end)
  end

  defp fallback_batch_tokens_to_resolve(_document, _first_token, [], acc, _reduce_fun), do: acc

  defp fallback_batch_tokens_to_resolve(
         document,
         first_token,
         [{pointer, rest_tokens} | rest],
         acc,
         reduce_fun
       ) do
    result = process(document, [first_token | rest_tokens])
    acc = reduce_fun.(pointer, result, acc)
    fallback_batch_tokens_to_resolve(document, first_token, rest, acc, reduce_fun)
  end

  defp batch_process_groups(_document, groups, acc, _reduce_fun)
       when map_size(groups) == 0,
       do: acc

  defp batch_process_groups(document, groups, acc, reduce_fun) when is_list(document) do
    if enough_indexed_list_groups?(groups, 8) do
      # Canonical indexes share one forward traversal; aliases and negatives use the compatibility path.
      {indexed_groups, acc} = index_list_groups(document, groups, {%{}, acc}, reduce_fun)
      traverse_indexed_groups(document, 0, indexed_groups, acc, reduce_fun)
    else
      batch_process_groups_independently(document, groups, acc, reduce_fun)
    end
  end

  defp batch_process_groups(document, groups, acc, reduce_fun) do
    batch_process_groups_independently(document, groups, acc, reduce_fun)
  end

  defp batch_process_groups_independently(document, groups, acc, reduce_fun) do
    batch_process_group_list(document, Map.to_list(groups), acc, reduce_fun)
  end

  defp batch_process_group_list(_document, [], acc, _reduce_fun), do: acc

  defp batch_process_group_list(document, [{token, entries} | rest], acc, reduce_fun) do
    acc = batch_process_child_group(document, token, entries, acc, reduce_fun)
    batch_process_group_list(document, rest, acc, reduce_fun)
  end

  defp enough_indexed_list_groups?(groups, threshold) do
    groups
    |> Enum.reduce_while(0, fn {token, _entries}, count ->
      if canonical_index?(token) do
        next_count = count + 1
        if next_count >= threshold, do: {:halt, true}, else: {:cont, next_count}
      else
        {:cont, count}
      end
    end)
    |> Kernel.==(true)
  end

  defp canonical_index?(token) do
    match?({:ok, _index}, canonical_index(token))
  end

  defp batch_process_child_group(_document, _token, [], acc, _reduce_fun), do: acc

  defp batch_process_child_group(document, token, entries, acc, reduce_fun) do
    case fetch_child(document, token) do
      {:ok, next_document} ->
        batch_process_entries(next_document, entries, acc, reduce_fun)

      {:error, _} = error ->
        fail_entries(entries, error, acc, reduce_fun)
    end
  end

  defp batch_process_entries(document, entries, acc, reduce_fun) do
    {acc, groups} = batch_partition_direct(document, entries, {acc, %{}}, reduce_fun)
    batch_process_groups(document, groups, acc, reduce_fun)
  end

  defp batch_partition_direct(_document, [], result, _reduce_fun), do: result

  defp batch_partition_direct(
         document,
         [{pointer, [next]} | rest],
         {acc, groups},
         reduce_fun
       ) do
    acc = reduce_fun.(pointer, value_to_token(document, next), acc)
    batch_partition_direct(document, rest, {acc, groups}, reduce_fun)
  end

  defp batch_partition_direct(
         document,
         [{pointer, [next | other_tokens]} | rest],
         {acc, groups},
         reduce_fun
       ) do
    groups = prepend_group_entry(groups, next, {pointer, other_tokens})
    batch_partition_direct(document, rest, {acc, groups}, reduce_fun)
  end

  defp prepend_group_entry(groups, key, entry) do
    case groups do
      %{^key => entries} -> %{groups | key => [entry | entries]}
      %{} -> Map.put(groups, key, [entry])
    end
  end

  defp index_list_groups(document, groups, acc, reduce_fun) do
    Enum.reduce(groups, acc, fn {token, entries}, {indexed_groups, inner_acc} ->
      case canonical_index(token) do
        {:ok, index} ->
          {Map.put(indexed_groups, index, entries), inner_acc}

        :error ->
          inner_acc = batch_process_child_group(document, token, entries, inner_acc, reduce_fun)
          {indexed_groups, inner_acc}
      end
    end)
  end

  defp traverse_indexed_groups(_document, _index, indexed_groups, acc, _reduce_fun)
       when map_size(indexed_groups) == 0,
       do: acc

  defp traverse_indexed_groups([], _index, indexed_groups, acc, reduce_fun) do
    Enum.reduce(indexed_groups, acc, fn {_index, entries}, inner_acc ->
      fail_entries(entries, @error_not_found, inner_acc, reduce_fun)
    end)
  end

  defp traverse_indexed_groups([value | rest], index, indexed_groups, acc, reduce_fun) do
    case Map.pop(indexed_groups, index) do
      {nil, indexed_groups} ->
        traverse_indexed_groups(rest, index + 1, indexed_groups, acc, reduce_fun)

      {entries, indexed_groups} ->
        acc = batch_process_entries(value, entries, acc, reduce_fun)
        traverse_indexed_groups(rest, index + 1, indexed_groups, acc, reduce_fun)
    end
  end

  defp canonical_index(token) do
    with {:ok, index} when index >= 0 <- parse_index(token),
         true <- Integer.to_string(index) == token do
      {:ok, index}
    else
      _ -> :error
    end
  end

  defp parse_index(token) do
    case Integer.parse(token) do
      {index, ""} -> {:ok, index}
      _ -> :error
    end
  end

  defp fail_entries(entries, error, acc, reduce_fun) do
    Enum.reduce(entries, acc, fn {pointer, _rest}, inner_acc ->
      reduce_fun.(pointer, error, inner_acc)
    end)
  end
end
