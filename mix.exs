defmodule Lapin.Mixfile do
  use Mix.Project

  def project do
    [
      app: :lapin,
      version: "0.4.0",
      elixir: "~> 1.7",
      description: "Elixir RabbitMQ Client",
      source_url: "https://github.com/lucacorti/lapin",
      package: package(),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        plt_add_deps: :project,
        ignore_warnings: ".dialyzer.ignore-warnings"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: [:dev]},
      {:earmark, ">= 0.0.0", only: [:dev]},
      {:credo, ">= 0.0.0", only: [:dev]},
      {:dialyxir, ">= 0.0.0", only: [:dev]},
      {:amqp, "~> 1.2"},
      {:connection, "~> 1.0.0"}
    ]
  end

  defp package do
    [
      maintainers: ["Luca Corti"],
      licenses: ["MIT"],
      links: %{GitHub: "https://github.com/lucacorti/lapin"}
    ]
  end

  defp docs do
    [
      main: "main",
      extras: [
        "docs/main.md"
      ]
    ]
  end
end
