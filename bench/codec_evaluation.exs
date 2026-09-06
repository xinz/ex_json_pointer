Code.require_file("bench_support.exs", __DIR__)

alias ExJSONPointer.BenchSupport

# This candidate is retained only to make the rejected one-pass iodata approach reproducible.
defmodule ExJSONPointer.BenchCodecCandidate do
  def encode([]), do: ""

  def encode(tokens) do
    escaped_tokens = Enum.map(tokens, &escape_token/1)
    IO.iodata_to_binary(["/", Enum.intersperse(escaped_tokens, "/")])
  end

  defp escape_token(token) when is_integer(token) do
    token |> Integer.to_string() |> escape_token()
  end

  defp escape_token(token) when is_binary(token), do: escape_token(token, [])

  defp escape_token("", acc), do: Enum.reverse(acc)

  defp escape_token(binary, acc) do
    case :binary.match(binary, ["~", "/"]) do
      :nomatch ->
        Enum.reverse([binary | acc])

      {position, 1} ->
        <<prefix::binary-size(position), character, rest::binary>> = binary
        replacement = if character == ?~, do: "~0", else: "~1"
        escape_token(rest, [replacement, prefix | acc])
    end
  end
end

paths =
  Enum.flat_map(1..100, fn _iteration ->
    [
      ["users", "0", "name"],
      ["a/b", "c~d", ""],
      [String.duplicate("plain", 20), String.duplicate("~/", 20)]
    ]
  end)

jobs = %{
  "current runtime-backed encoder" => fn input ->
    Enum.map(input, &ExJSONPointer.encode_path/1)
  end,
  "candidate one-pass iodata encoder" => fn input ->
    Enum.map(input, &ExJSONPointer.BenchCodecCandidate.encode/1)
  end
}

inputs = %{"300 mixed paths" => paths}

expected = fn _job_name, input ->
  Enum.map(input, &ExJSONPointer.encode_path/1)
end

BenchSupport.assert_jobs!("codec candidate evaluation", jobs, inputs, expected)
Benchee.run(jobs, BenchSupport.options(inputs))
