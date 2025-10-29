defmodule Przma.Schemas.Conversation do
  @moduledoc """
  Conversation schema for messaging.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversations" do
    field :topic, :string
    field :status, Ecto.Enum, values: [:active, :archived, :ended], default: :active
    field :context, :map, default: %{}
    field :metadata, :map, default: %{}
    field :ended_at, :utc_datetime

    belongs_to :organization, Przma.Schemas.Organization
    belongs_to :initiated_by, Przma.Schemas.Member
    belongs_to :ended_by, Przma.Schemas.Member

    has_many :messages, Przma.Schemas.Message
    many_to_many :participants, Przma.Schemas.Member, join_through: "conversation_participants"

    timestamps()
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:topic, :status, :context, :metadata, :organization_id,
                    :initiated_by_id, :ended_by_id, :ended_at])
    |> validate_required([:organization_id, :initiated_by_id])
  end
end
