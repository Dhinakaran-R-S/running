defmodule Przma.Schemas.Organization do
  @moduledoc """
  Organization (tenant) schema.
  Each organization has complete data isolation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :email, :string
    field :plan, Ecto.Enum, values: [:free, :basic, :professional, :enterprise], default: :free
    field :status, Ecto.Enum, values: [:active, :suspended, :cancelled], default: :active
    field :settings, :map, default: %{}
    field :metadata, :map, default: %{}

    has_many :members, Przma.Schemas.Member
    has_many :activities, Przma.Schemas.Activity

    timestamps()
  end

  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :slug, :email, :plan, :status, :settings, :metadata])
    |> validate_required([:name, :slug, :email])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:slug)
    |> unique_constraint(:email)
  end
end
