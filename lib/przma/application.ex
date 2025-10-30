defmodule Przma.Application do
  @moduledoc """
  Main OTP Application for PRZMA platform.

  Starts and supervises all core services:
  - Multi-tenant management
  - Broadway AI enrichment pipeline
  - Local AI inference (Ollama)
  - Web endpoint (Phoenix)
  - Background jobs
  - Cluster coordination (if distributed)
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting PRZMA Application...")

    children = [
      # Database
      Przma.Repo,

      # PubSub for real-time updates
      {Phoenix.PubSub, name: Przma.PubSub},

      # Multi-tenant management
      Przma.MultiTenant,

      # Local AI inference
      # Przma.AI.LocalInference,

      # Broadway pipeline for AI enrichment
      Przma.ActivityStreams.Pipeline,

      # Web endpoint
      PrzmaWeb.Endpoint,

      # Background job processor (optional)
      # {Oban, oban_config()},

      # Cluster coordination (if distributed)
      # {Cluster.Supervisor, [topologies(), [name: Przma.ClusterSupervisor]]},
    ]

    opts = [strategy: :one_for_one, name: Przma.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("PRZMA Application started successfully")
        {:ok, pid}

      error ->
        Logger.error("Failed to start PRZMA Application: #{inspect(error)}")
        error
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    PrzmaWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Private Functions

  # defp oban_config do
  #   Application.fetch_env!(:przma, Oban)
  # end

  # defp topologies do
  #   [
  #     przma_cluster: [
  #       strategy: Cluster.Strategy.Gossip,
  #       config: [
  #         port: 45892,
  #         if_addr: "0.0.0.0",
  #         multicast_addr: "230.1.1.251",
  #         multicast_ttl: 1,
  #         secret: Application.get_env(:przma, :cluster_secret)
  #       ]
  #     ]
  #   ]
  # end
end
