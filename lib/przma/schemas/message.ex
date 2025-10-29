defmodule Przma.Schemas.Message do
  @moduledoc """
  Message schema within a conversation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field :role, Ecto.Enum, values: [:user, :assistant, :system], default: :user
    field :content, :string
    field :content_type, :string, default: "text"
    field :metadata, :map, default: %{}
    field :sent_at, :utc_datetime

    belongs_to :conversation, Przma.Schemas.Conversation
    belongs_to :member, Przma.Schemas.Member

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :content_type, :metadata, :sent_at,
                    :conversation_id, :member_id])
    |> validate_required([:content, :conversation_id, :sent_at])
    |> validate_length(:content, max: 10000)
  end
end
