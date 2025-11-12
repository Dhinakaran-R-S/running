defmodule Przma.MixProject do
  use Mix.Project

  def project do
    [
      app: :przma,
      version: "2.0.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Przma.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Phoenix Framework
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_live_dashboard, "~> 0.8.0"},
      {:phoenix_live_view, "~> 1.1.16"},
      {:phoenix_view, "~> 2.0"},

      # Asset Builders
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},

      # Database
      {:ecto_sql, "~> 3.13.2"},
      {:postgrex, ">= 0.0.0"},
      {:pgvector, "~> 0.2.0"},

      # JSON
      {:jason, "~> 1.4"},
      {:poison, "~> 5.0"},

      # Authentication & Security
      {:pbkdf2_elixir, "~> 2.3.1"},
      {:joken, "~> 2.5"},
      {:guardian, "~> 2.3"},

      # Background Jobs
      {:oban, "~> 2.15"},
      {:gen_stage, "~> 1.2"},
      {:broadway, "~> 1.0"},

      # HTTP Clients
      {:req, "~> 0.5.15"},
      {:finch, "~> 0.16"},
      {:tesla, "~> 1.7"},
      {:hackney, "~> 1.18"},
      {:httpoison, "~> 1.8"},

      # AWS SDK
      {:ex_aws, "~> 2.4"},
      {:ex_aws_s3, "~> 2.3"},
      {:sweet_xml, "~> 0.7"},

      # Authentication (additional)
      # {:argon2_elixir, "~> 3.2"},

      # Caching
      {:cachex, "~> 3.6"},
      {:nebulex, "~> 2.5"},

      # Monitoring & Telemetry
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.1.0"},
      {:telemetry_poller, "~> 1.0"},

      # Development & Testing
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      {:floki, ">= 0.30.0", only: :test},
      {:ex_machina, "~> 2.7", only: :test},
      {:faker, "~> 0.17", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},

      # Utilities
      {:timex, "~> 3.7"},
      {:decimal, "~> 2.0"},
      {:uuid, "~> 1.1"},

      # Web Server
      {:plug_cowboy, "~> 2.6"},
      {:cors_plug, "~> 3.0"},

      # Email (optional - choose one)
      {:swoosh, "~> 1.11"},
      # {:bamboo, "~> 2.2"},

      # Rate Limiting
      {:hammer, "~> 6.1"},

      # Logging
      {:logger_file_backend, "~> 0.0.13"},

      # Configuration
      {:dotenvy, "~> 0.7.0"}
    ]
  end

 defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind przma", "esbuild przma"],
      "assets.deploy": [
        "tailwind przma --minify",
        "esbuild przma --minify",
        "phx.digest"
      ]
    ]
  end
end
