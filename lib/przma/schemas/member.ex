defmodule Przma.Schemas.Member do
  @moduledoc """
  Member (user) schema within an organization.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "members" do
    field :name, :string
    field :email, :string
    field :username, :string
    field :status, Ecto.Enum, values: [:active, :inactive, :suspended], default: :active
    field :metadata, :map, default: %{}

    belongs_to :organization, Przma.Schemas.Organization
    many_to_many :roles, Przma.Auth.Role, join_through: "member_roles"
    has_many :activities, Przma.Schemas.Activity, foreign_key: :actor_id

    timestamps()
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:name, :email, :username, :organization_id, :status, :metadata])
    |> validate_required([:name, :email, :organization_id])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint([:email, :organization_id])
    |> unique_constraint([:username, :organization_id])
  end
end
