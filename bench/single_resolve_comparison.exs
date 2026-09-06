Code.require_file("bench_support.exs", __DIR__)

alias ExJSONPointer.BenchSupport

small_data = %{
  "a" => %{
    "b" => %{"c" => [1, 2, 3], "" => "empty string"},
    "b2" => %{"c2" => [%{"d2-1" => [4, 5, 6]}, %{"d2-2" => "7"}]}
  }
}

large_data =
  Enum.into(1..5_000, %{}, fn i ->
    {
      "item_#{i}",
      %{
        "meta" => %{"id" => i, "type" => "record"},
        "payload" => %{
          "nested" => %{
            "values" => [
              i,
              i * 2,
              %{
                "target" => "value_#{i}",
                "flags" => %{
                  "active" => rem(i, 2) == 0,
                  "archived" => rem(i, 5) == 0
                }
              }
            ]
          }
        }
      }
    }
  end)

jobs = %{
  ":ex_json_pointer implementation" => fn {data, pointer} ->
    ExJSONPointer.resolve(data, pointer)
  end,
  ":odgn_json_pointer implementation" => fn {data, pointer} ->
    JSONPointer.get(data, pointer)
  end
}

inputs = %{
  "small dataset" => {small_data, "/a/b2/c2/0"},
  "large dataset" => {large_data, "/item_4096/payload/nested/values/2/target"}
}

expected = fn _job_name, {data, pointer} -> ExJSONPointer.resolve(data, pointer) end

BenchSupport.assert_jobs!("single resolve comparison", jobs, inputs, expected)
Benchee.run(jobs, BenchSupport.options(inputs))
