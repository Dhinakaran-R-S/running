defmodule Przma.Schemas.Activity do
  @moduledoc """
  ActivityStreams 2.0 activity schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "activities" do
    field :type, :string, default: "Activity"
    field :actor_id, :binary_id
    field :verb, :string
    field :object, :map
    field :target, :map
    field :published, :utc_datetime

    # Framework mappings
    field :preserve, {:array, :string}, default: []
    field :seven_p, {:array, :string}, default: []

    # AI enrichment
    field :perception_enrichment, :map
    field :synthesis, :map
    field :embedding, Pgvector.Ecto.Vector

    # Metadata
    field :context, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :organization, Przma.Schemas.Organization

    timestamps()
  end

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [:type, :actor_id, :verb, :object, :target, :published,
                    :preserve, :seven_p, :context, :metadata, :organization_id])
    |> validate_required([:actor_id, :verb, :object, :published, :organization_id])
    |> validate_inclusion(:verb, get_valid_verbs())
  end

  defp get_valid_verbs do
    ~w(attend learn create complete achieve share reflect meet teach practice
       read write watch listen exercise invest save earn purchase improve
       plan organize meditate help support contribute give collaborate)
  end
end
