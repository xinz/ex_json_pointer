defmodule ExJSONPointer.Relative do
  @moduledoc false

  @error_not_found {:error, "not found"}
  @error_syntax {:error, "invalid relative JSON pointer syntax"}

  def valid_relative_json_pointer?(pointer) do
    case parse_relative_json_pointer(pointer) do
      {:ok, {_prefix, _index_delta, {:pointer, json_pointer}}} ->
        ExJSONPointer.RFC6901.valid_json_pointer?(json_pointer)

      {:ok, _parsed} ->
        true

      {:error, _} ->
        false
    end
  end

  def resolve(_docoument, "", _relative) do
    # Refer https://datatracker.ietf.org/doc/html/draft-bhutton-relative-json-pointer-00#section-4
    # If the current referenced value is the root of the document, then evaluation fails.
    @error_not_found
  end

  def resolve(document, start_json_pointer, relative_pointer) do
    case parse_relative_json_pointer(relative_pointer) do
      {:ok, {prefix, _index_delta, _suffix} = relative} ->
        document
        |> ExJSONPointer.RFC6901.relative_context(start_json_pointer, prefix)
        |> resolve_from_context(relative)

      {:error, _} = relative_error ->
        preserve_start_error_precedence(document, start_json_pointer, relative_error)
    end
  end

  defp preserve_start_error_precedence(document, start_json_pointer, relative_error) do
    case ExJSONPointer.RFC6901.relative_context(document, start_json_pointer, 0) do
      {:error, _} = start_error -> start_error
      {:ok, _start, _target, _parent} -> relative_error
    end
  end

  defp parse_relative_json_pointer(pointer) do
    relative_json_pointer_regex = ~r/^(0|[1-9][0-9]*)([+-](?:0|[1-9][0-9]*))?(?:(\/(?:[^#].*)?)|(#))?$/
    case Regex.run(relative_json_pointer_regex, pointer, capture: :all_but_first) do
      nil ->
        @error_syntax

      captures ->
        [prefix, index_manipulation, json_pointer, hash_ending] =
          captures ++ List.duplicate("", 4 - length(captures))

        {:ok,
         {String.to_integer(prefix), parse_index_delta(index_manipulation),
          parse_suffix(json_pointer, hash_ending)}}
    end
  end

  defp parse_index_delta(""), do: nil
  defp parse_index_delta(index_manipulation), do: String.to_integer(index_manipulation)

  defp parse_suffix(_json_pointer, "#"), do: :hash
  defp parse_suffix("", _hash_ending), do: :value
  defp parse_suffix(json_pointer, _hash_ending), do: {:pointer, json_pointer}

  defp resolve_from_context({:error, _} = error, _relative), do: error

  defp resolve_from_context({:ok, _start, target, parent}, {_prefix, nil, suffix}) do
    resolve_target(target, parent, suffix)
  end

  defp resolve_from_context({:ok, _start, _target, parent}, {_prefix, index_delta, suffix}) do
    resolve_adjusted_target(parent, index_delta, suffix)
  end

  defp resolve_target({:ok, value}, _parent, :value), do: {:ok, value}

  defp resolve_target({:ok, value}, _parent, {:pointer, pointer}) do
    resolve_down(value, pointer)
  end

  defp resolve_target(_target, {:ok, parent, ref_token}, :hash) when is_list(parent) do
    parse_index(ref_token)
  end

  defp resolve_target(_target, {:ok, _parent, ref_token}, :hash), do: {:ok, ref_token}
  defp resolve_target(_target, _parent, _suffix), do: @error_not_found

  defp resolve_adjusted_target({:ok, parent, ref_token}, index_delta, suffix)
       when is_list(parent) do
    with {:ok, current_index} <- parse_index(ref_token),
         adjusted_index when adjusted_index >= 0 <- current_index + index_delta,
         {:ok, value} <- Enum.fetch(parent, adjusted_index) do
      resolve_adjusted_value(value, adjusted_index, suffix)
    else
      adjusted_index when is_integer(adjusted_index) and adjusted_index < 0 -> @error_syntax
      :error -> @error_not_found
      {:error, _} = error -> error
    end
  end

  defp resolve_adjusted_target(_parent, _index_delta, _suffix), do: @error_syntax

  defp resolve_adjusted_value(_value, adjusted_index, :hash), do: {:ok, adjusted_index}
  defp resolve_adjusted_value(value, _adjusted_index, :value), do: {:ok, value}

  defp resolve_adjusted_value(value, _adjusted_index, {:pointer, pointer}) do
    resolve_down(value, pointer)
  end

  defp resolve_down(value, pointer) when is_map(value) or is_list(value) do
    ExJSONPointer.RFC6901.resolve(value, pointer)
  end

  defp resolve_down(_value, _pointer), do: @error_not_found

  defp parse_index(token) do
    case Integer.parse(token) do
      {index, ""} -> {:ok, index}
      _ -> @error_syntax
    end
  end
end
