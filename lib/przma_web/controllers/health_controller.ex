defmodule PrzmaWeb.HealthController do
  @moduledoc """
  Health check endpoints for monitoring and load balancers.
  """
  
  use PrzmaWeb, :controller
  
  alias Przma.HealthCheck
  
  @doc """
  Comprehensive health check of all system components.
  """
  def index(conn, _params) do
    health = HealthCheck.check()
    
    status_code = if health.status == :healthy, do: 200, else: 503
    
    conn
    |> put_status(status_code)
    |> json(health)
  end
  
  @doc """
  Readiness check - is the app ready to serve traffic?
  """
  def ready(conn, _params) do
    health = HealthCheck.check()
    
    if health.status == :healthy do
      json(conn, %{ready: true, timestamp: DateTime.utc_now()})
    else
      conn
      |> put_status(503)
      |> json(%{ready: false, reason: health.checks, timestamp: DateTime.utc_now()})
    end
  end
  
  @doc """
  Liveness check - is the app running?
  """
  def live(conn, _params) do
    json(conn, %{alive: true, timestamp: DateTime.utc_now()})
  end
  
  @doc """
  Detailed component status.
  """
  def status(conn, _params) do
    status = %{
      application: :running,
      version: Application.spec(:przma, :vsn) |> to_string(),
      uptime: System.monotonic_time(:second),
      node: Node.self(),
      components: HealthCheck.check().checks,
      timestamp: DateTime.utc_now()
    }
    
    json(conn, status)
  end
  
  @doc """
  Database health check.
  """
  def database(conn, _params) do
    case HealthCheck.check_database() do
      :healthy ->
        json(conn, %{status: :healthy, timestamp: DateTime.utc_now()})
      
      :unhealthy ->
        conn
        |> put_status(503)
        |> json(%{status: :unhealthy, timestamp: DateTime.utc_now()})
    end
  end
  
  @doc """
  AI services health check.
  """
  def ai_services(conn, _params) do
    case HealthCheck.check_ollama() do
      :healthy ->
        json(conn, %{status: :healthy, timestamp: DateTime.utc_now()})
      
      :unhealthy ->
        conn
        |> put_status(503)
        |> json(%{status: :unhealthy, timestamp: DateTime.utc_now()})
    end
  end
end
