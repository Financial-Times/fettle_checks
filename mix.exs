defmodule FettleChecks.Mixfile do
  use Mix.Project

  def project do
    [
      app: :fettle_checks,
      version: "0.3.0",
      elixir: "~> 1.11",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      aliases: [test: "test --no-start"],
      source_url: "https://github.com/Financial-Times/fettle_checks",
      description: description(),
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger, :httpoison]]
  end

  def package do
    [
      maintainers: ["Ellis Pritchard"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/Financial-Times/fettle_checks"}
    ]
  end

  defp description do
    """
    A library of health checker implementations for Fettle.
    """
  end

  def docs do
    [main: "readme", extras: ["README.md"]]
  end

  # Dependencies can be Hex packages:
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      # {:fettle, github: "Financial-Times/fettle"},
      {:fettle, github: "Financial-Times/fettle", tag: "v1.1.0"},
      {:poison, "~> 4.0"},
      {:httpoison, "~> 1.7"},
      {:plug, "~> 1.11", only: [:test]},
      {:plug_cowboy, "~> 2.4", only: [:test]},
      {:cowboy, "~> 2.8", only: [:test]},
      {:credo, "~> 1.5", only: [:dev, :test]},
      {:mix_test_watch, "~> 1.0.2", only: :dev, runtime: false},
      {:ex_doc, "~> 0.23.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:inch_ex, "~> 2.0", only: :docs}
    ]
  end
end
