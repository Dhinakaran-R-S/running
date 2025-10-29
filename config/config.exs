# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
# config/config.exs
import Config

# Configure your database
config :przma, Przma.Repo,
  database: "przma_#{config_env()}",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Configure the endpoint
config :przma, PrzmaWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: PrzmaWeb.ErrorView, accepts: ~w(json)],
  pubsub_server: Przma.PubSub,
  live_view: [signing_salt: "your-secret-salt"]

# Configure Oban
# config :przma, Oban,
#   repo: Przma.Repo,
#   plugins: [
#     {Oban.Plugins.Pruner, max_age: 300},
#     {Oban.Plugins.Cron, crontab: Przma.Scheduler.cron_config()}
#   ],
#   queues: [
#     enrichment: 10,
#     analytics: 5,
#     notifications: 3,
#     emails: 2,
#     push: 2,
#     maintenance: 1
#   ]

# Configure Joken for JWT
config :joken, default_signer: "your-secret-key-here"

# Configure AI Services
config :przma, :ollama,
  base_url: "http://localhost:11434",
  model: "llama2",
  embedding_model: "nomic-embed-text",
  timeout: 30_000

# Configure CAS Storage
config :przma, :cas,
  storage_path: "./storage/cas",
  max_file_size: 104_857_600  # 100 MB

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config
import_config "#{config_env()}.exs"
