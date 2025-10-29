defmodule Przma.ActivityStreams.Pipeline do
  @moduledoc """
  Broadway pipeline for processing and enriching activities with AI.

  Pipeline stages:
  1. Producer - Receives activities from Phoenix controllers
  2. Processor - Parallelized AI enrichment
  3. Batch Consumer - Stores enriched activities
  """

  use Broadway

  alias Broadway.Message
  alias Przma.Perception.{
    SelfAwareness,
    CulturalSentiment,
    BehavioralIntelligence,
    SensoryPerception,
    Empathy,
    Spiritual,
    Food,
    Wellness,
    Social,
    PERMA,
    Strengths,
    Mindset,
    Narrative,
    Generativity,
    Orchestrator
  }

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {Broadway.DummyProducer, []},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: System.schedulers_online() * 2,
          max_demand: 10
        ]
      ],
      batchers: [
        default: [
          concurrency: 5,
          batch_size: 50,
          batch_timeout: 1000
        ]
      ]
    )
  end

  @doc """
  Enqueue an activity for processing.
  """
  def enqueue_activity(activity) do
    Broadway.test_message(__MODULE__, activity)
  end

  @impl true
  def handle_message(_processor, message, _context) do
    activity = message.data
    member_id = activity["actor"]

    # Get member context
    member = Przma.Accounts.get_member!(member_id)

    # Enrich with all applicable modules
    enriched_activity = activity
    |> enrich_with_self_awareness(member)
    |> enrich_with_sentiment(member)
    |> enrich_with_behavioral(member)
    |> enrich_with_sensory(member)
    |> enrich_with_empathy(member)
    |> enrich_with_spiritual(member)
    |> enrich_with_food(member)
    |> enrich_with_wellness(member)
    |> enrich_with_social(member)
    |> enrich_with_perma(member)
    |> enrich_with_strengths(member)
    |> enrich_with_mindset(member)
    |> enrich_with_narrative(member)
    |> enrich_with_generativity(member)
    |> add_synthesis()

    message
    |> Message.update_data(fn _ -> enriched_activity end)
  end

  @impl true
  def handle_batch(:default, messages, _batch_info, _context) do
    activities = Enum.map(messages, & &1.data)

    # Batch store in both databases
    Task.async(fn -> store_in_couchdb_batch(activities) end)
    Task.async(fn -> store_in_postgres_batch(activities) end)

    # Broadcast updates
    Enum.each(activities, &broadcast_activity/1)

    messages
  end

  # Enrichment Functions

  defp enrich_with_self_awareness(activity, member) do
    enrichment = SelfAwareness.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "self_awareness"], enrichment)
  end

  defp enrich_with_sentiment(activity, member) do
    enrichment = CulturalSentiment.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "sentiment"], enrichment)
  end

  defp enrich_with_behavioral(activity, member) do
    enrichment = BehavioralIntelligence.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "behavioral"], enrichment)
  end

  defp enrich_with_sensory(activity, member) do
    enrichment = SensoryPerception.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "sensory"], enrichment)
  end

  defp enrich_with_empathy(activity, member) do
    enrichment = Empathy.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "empathy"], enrichment)
  end

  defp enrich_with_spiritual(activity, member) do
    enrichment = Spiritual.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "spiritual"], enrichment)
  end

  defp enrich_with_food(activity, member) do
    enrichment = Food.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "food"], enrichment)
  end

  defp enrich_with_wellness(activity, member) do
    enrichment = Wellness.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "wellness"], enrichment)
  end

  defp enrich_with_social(activity, member) do
    enrichment = Social.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "social"], enrichment)
  end

  defp enrich_with_perma(activity, member) do
    enrichment = PERMA.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "perma"], enrichment)
  end

  defp enrich_with_strengths(activity, member) do
    enrichment = Strengths.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "strengths"], enrichment)
  end

  defp enrich_with_mindset(activity, member) do
    enrichment = Mindset.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "mindset"], enrichment)
  end

  defp enrich_with_narrative(activity, member) do
    enrichment = Narrative.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "narrative"], enrichment)
  end

  defp enrich_with_generativity(activity, member) do
    enrichment = Generativity.enrich_activity(activity, member)
    put_in(activity, ["perception_enrichment", "generativity"], enrichment)
  end

  defp add_synthesis(activity) do
    # Orchestrator synthesizes all enrichments
    synthesis = Orchestrator.synthesize(activity)
    Map.put(activity, "synthesis", synthesis)
  end

  defp store_in_couchdb_batch(activities) do
    # Group by tenant for batch operations
    activities
    |> Enum.group_by(& &1["context"]["tenant_id"])
    |> Enum.each(fn {tenant_id, tenant_activities} ->
      database_name = "przma_#{tenant_id}"

      docs = Enum.map(tenant_activities, fn activity ->
        activity
        |> Map.put("_id", activity["id"])
        |> Map.put("type", "activity")
      end)

      HTTPoison.post(
        "#{couchdb_url()}/#{database_name}/_bulk_docs",
        Jason.encode!(%{"docs" => docs}),
        [{"Content-Type", "application/json"}],
        [hackney: [basic_auth: couchdb_credentials()]]
      )
    end)
  end

  defp store_in_postgres_batch(activities) do
    # Group by tenant for batch operations
    activities
    |> Enum.group_by(& &1["context"]["tenant_id"])
    |> Enum.each(fn {tenant_id, tenant_activities} ->
      schema_name = "tenant_#{tenant_id}"

      values = Enum.map_join(tenant_activities, ", ", fn activity ->
        "(
          '#{activity["id"]}',
          '#{activity["actor"]}',
          '#{activity["verb"]}',
          '#{Jason.encode!(activity["object"])}',
          #{if activity["target"], do: "'#{Jason.encode!(activity["target"])}'", else: "NULL"},
          '#{activity["published"]}',
          '#{Jason.encode!(%{
            preserve: activity["preserve"],
            seven_p: activity["seven_p"],
            perception_enrichment: activity["perception_enrichment"]
          })}'
        )"
      end)

      Ecto.Adapters.SQL.query(
        Przma.Repo,
        """
        INSERT INTO #{schema_name}.activities
          (id, actor, verb, object, target, published, metadata)
        VALUES #{values}
        ON CONFLICT (id) DO UPDATE SET
          metadata = EXCLUDED.metadata
        """,
        []
      )
    end)
  end

  defp broadcast_activity(activity) do
    PrzmaWeb.Endpoint.broadcast(
      "activities:#{activity["actor"]}",
      "activity_enriched",
      activity
    )
  end

  defp couchdb_url do
    Application.get_env(:przma, :couchdb_url, "http://localhost:5984")
  end

  defp couchdb_credentials do
    {
      Application.get_env(:przma, :couchdb_user, "admin"),
      Application.get_env(:przma, :couchdb_password, "password")
    }
  end
end
