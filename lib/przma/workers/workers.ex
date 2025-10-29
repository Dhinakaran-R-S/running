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

defmodule Przma.Workers.NotificationWorker do
  @moduledoc """
  Worker for sending notifications.
  """
  
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    priority: 2
  
  alias Przma.Notifications
  require Logger
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"member_id" => member_id, "type" => type, "data" => data}}) do
    Logger.info("Sending notification to member #{member_id}: #{type}")
    
    case Notifications.send_notification(member_id, type, data) do
      :ok -> :ok
      {:error, reason} ->
        Logger.error("Failed to send notification: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

defmodule Przma.Workers.EmailWorker do
  @moduledoc """
  Worker for sending emails.
  """
  
  use Oban.Worker,
    queue: :emails,
    max_attempts: 5,
    priority: 3
  
  require Logger
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"member_id" => member_id, "type" => type, "data" => data}}) do
    Logger.info("Sending email to member #{member_id}: #{type}")
    
    # TODO: Implement email sending using your preferred email service
    # Example: Przma.Mailer.send_email(member_id, type, data)
    
    :ok
  end
end

defmodule Przma.Workers.PushNotificationWorker do
  @moduledoc """
  Worker for sending push notifications.
  """
  
  use Oban.Worker,
    queue: :push,
    max_attempts: 3,
    priority: 2
  
  require Logger
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"member_id" => _member_id, "type" => type, "data" => _data}}) do
    Logger.info("Sending push notification: #{type}")
    
    # TODO: Implement push notification using FCM/APNS
    # Example: Przma.PushService.send(member_id, type, data)
    
    :ok
  end
end

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

defmodule Przma.Workers.CleanupWorker do
  @moduledoc """
  Scheduled worker for cleaning up old data.
  
  Runs daily at 3 AM via Oban cron.
  """
  
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    priority: 4
  
  alias Przma.Repo
  import Ecto.Query
  require Logger
  
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Running cleanup tasks")
    
    cleanup_expired_sessions()
    cleanup_expired_tokens()
    cleanup_old_audit_logs()
    cleanup_orphaned_cas_objects()
    
    :ok
  end
  
  defp cleanup_expired_sessions do
    cutoff = DateTime.utc_now() |> DateTime.add(-30, :day)
    
    count = from(s in Przma.Auth.Session,
      where: s.expires_at < ^cutoff or s.status == :expired
    )
    |> Repo.delete_all()
    
    Logger.info("Cleaned up #{elem(count, 0)} expired sessions")
  end
  
  defp cleanup_expired_tokens do
    cutoff = DateTime.utc_now()
    
    count = from(t in Przma.Auth.RefreshToken,
      where: t.expires_at < ^cutoff
    )
    |> Repo.delete_all()
    
    Logger.info("Cleaned up #{elem(count, 0)} expired tokens")
  end
  
  defp cleanup_old_audit_logs do
    # Keep audit logs for 1 year
    cutoff = DateTime.utc_now() |> DateTime.add(-365, :day)
    
    count = from(a in Przma.AuditLog,
      where: a.timestamp < ^cutoff and a.severity != :critical
    )
    |> Repo.delete_all()
    
    Logger.info("Cleaned up #{elem(count, 0)} old audit logs")
  end
  
  defp cleanup_orphaned_cas_objects do
    # Remove CAS objects with reference_count = 0 that are older than 7 days
    cutoff = DateTime.utc_now() |> DateTime.add(-7, :day)
    
    count = from(c in Przma.CAS.Object,
      where: c.reference_count == 0 and c.inserted_at < ^cutoff
    )
    |> Repo.delete_all()
    
    Logger.info("Cleaned up #{elem(count, 0)} orphaned CAS objects")
  end
end

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
