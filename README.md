# ExJSONPointer

[![hex.pm version](https://img.shields.io/hexpm/v/ex_json_pointer.svg?v=1)](https://hex.pm/packages/ex_json_pointer)

<!-- MDOC !-->

An Elixir implementation of [RFC 6901](https://www.rfc-editor.org/rfc/rfc6901.html) JSON Pointer for locating specific values within JSON documents, and also supports [Relative JSON Pointer](https://datatracker.ietf.org/doc/html/draft-bhutton-relative-json-pointer-00) of the JSON Schema Specification draft-2020-12.

## Usage

The JSON pointer string syntax can be represented as a JSON string:

```elixir
iex> ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => "hello"}}}, "/a/b/c")
{:ok, "hello"}

iex> ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => "hello"}}}, "/a/b")
{:ok, %{"c" => "hello"}}

iex> ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => [1, 2, 3]}}}, "/a/b/c")
{:ok, [1, 2, 3]}

iex> ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => [1, 2, 3]}}}, "/a/b/c/2")
{:ok, 3}

iex> ExJSONPointer.resolve(%{"a" => [%{"b" => %{"c" => [1, 2]}}, 2, 3]}, "/a/2")
{:ok, 3}

iex> ExJSONPointer.resolve(%{"a" => [%{"b" => %{"c" => [1, 2]}}, 2, 3]}, "/a/0/b/c/1")
{:ok, 2}
```

or a URI fragment identifier:

```elixir
iex> ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => "hello"}}}, "#/a/b/c")
{:ok, "hello"}

iex> ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => "hello"}}}, "#/a/b")
{:ok, %{"c" => "hello"}}

iex> ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => [1, 2, 3]}}}, "#/a/b/c")
{:ok, [1, 2, 3]}

iex> ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => [1, 2, 3]}}}, "#/a/b/c/2")
{:ok, 3}

iex> ExJSONPointer.resolve(%{"a" => [%{"b" => %{"c" => [1, 2]}}, 2, 3]}, "#/a/2")
{:ok, 3}

iex> ExJSONPointer.resolve(%{"a" => [%{"b" => %{"c" => [1, 2]}}, 2, 3]}, "#/a/0/b/c/1")
{:ok, 2}
```

If the existing JSON pointer points to a `nil` value, then it will return `{:ok, nil}` in this case.

```elixir
iex> ExJSONPointer.resolve(%{"a" => %{"b" => nil}}, "/a/b")
{:ok, nil}
```

Some cases that a JSON pointer that references a nonexistent value:

```elixir
iex> ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => "hello"}}}, "/a/b/d")
{:error, "not found"}

iex> ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => [1, 2, 3]}}}, "/a/b/c/4")
{:error, "not found"}

iex> ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => "hello"}}}, "#/a/b/d")
{:error, "not found"}

iex> ExJSONPointer.resolve(%{"a" => %{"b" => %{"c" => [1, 2, 3]}}}, "#/a/b/c/4")
{:error, "not found"}
```

Some cases that a JSON pointer has some empty reference tokens, and link a `$ref` [test case](https://github.com/json-schema-org/JSON-Schema-Test-Suite/blob/main/tests/draft2020-12/ref.json#L1023) from JSON Schema Test Suite(draft 2020-12) for reference.

```elixir
iex> ExJSONPointer.resolve(%{"" => %{"" => 1}}, "/")
{:ok, %{"" => 1}}

iex> ExJSONPointer.resolve(%{"" => %{"" => 1}}, "//")
{:ok, 1}

iex> ExJSONPointer.resolve(%{"" => %{"" => 1, "b" => %{"" => 2}}}, "//b")
{:ok, %{"" => 2}}

iex> ExJSONPointer.resolve(%{"" => %{"" => 1, "b" => %{"" => 2}}}, "//b/")
{:ok, 2}

iex> ExJSONPointer.resolve(%{"" => %{"" => 1, "b" => %{"" => 2}}}, "//b///")
{:error, "not found"}
```

Invalid JSON pointer syntax:

```elixir
iex> ExJSONPointer.resolve(%{"a" =>%{"b" => %{"c" => [1, 2, 3]}}}, "a/b")
{:error, "invalid JSON pointer syntax"}

iex> ExJSONPointer.resolve(%{"a" =>%{"b" => %{"c" => [1, 2, 3]}}}, "##/a")
{:error, "invalid JSON pointer syntax"}

```

## Relative JSON Pointer

This library also supports [Relative JSON Pointer](https://datatracker.ietf.org/doc/html/draft-bhutton-relative-json-pointer-00) of the JSON Schema Specification draft-2020-12 which allows you to reference values relative to a specific location within a JSON document.

A relative JSON pointer consists of:
- A non-negative integer (prefix) that indicates how many levels up to traverse
- An optional index manipulation (+N or -N) for array elements
- An optional JSON pointer to navigate from the referenced location

```elixir
# Sample data
iex> data = %{"foo" => ["bar", "baz"], "highly" => %{"nested" => %{"objects" => true}}}
iex> ExJSONPointer.resolve(data, "/foo/1", "0") # Get the current value (0 levels up)
{:ok, "baz"}
# Get the parent array and access its first element (1 level up, then to index 0)
iex> ExJSONPointer.resolve(data, "/foo/1", "1/0")
{:ok, "bar"}
# Get the previous element in the array (current level, index - 1)
iex> ExJSONPointer.resolve(data, "/foo/1", "0-1")
{:ok, "bar"}
# Go up to the root and access a nested property
iex> ExJSONPointer.resolve(data, "/foo/1", "2/highly/nested/objects")
{:ok, true}
# Get the index of the current element in its array
iex> ExJSONPointer.resolve(data, "/foo/1", "0#")
{:ok, 1}

# Get the key name of a property in an object
iex> data2 = %{"features" => [%{"name" => "environment friendly", "url" => "http://example.com"}]}
iex> ExJSONPointer.resolve(data2, "/features/0/url", "1/name")
{:ok, "environment friendly"}
iex> ExJSONPointer.resolve(data2, "/features/0/url", "2#")
{:ok, "features"}
```

Please see the test cases for more examples.
