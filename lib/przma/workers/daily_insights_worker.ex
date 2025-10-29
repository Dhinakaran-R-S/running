defmodule Przma.Workers.DailyInsightsWorker do
  @moduledoc """
  Scheduled worker that generates daily insights for members.

  Runs daily at 2 AM via Oban cron.
  """

  use Oban.Worker,
    queue: :analytics,
    max_attempts: 2,
    priority: 3

  alias Przma.{Repo, Accounts, ActivityStreams}
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Generating daily insights")

    # Get all active organizations
    organizations = Repo.all(from o in Przma.Schemas.Organization, where: o.status == :active)

    Enum.each(organizations, fn org ->
      generate_org_insights(org)
    end)

    :ok
  end

  defp generate_org_insights(organization) do
    # Get all members
    members = Accounts.list_members(organization.id)

    Enum.each(members, fn member ->
      # Get yesterday's activities
      yesterday = DateTime.utc_now() |> DateTime.add(-1, :day)

      activities = ActivityStreams.get_activities(organization.id, %{
        actor: member.id,
        from_date: yesterday
      })

      if length(elem(activities, 1)) > 0 do
        insights = generate_insights(elem(activities, 1))

        # Send insights notification
        Przma.Notifications.send_notification(member.id, "daily_insights", insights)
      end
    end)
  end

  defp generate_insights(activities) do
    %{
      total_activities: length(activities),
      preserve_coverage: get_preserve_coverage(activities),
      seven_p_coverage: get_seven_p_coverage(activities),
      top_verbs: get_top_verbs(activities),
      growth_areas: identify_growth_areas(activities)
    }
  end

  defp get_preserve_coverage(activities) do
    activities
    |> Enum.flat_map(& &1.preserve)
    |> Enum.uniq()
  end

  defp get_seven_p_coverage(activities) do
    activities
    |> Enum.flat_map(& &1.seven_p)
    |> Enum.uniq()
  end

  defp get_top_verbs(activities) do
    activities
    |> Enum.group_by(& &1.verb)
    |> Enum.map(fn {verb, acts} -> {verb, length(acts)} end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(5)
  end

  defp identify_growth_areas(activities) do
    # Analyze enrichment data to identify growth opportunities
    activities
    |> Enum.filter(& &1.perception_enrichment)
    |> Enum.flat_map(fn activity ->
      activity.perception_enrichment
      |> Map.get("growth_indicators", %{})
      |> Map.get("opportunities", [])
    end)
    |> Enum.uniq()
    |> Enum.take(3)
  end
end
