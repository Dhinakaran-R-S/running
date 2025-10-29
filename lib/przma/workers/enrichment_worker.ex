defmodule Przma.Workers.EnrichmentWorker do
  @moduledoc """
  Oban worker for AI enrichment of activities.

  Processes activities through the perception modules and generates embeddings.
  """

  use Oban.Worker,
    queue: :enrichment,
    max_attempts: 3,
    priority: 1

  alias Przma.{Repo, ActivityStreams}
  alias Przma.Schemas.Activity
  alias Przma.AI.{LocalInference, VectorStore}
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"activity_id" => activity_id}}) do
    Logger.info("Enriching activity: #{activity_id}")

    with {:ok, activity} <- get_activity(activity_id),
         {:ok, enrichment} <- enrich_activity(activity),
         {:ok, embedding} <- generate_embedding(activity),
         {:ok, _} <- store_enrichment(activity, enrichment, embedding) do

      # Broadcast enrichment complete
      broadcast_enrichment_complete(activity)

      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to enrich activity #{activity_id}: #{inspect(reason)}")
        error
    end
  end

  defp get_activity(activity_id) do
    case Repo.get(Activity, activity_id) do
      nil -> {:error, :not_found}
      activity -> {:ok, activity}
    end
  end

  defp enrich_activity(activity) do
    # Run through perception modules
    modules = [
      Przma.AI.PerceptionModules.EmotionalIntelligence,
      Przma.AI.PerceptionModules.ConsciousnessLevel,
      Przma.AI.PerceptionModules.BehaviorPattern,
      Przma.AI.PerceptionModules.GrowthIndicators,
      Przma.AI.PerceptionModules.RelationshipDynamics
    ]

    enrichment = Enum.reduce(modules, %{}, fn module, acc ->
      case module.analyze(activity) do
        {:ok, result} ->
          Map.put(acc, module.key(), result)

        {:error, _} ->
          acc
      end
    end)

    {:ok, enrichment}
  end

  defp generate_embedding(activity) do
    # Create text representation of activity
    text = ActivityStreams.to_text(activity)

    LocalInference.generate_embeddings(text)
  end

  defp store_enrichment(activity, enrichment, embedding) do
    activity
    |> Ecto.Changeset.change(%{
      perception_enrichment: enrichment,
      embedding: embedding
    })
    |> Repo.update()
  end

  defp broadcast_enrichment_complete(activity) do
    PrzmaWeb.Endpoint.broadcast(
      "activity:tenant:#{activity.organization_id}",
      "enrichment_complete",
      %{activity_id: activity.id}
    )
  end
end
