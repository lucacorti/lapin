defmodule Lapin.Mixfile do
  use Mix.Project

  def project do
    [
      app: :lapin,
      version: "0.3.4",
      elixir: "~> 1.5",
      description: "Elixir RabbitMQ Client",
      source_url: "https://github.com/lucacorti/lapin",
      package: package(),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Lapin.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: [:dev]},
      {:earmark, ">= 0.0.0", only: [:dev]},
      {:credo, ">= 0.0.0", only: [:dev]},
      {:dialyxir, ">= 0.0.0", only: [:dev]},
      {:amqp, "~> 1.0"},
      {:connection, "~> 1.0.0"},
      {:ranch_proxy_protocol, "~> 2.0", override: true},
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
