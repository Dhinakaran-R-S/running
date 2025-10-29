defmodule Przma.Auth.PermissionSchema do
  @moduledoc """
  Permission schema for RBAC.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "permissions" do
    field :name, :string
    field :description, :string
    field :resource, :string
    field :action, :string

    timestamps()
  end

  def changeset(permission, attrs) do
    permission
    |> cast(attrs, [:name, :description, :resource, :action])
    |> validate_required([:name, :resource, :action])
    |> unique_constraint(:name)
  end
end
