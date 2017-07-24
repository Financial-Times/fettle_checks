defmodule FettleChecks.Mixfile do
  use Mix.Project

  def project do
    [app: :fettle_checks,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     aliases: [test: "test --no-start"],
     source_url: "https://github.com/Financial-Times/fettle_checks",
     description: description(),
     package: package(),
     docs: docs(),
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger]]
  end

  def package do
    [
      maintainers: ["Ellis Pritchard"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/Financial-Times/fettle_checks"} ]
  end

  defp description do
    """
    A library of health checker implementations for Fettle.
    """
  end

  def docs do
    [main: "readme",
     extras: ["README.md"]]
  end

  # Dependencies can be Hex packages:
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      # {:fettle, github: "Financial-Times/fettle"},
      {:fettle, "~> 0.1"},
      {:poison, "~> 3.1"},
      {:httpoison, "~> 0.11"},
      {:plug, "~> 1.3", only: [:test]},
      {:cowboy, "~> 1.0", only: [:test]},
      {:credo, "~> 0.5", only: [:dev, :test]},
      {:mix_test_watch, "~> 0.3", only: :dev, runtime: false},
      {:ex_doc, "~> 0.14", only: :dev, runtime: false},
      {:dialyxir, "~> 0.5.0", only: [:dev], runtime: false},
      {:inch_ex, ">= 0.0.0", only: :docs}
    ]
  end
end
