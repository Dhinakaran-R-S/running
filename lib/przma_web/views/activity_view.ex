defmodule PrzmaWeb.ActivityView do
  @moduledoc """
  JSON view for ActivityStreams activities.
  """
  
  use PrzmaWeb, :view
  
  alias PrzmaWeb.ActivityView
  
  def render("index.json", %{activities: activities}) do
    %{
      data: render_many(activities, ActivityView, "activity.json"),
      count: length(activities)
    }
  end
  
  def render("show.json", %{activity: activity}) do
    %{data: render_one(activity, ActivityView, "activity.json")}
  end
  
  def render("activity.json", %{activity: activity}) do
    %{
      id: activity.id,
      type: activity.type || "Activity",
      actor: activity.actor,
      verb: activity.verb,
      object: activity.object,
      target: activity.target,
      published: activity.published,
      
      # Framework mappings
      preserve: activity.preserve,
      seven_p: activity.seven_p,
      
      # AI enrichment (if available)
      perception_enrichment: render_enrichment(activity.perception_enrichment),
      synthesis: activity.synthesis,
      
      # Metadata
      context: activity.context,
      embedding_generated: activity.embedding != nil,
      
      timestamps: %{
        created_at: activity.inserted_at,
        updated_at: activity.updated_at
      }
    }
  end
  
  def render("search.json", %{results: results}) do
    %{
      data: Enum.map(results, &render_search_result/1),
      count: length(results)
    }
  end
  
  defp render_search_result(result) do
    %{
      id: result.id,
      similarity_score: result.similarity_score,
      activity: %{
        actor: result.activity.actor,
        verb: result.activity.verb,
        published: result.activity.published
      },
      content: result.content,
      metadata: result.metadata
    }
  end
  
  defp render_enrichment(nil), do: nil
  defp render_enrichment(enrichment) when is_map(enrichment) do
    enrichment
    |> Enum.map(fn {module, data} -> {module, sanitize_enrichment(data)} end)
    |> Enum.into(%{})
  end
  
  defp sanitize_enrichment(data) when is_map(data) do
    # Remove any sensitive or overly verbose data
    Map.take(data, [:primary_emotion, :consciousness_level, :key_insights, 
                     :behavior_pattern, :growth_indicators])
  end
  defp sanitize_enrichment(data), do: data
end
