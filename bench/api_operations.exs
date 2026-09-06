Code.require_file("bench_support.exs", __DIR__)

alias ExJSONPointer.BenchSupport

compiled_document = %{
  "users" => [%{"profile" => %{"name" => "alice", "active" => true}}]
}

compiled_pointer_source = "#/users/0/profile/name"
{:ok, compiled_pointer} = ExJSONPointer.compile(compiled_pointer_source)
compiled_documents = List.duplicate(compiled_document, 200)

compiled_jobs = %{
  "resolve/2 reparses pointer" => fn {documents, pointer, _compiled} ->
    Enum.map(documents, &ExJSONPointer.resolve(&1, pointer))
  end,
  "resolve_compiled/2 reuses tokens" => fn {documents, _pointer, compiled} ->
    Enum.map(documents, &ExJSONPointer.resolve_compiled(&1, compiled))
  end
}

compiled_inputs = %{
  "200 repeated resolutions" => {compiled_documents, compiled_pointer_source, compiled_pointer}
}

compiled_expected = fn _job_name, {documents, _pointer, _compiled} ->
  List.duplicate({:ok, "alice"}, length(documents))
end

BenchSupport.assert_jobs!("compiled pointers", compiled_jobs, compiled_inputs, compiled_expected)
Benchee.run(compiled_jobs, BenchSupport.options(compiled_inputs))

relative_document = %{
  "users" => [
    %{"name" => "alice", "tags" => ["admin", "ops"]},
    %{"name" => "bob", "tags" => ["reader"]},
    %{"name" => "carol", "tags" => ["editor", "author"]}
  ],
  "meta" => %{"count" => 3}
}

relative_cases = [
  {"0", {:ok, "author"}},
  {"0#", {:ok, 1}},
  {"1#", {:ok, "tags"}},
  {"2/name", {:ok, "carol"}},
  {"3/0/name", {:ok, "alice"}},
  {"4/meta/count", {:ok, 3}},
  {"2/missing", {:error, "not found"}}
]

relative_jobs = %{
  "resolve/3 relative pointers" => fn {document, start_pointer, cases} ->
    Enum.map(cases, fn {relative_pointer, _expected} ->
      ExJSONPointer.resolve(document, start_pointer, relative_pointer)
    end)
  end
}

relative_inputs = %{
  "array and map ancestry" => {relative_document, "/users/2/tags/1", relative_cases}
}

relative_expected = fn _job_name, {_document, _start_pointer, cases} ->
  Enum.map(cases, fn {_relative_pointer, expected} -> expected end)
end

BenchSupport.assert_jobs!("relative pointers", relative_jobs, relative_inputs, relative_expected)
Benchee.run(relative_jobs, BenchSupport.options(relative_inputs))

path_cases = [
  {[], "", "#"},
  {["users", "0", "name"], "/users/0/name", "#/users/0/name"},
  {["a/b", "c~d", ""], "/a~1b/c~0d/", "#/a~1b/c~0d/"},
  {["a b", "c%d", "k\"l"], "/a b/c%d/k\"l", "#/a%20b/c%25d/k%22l"},
  {["unicode", "雪", 42], "/unicode/雪/42", "#/unicode/%E9%9B%AA/42"}
]

encode_cases = path_cases |> List.duplicate(20) |> List.flatten()

encode_jobs = %{
  "encode_path/2 JSON string" => fn cases ->
    Enum.map(cases, fn {tokens, _json_pointer, _uri_pointer} ->
      ExJSONPointer.encode_path(tokens, format: "json_string")
    end)
  end,
  "encode_path/2 URI fragment" => fn cases ->
    Enum.map(cases, fn {tokens, _json_pointer, _uri_pointer} ->
      ExJSONPointer.encode_path(tokens, format: "uri_fragment")
    end)
  end
}

encode_inputs = %{"100 mixed paths" => encode_cases}

encode_expected = fn
  "encode_path/2 JSON string", cases ->
    Enum.map(cases, fn {_tokens, json_pointer, _uri_pointer} -> json_pointer end)

  "encode_path/2 URI fragment", cases ->
    Enum.map(cases, fn {_tokens, _json_pointer, uri_pointer} -> uri_pointer end)
end

BenchSupport.assert_jobs!("path encoding", encode_jobs, encode_inputs, encode_expected)
Benchee.run(encode_jobs, BenchSupport.options(encode_inputs))

decode_cases =
  Enum.flat_map(encode_cases, fn {tokens, json_pointer, uri_pointer} ->
    [{json_pointer, {:ok, Enum.map(tokens, &to_string/1)}}, {uri_pointer, {:ok, Enum.map(tokens, &to_string/1)}}]
  end)

decode_jobs = %{
  "decode_path/1" => fn cases ->
    Enum.map(cases, fn {pointer, _expected} -> ExJSONPointer.decode_path(pointer) end)
  end
}

decode_inputs = %{"200 JSON string and URI paths" => decode_cases}

decode_expected = fn _job_name, cases ->
  Enum.map(cases, fn {_pointer, expected} -> expected end)
end

BenchSupport.assert_jobs!("path decoding", decode_jobs, decode_inputs, decode_expected)
Benchee.run(decode_jobs, BenchSupport.options(decode_inputs))

json_validation_cases = [
  {"", true},
  {"/users/0/name", true},
  {"/a~1b/c~0d", true},
  {"/empty//token", true},
  {"#", false},
  {"users/0/name", false},
  {"/bad~escape", false},
  {"/~2", false}
]

relative_validation_cases = [
  {"0", true},
  {"0#", true},
  {"1/users/0", true},
  {"2-1/name", true},
  {"/users/0", false},
  {"01/name", false},
  {"-1/name", false},
  {"0##", false}
]

validation_jobs = %{
  "JSON and relative pointer validation" => fn {json_cases, relative_cases_for_validation} ->
    {
      Enum.map(json_cases, fn {pointer, _expected} ->
        ExJSONPointer.valid_json_pointer?(pointer)
      end),
      Enum.map(relative_cases_for_validation, fn {pointer, _expected} ->
        ExJSONPointer.valid_relative_json_pointer?(pointer)
      end)
    }
  end
}

validation_inputs = %{
  "mixed valid and invalid pointers" => {json_validation_cases, relative_validation_cases}
}

validation_expected = fn _job_name, {json_cases, relative_cases_for_validation} ->
  {
    Enum.map(json_cases, fn {_pointer, expected} -> expected end),
    Enum.map(relative_cases_for_validation, fn {_pointer, expected} -> expected end)
  }
end

BenchSupport.assert_jobs!("pointer validation", validation_jobs, validation_inputs, validation_expected)
Benchee.run(validation_jobs, BenchSupport.options(validation_inputs))

resolve_while_cases = [
  {"/users/2/tags/1", {"author", {4, ["1", "tags", "2", "users"]}}},
  {"/users/0/name", {"alice", {3, ["name", "0", "users"]}}},
  {"/meta/count", {3, {2, ["count", "meta"]}}},
  {"/users/9/name", {:error, "not found"}},
  {"", {relative_document, {0, []}}}
]

resolve_while_handler = fn current, ref_token, {_document, {count, tokens}} ->
  {:cont, {current, {count + 1, [ref_token | tokens]}}}
end

resolve_while_jobs = %{
  "resolve_while/4 with traversal accumulator" => fn {document, cases} ->
    Enum.map(cases, fn {pointer, _expected} ->
      ExJSONPointer.resolve_while(document, pointer, {0, []}, resolve_while_handler)
    end)
  end
}

resolve_while_inputs = %{
  "successful, missing, and root paths" => {relative_document, resolve_while_cases}
}

resolve_while_expected = fn _job_name, {_document, cases} ->
  Enum.map(cases, fn {_pointer, expected} -> expected end)
end

BenchSupport.assert_jobs!("resolve_while", resolve_while_jobs, resolve_while_inputs, resolve_while_expected)
Benchee.run(resolve_while_jobs, BenchSupport.options(resolve_while_inputs))
