defmodule Przma.Auth.Session do
  @moduledoc """
  User session management.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Przma.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sessions" do
    belongs_to :user, Przma.Auth.User

    field :token_hash, :string
    field :ip_address, :string
    field :user_agent, :string
    field :device_id, :string
    field :status, Ecto.Enum, values: [:active, :expired, :revoked], default: :active
    field :last_active_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :metadata, :map, default: %{}

    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:user_id, :token_hash, :ip_address, :user_agent, :device_id, :expires_at, :metadata])
    |> validate_required([:user_id, :expires_at])
  end

  def create(user, opts \\ []) do
    attrs = %{
      user_id: user.id,
      token_hash: generate_token_hash(),
      ip_address: opts[:ip_address],
      user_agent: opts[:user_agent],
      device_id: opts[:device_id],
      expires_at: DateTime.utc_now() |> DateTime.add(604_800, :second),  # 7 days
      last_active_at: DateTime.utc_now(),
      metadata: opts[:metadata] || %{}
    }

    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def get(session_id) do
    case Repo.get(__MODULE__, session_id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  def valid?(session) do
    session.status == :active &&
    DateTime.compare(session.expires_at, DateTime.utc_now()) == :gt
  end

  def revoke(session_id) do
    from(s in __MODULE__, where: s.id == ^session_id)
    |> Repo.update_all(set: [status: :expired])

    :ok
  end

  def revoke_all(user_id) do
    from(s in __MODULE__, where: s.user_id == ^user_id and s.status == :active)
    |> Repo.update_all(set: [status: :revoked])

    :ok
  end

  defp generate_token_hash do
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end
end
