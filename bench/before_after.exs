Code.require_file("bench_support.exs", __DIR__)

alias ExJSONPointer.BenchSupport

# Run `mix run before_after.exs` for a smoke comparison or set
# `BENCHMARK_PROFILE=full` for longer measurements.
#
# The frozen baseline changes only the module namespace. Loading it directly
# keeps the comparison independent from Git history and runtime source rewriting.
Code.require_file("e5567ca/lib/ex_json_pointer/rfc6901.ex", __DIR__)
Code.require_file("e5567ca/lib/ex_json_pointer/relative.ex", __DIR__)
Code.require_file("e5567ca/lib/ex_json_pointer.ex", __DIR__)

IO.puts("Loaded frozen before implementation from bench/e5567ca")

run_suite = fn suite_name, jobs, inputs, expected ->
  BenchSupport.assert_jobs!(suite_name, jobs, inputs, expected)
  Benchee.run(jobs, BenchSupport.options(inputs))
end

single_document = %{
  "users" => [
    %{"profile" => %{"name" => "alice", "email" => "alice@example.com"}},
    %{"profile" => %{"name" => "bob", "email" => "bob@example.com"}}
  ],
  "a/b" => %{"m~n" => 42}
}

single_pointers =
  Enum.flat_map(1..100, fn _iteration ->
    [
      "/users/0/profile/name",
      "#/users/1/profile/email",
      "/a~1b/m~0n",
      "/users/not-an-index",
      "/users/9/profile/name"
    ]
  end)

single_jobs = %{
  "before resolve/2" => fn {document, pointers} ->
    Enum.map(pointers, &ExJSONPointerBefore.resolve(document, &1))
  end,
  "updated resolve/2" => fn {document, pointers} ->
    Enum.map(pointers, &ExJSONPointer.resolve(document, &1))
  end
}

single_inputs = %{"500 successful and failing pointers" => {single_document, single_pointers}}

single_expected = fn _job_name, {document, pointers} ->
  Enum.map(pointers, &ExJSONPointer.resolve(document, &1))
end

run_suite.("before/after single resolution", single_jobs, single_inputs, single_expected)

array_document = %{
  "items" => Enum.map(0..9_999, fn index -> %{"value" => index, "even" => rem(index, 2) == 0} end)
}

array_pointers =
  Enum.map(0..499, fn index -> "/items/" <> Integer.to_string(index * 20) <> "/value" end)

shared_document = %{
  "users" =>
    Enum.into(1..100, %{}, fn index ->
      key = Integer.to_string(index)
      {key, %{"profile" => %{"name" => "user_" <> key, "active" => true}}}
    end)
}

shared_pointers =
  Enum.flat_map(1..100, fn index ->
    key = Integer.to_string(index)
    ["/users/" <> key <> "/profile/name", "/users/" <> key <> "/profile/active"]
  end)

scattered_document =
  Enum.into(1..200, %{}, fn index ->
    key = Integer.to_string(index)
    {"key_" <> key, %{"value" => index}}
  end)

scattered_pointers =
  Enum.map(1..200, fn index -> "/key_" <> Integer.to_string(index) <> "/value" end)

batch_jobs = %{
  "before batch_resolve/2" => fn {document, pointers} ->
    ExJSONPointerBefore.batch_resolve(document, pointers)
  end,
  "updated batch_resolve/2" => fn {document, pointers} ->
    ExJSONPointer.batch_resolve(document, pointers)
  end
}

batch_inputs = %{
  "500 high sibling array indexes" => {array_document, array_pointers},
  "200 shared map prefixes" => {shared_document, shared_pointers},
  "200 scattered map prefixes" => {scattered_document, scattered_pointers}
}

batch_expected = fn _job_name, {document, pointers} ->
  ExJSONPointer.batch_resolve(document, pointers)
end

run_suite.("before/after batch resolution", batch_jobs, batch_inputs, batch_expected)

relative_document = %{
  "name" => "some product",
  "price" => 10.5,
  "features" => [
    "easy to use",
    %{"name" => "environment friendly", "url" => "https://example.com"}
  ]
}

relative_pointers =
  Enum.flat_map(1..50, fn _iteration ->
    ["0", "0#", "1#", "1/name", "2#", "2/0", "1-1", "3/price"]
  end)

relative_jobs = %{
  "before relative resolve/3" => fn {document, start_pointer, pointers} ->
    Enum.map(pointers, &ExJSONPointerBefore.resolve(document, start_pointer, &1))
  end,
  "updated relative resolve/3" => fn {document, start_pointer, pointers} ->
    Enum.map(pointers, &ExJSONPointer.resolve(document, start_pointer, &1))
  end
}

relative_inputs = %{
  "400 relative resolutions" => {relative_document, "/features/1/url", relative_pointers}
}

relative_expected = fn _job_name, {document, start_pointer, pointers} ->
  Enum.map(pointers, &ExJSONPointer.resolve(document, start_pointer, &1))
end

run_suite.("before/after relative resolution", relative_jobs, relative_inputs, relative_expected)

path_tokens =
  Enum.flat_map(1..50, fn _iteration ->
    [
      ["users", "0", "profile", "name"],
      ["a/b", "c~d", ""],
      ["a b", "c%d", "雪", 42]
    ]
  end)

codec_job = fn implementation, paths ->
  Enum.map(paths, fn tokens ->
    json_pointer = implementation.encode_path(tokens, format: "json_string")
    uri_pointer = implementation.encode_path(tokens, format: "uri_fragment")

    {
      json_pointer,
      uri_pointer,
      implementation.decode_path(json_pointer),
      implementation.decode_path(uri_pointer),
      implementation.valid_json_pointer?(json_pointer)
    }
  end)
end

codec_jobs = %{
  "before path codec" => fn paths -> codec_job.(ExJSONPointerBefore, paths) end,
  "updated path codec" => fn paths -> codec_job.(ExJSONPointer, paths) end
}

codec_inputs = %{"150 mixed paths" => path_tokens}
codec_expected = fn _job_name, paths -> codec_job.(ExJSONPointer, paths) end

run_suite.("before/after path codec", codec_jobs, codec_inputs, codec_expected)

compiled_source = "#/users/1/profile/email"
{:ok, compiled_pointer} = ExJSONPointer.compile(compiled_source)
compiled_documents = List.duplicate(single_document, 500)

compiled_jobs = %{
  "before resolve/2 reparses pointer" => fn {documents, source, _compiled} ->
    Enum.map(documents, &ExJSONPointerBefore.resolve(&1, source))
  end,
  "updated resolve_compiled/2 reuses tokens" => fn {documents, _source, compiled} ->
    Enum.map(documents, &ExJSONPointer.resolve_compiled(&1, compiled))
  end
}

compiled_inputs = %{
  "500 repeated resolutions" => {compiled_documents, compiled_source, compiled_pointer}
}

compiled_expected = fn _job_name, {documents, _source, _compiled} ->
  List.duplicate({:ok, "bob@example.com"}, length(documents))
end

run_suite.("before/after compiled pointer reuse", compiled_jobs, compiled_inputs, compiled_expected)
