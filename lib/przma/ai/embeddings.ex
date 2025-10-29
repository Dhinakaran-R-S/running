defmodule Przma.AI.Embeddings do
  @moduledoc """
  Manages text embeddings for semantic search.
  Uses local embedding models via Ollama.
  """

  alias Przma.AI.LocalInference

  @doc """
  Generate embeddings for a text with optional context.
  """
  def generate(params) do
    text = params[:text]
    context = params[:context] || ""

    # Combine text with context for richer embeddings
    full_text = if context != "" do
      "#{text}\n\nContext: #{context}"
    else
      text
    end

    case LocalInference.generate_embeddings(full_text) do
      {:ok, embedding} -> embedding
      {:error, _} -> []
    end
  end

  @doc """
  Generate embeddings for multiple texts in batch.
  """
  def generate_batch(texts) do
    texts
    |> Task.async_stream(
      fn text -> generate(%{text: text}) end,
      max_concurrency: 5,
      timeout: 30_000
    )
    |> Enum.map(fn {:ok, embedding} -> embedding end)
  end
end
