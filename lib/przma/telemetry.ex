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
