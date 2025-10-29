defmodule Przma.Auth.Role do
  @moduledoc """
  Role schema for RBAC.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "roles" do
    field :name, :string
    field :description, :string
    field :level, :integer, default: 0

    many_to_many :permissions, Przma.Auth.PermissionSchema, join_through: "role_permissions"

    timestamps()
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description, :level])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
