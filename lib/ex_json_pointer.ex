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
