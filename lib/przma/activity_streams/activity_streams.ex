defmodule Przma.ActivityStreams do
  @moduledoc """
  ActivityStreams 2.0 integration for PRZMA platform.

  Provides:
  - W3C ActivityStreams 2.0 vocabulary
  - 60+ verbs with automatic PRESERVE/7P mapping
  - Natural language parsing to structured activities
  - CouchDB and PostgreSQL storage
  """

  alias Przma.ActivityStreams.{VerbMapping, NaturalLanguageParser}

  defmodule Activity do
    @derive {Jason.Encoder, only: [:id, :type, :actor, :verb, :object, :target, :published, :context, :preserve, :seven_p, :perception_enrichment]}
    defstruct [
      :id,
      :type,
      :actor,
      :verb,
      :object,
      :target,
      :published,
      :context,
      :preserve,
      :seven_p,
      :perception_enrichment
    ]
  end

  @doc """
  Create a new activity from structured data.

  ## Examples

      iex> Przma.ActivityStreams.create_activity(%{
      ...>   actor: "user:123",
      ...>   verb: "learn",
      ...>   object: %{type: "Course", name: "Elixir Programming"}
      ...> })
      {:ok, %Activity{}}
  """
  def create_activity(attrs, tenant_id) do
    activity = %Activity{
      id: generate_activity_id(),
      type: "Activity",
      actor: attrs[:actor],
      verb: attrs[:verb],
      object: attrs[:object],
      target: attrs[:target],
      published: DateTime.utc_now(),
      context: %{
        tenant_id: tenant_id,
        application: "przma"
      }
    }

    # Add automatic mappings
    activity = activity
    |> add_preserve_mapping()
    |> add_seven_p_mapping()

    # Store in both databases
    with {:ok, _} <- store_in_couchdb(activity, tenant_id),
         {:ok, _} <- store_in_postgres(activity, tenant_id) do
      {:ok, activity}
    end
  end

  @doc """
  Parse natural language into an activity.

  ## Examples

      iex> Przma.ActivityStreams.parse_natural_language(
      ...>   "I attended the Elixir conference today",
      ...>   "user:123",
      ...>   "tenant_a"
      ...> )
      {:ok, %Activity{verb: "attend", object: %{type: "Event", name: "Elixir conference"}}}
  """
  def parse_natural_language(text, actor, tenant_id) do
    case NaturalLanguageParser.parse(text) do
      {:ok, parsed} ->
        create_activity(
          Map.merge(parsed, %{actor: actor}),
          tenant_id
        )

      error -> error
    end
  end

  @doc """
  Get activities with filters.
  """
  def get_activities(tenant_id, filters \\ %{}) do
    # Query from PostgreSQL for fast filtering
    query_postgres_activities(tenant_id, filters)
  end

  @doc """
  Update an existing activity.
  """
  def update_activity(activity_id, updates, tenant_id) do
    with {:ok, activity} <- get_activity(activity_id, tenant_id),
         updated <- Map.merge(activity, updates),
         {:ok, _} <- store_in_couchdb(updated, tenant_id),
         {:ok, _} <- store_in_postgres(updated, tenant_id) do
      {:ok, updated}
    end
  end

  @doc """
  Delete an activity.
  """
  def delete_activity(activity_id, tenant_id) do
    with :ok <- delete_from_couchdb(activity_id, tenant_id),
         :ok <- delete_from_postgres(activity_id, tenant_id) do
      :ok
    end
  end

  # Private Functions

  defp add_preserve_mapping(activity) do
    preserve_categories = VerbMapping.verb_to_preserve(activity.verb)
    %{activity | preserve: preserve_categories}
  end

  defp add_seven_p_mapping(activity) do
    seven_p_categories = VerbMapping.verb_to_seven_p(activity.verb)
    %{activity | seven_p: seven_p_categories}
  end

  defp store_in_couchdb(activity, tenant_id) do
    database_name = "przma_#{tenant_id}"

    # Prepare document for CouchDB
    doc = activity
    |> Map.from_struct()
    |> Map.put("_id", activity.id)
    |> Map.put("type", "activity")

    case HTTPoison.post(
      "#{couchdb_url()}/#{database_name}",
      Jason.encode!(doc),
      [{"Content-Type", "application/json"}],
      [hackney: [basic_auth: couchdb_credentials()]]
    ) do
      {:ok, %{status_code: 201}} -> {:ok, activity}
      error -> {:error, error}
    end
  end

  defp store_in_postgres(activity, tenant_id) do
    schema_name = "tenant_#{tenant_id}"

    Ecto.Adapters.SQL.query(
      Przma.Repo,
      """
      INSERT INTO #{schema_name}.activities
        (id, actor, verb, object, target, published, metadata)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      ON CONFLICT (id) DO UPDATE SET
        actor = EXCLUDED.actor,
        verb = EXCLUDED.verb,
        object = EXCLUDED.object,
        target = EXCLUDED.target,
        metadata = EXCLUDED.metadata
      """,
      [
        activity.id,
        activity.actor,
        activity.verb,
        Jason.encode!(activity.object),
        Jason.encode!(activity.target),
        activity.published,
        Jason.encode!(%{
          preserve: activity.preserve,
          seven_p: activity.seven_p,
          context: activity.context
        })
      ]
    )
  end

  defp query_postgres_activities(tenant_id, filters) do
    schema_name = "tenant_#{tenant_id}"

    base_query = "SELECT * FROM #{schema_name}.activities WHERE 1=1"

    {query, params} = build_filter_query(base_query, filters)

    case Ecto.Adapters.SQL.query(Przma.Repo, query, params) do
      {:ok, %{rows: rows, columns: columns}} ->
        activities = Enum.map(rows, fn row ->
          Enum.zip(columns, row)
          |> Enum.into(%{})
          |> parse_activity_row()
        end)

        {:ok, activities}

      error -> {:error, error}
    end
  end

  defp build_filter_query(base_query, filters) do
    Enum.reduce(filters, {base_query, []}, fn
      {:actor, actor}, {query, params} ->
        {query <> " AND actor = $#{length(params) + 1}", params ++ [actor]}

      {:verb, verb}, {query, params} ->
        {query <> " AND verb = $#{length(params) + 1}", params ++ [verb]}

      {:date_from, date}, {query, params} ->
        {query <> " AND published >= $#{length(params) + 1}", params ++ [date]}

      {:date_to, date}, {query, params} ->
        {query <> " AND published <= $#{length(params) + 1}", params ++ [date]}

      _, acc -> acc
    end)
  end

  defp parse_activity_row(row) do
    %Activity{
      id: row["id"],
      type: "Activity",
      actor: row["actor"],
      verb: row["verb"],
      object: Jason.decode!(row["object"]),
      target: if(row["target"], do: Jason.decode!(row["target"]), else: nil),
      published: row["published"],
      context: Jason.decode!(row["metadata"])["context"],
      preserve: Jason.decode!(row["metadata"])["preserve"],
      seven_p: Jason.decode!(row["metadata"])["seven_p"]
    }
  end

  defp get_activity(activity_id, tenant_id) do
    schema_name = "tenant_#{tenant_id}"

    case Ecto.Adapters.SQL.query(
      Przma.Repo,
      "SELECT * FROM #{schema_name}.activities WHERE id = $1",
      [activity_id]
    ) do
      {:ok, %{rows: [row], columns: columns}} ->
        activity = Enum.zip(columns, row)
        |> Enum.into(%{})
        |> parse_activity_row()

        {:ok, activity}

      {:ok, %{rows: []}} -> {:error, :not_found}
      error -> {:error, error}
    end
  end

  defp delete_from_couchdb(activity_id, tenant_id) do
    database_name = "przma_#{tenant_id}"

    # Get current revision first
    case HTTPoison.get(
      "#{couchdb_url()}/#{database_name}/#{activity_id}",
      [],
      [hackney: [basic_auth: couchdb_credentials()]]
    ) do
      {:ok, %{status_code: 200, body: body}} ->
        doc = Jason.decode!(body)
        rev = doc["_rev"]

        HTTPoison.delete(
          "#{couchdb_url()}/#{database_name}/#{activity_id}?rev=#{rev}",
          [],
          [hackney: [basic_auth: couchdb_credentials()]]
        )

        :ok

      _ -> {:error, :not_found}
    end
  end

  defp delete_from_postgres(activity_id, tenant_id) do
    schema_name = "tenant_#{tenant_id}"

    case Ecto.Adapters.SQL.query(
      Przma.Repo,
      "DELETE FROM #{schema_name}.activities WHERE id = $1",
      [activity_id]
    ) do
      {:ok, _} -> :ok
      error -> {:error, error}
    end
  end

  defp generate_activity_id do
    "activity:#{Ecto.UUID.generate()}"
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
