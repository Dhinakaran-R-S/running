defmodule Przma.AI.EmbeddingStage do
  @moduledoc """
  GenStage consumer for generating embeddings in parallel.
  Uses local embedding models (Nomic Embed, BGE, etc.)
  """

  use GenStage

  alias Przma.AI.{LocalInference, VectorStore}

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  def init(opts) do
    workers = opts[:workers] || System.schedulers_online()
    {:consumer, %{workers: workers}, subscribe_to: opts[:subscribe_to]}
  end

  def handle_events(activities, _from, state) do
    enriched =
      activities
      |> Task.async_stream(
        &generate_and_store_embedding/1,
        max_concurrency: state.workers,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    {:noreply, enriched, state}
  end

  defp generate_and_store_embedding(activity) do
    # Build context string
    context = build_context_string(activity)

    # Generate embedding
    case LocalInference.generate_embeddings(context) do
      {:ok, embedding} ->
        # Store in vector database
        tenant_id = activity["context"]["tenant_id"]
        VectorStore.store_embedding(activity["id"], embedding, tenant_id)

        Map.put(activity, "embedding_generated", true)

      {:error, reason} ->
        Logger.error("Failed to generate embedding: #{inspect(reason)}")
        activity
    end
  end

  defp build_context_string(activity) do
    """
    Verb: #{activity["verb"]}
    Object: #{Jason.encode!(activity["object"])}
    PRESERVE: #{Enum.join(activity["preserve"] || [], ", ")}
    7P: #{Enum.join(activity["seven_p"] || [], ", ")}
    """
  end
end
