defmodule Przma.Auth.User do
  @moduledoc """
  User schema and functions with extended fields.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Przma.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :first_name, :string
    field :last_name, :string
    field :username, :string
    field :email, :string
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true
    field :password_hash, :string
    field :tenant_id, :binary_id
    field :status, Ecto.Enum, values: [:active, :inactive, :suspended], default: :active

    # New additional fields
    field :deleted_at, :utc_datetime
    field :is_active, :boolean, default: true
    field :is_verified, :boolean, default: false
    field :auth_provider, :string, default: "local"
    field :failed_login_attempts, :integer, default: 0
    field :last_login_at, :utc_datetime
    field :password_changed_at, :utc_datetime
    field :mfa_enabled, :boolean, default: false
    field :mfa_secret, :string

    many_to_many :roles, Przma.Auth.Role, join_through: "user_roles"
    has_many :sessions, Przma.Auth.Session

    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: :updated_at)
  end

  # Updated registration changeset
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :first_name,
      :last_name,
      :username,
      :email,
      :password,
      :password_confirmation,
      :tenant_id,
      :auth_provider
    ])
    |> validate_required([:first_name, :last_name, :email, :password, :password_confirmation])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_length(:password, min: 8)
    |> validate_password_confirmation()
    |> validate_password_strength()
    |> unique_constraint(:username)
    |> unique_constraint(:email)
    |> put_default_values()
    |> hash_password()
  end

  # Default values
  defp put_default_values(changeset) do
    changeset
    |> put_change(:is_active, true)
    |> put_change(:is_verified, false)
    |> put_change(:auth_provider, "local")
    |> put_change(:failed_login_attempts, 0)
  end

  # Email-based queries
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

  # Verify password
  def verify_password(user, password) do
    Pbkdf2.verify_pass(password, user.password_hash)
  end

  # Update password logic
  def update_password(user, new_password) do
    user
    |> change()
    |> put_change(:password, new_password)
    |> validate_length(:password, min: 8)
    |> validate_password_strength()
    |> hash_password()
    |> Repo.update()
  end

  # Hash password using Pbkdf2
  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password ->
        changeset
        |> put_change(:password_hash, Pbkdf2.hash_pwd_salt(password))
        |> delete_change(:password)
        |> delete_change(:password_confirmation)
    end
  end

  # Password confirmation check
  defp validate_password_confirmation(changeset) do
    validate_confirmation(changeset, :password, message: "does not match password")
  end

  # Password strength rules
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

        true ->
          changeset
      end
    else
      changeset
    end
  end
end
