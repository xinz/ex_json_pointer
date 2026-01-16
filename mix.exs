defmodule ExJSONPointer.MixProject do
  use Mix.Project

  @source_url "https://github.com/xinz/ex_json_pointer"

  def project do
    [
      app: :ex_json_pointer,
      version: "0.5.1",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description do
    "An Elixir implementation of RFC 6901 JSON Pointer and Relative JSON Pointer."
  end

  defp deps() do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      formatter_opts: [gfm: true],
      extras: [
        "README.md"
      ]
    ]
  end

end
