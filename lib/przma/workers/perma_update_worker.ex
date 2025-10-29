defmodule Przma.Workers.PermaUpdateWorker do
  @moduledoc """
  Worker to calculate and update PERMA scores.

  Runs every 15 minutes via Oban cron.
  """

  use Oban.Worker,
    queue: :analytics,
    max_attempts: 2,
    priority: 3

  alias Przma.{Repo, ActivityStreams}
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Updating PERMA scores")

    # Get organizations that need PERMA updates
    organizations = Repo.all(from o in Przma.Schemas.Organization, where: o.status == :active)

    Enum.each(organizations, fn org ->
      update_org_perma_scores(org)
    end)

    :ok
  end

  defp update_org_perma_scores(organization) do
    # Calculate PERMA scores for each member
    members = Przma.Accounts.list_members(organization.id)

    Enum.each(members, fn member ->
      # Get recent activities (last 30 days)
      {:ok, activities} = ActivityStreams.get_activities(organization.id, %{
        actor: member.id,
        from_date: DateTime.utc_now() |> DateTime.add(-30, :day)
      })

      perma_score = calculate_perma_score(activities)

      # Update member metadata
      metadata = Map.put(member.metadata || %{}, "perma_score", perma_score)
      Przma.Accounts.update_member(member, %{metadata: metadata})
    end)
  end

  defp calculate_perma_score(activities) do
    %{
      positive_emotion: calculate_p_score(activities),
      engagement: calculate_e_score(activities),
      relationships: calculate_r_score(activities),
      meaning: calculate_m_score(activities),
      accomplishment: calculate_a_score(activities),
      overall: 0.0  # Will be calculated from above
    }
    |> calculate_overall()
  end

  defp calculate_p_score(activities) do
    # Analyze positive emotions from enrichment data
    positive_count = Enum.count(activities, fn act ->
      case act.perception_enrichment do
        %{"emotional_intelligence" => %{"primary_emotion" => emotion}} ->
          emotion in ["joy", "gratitude", "contentment", "excitement"]
        _ -> false
      end
    end)

    if length(activities) > 0, do: positive_count / length(activities) * 10, else: 0.0
  end

  defp calculate_e_score(activities) do
    # Count engaging activities
    engaging_verbs = ["learn", "create", "practice", "exercise"]
    engaging_count = Enum.count(activities, fn act -> act.verb in engaging_verbs end)

    if length(activities) > 0, do: engaging_count / length(activities) * 10, else: 0.0
  end

  defp calculate_r_score(activities) do
    # Count relationship activities
    relationship_verbs = ["share", "meet", "help", "support", "collaborate"]
    relationship_count = Enum.count(activities, fn act -> act.verb in relationship_verbs end)

    if length(activities) > 0, do: relationship_count / length(activities) * 10, else: 0.0
  end

  defp calculate_m_score(activities) do
    # Check for meaning-related PRESERVE categories
    meaning_preserve = ["purpose", "excellence"]
    meaning_count = Enum.count(activities, fn act ->
      Enum.any?(act.preserve, &(&1 in meaning_preserve))
    end)

    if length(activities) > 0, do: meaning_count / length(activities) * 10, else: 0.0
  end

  defp calculate_a_score(activities) do
    # Count accomplishment activities
    accomplishment_verbs = ["complete", "achieve", "improve"]
    accomplishment_count = Enum.count(activities, fn act -> act.verb in accomplishment_verbs end)

    if length(activities) > 0, do: accomplishment_count / length(activities) * 10, else: 0.0
  end

  defp calculate_overall(scores) do
    overall = (scores.positive_emotion + scores.engagement + scores.relationships +
               scores.meaning + scores.accomplishment) / 5

    Map.put(scores, :overall, Float.round(overall, 2))
  end
end
