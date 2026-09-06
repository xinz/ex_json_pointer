defmodule ExJSONPointer.BenchSupport do
  @moduledoc false

  @doc """
  Runs every benchmark job once for every input and checks its result before
  Benchee starts collecting measurements.
  """
  def assert_jobs!(suite_name, jobs, inputs, expected_fun) do
    Enum.each(inputs, fn {input_name, input} ->
      Enum.each(jobs, fn {job_name, job} ->
        expected = expected_fun.(job_name, input)
        actual = job.(input)

        unless actual == expected do
          raise """
          correctness preflight failed for #{suite_name}
          job: #{job_name}
          input: #{input_name}
          expected: #{inspect(expected, limit: 20)}
          actual: #{inspect(actual, limit: 20)}
          """
        end
      end)
    end)

    IO.puts("Correctness preflight passed: #{suite_name}")
  end

  @doc """
  Returns short defaults suitable for local smoke runs.

  Set `BENCHMARK_PROFILE=full` for longer measurements used to make performance
  decisions. Benchee 1.5 supports reductions directly through `:reduction_time`,
  so every benchmark records run time, memory, and reductions.
  """
  def options(inputs, overrides \\ []) do
    durations =
      case System.get_env("BENCHMARK_PROFILE") do
        "full" -> [warmup: 2, time: 5, memory_time: 2, reduction_time: 2]
        _ -> [warmup: 0.1, time: 0.3, memory_time: 0.2, reduction_time: 0.2]
      end

    defaults = [inputs: inputs, print: [fast_warning: false]] ++ durations
    Keyword.merge(defaults, overrides)
  end
end
