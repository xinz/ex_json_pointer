Code.require_file("bench_support.exs", __DIR__)

alias ExJSONPointer.BenchSupport

small_doc = %{
  "a" => %{
    "b" => %{
      "c" => [1, 2, %{"d" => "target1"}],
      "e" => "target2"
    },
    "f" => [10, 20, 30, 40]
  },
  "x" => %{"y" => %{"z" => "target3"}}
}

large_doc =
  Enum.into(1..1_000, %{}, fn i ->
    {
      "key_#{i}",
      %{"nested_1" => %{"nested_2" => [i, i * 2, %{"target" => "val_#{i}"}]}}
    }
  end)

shared_prefix_doc = %{
  "users" =>
    Enum.into(1..100, %{}, fn i ->
      {
        Integer.to_string(i),
        %{
          "profile" => %{
            "name" => "user_#{i}",
            "email" => "user_#{i}@example.com"
          },
          "settings" => %{"theme" => if(rem(i, 2) == 0, do: "dark", else: "light")},
          "posts" => %{"0" => %{"title" => "title_#{i}"}}
        }
      }
    end)
}

array_doc = %{
  "items" =>
    Enum.map(0..4_095, fn i ->
      %{"id" => i, "value" => "value_#{i}"}
    end)
}

pointers_small = [
  "/a/b/c/2/d",
  "/a/b/e",
  "/a/f/2",
  "/x/y/z",
  "/not/found/path"
]

pointers_large =
  Enum.map(1..100, fn i ->
    "/key_#{i}/nested_1/nested_2/2/target"
  end) ++ ["/key_999/not/found"]

pointers_shared_prefix =
  Enum.flat_map(1..25, fn i ->
    user = Integer.to_string(i)

    [
      "/users/#{user}/profile/name",
      "/users/#{user}/profile/email",
      "/users/#{user}/settings/theme",
      "/users/#{user}/posts/0/title"
    ]
  end) ++ ["/users/999/profile/name", "/users/1/profile/name", "/users/1/profile/name"]

pointers_sibling_array =
  Enum.map(4_064..4_095, fn index -> "/items/#{index}/value" end) ++
    ["/items/4095/value", "/items/4096/value"]

normalize_result = fn
  value when is_binary(value) -> String.upcase(value)
  value when is_integer(value) -> value * 2
  value -> value
end

reduce_result = fn pointer, result, acc ->
  normalized =
    case result do
      {:ok, value} -> {:ok, normalize_result.(value)}
      {:error, reason} -> {:error, reason}
    end

  %{
    count: acc.count + 1,
    results: Map.put(acc.results, pointer, normalized)
  }
end

initial_acc = %{count: 0, results: %{}}

jobs = %{
  "direct resolve/2 then reduction" => fn {document, pointers} ->
    Enum.reduce(pointers, initial_acc, fn pointer, acc ->
      reduce_result.(pointer, ExJSONPointer.resolve(document, pointer), acc)
    end)
  end,
  "batch_resolve/2 then reduction" => fn {document, pointers} ->
    resolved = ExJSONPointer.batch_resolve(document, pointers)

    Enum.reduce(pointers, initial_acc, fn pointer, acc ->
      reduce_result.(pointer, Map.fetch!(resolved, pointer), acc)
    end)
  end,
  "batch_resolve_reduce/4" => fn {document, pointers} ->
    ExJSONPointer.batch_resolve_reduce(document, pointers, initial_acc, reduce_result)
  end
}

inputs = %{
  "small document / few pointers" => {small_doc, pointers_small},
  "large document / scattered pointers" => {large_doc, pointers_large},
  "shared prefixes and duplicate pointers" => {shared_prefix_doc, pointers_shared_prefix},
  "high-index sibling array" => {array_doc, pointers_sibling_array}
}

expected = fn _job_name, {document, pointers} ->
  Enum.reduce(pointers, initial_acc, fn pointer, acc ->
    reduce_result.(pointer, ExJSONPointer.resolve(document, pointer), acc)
  end)
end

BenchSupport.assert_jobs!("batch resolve reduction", jobs, inputs, expected)
Benchee.run(jobs, BenchSupport.options(inputs))
