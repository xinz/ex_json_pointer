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
          "settings" => %{
            "theme" => if(rem(i, 2) == 0, do: "dark", else: "light"),
            "locale" => "en"
          },
          "posts" => %{
            "0" => %{"title" => "title_#{i}", "published" => true},
            "1" => %{"title" => "draft_#{i}", "published" => false}
          }
        }
      }
    end)
}

array_doc = %{
  "items" =>
    Enum.map(0..4_095, fn i ->
      %{"id" => i, "value" => "value_#{i}", "metadata" => %{"even" => rem(i, 2) == 0}}
    end)
}

input_order_doc =
  Enum.into(1..12, %{}, fn group ->
    fields = Enum.into(1..4, %{}, fn field -> {"field_#{field}", {group, field}} end)
    {"group_#{group}", fields}
  end)

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
  end) ++ ["/users/999/profile/name"]

high_index_pointers = [
  "/items/1024/id",
  "/items/2048/value",
  "/items/3072/metadata/even",
  "/items/4095/id",
  "/items/4096/value"
]

sibling_array_pointers =
  Enum.map(4_064..4_095, fn index -> "/items/#{index}/value" end) ++
    ["/items/4096/value"]

adaptive_eight_pointers =
  Enum.map(1..8, fn i -> "/key_#{i}/nested_1/nested_2/2/target" end)

adaptive_nine_pointers =
  Enum.map(1..9, fn i -> "/key_#{i}/nested_1/nested_2/2/target" end)

shared_first_pointers =
  for group <- 1..12, field <- 1..4 do
    "/group_#{group}/field_#{field}"
  end

interleaved_pointers =
  for field <- 1..4, group <- 1..12 do
    "/group_#{group}/field_#{field}"
  end

jobs = %{
  "direct resolve/2 per pointer" => fn {document, pointers} ->
    Enum.into(pointers, %{}, fn pointer -> {pointer, ExJSONPointer.resolve(document, pointer)} end)
  end,
  "manual first-token grouping" => fn {document, pointers} ->
    pointers
    |> Enum.group_by(fn pointer ->
      case String.split(pointer, "/", trim: true) do
        [first | _] -> first
        [] -> ""
      end
    end)
    |> Enum.reduce(%{}, fn {_first, grouped_pointers}, acc ->
      Enum.reduce(grouped_pointers, acc, fn pointer, inner_acc ->
        Map.put(inner_acc, pointer, ExJSONPointer.resolve(document, pointer))
      end)
    end)
  end,
  "batch_resolve/2" => fn {document, pointers} ->
    ExJSONPointer.batch_resolve(document, pointers)
  end
}

inputs = %{
  "small document / few pointers" => {small_doc, pointers_small},
  "large document / scattered pointers" => {large_doc, pointers_large},
  "shared map prefix" => {shared_prefix_doc, pointers_shared_prefix},
  "high array indices" => {array_doc, high_index_pointers},
  "high-index sibling array" => {array_doc, sibling_array_pointers},
  "adaptive boundary / 8 scattered pointers" => {large_doc, adaptive_eight_pointers},
  "adaptive boundary / 9 scattered pointers" => {large_doc, adaptive_nine_pointers},
  "input order / shared prefixes first" => {input_order_doc, shared_first_pointers},
  "input order / shared prefixes interleaved" => {input_order_doc, interleaved_pointers}
}

expected = fn _job_name, {document, pointers} ->
  Enum.into(pointers, %{}, fn pointer -> {pointer, ExJSONPointer.resolve(document, pointer)} end)
end

BenchSupport.assert_jobs!("batch resolve", jobs, inputs, expected)
Benchee.run(jobs, BenchSupport.options(inputs))
