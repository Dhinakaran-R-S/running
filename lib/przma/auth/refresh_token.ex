defmodule Przma.Auth.RefreshToken do
  @moduledoc """
  Refresh token storage for revocation support.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "refresh_tokens" do
    field :token, :string
    field :user_id, :binary_id
    field :session_id, :binary_id
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    timestamps(updated_at: false)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:token, :user_id, :session_id, :expires_at, :revoked_at])
    |> validate_required([:token, :user_id, :session_id, :expires_at])
    |> unique_constraint(:token)
  end
end
