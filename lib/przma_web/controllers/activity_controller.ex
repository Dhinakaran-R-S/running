defmodule PrzmaWeb.ActivityController do
  @moduledoc """
  REST API controller for ActivityStreams activities.
  
  Handles CRUD operations for activities with proper tenant isolation.
  """
  
  use PrzmaWeb, :controller
  
  alias Przma.{ActivityStreams, Repo}
  alias Przma.AI.VectorStore
  alias PrzmaWeb.ErrorView
  
  action_fallback PrzmaWeb.FallbackController
  
  @doc """
  List activities for current tenant.
  
  Query params:
  - actor: Filter by actor ID
  - verb: Filter by verb
  - preserve: Filter by PRESERVE categories
  - seven_p: Filter by 7P categories
  - from_date: Filter from date
  - to_date: Filter to date
  - limit: Number of results (default 20, max 100)
  """
  def index(conn, params) do
    tenant_id = conn.assigns.current_tenant_id
    
    filters = %{
      actor: params["actor"],
      verb: params["verb"],
      preserve: params["preserve"],
      seven_p: params["seven_p"],
      from_date: parse_date(params["from_date"]),
      to_date: parse_date(params["to_date"]),
      limit: min(String.to_integer(params["limit"] || "20"), 100)
    }
    |> Enum.filter(fn {_k, v} -> v != nil end)
    |> Enum.into(%{})
    
    case ActivityStreams.get_activities(tenant_id, filters) do
      {:ok, activities} ->
        render(conn, "index.json", activities: activities)
      
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> render(ErrorView, "error.json", error: reason)
    end
  end
  
  @doc """
  Get a specific activity by ID.
  """
  def show(conn, %{"id" => id}) do
    tenant_id = conn.assigns.current_tenant_id
    
    case ActivityStreams.get_activity(id, tenant_id) do
      {:ok, activity} ->
        render(conn, "show.json", activity: activity)
      
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(ErrorView, "error.json", error: "Activity not found")
    end
  end
  
  @doc """
  Create new activity from structured data.
  """
  def create(conn, %{"activity" => activity_params}) do
    tenant_id = conn.assigns.current_tenant_id
    actor = conn.assigns.current_user_id
    
    params = Map.put(activity_params, "actor", actor)
    
    case ActivityStreams.create_activity(params, tenant_id) do
      {:ok, activity} ->
        # Enqueue for enrichment
        Przma.ActivityStreams.Pipeline.enqueue_activity(activity)
        
        conn
        |> put_status(:created)
        |> render("show.json", activity: activity)
      
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ErrorView, "error.json", changeset: changeset)
    end
  end
  
  @doc """
  Create activity from natural language.
  """
  def create_from_text(conn, %{"text" => text}) do
    tenant_id = conn.assigns.current_tenant_id
    actor = conn.assigns.current_user_id
    
    case ActivityStreams.parse_natural_language(text, actor, tenant_id) do
      {:ok, activity} ->
        # Enqueue for enrichment
        Przma.ActivityStreams.Pipeline.enqueue_activity(activity)
        
        conn
        |> put_status(:created)
        |> render("show.json", activity: activity)
      
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ErrorView, "error.json", error: reason)
    end
  end
  
  @doc """
  Update an activity.
  """
  def update(conn, %{"id" => id, "activity" => activity_params}) do
    tenant_id = conn.assigns.current_tenant_id
    
    case ActivityStreams.update_activity(id, activity_params, tenant_id) do
      {:ok, activity} ->
        render(conn, "show.json", activity: activity)
      
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(ErrorView, "error.json", error: "Activity not found")
      
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ErrorView, "error.json", changeset: changeset)
    end
  end
  
  @doc """
  Delete an activity.
  """
  def delete(conn, %{"id" => id}) do
    tenant_id = conn.assigns.current_tenant_id
    
    case ActivityStreams.delete_activity(id, tenant_id) do
      :ok ->
        send_resp(conn, :no_content, "")
      
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(ErrorView, "error.json", error: "Activity not found")
    end
  end
  
  @doc """
  Search activities using semantic search.
  """
  def search(conn, %{"query" => query}) do
    tenant_id = conn.assigns.current_tenant_id
    
    # Generate embedding for query
    case Przma.AI.LocalInference.generate_embeddings(query) do
      {:ok, embedding} ->
        filters = %{
          top_k: String.to_integer(conn.params["limit"] || "10"),
          similarity_threshold: String.to_float(conn.params["threshold"] || "0.7"),
          filters: build_search_filters(conn.params)
        }
        
        case VectorStore.similarity_search(embedding, tenant_id, filters) do
          {:ok, results} ->
            render(conn, "search.json", results: results)
          
          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> render(ErrorView, "error.json", error: reason)
        end
      
      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> render(ErrorView, "error.json", error: reason)
    end
  end
  
  @doc """
  Get enrichment status for an activity.
  """
  def enrichment_status(conn, %{"id" => id}) do
    tenant_id = conn.assigns.current_tenant_id
    
    case ActivityStreams.get_activity(id, tenant_id) do
      {:ok, activity} ->
        status = %{
          activity_id: id,
          has_enrichment: activity.perception_enrichment != nil,
          has_embedding: activity.embedding != nil,
          enrichment_modules: get_enrichment_modules(activity),
          synthesis: activity.synthesis
        }
        
        json(conn, status)
      
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(ErrorView, "error.json", error: "Activity not found")
    end
  end
  
  # Private Functions
  
  defp parse_date(nil), do: nil
  defp parse_date(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end
  
  defp build_search_filters(params) do
    %{}
    |> maybe_add_filter(:verb, params["verb"])
    |> maybe_add_filter(:preserve, params["preserve"])
    |> maybe_add_filter(:seven_p, params["seven_p"])
    |> maybe_add_filter(:date_from, parse_date(params["from_date"]))
    |> maybe_add_filter(:date_to, parse_date(params["to_date"]))
  end
  
  defp maybe_add_filter(filters, _key, nil), do: filters
  defp maybe_add_filter(filters, key, value), do: Map.put(filters, key, value)
  
  defp get_enrichment_modules(activity) do
    case activity.perception_enrichment do
      nil -> []
      enrichment -> Map.keys(enrichment)
    end
  end
end
