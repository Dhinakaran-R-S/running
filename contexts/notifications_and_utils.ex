defmodule Przma.Notifications do
  @moduledoc """
  The Notifications context for managing multi-channel notifications.

  Supports:
  - Email notifications
  - In-app notifications
  - Push notifications
  - Webhook notifications
  """

  alias Przma.Repo
  alias Przma.Schemas.Member
  alias PrzmaWeb.Endpoint

  @doc """
  Sends a notification to a member.
  """
  def send_notification(member_id, type, data) do
    with {:ok, member} <- get_member(member_id),
         preferences <- get_notification_preferences(member) do

      # Send via enabled channels
      if preferences.email_enabled do
        send_email_notification(member, type, data)
      end

      if preferences.push_enabled do
        send_push_notification(member, type, data)
      end

      # Always send in-app notification
      send_in_app_notification(member, type, data)

      :ok
    end
  end

  @doc """
  Sends an in-app notification via WebSocket.
  """
  def send_in_app_notification(member, type, data) do
    payload = %{
      type: type,
      data: data,
      timestamp: DateTime.utc_now()
    }

    Endpoint.broadcast("member:#{member.id}", "notification", payload)
  end

  @doc """
  Sends an email notification.
  """
  def send_email_notification(member, type, data) do
    # Queue email sending via Oban
    %{
      member_id: member.id,
      type: type,
      data: data
    }
    |> Przma.Workers.EmailWorker.new()
    |> Oban.insert()
  end

  @doc """
  Sends a push notification.
  """
  def send_push_notification(member, type, data) do
    # Queue push notification via Oban
    %{
      member_id: member.id,
      type: type,
      data: data
    }
    |> Przma.Workers.PushNotificationWorker.new()
    |> Oban.insert()
  end

  @doc """
  Broadcasts notification to entire organization.
  """
  def broadcast_to_organization(organization_id, type, data) do
    Endpoint.broadcast("activity:tenant:#{organization_id}", "notification", %{
      type: type,
      data: data,
      timestamp: DateTime.utc_now()
    })
  end

  # Private Functions

  defp get_member(member_id) do
    case Repo.get(Member, member_id) do
      nil -> {:error, :not_found}
      member -> {:ok, member}
    end
  end

  defp get_notification_preferences(member) do
    # Get from member metadata or use defaults
    preferences = member.metadata["notification_preferences"] || %{}

    %{
      email_enabled: Map.get(preferences, "email_enabled", true),
      push_enabled: Map.get(preferences, "push_enabled", true),
      in_app_enabled: Map.get(preferences, "in_app_enabled", true)
    }
  end
end

defmodule Przma.HealthCheck do
  @moduledoc """
  System health check utilities.
  """

  alias Przma.Repo

  @doc """
  Performs comprehensive health check of all components.
  """
  def check do
    checks = %{
      database: check_database(),
      ollama: check_ollama(),
      cache: check_cache(),
      storage: check_storage()
    }

    status = if all_healthy?(checks), do: :healthy, else: :unhealthy

    %{
      status: status,
      checks: checks,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Checks database connectivity.
  """
  def check_database do
    try do
      Repo.query!("SELECT 1", [])
      :healthy
    rescue
      _ -> :unhealthy
    end
  end

  @doc """
  Checks Ollama AI service connectivity.
  """
  def check_ollama do
    case Przma.AI.LocalInference.health_check() do
      :ok -> :healthy
      _ -> :unhealthy
    end
  end

  @doc """
  Checks cache availability.
  """
  def check_cache do
    try do
      Przma.Cache.put("health_check", true, ttl: 1)
      case Przma.Cache.get("health_check") do
        true -> :healthy
        _ -> :unhealthy
      end
    rescue
      _ -> :unhealthy
    end
  end

  @doc """
  Checks storage system.
  """
  def check_storage do
    case Przma.CAS.health_check() do
      :ok -> :healthy
      _ -> :unhealthy
    end
  end

  # Private Functions

  defp all_healthy?(checks) do
    Enum.all?(checks, fn {_component, status} -> status == :healthy end)
  end
end

defmodule Przma.Cache do
  @moduledoc """
  Simple ETS-based cache with TTL support.

  For production, consider using Cachex or Nebulex.
  """

  use GenServer

  @table_name :przma_cache
  @cleanup_interval 60_000  # 1 minute

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stores a value in cache with optional TTL (in seconds).
  """
  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, :infinity)
    expires_at = calculate_expiry(ttl)

    :ets.insert(@table_name, {key, value, expires_at})
    :ok
  end

  @doc """
  Retrieves a value from cache.
  """
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expires_at}] ->
        if expired?(expires_at) do
          :ets.delete(@table_name, key)
          nil
        else
          value
        end

      [] -> nil
    end
  end

  @doc """
  Deletes a value from cache.
  """
  def delete(key) do
    :ets.delete(@table_name, key)
    :ok
  end

  @doc """
  Clears all cache entries.
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private Functions

  defp calculate_expiry(:infinity), do: :infinity
  defp calculate_expiry(ttl) when is_integer(ttl) do
    System.system_time(:second) + ttl
  end

  defp expired?(:infinity), do: false
  defp expired?(expires_at) do
    System.system_time(:second) > expires_at
  end

  defp cleanup_expired do
    now = System.system_time(:second)

    :ets.foldl(fn {key, _value, expires_at}, acc ->
      if expires_at != :infinity && expires_at < now do
        :ets.delete(@table_name, key)
      end
      acc
    end, :ok, @table_name)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end

defmodule Przma.Scheduler do
  @moduledoc """
  Scheduled task coordinator using Oban Cron.

  Defines recurring jobs for maintenance and analytics.
  """

  @doc """
  Returns Oban cron configuration.
  """
  def cron_config do
    [
      # Daily insights generation at 2 AM
      {"0 2 * * *", Przma.Workers.DailyInsightsWorker},

      # Hourly activity enrichment catch-up
      {"0 * * * *", Przma.Workers.EnrichmentCatchupWorker},

      # Every 15 minutes: update PERMA scores
      {"*/15 * * * *", Przma.Workers.PermaUpdateWorker},

      # Weekly reports on Sunday at 9 AM
      {"0 9 * * 0", Przma.Workers.WeeklyReportWorker},

      # Daily cleanup of old data at 3 AM
      {"0 3 * * *", Przma.Workers.CleanupWorker},

      # Every 5 minutes: sync offline changes
      {"*/5 * * * *", Przma.Workers.OfflineSyncWorker}
    ]
  end
end

defmodule Przma.Telemetry do
  @moduledoc """
  Telemetry event definitions and handlers.
  """

  use Supervisor
  import Telemetry.Metrics

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns list of metrics for monitoring.
  """
  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("przma.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "Total time spent executing database queries"
      ),

      # Custom Business Metrics
      counter("przma.activities.created.count",
        description: "Number of activities created"
      ),
      counter("przma.enrichment.completed.count",
        description: "Number of enrichment jobs completed"
      ),
      distribution("przma.enrichment.duration",
        unit: {:native, :millisecond},
        description: "Time to enrich an activity"
      ),

      # VM Metrics
      last_value("vm.memory.total", unit: {:byte, :megabyte}),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.system_counts.process_count")
    ]
  end

  defp periodic_measurements do
    []
  end
end
