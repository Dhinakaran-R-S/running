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

defmodule Przma.ActivityStreams.VerbMapping do
  @moduledoc """
  Maps ActivityStreams verbs to PRESERVE and 7P frameworks.
  """
  
  @verb_mappings %{
    # Presence & Awareness
    "attend" => %{preserve: ["presence"], seven_p: ["places", "people"]},
    "arrive" => %{preserve: ["presence"], seven_p: ["places"]},
    "leave" => %{preserve: ["presence"], seven_p: ["places"]},
    "experience" => %{preserve: ["presence"], seven_p: ["perspectives"]},
    "observe" => %{preserve: ["presence"], seven_p: ["perspectives"]},
    
    # Relationships
    "connect" => %{preserve: ["relationships"], seven_p: ["people"]},
    "meet" => %{preserve: ["relationships"], seven_p: ["people"]},
    "call" => %{preserve: ["relationships"], seven_p: ["people"]},
    "message" => %{preserve: ["relationships"], seven_p: ["people"]},
    "collaborate" => %{preserve: ["relationships"], seven_p: ["people", "progress"]},
    
    # Learning & Enablement
    "learn" => %{preserve: ["enablement"], seven_p: ["pursuits", "progress"]},
    "teach" => %{preserve: ["enablement", "relationships"], seven_p: ["people", "pursuits"]},
    "study" => %{preserve: ["enablement"], seven_p: ["pursuits"]},
    "practice" => %{preserve: ["enablement", "execution"], seven_p: ["pursuits", "progress"]},
    "master" => %{preserve: ["enablement", "excellence"], seven_p: ["pursuits", "progress"]},
    
    # Creation & Stories
    "create" => %{preserve: ["stories", "value_creation"], seven_p: ["portfolio", "progress"]},
    "write" => %{preserve: ["stories"], seven_p: ["portfolio"]},
    "design" => %{preserve: ["stories", "value_creation"], seven_p: ["portfolio"]},
    "build" => %{preserve: ["execution", "value_creation"], seven_p: ["portfolio", "progress"]},
    "publish" => %{preserve: ["stories"], seven_p: ["portfolio"]},
    
    # Execution & Progress
    "complete" => %{preserve: ["execution"], seven_p: ["progress"]},
    "achieve" => %{preserve: ["execution", "excellence"], seven_p: ["progress"]},
    "accomplish" => %{preserve: ["execution"], seven_p: ["progress"]},
    "finish" => %{preserve: ["execution"], seven_p: ["progress"]},
    "deliver" => %{preserve: ["execution", "value_creation"], seven_p: ["progress", "portfolio"]},
    
    # Resources & Value
    "acquire" => %{preserve: ["resources"], seven_p: ["portfolio"]},
    "invest" => %{preserve: ["resources", "value_creation"], seven_p: ["portfolio", "progress"]},
    "save" => %{preserve: ["resources"], seven_p: ["portfolio"]},
    "earn" => %{preserve: ["resources", "value_creation"], seven_p: ["portfolio", "progress"]},
    "purchase" => %{preserve: ["resources"], seven_p: ["portfolio"]},
    
    # Excellence & Growth
    "improve" => %{preserve: ["excellence"], seven_p: ["progress"]},
    "optimize" => %{preserve: ["excellence"], seven_p: ["progress"]},
    "excel" => %{preserve: ["excellence"], seven_p: ["progress"]},
    "refine" => %{preserve: ["excellence"], seven_p: ["progress"]},
    "perfect" => %{preserve: ["excellence"], seven_p: ["progress"]},
    
    # Reflection & Purpose
    "reflect" => %{preserve: ["presence", "stories"], seven_p: ["perspectives", "purpose"]},
    "journal" => %{preserve: ["stories"], seven_p: ["perspectives"]},
    "meditate" => %{preserve: ["presence"], seven_p: ["perspectives"]},
    "contemplate" => %{preserve: ["presence"], seven_p: ["perspectives", "purpose"]},
    "envision" => %{preserve: ["stories"], seven_p: ["purpose"]},
    
    # Sharing & Connection
    "share" => %{preserve: ["relationships", "value_creation"], seven_p: ["people", "portfolio"]},
    "contribute" => %{preserve: ["value_creation", "relationships"], seven_p: ["people", "progress"]},
    "give" => %{preserve: ["value_creation", "relationships"], seven_p: ["people"]},
    "help" => %{preserve: ["relationships", "enablement"], seven_p: ["people"]},
    "support" => %{preserve: ["relationships", "enablement"], seven_p: ["people"]},
    
    # Consumption & Experience
    "read" => %{preserve: ["enablement"], seven_p: ["pursuits"]},
    "watch" => %{preserve: ["presence"], seven_p: ["pursuits"]},
    "listen" => %{preserve: ["presence"], seven_p: ["pursuits"]},
    "consume" => %{preserve: ["presence"], seven_p: ["pursuits"]},
    "enjoy" => %{preserve: ["presence"], seven_p: ["perspectives"]},
    
    # Planning & Strategy
    "plan" => %{preserve: ["stories", "execution"], seven_p: ["progress", "purpose"]},
    "organize" => %{preserve: ["execution"], seven_p: ["progress"]},
    "strategize" => %{preserve: ["stories", "execution"], seven_p: ["purpose", "progress"]},
    "prepare" => %{preserve: ["execution"], seven_p: ["progress"]},
    "schedule" => %{preserve: ["execution"], seven_p: ["progress"]},
    
    # Health & Wellness
    "exercise" => %{preserve: ["presence", "execution"], seven_p: ["pursuits", "progress"]},
    "rest" => %{preserve: ["presence"], seven_p: ["perspectives"]},
    "heal" => %{preserve: ["presence", "excellence"], seven_p: ["progress"]},
    "nourish" => %{preserve: ["presence"], seven_p: ["pursuits"]},
    "relax" => %{preserve: ["presence"], seven_p: ["perspectives"]}
  }
  
  def verb_to_preserve(verb) do
    case Map.get(@verb_mappings, verb) do
      %{preserve: categories} -> categories
      nil -> []
    end
  end
  
  def verb_to_seven_p(verb) do
    case Map.get(@verb_mappings, verb) do
      %{seven_p: categories} -> categories
      nil -> []
    end
  end
  
  def all_verbs do
    Map.keys(@verb_mappings)
  end
  
  def get_mapping(verb) do
    Map.get(@verb_mappings, verb)
  end
end

defmodule Przma.ActivityStreams.NaturalLanguageParser do
  @moduledoc """
  Parses natural language into structured ActivityStreams.
  """
  
  @verb_patterns %{
    ~r/attended|went to|joined/i => "attend",
    ~r/learned|studied|took a course/i => "learn",
    ~r/created|made|built/i => "create",
    ~r/completed|finished|accomplished/i => "complete",
    ~r/met|connected with|talked to/i => "meet",
    ~r/read|reading/i => "read",
    ~r/watched|viewing/i => "watch",
    ~r/exercised|worked out/i => "exercise",
    ~r/reflected|journaled|thought about/i => "reflect",
    ~r/shared|posted|published/i => "share"
  }
  
  def parse(text) do
    verb = extract_verb(text)
    object = extract_object(text, verb)
    
    {:ok, %{
      verb: verb,
      object: object
    }}
  end
  
  defp extract_verb(text) do
    Enum.find_value(@verb_patterns, "experience", fn {pattern, verb} ->
      if String.match?(text, pattern), do: verb
    end)
  end
  
  defp extract_object(text, _verb) do
    # Simple extraction - in production, use NLP library
    # Extract the main noun phrase after the verb
    words = String.split(text, " ")
    object_words = Enum.drop(words, 1)
    
    %{
      type: "Thing",
      name: Enum.join(object_words, " ")
    }
  end
end
