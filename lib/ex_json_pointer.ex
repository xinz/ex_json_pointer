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
  Resolve the JSON document with the given JSON Pointer to find the accompanying value.

  The pointer can be either:
  - An empty string ("") or "#" to reference the whole document
  - A JSON String Representation starting with "/"
  - A URI Fragment Identifier Representation starting with "#"

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
  Resolve a relative JSON pointer from a starting position within a JSON document.

  This function implements the Relative JSON Pointer specification as described in
  [draft-bhutton-relative-json-pointer-00](https://datatracker.ietf.org/doc/html/draft-bhutton-relative-json-pointer-00).

  A relative JSON pointer consists of:
  - A non-negative integer (prefix) that indicates how many levels up to traverse
  - An optional index manipulation (+N or -N) for array elements
  - An optional JSON pointer to navigate from the referenced location

  ## Parameters
  - `document`: The JSON document to be processed
  - `start_json_pointer`: A JSON pointer that identifies the starting location within the document
  - `relative`: The relative JSON pointer to evaluate from the starting location

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
  Resolve a JSON pointer while accumulating state during traversal.

  This function allows you to track the traversal path and accumulate values as the JSON pointer
  is being resolved. It is designed to be useful for implementing operations that need context
  about the traversal path, such as relative JSON pointers.

  ## Parameters
  - `document`: The JSON document to be processed
  - `pointer`: A JSON pointer that identifies the location within the document
  - `acc`: An initial accumulator value that will be passed to the resolve function
  - `resolve_fun`: A function that receives the current value, reference token, and accumulated state
    and returns either `{:cont, {new_value, new_acc}}` to continue or `{:halt, result}` to stop traversal

  The `resolve_fun` receives three arguments:
  - The current value at the reference token
  - The current reference token being processed
  - A tuple containing the processing document and the current accumulator

  ## Examples

      iex> data = %{"a" => %{"b" => %{"c" => [10, 20, 30]}}}
      iex> init_acc = %{}
      iex> fun = fn current, ref_token, {_document, acc} ->
      ...>   {:cont, {current, Map.put(acc, ref_token, current)}}
      ...> end
      iex> {value, result} = ExJSONPointer.resolve_while(data, "/a/b/c/0", init_acc, fun)
      iex> value
      10
      iex> result["c"]
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
end
