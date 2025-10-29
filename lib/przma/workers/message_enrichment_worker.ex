defmodule Przma.Workers.MessageEnrichmentWorker do
  @moduledoc """
  Worker for enriching conversation messages with AI analysis.
  """

  use Oban.Worker,
    queue: :enrichment,
    max_attempts: 3,
    priority: 2

  alias Przma.{Repo, Conversations}
  alias Przma.Schemas.Message
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id}}) do
    Logger.info("Enriching message: #{message_id}")

    with {:ok, message} <- Conversations.get_message(message_id),
         {:ok, analysis} <- analyze_message(message),
         {:ok, _} <- store_analysis(message, analysis) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to enrich message #{message_id}: #{inspect(reason)}")
        error
    end
  end

  defp analyze_message(message) do
    # Analyze sentiment, intent, entities, etc.
    analysis = %{
      sentiment: detect_sentiment(message.content),
      intent: detect_intent(message.content),
      entities: extract_entities(message.content)
    }

    {:ok, analysis}
  end

  defp store_analysis(message, analysis) do
    metadata = Map.put(message.metadata || %{}, "analysis", analysis)

    message
    |> Ecto.Changeset.change(%{metadata: metadata})
    |> Repo.update()
  end

  defp detect_sentiment(text) do
    # TODO: Implement sentiment analysis
    "neutral"
  end

  defp detect_intent(text) do
    # TODO: Implement intent detection
    "statement"
  end

  defp extract_entities(_text) do
    # TODO: Implement entity extraction
    []
  end
end
