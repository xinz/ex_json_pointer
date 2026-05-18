defmodule ExJSONPointer do
  @external_resource readme = Path.join([__DIR__, "../README.md"])
  @moduledoc File.read!(readme)
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  @typedoc """
  The JSON document to be processed, must be a map.
  """
  @type document :: map() | list()

  @typedoc """
  The JSON Pointer string that follows RFC 6901 specification.
  Can be either a JSON String Representation (starting with '/') or
  a URI Fragment Identifier Representation (starting with '#').
  """
  @type pointer :: String.t()

  @typedoc """
  The result of resolving a JSON Pointer:
  * `{:ok, term()}` - the resolved value on success
  * `{:error, String.t()}` - when there is an error in pointer syntax or value not found
  """
  @type result :: {:ok, term()} | {:error, String.t()}

  @typedoc """
  A reducer callback used by `batch_resolve_reduce/4`.

  It receives:
  1. The original JSON pointer string.
  2. The result produced for that pointer.
  3. The current accumulator.

  It must return the updated accumulator.
  """
  @type batch_reduce_fun(acc) :: (pointer, result, acc -> acc)

  @doc """
  Resolves a value from a JSON document using a JSON Pointer.

  Implements [RFC 6901](https://tools.ietf.org/html/rfc6901).

  The pointer can be either:
  - An empty string `""` or `"#"` to reference the whole document.
  - A JSON String Representation starting with `/`.
  - A URI Fragment Identifier Representation starting with `#`.

  ## Examples

      iex> doc = %{"foo" => %{"bar" => "baz"}}
      iex> ExJSONPointer.resolve(doc, "/foo/bar")
      {:ok, "baz"}
      iex> ExJSONPointer.resolve(doc, "/foo/baz")
      {:error, "not found"}
      iex> ExJSONPointer.resolve(doc, "##foo")
      {:error, "invalid JSON pointer syntax"}
  """
  @spec resolve(document, pointer) :: result
  defdelegate resolve(document, pointer), to: __MODULE__.RFC6901

  @doc """
  Resolves multiple JSON Pointers against a JSON document in a batch.

  This function is useful when you need to resolve a set of pointers against the
  same document and some of those pointers share common prefixes. In those cases,
  the implementation may reuse part of the traversal work instead of resolving
  every pointer fully and independently.

  The function uses an adaptive strategy internally:
  - for smaller batches, or for batches with enough shared leading tokens, it
    uses a grouped traversal strategy;
  - for sparse batches with little shared prefix overlap, it falls back to
    resolving each pointer individually.

  The returned value is always a map keyed by the original pointer strings, where
  each value is the same kind of result returned by `resolve/2`.

  ## Parameters

  - `document`: The JSON document to be processed.
  - `pointers`: A list of JSON pointer strings.

  ## Notes

  - An empty string `""` or `"#"` resolves to the whole document.
  - Invalid pointer syntax is reported per pointer as
    `{:error, "invalid JSON pointer syntax"}`.
  - Missing values are reported per pointer as `{:error, "not found"}`.
  - When duplicate pointers are given, the returned map contains a single entry
    for that pointer key, following normal map semantics.

  ## Examples

      iex> doc = %{"foo" => %{"bar" => "baz", "qux" => "corge"}}
      iex> ExJSONPointer.batch_resolve(doc, ["/foo/bar", "/foo/qux", "/foo/unknown"])
      %{
        "/foo/bar" => {:ok, "baz"},
        "/foo/qux" => {:ok, "corge"},
        "/foo/unknown" => {:error, "not found"}
      }

      iex> doc = %{"users" => %{"1" => %{"profile" => %{"name" => "alice", "email" => "alice@example.com"}}}}
      iex> ExJSONPointer.batch_resolve(doc, ["/users/1/profile/name", "/users/1/profile/email"])
      %{
        "/users/1/profile/name" => {:ok, "alice"},
        "/users/1/profile/email" => {:ok, "alice@example.com"}
      }

      iex> doc = %{"foo" => "bar"}
      iex> ExJSONPointer.batch_resolve(doc, ["", "#", "foo"])
      %{
        "" => {:ok, %{"foo" => "bar"}},
        "#" => {:ok, %{"foo" => "bar"}},
        "foo" => {:error, "invalid JSON pointer syntax"}
      }
  """
  @spec batch_resolve(document, [pointer]) :: %{pointer => result}
  defdelegate batch_resolve(document, pointers), to: __MODULE__.RFC6901

  @doc """
  Resolves multiple JSON Pointers against a JSON document and reduces the results
  with a callback.

  This function is useful when you want to process each batch result directly
  into a custom accumulator instead of always materializing the full
  `%{pointer => result}` map returned by `batch_resolve/2`.

  The reducer callback receives:
  1. The original pointer string.
  2. The result for that pointer.
  3. The current accumulator.

  It must return the updated accumulator.

  ## Parameters

  - `document`: The JSON document to be processed.
  - `pointers`: A list of JSON pointer strings.
  - `acc`: The initial accumulator.
  - `reduce_fun`: A reducer callback invoked for each pointer result.

  ## Examples

      iex> doc = %{"users" => %{"1" => %{"profile" => %{"name" => "alice", "email" => "alice@example.com"}}}}
      iex> ExJSONPointer.batch_resolve_reduce(
      ...>   doc,
      ...>   ["/users/1/profile/name", "/users/1/profile/email", "/users/2/profile/name"],
      ...>   %{},
      ...>   fn pointer, result, acc ->
      ...>     case result do
      ...>       {:ok, value} -> Map.put(acc, pointer, value)
      ...>       {:error, _reason} -> acc
      ...>     end
      ...>   end
      ...> )
      %{
        "/users/1/profile/name" => "alice",
        "/users/1/profile/email" => "alice@example.com"
      }

      iex> doc = %{"foo" => "bar"}
      iex> ExJSONPointer.batch_resolve_reduce(
      ...>   doc,
      ...>   ["", "#", "foo"],
      ...>   [],
      ...>   fn pointer, result, acc -> [{pointer, result} | acc] end
      ...> )
      ...> |> Enum.reverse()
      [
        {"", {:ok, %{"foo" => "bar"}}},
        {"#", {:ok, %{"foo" => "bar"}}},
        {"foo", {:error, "invalid JSON pointer syntax"}}
      ]
  """
  @spec batch_resolve_reduce(document, [pointer], acc, batch_reduce_fun(acc)) :: acc when acc: term()
  defdelegate batch_resolve_reduce(document, pointers, acc, reduce_fun), to: __MODULE__.RFC6901

  @doc """
  Resolves a relative JSON pointer starting from a specific location within a JSON document.

  Implements the Relative JSON Pointer specification (e.g. [draft-handrews-relative-json-pointer-01](https://tools.ietf.org/html/draft-handrews-relative-json-pointer-01)).

  A relative JSON pointer consists of:
  - A non-negative integer (prefix) indicating how many levels up to traverse.
  - An optional index manipulation (`+N` or `-N`) for array elements.
  - An optional JSON pointer to navigate downwards from the referenced location.
  - Or a `#` to retrieve the key/index of the current value.

  ## Parameters

  - `document`: The JSON document to be processed.
  - `start_json_pointer`: A JSON pointer that identifies the starting location within the document.
  - `relative`: The relative JSON pointer string to evaluate.

  ## Examples

      iex> data = %{"foo" => ["bar", "baz"], "highly" => %{"nested" => %{"objects" => true}}}
      iex> ExJSONPointer.resolve(data, "/foo/1", "0")
      {:ok, "baz"}
      iex> ExJSONPointer.resolve(data, "/foo/1", "1/0")
      {:ok, "bar"}
      iex> ExJSONPointer.resolve(data, "/foo/1", "0-1")
      {:ok, "bar"}
      iex> ExJSONPointer.resolve(data, "/foo/1", "2/highly/nested/objects")
      {:ok, true}
      iex> ExJSONPointer.resolve(data, "/foo/1", "0#")
      {:ok, 1}
  """
  @spec resolve(document, pointer, String.t()) :: result
  defdelegate resolve(document, start_json_pointer, relative), to: __MODULE__.Relative

  @doc """
  Traverses a JSON document using a JSON pointer, maintaining an accumulator.

  This function is similar to `Enum.reduce_while/3` but follows the path of a JSON Pointer.
  It allows tracking the traversal path and accumulating values as the pointer is resolved.
  This is useful for implementing operations that require context about the traversal path,
  such as Relative JSON Pointers.

  ## Parameters

  - `document`: The JSON document to be processed.
  - `pointer`: A JSON pointer string.
  - `acc`: An initial accumulator value.
  - `resolve_fun`: A callback function invoked for each segment of the pointer.

  ## The Callback Function

  The `resolve_fun` receives three arguments:
  1. The current value found at the reference token.
  2. The current reference token (key or index) being processed.
  3. A tuple `{current_document, accumulator}` containing the document context at the current level and the accumulator.

  It must return one of:
  - `{:cont, {new_value, new_acc}}`: Continues traversal with `new_value` as the context for the next token and `new_acc` as the updated accumulator.
  - `{:halt, result}`: Stops traversal immediately and returns `result`.

  ## Examples

      iex> data = %{"a" => %{"b" => %{"c" => [10, 20, 30]}}}
      iex> init_acc = %{}
      iex> fun = fn current, ref_token, {_document, acc} ->
      ...>   {:cont, {current, Map.put(acc, ref_token, current)}}
      ...> end
      iex> {value, acc} = ExJSONPointer.resolve_while(data, "/a/b/c/0", init_acc, fun)
      iex> value
      10
      iex> acc["c"]
      [10, 20, 30]
  """
  @spec resolve_while(document, pointer, acc, (term, String.t(), {document, acc} -> {:cont, {term, acc}} | {:halt, term})) :: {term, acc} | {:error, String.t()} when acc: term()
  defdelegate resolve_while(document, pointer, acc, resolve_fun), to: __MODULE__.RFC6901

  @doc """
  Decodes a JSON Pointer string into a tokenized path.

  This helper accepts both JSON Pointer surface syntaxes supported by the library:

  - the JSON string representation (`""`, `"/..."`)
  - the URI fragment identifier representation (`"#"`, `"#/..."`)

  Decoded reference tokens are always returned as strings.

  ## Examples

      iex> ExJSONPointer.decode_path("#/$defs/name")
      {:ok, ["$defs", "name"]}

      iex> ExJSONPointer.decode_path("/items/0")
      {:ok, ["items", "0"]}

      iex> ExJSONPointer.decode_path("#")
      {:ok, []}

      iex> ExJSONPointer.decode_path("foo")
      {:error, "invalid JSON pointer syntax"}
  """
  @spec decode_path(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  defdelegate decode_path(pointer), to: __MODULE__.RFC6901

  @doc """
  Encodes a tokenized path as a JSON Pointer string using the requested surface format.

  Supported formats are:

  - `"json_string"` - returns the JSON string representation such as `"/a/b"`
  - `"uri_fragment"` - returns the URI fragment identifier representation such as `"#/a/b"`

  The `opts` argument defaults to `[format: "json_string"]`.

  ## Examples
      iex> ExJSONPointer.encode_path(["$defs", "name"])
      "/$defs/name"

      iex> ExJSONPointer.encode_path(["$defs", "name"], format: "json_string")
      "/$defs/name"

      iex> ExJSONPointer.encode_path(["$defs", "name"], format: "uri_fragment")
      "#/$defs/name"

      iex> ExJSONPointer.encode_path(["a b", "c%d"], format: "uri_fragment")
      "#/a%20b/c%25d"

      iex> ExJSONPointer.encode_path([], format: "uri_fragment")
      "#"
  """
  @spec encode_path([String.t() | integer()], keyword()) :: String.t()
  def encode_path(tokens, opts \\ [format: "json_string"]) do
    __MODULE__.RFC6901.encode_path(tokens, opts)
  end

  @doc """
  Validates if the given string follows the JSON Pointer format (RFC 6901, section 5).

  According to JSON Schema specification (draft 2020-12), the `json-pointer` format
  expects the string to be a valid JSON String Representation of a JSON Pointer.
  This means it must either be an empty string or start with a slash `/`. URI Fragment
  Identifier Representations (starting with `#`) are not considered valid
  for this format check.

  It also validates that tilde `~` characters are properly escaped as `~0` (for `~`)
  or `~1` (for `/`).

  ## Examples

      iex> ExJSONPointer.valid_json_pointer?("/foo/bar")
      true

      iex> ExJSONPointer.valid_json_pointer?("/foo/bar~0/baz~1/%a")
      true

      iex> ExJSONPointer.valid_json_pointer?("")
      true

      iex> ExJSONPointer.valid_json_pointer?("/")
      true

      iex> ExJSONPointer.valid_json_pointer?("/foo//bar")
      true

      iex> ExJSONPointer.valid_json_pointer?("/~1.1")
      true

      iex> ExJSONPointer.valid_json_pointer?("/foo/bar~")
      false

      iex> ExJSONPointer.valid_json_pointer?("/~2")
      false

      iex> ExJSONPointer.valid_json_pointer?("#")
      false

      iex> ExJSONPointer.valid_json_pointer?("some/path")
      false
  """
  @spec valid_json_pointer?(pointer) :: boolean()
  defdelegate valid_json_pointer?(pointer), to: __MODULE__.RFC6901

  @doc """
  Validates if the given string follows the Relative JSON Pointer format.

  This implements the validation for the `relative-json-pointer` format from JSON Schema.
  A relative JSON pointer consists of:
  - A non-negative integer prefix (0, 1, 2...)
  - An optional index manipulation (+/- and integer) (e.g., +1, -1)
  - Followed by either:
    - A hash character `#`
    - A JSON Pointer (starting with `/` or empty)

  ## Examples

      iex> ExJSONPointer.valid_relative_json_pointer?("1")
      true

      iex> ExJSONPointer.valid_relative_json_pointer?("0/foo/bar")
      true

      iex> ExJSONPointer.valid_relative_json_pointer?("0#")
      true

      iex> ExJSONPointer.valid_relative_json_pointer?("/foo/bar")
      false
  """
  @spec valid_relative_json_pointer?(String.t()) :: boolean()
  defdelegate valid_relative_json_pointer?(pointer), to: __MODULE__.Relative
end
