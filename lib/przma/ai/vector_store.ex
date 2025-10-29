defmodule Przma.AI.VectorStore do
  @moduledoc """
  Vector storage and similarity search using pgvector.
  
  Supports:
  - Semantic similarity search
  - Multi-signal relevance ranking
  - Result diversification
  - Confidence threshold filtering
  """
  
  require Logger
  
  @default_top_k 10
  @default_similarity_threshold 0.7
  
  defmodule SearchResult do
    defstruct [
      :id,
      :content,
      :similarity_score,
      :metadata,
      :activity
    ]
  end
  
  @doc """
  Store an embedding in the vector database.
  """
  def store_embedding(activity_id, embedding, tenant_id, metadata \\ %{}) do
    schema_name = "tenant_#{tenant_id}"
    
    # Convert embedding list to pgvector format
    vector_str = format_vector(embedding)
    
    case Ecto.Adapters.SQL.query(
      Przma.Repo,
      """
      UPDATE #{schema_name}.activities 
      SET embedding = $1, 
          metadata = metadata || $2
      WHERE id = $3
      """,
      [vector_str, Jason.encode!(metadata), activity_id]
    ) do
      {:ok, _} -> :ok
      error -> 
        Logger.error("Failed to store embedding: #{inspect(error)}")
        error
    end
  end
  
  @doc """
  Search for similar activities using vector similarity.
  
  ## Options
  - `:top_k` - Number of results to return (default: 10)
  - `:similarity_threshold` - Minimum similarity score (default: 0.7)
  - `:filters` - Additional filters (actor, verb, date range, etc.)
  """
  def similarity_search(query_embedding, tenant_id, opts \\ %{}) do
    top_k = opts[:top_k] || @default_top_k
    threshold = opts[:similarity_threshold] || @default_similarity_threshold
    filters = opts[:filters] || %{}
    
    schema_name = "tenant_#{tenant_id}"
    vector_str = format_vector(query_embedding)
    
    # Build query with filters
    {base_query, params} = build_search_query(schema_name, vector_str, top_k, threshold, filters)
    
    case Ecto.Adapters.SQL.query(Przma.Repo, base_query, params) do
      {:ok, %{rows: rows, columns: columns}} ->
        results = Enum.map(rows, fn row ->
          parse_search_result(columns, row)
        end)
        
        {:ok, results}
      
      error -> 
        Logger.error("Vector search failed: #{inspect(error)}")
        error
    end
  end
  
  @doc """
  Find activities semantically similar to a given activity.
  """
  def find_similar_activities(activity_id, tenant_id, opts \\ %{}) do
    schema_name = "tenant_#{tenant_id}"
    
    # Get the activity's embedding
    case Ecto.Adapters.SQL.query(
      Przma.Repo,
      "SELECT embedding FROM #{schema_name}.activities WHERE id = $1",
      [activity_id]
    ) do
      {:ok, %{rows: [[embedding]]}} when not is_nil(embedding) ->
        similarity_search(parse_vector(embedding), tenant_id, opts)
      
      _ -> {:error, :activity_not_found_or_no_embedding}
    end
  end
  
  @doc """
  Hybrid search combining vector similarity and keyword search.
  """
  def hybrid_search(query_text, tenant_id, opts \\ %{}) do
    # Generate embedding for query
    {:ok, query_embedding} = Przma.AI.LocalInference.generate_embeddings(query_text)
    
    # Get vector search results
    {:ok, vector_results} = similarity_search(query_embedding, tenant_id, opts)
    
    # Get keyword search results
    keyword_results = keyword_search(query_text, tenant_id, opts)
    
    # Merge and re-rank results
    merged = merge_search_results(vector_results, keyword_results)
    
    {:ok, merged}
  end
  
  @doc """
  Get statistics about vector embeddings for a tenant.
  """
  def embedding_stats(tenant_id) do
    schema_name = "tenant_#{tenant_id}"
    
    case Ecto.Adapters.SQL.query(
      Przma.Repo,
      """
      SELECT 
        COUNT(*) FILTER (WHERE embedding IS NOT NULL) as embedded_count,
        COUNT(*) FILTER (WHERE embedding IS NULL) as not_embedded_count,
        COUNT(*) as total_count
      FROM #{schema_name}.activities
      """,
      []
    ) do
      {:ok, %{rows: [[embedded, not_embedded, total]]}} ->
        %{
          total_activities: total,
          embedded_activities: embedded,
          not_embedded_activities: not_embedded,
          embedding_coverage: if(total > 0, do: embedded / total, else: 0.0)
        }
      
      _ -> %{}
    end
  end
  
  @doc """
  Batch update embeddings for multiple activities.
  """
  def batch_update_embeddings(updates, tenant_id) do
    schema_name = "tenant_#{tenant_id}"
    
    # Build VALUES clause for batch update
    values = Enum.map_join(updates, ", ", fn {activity_id, embedding} ->
      vector_str = format_vector(embedding)
      "('#{activity_id}', '#{vector_str}')"
    end)
    
    query = """
    UPDATE #{schema_name}.activities AS a
    SET embedding = v.embedding
    FROM (VALUES #{values}) AS v(id, embedding)
    WHERE a.id = v.id::uuid
    """
    
    case Ecto.Adapters.SQL.query(Przma.Repo, query, []) do
      {:ok, _} -> :ok
      error -> error
    end
  end
  
  # Private Functions
  
  defp build_search_query(schema_name, vector_str, top_k, threshold, filters) do
    base_query = """
    SELECT 
      id,
      actor,
      verb,
      object,
      target,
      published,
      metadata,
      1 - (embedding <=> $1) as similarity_score
    FROM #{schema_name}.activities
    WHERE embedding IS NOT NULL
      AND (embedding <=> $1) < $2
    """
    
    params = [vector_str, 1.0 - threshold]
    
    # Add filters
    {query, params} = add_filters(base_query, params, filters)
    
    # Add ordering and limit
    query = query <> "\nORDER BY embedding <=> $1 LIMIT $#{length(params) + 1}"
    params = params ++ [top_k]
    
    {query, params}
  end
  
  defp add_filters(query, params, filters) do
    Enum.reduce(filters, {query, params}, fn
      {:actor, actor}, {q, p} ->
        {q <> " AND actor = $#{length(p) + 1}", p ++ [actor]}
      
      {:verb, verb}, {q, p} ->
        {q <> " AND verb = $#{length(p) + 1}", p ++ [verb]}
      
      {:verbs, verbs}, {q, p} when is_list(verbs) ->
        placeholders = Enum.map_join(1..length(verbs), ", ", fn i -> "$#{length(p) + i}" end)
        {q <> " AND verb IN (#{placeholders})", p ++ verbs}
      
      {:date_from, date}, {q, p} ->
        {q <> " AND published >= $#{length(p) + 1}", p ++ [date]}
      
      {:date_to, date}, {q, p} ->
        {q <> " AND published <= $#{length(p) + 1}", p ++ [date]}
      
      {:preserve, categories}, {q, p} when is_list(categories) ->
        {q <> " AND metadata->>'preserve' @> $#{length(p) + 1}", p ++ [Jason.encode!(categories)]}
      
      {:seven_p, categories}, {q, p} when is_list(categories) ->
        {q <> " AND metadata->>'seven_p' @> $#{length(p) + 1}", p ++ [Jason.encode!(categories)]}
      
      _, acc -> acc
    end)
  end
  
  defp keyword_search(query_text, tenant_id, opts) do
    schema_name = "tenant_#{tenant_id}"
    top_k = opts[:top_k] || @default_top_k
    
    # Use PostgreSQL full-text search
    case Ecto.Adapters.SQL.query(
      Przma.Repo,
      """
      SELECT 
        id,
        actor,
        verb,
        object,
        target,
        published,
        metadata,
        ts_rank(
          to_tsvector('english', object::text),
          plainto_tsquery('english', $1)
        ) as rank_score
      FROM #{schema_name}.activities
      WHERE to_tsvector('english', object::text) @@ plainto_tsquery('english', $1)
      ORDER BY rank_score DESC
      LIMIT $2
      """,
      [query_text, top_k]
    ) do
      {:ok, %{rows: rows, columns: columns}} ->
        Enum.map(rows, fn row ->
          parse_search_result(columns, row)
        end)
      
      _ -> []
    end
  end
  
  defp merge_search_results(vector_results, keyword_results) do
    # Combine results by ID and average scores
    all_results = vector_results ++ keyword_results
    
    all_results
    |> Enum.group_by(& &1.id)
    |> Enum.map(fn {_id, results} ->
      # Average the scores if result appears in both
      avg_score = Enum.reduce(results, 0.0, fn r, acc -> 
        acc + (r.similarity_score || 0.0)
      end) / length(results)
      
      %{List.first(results) | similarity_score: avg_score}
    end)
    |> Enum.sort_by(& &1.similarity_score, :desc)
  end
  
  defp parse_search_result(columns, row) do
    result = Enum.zip(columns, row) |> Enum.into(%{})
    
    %SearchResult{
      id: result["id"],
      content: Jason.decode!(result["object"]),
      similarity_score: result["similarity_score"] || result["rank_score"],
      metadata: Jason.decode!(result["metadata"]),
      activity: %{
        actor: result["actor"],
        verb: result["verb"],
        published: result["published"]
      }
    }
  end
  
  defp format_vector(embedding) when is_list(embedding) do
    "[#{Enum.join(embedding, ",")}]"
  end
  
  defp parse_vector(vector_str) when is_binary(vector_str) do
    vector_str
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(",")
    |> Enum.map(&String.to_float/1)
  end
end

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
