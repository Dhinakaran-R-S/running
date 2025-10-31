defmodule Przma.Auth.User do
  @moduledoc """
  User schema and functions.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Przma.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :username, :string
    field :email, :string
    field :password_hash, :string
    field :password, :string, virtual: true
    field :tenant_id, :binary_id
    field :status, Ecto.Enum, values: [:active, :inactive, :suspended], default: :active
    field :mfa_enabled, :boolean, default: false
    field :mfa_secret, :string

    many_to_many :roles, Przma.Auth.Role, join_through: "user_roles"
    has_many :sessions, Przma.Auth.Session

    timestamps()
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :password, :tenant_id])
    |> validate_required([:username, :email, :password, :tenant_id])
    |> validate_format(:email, ~r/@/)
    |> validate_length(:password, min: 8)
    |> validate_password_strength()
    |> unique_constraint(:username)
    |> unique_constraint(:email)
    |> hash_password()
  end

  def get(user_id) do
    case Repo.get(__MODULE__, user_id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def get_by_username(username) do
    case Repo.get_by(__MODULE__, username: username) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def get_by_email(email) do
    case Repo.get_by(__MODULE__, email: email) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def verify_password(user, password) do
    Pbkdf2.verify_pass(password, user.password_hash)
  end

  def update_password(user, new_password) do
    user
    |> change()
    |> put_change(:password, new_password)
    |> validate_length(:password, min: 8)
    |> validate_password_strength()
    |> hash_password()
    |> Repo.update()
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password ->
        changeset
        |> put_change(:password_hash, Pbkdf2.hash_pwd_salt(password))
        |> delete_change(:password)
    end
  end

  defp validate_password_strength(changeset) do
    password = get_change(changeset, :password)

    if password do
      cond do
        String.length(password) < 8 ->
          add_error(changeset, :password, "must be at least 8 characters")

        not String.match?(password, ~r/[a-z]/) ->
          add_error(changeset, :password, "must contain lowercase letter")

        not String.match?(password, ~r/[A-Z]/) ->
          add_error(changeset, :password, "must contain uppercase letter")

        not String.match?(password, ~r/[0-9]/) ->
          add_error(changeset, :password, "must contain number")

        true -> changeset
      end
    else
      changeset
    end
  end
end
