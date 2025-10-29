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
      Przma.AI.LocalInference,
      
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
  
  defp oban_config do
    Application.fetch_env!(:przma, Oban)
  end
  
  defp topologies do
    [
      przma_cluster: [
        strategy: Cluster.Strategy.Gossip,
        config: [
          port: 45892,
          if_addr: "0.0.0.0",
          multicast_addr: "230.1.1.251",
          multicast_ttl: 1,
          secret: Application.get_env(:przma, :cluster_secret)
        ]
      ]
    ]
  end
end

defmodule Przma.Release do
  @moduledoc """
  Release tasks for PRZMA deployment.
  
  Run migrations, setup, etc.
  """
  
  @app :przma
  
  def migrate do
    load_app()
    
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
  
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end
  
  def setup do
    load_app()
    
    # Create databases
    for repo <- repos() do
      case repo.__adapter__.storage_up(repo.config) do
        :ok -> IO.puts("Database created for #{inspect(repo)}")
        {:error, :already_up} -> IO.puts("Database already exists for #{inspect(repo)}")
        {:error, term} -> IO.puts("Error creating database: #{inspect(term)}")
      end
    end
    
    # Run migrations
    migrate()
    
    # Setup CouchDB
    setup_couchdb()
    
    # Seed data if needed
    # seed()
  end
  
  def seed do
    load_app()
    
    # Run seed scripts
    seed_path = Path.join([:code.priv_dir(@app), "repo", "seeds.exs"])
    
    if File.exists?(seed_path) do
      Code.eval_file(seed_path)
      IO.puts("Seeding complete")
    else
      IO.puts("No seed file found")
    end
  end
  
  defp setup_couchdb do
    couchdb_url = Application.get_env(@app, :couchdb_url)
    {user, pass} = Application.get_env(@app, :couchdb_credentials)
    
    IO.puts("Setting up CouchDB at #{couchdb_url}")
    
    # Verify CouchDB is accessible
    case HTTPoison.get(couchdb_url, [], [hackney: [basic_auth: {user, pass}]]) do
      {:ok, %{status_code: 200}} ->
        IO.puts("CouchDB is accessible")
        :ok
      
      error ->
        IO.puts("Failed to connect to CouchDB: #{inspect(error)}")
        {:error, :couchdb_not_accessible}
    end
  end
  
  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
  
  defp load_app do
    Application.load(@app)
  end
end

defmodule Przma.HealthCheck do
  @moduledoc """
  Health check endpoints for monitoring and load balancers.
  """
  
  @doc """
  Check overall system health.
  """
  def check do
    checks = %{
      database: check_database(),
      couchdb: check_couchdb(),
      ollama: check_ollama(),
      storage: check_storage()
    }
    
    overall_status = if Enum.all?(checks, fn {_, status} -> status == :healthy end) do
      :healthy
    else
      :unhealthy
    end
    
    %{
      status: overall_status,
      checks: checks,
      timestamp: DateTime.utc_now()
    }
  end
  
  defp check_database do
    case Ecto.Adapters.SQL.query(Przma.Repo, "SELECT 1", []) do
      {:ok, _} -> :healthy
      _ -> :unhealthy
    end
  end
  
  defp check_couchdb do
    couchdb_url = Application.get_env(:przma, :couchdb_url)
    {user, pass} = Application.get_env(:przma, :couchdb_credentials)
    
    case HTTPoison.get(couchdb_url, [], [hackney: [basic_auth: {user, pass}]]) do
      {:ok, %{status_code: 200}} -> :healthy
      _ -> :unhealthy
    end
  end
  
  defp check_ollama do
    case Przma.AI.LocalInference.health_check() do
      %{status: :healthy} -> :healthy
      _ -> :unhealthy
    end
  end
  
  defp check_storage do
    # Check if we can write to storage
    test_file = "/tmp/przma_health_check_#{System.system_time()}"
    
    case File.write(test_file, "test") do
      :ok ->
        File.rm(test_file)
        :healthy
      _ -> :unhealthy
    end
  end
end

defmodule PrzmaWeb.HealthController do
  @moduledoc """
  HTTP endpoints for health checks.
  """
  
  use PrzmaWeb, :controller
  
  def index(conn, _params) do
    health = Przma.HealthCheck.check()
    
    status_code = if health.status == :healthy, do: 200, else: 503
    
    conn
    |> put_status(status_code)
    |> json(health)
  end
  
  def ready(conn, _params) do
    # Readiness check - is the app ready to serve traffic?
    health = Przma.HealthCheck.check()
    
    if health.status == :healthy do
      json(conn, %{ready: true})
    else
      conn
      |> put_status(503)
      |> json(%{ready: false, reason: health.checks})
    end
  end
  
  def live(conn, _params) do
    # Liveness check - is the app running?
    json(conn, %{alive: true})
  end
end
