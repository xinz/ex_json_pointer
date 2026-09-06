defmodule ExJSONPointer.RFC6901 do
  @moduledoc false

  alias ExJSONPointer.{BatchResolver, Compiled}

  @error_not_found {:error, "not found"}
  @error_invalid_syntax {:error, "invalid JSON pointer syntax"}

  def resolve(document, ""), do: {:ok, document}
  def resolve(document, "#"), do: {:ok, document}

  def resolve(document, pointer)
      when is_map(document) and is_binary(pointer)
      when is_list(document) and is_binary(pointer) do
    do_resolve(document, pointer)
  end

  def compile(pointer) when is_binary(pointer) do
    case split_json_pointer(pointer) do
      {:error, _} = error -> error
      tokens -> {:ok, %Compiled{tokens: tokens}}
    end
  end

  def compile(_pointer), do: @error_invalid_syntax

  def resolve_compiled(document, %Compiled{tokens: []}), do: {:ok, document}

  def resolve_compiled(document, %Compiled{tokens: tokens})
      when is_map(document) or is_list(document) do
    process(document, tokens)
  end

  def relative_context(document, pointer, prefix)
      when (is_map(document) or is_list(document)) and is_binary(pointer) and
             is_integer(prefix) and prefix >= 0 do
    case split_json_pointer(pointer) do
      {:error, _} = error ->
        error

      tokens ->
        target_depth = length(tokens) - prefix
        resolve_relative_context(document, tokens, 0, target_depth, :error, :error)
    end
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

  def encode_path(tokens, opts \\ [format: "json_string"])

  def encode_path([], opts) do
    do_encode_path([], Keyword.get(opts, :format))
  end

  def encode_path(tokens, opts) when is_list(tokens) and is_list(opts) do
    tokens
    |> Enum.map(&escape_token/1)
    |> do_encode_path(Keyword.get(opts, :format))
  end

  defp do_encode_path(tokens, "json_string") do
    encode_json_string_path(tokens)
  end
  defp do_encode_path(tokens, "uri_fragment") do
    encode_uri_fragment_path(tokens)
  end
  defp do_encode_path(_tokens, format) do
    raise ArgumentError,
      "expected :format to be \"json_string\" or \"uri_fragment\", got: #{inspect(format)}"
  end

  def valid_json_pointer?(""), do: true
  def valid_json_pointer?("/"), do: true
  def valid_json_pointer?("/" <> _ = pointer) do
    not Regex.match?(~r/~[^01]|~$/, pointer)
  end
  def valid_json_pointer?(_), do: false

  defdelegate batch_resolve(document, pointers), to: BatchResolver, as: :resolve

  defdelegate batch_resolve_reduce(document, pointers, acc, reduce_fun),
    to: BatchResolver,
    as: :reduce

  defp unescape(pointer) do
    case :binary.match(pointer, "~") do
      :nomatch ->
        pointer

      {_position, 1} ->
        pointer
        |> String.replace("~1", "/")
        |> String.replace("~0", "~")
    end
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

  defp encode_json_string_path([]), do: ""
  defp encode_json_string_path(escaped_tokens), do: "/" <> Enum.join(escaped_tokens, "/")

  defp encode_uri_fragment_path([]), do: "#"

  defp encode_uri_fragment_path(escaped_tokens) do
    encoded_tokens = Enum.map(escaped_tokens, &encode_uri_fragment_token/1)
    "#/" <> Enum.join(encoded_tokens, "/")
  end

  defp encode_uri_fragment_token(token) do
    URI.encode(token, &uri_fragment_char_unescaped?/1)
  end

  defp uri_fragment_char_unescaped?(?#), do: false
  defp uri_fragment_char_unescaped?(char), do: URI.char_unescaped?(char)

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

  @doc false
  def process(value, []), do: {:ok, value}

  def process(document, [ref_token]) when is_list(document) or is_map(document) do
    value_to_token(document, ref_token)
  end

  def process(document, [ref_token | rest]) when is_map(document) do
    key = unescape(ref_token)

    case document do
      %{^key => value} -> process(value, rest)
      %{} -> @error_not_found
    end
  end

  def process(document, [ref_token | rest]) when is_list(document) do
    case parse_index(ref_token) do
      {:ok, index} when index >= 0 -> process_list_index(document, index, rest)
      {:ok, index} -> process_negative_list_index(document, index, rest)
      :error -> @error_not_found
    end
  end

  def process(_value, _ref_tokens), do: @error_not_found

  defp process_list_index([value | _rest], 0, ref_tokens), do: process(value, ref_tokens)

  defp process_list_index([_value | rest], index, ref_tokens) do
    process_list_index(rest, index - 1, ref_tokens)
  end

  defp process_list_index([], _index, _ref_tokens), do: @error_not_found

  defp process_negative_list_index(document, index, ref_tokens) do
    case Enum.fetch(document, index) do
      {:ok, value} -> process(value, ref_tokens)
      :error -> @error_not_found
    end
  end

  @doc false
  def value_to_token(document, "") when is_map(document), do: find_value_by_token(document, "")

  def value_to_token(document, token) when is_map(document) do
    if :binary.last(token) == ?# do
      token = binary_part(token, 0, byte_size(token) - 1)
      find_value_by_token(document, token, true)
    else
      find_value_by_token(document, token)
    end
  end

  def value_to_token(document, "") when is_list(document), do: find_value_by_index(document, "")

  def value_to_token(document, token) when is_list(document) do
    if :binary.last(token) == ?# do
      token = binary_part(token, 0, byte_size(token) - 1)
      find_value_by_index(document, token, true)
    else
      find_value_by_index(document, token)
    end
  end

  def value_to_token(_, _), do: @error_not_found

  @doc false
  def fetch_child(document, token) when is_map(document) do
    case Map.fetch(document, unescape(token)) do
      {:ok, value} -> {:ok, value}
      :error -> @error_not_found
    end
  end

  def fetch_child(document, token) when is_list(document) do
    with {:ok, index} <- parse_index(token),
         {:ok, value} <- Enum.fetch(document, index) do
      {:ok, value}
    else
      _ -> @error_not_found
    end
  end

  def fetch_child(_document, _token), do: @error_not_found

  defp parse_index(token) do
    case Integer.parse(token) do
      {index, ""} -> {:ok, index}
      _ -> :error
    end
  end

  defp find_value_by_index(document, token, return_index \\ false) do
    with {:ok, index} <- parse_index(token),
         {:ok, value} <- Enum.fetch(document, index) do
      if return_index, do: {:ok, index}, else: {:ok, value}
    else
      _ -> @error_not_found
    end
  end

  defp find_value_by_token(document, token, return_token \\ false) do
    case Map.fetch(document, unescape(token)) do
      {:ok, _value} when return_token -> {:ok, token}
      {:ok, value} -> {:ok, value}
      :error -> @error_not_found
    end
  end

  defp resolve_relative_context(value, [], depth, target_depth, target, parent) do
    target = capture_relative_target(target, value, depth, target_depth)
    {:ok, value, target, parent}
  end

  defp resolve_relative_context(value, [token | rest], depth, target_depth, target, parent) do
    target = capture_relative_target(target, value, depth, target_depth)

    parent =
      if depth == target_depth - 1 do
        {:ok, value, token}
      else
        parent
      end

    case fetch_child(value, token) do
      {:ok, child} ->
        resolve_relative_context(child, rest, depth + 1, target_depth, target, parent)

      {:error, _} = error ->
        error
    end
  end

  defp capture_relative_target(_target, value, depth, depth), do: {:ok, value}
  defp capture_relative_target(target, _value, _depth, _target_depth), do: target

  def resolve_while(document, pointer, acc, resolve_fun)
      when is_map(document) and is_binary(pointer)
      when is_list(document) and is_binary(pointer) do
    case split_json_pointer(pointer) do
      [] ->
        {document, acc}

      ref_tokens when is_list(ref_tokens) ->
        Enum.reduce_while(ref_tokens, {document, acc}, fn ref_token, {doc, acc} ->
          case fetch_child(doc, ref_token) do
            {:ok, value} -> resolve_fun.(value, ref_token, {doc, acc})
            {:error, _} = error -> {:halt, error}
          end
        end)

      {:error, _} = error ->
        error
    end
  end

  @doc false
  def split_json_pointer(pointer, opts \\ [])
  def split_json_pointer("", _opts), do: []
  def split_json_pointer("#", _opts), do: []
  def split_json_pointer("/" <> _ = pointer, opts) do
    pointer |> String.split("/", opts) |> remove_first_item_if_empty_str()
  end
  def split_json_pointer("#/" <> _ = pointer, opts) do
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
  def split_json_pointer(_pointer, _opts), do: @error_invalid_syntax

  defp remove_first_item_if_empty_str(["" | ref_tokens]), do: ref_tokens
  defp remove_first_item_if_empty_str(ref_tokens), do: ref_tokens
end
