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
