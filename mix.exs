defmodule EctoSpect.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/onnimonni/ecto_spect"

  def project do
    [
      app: :ecto_spect,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.10"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},

      # test only
      {:postgrex, "~> 0.22", only: [:test]},

      # optional — enables `mix ecto_spect.install`
      {:igniter, "~> 0.5", optional: true},

      # dev only
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Analyzes PostgreSQL EXPLAIN plans during ExUnit runs and fails tests on bad query patterns."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "EctoSpect",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end

  defp aliases do
    [
      "test.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "test.reset": ["ecto.drop --quiet", "test.setup"]
    ]
  end
end
