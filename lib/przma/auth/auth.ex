defmodule Przma.Auth do
  @moduledoc """
  Authentication and authorization system for PRZMA.

  Features:
  - JWT-based authentication with refresh tokens
  - Role-based access control (RBAC)
  - Session management
  - Token revocation and blacklisting
  - Multi-factor authentication (MFA) support
  - Password strength validation
  """

  alias Przma.Auth.{Token, Session, User, Permission}
  alias Przma.Repo
  # import Ecto.Query

  # Token configuration
  @access_token_ttl 900  # 15 minutes
  @refresh_token_ttl 604_800  # 7 days

  @doc """
  Authenticate user with username and password.
  """
  def authenticate(username, password) do
    with {:ok, user} <- User.get_by_username(username),
         true <- User.verify_password(user, password),
         {:ok, session} <- Session.create(user),
         {:ok, tokens} <- Token.generate_tokens(user, session) do
      {:ok, user, tokens}
    else
      false -> {:error, :invalid_credentials}
      error -> error
    end
  end

  @doc """
  Refresh access token using refresh token.
  """
  def refresh_token(refresh_token) do
    with {:ok, claims} <- Token.verify_refresh_token(refresh_token),
         {:ok, user} <- User.get(claims["sub"]),
         {:ok, session} <- Session.get(claims["sid"]),
         true <- Session.valid?(session),
         {:ok, tokens} <- Token.generate_tokens(user, session) do
      # Optionally revoke old refresh token
      Token.revoke(refresh_token)
      {:ok, tokens}
    else
      {:error, :expired} -> {:error, :refresh_token_expired}
      {:error, :invalid} -> {:error, :invalid_refresh_token}
      false -> {:error, :session_invalid}
      error -> error
    end
  end

  @doc """
  Revoke all tokens for a user.
  """
  def revoke_all_tokens(user_id) do
    # Revoke all sessions
    Session.revoke_all(user_id)

    # Add user to blacklist temporarily
    Token.blacklist_user(user_id, @refresh_token_ttl)

    :ok
  end

  @doc """
  Logout user by revoking session.
  """
  def logout(token) do
    case Token.verify_access_token(token) do
      {:ok, claims} ->
        Session.revoke(claims["sid"])
        Token.revoke(token)
        :ok

      error -> error
    end
  end

  @doc """
  Check if user has permission.
  """
  def authorize(user, permission) do
    case Permission.user_has_permission?(user, permission) do
      true -> :ok
      false -> {:error, :unauthorized}
    end
  end

  @doc """
  Check if user has role.
  """
  def has_role?(user, role) do
    user
    |> Repo.preload(:roles)
    |> Map.get(:roles, [])
    |> Enum.any?(&(&1.name == to_string(role)))
  end

  @doc """
  Register new user.
  """
  def register(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Change user password.
  """
  def change_password(user, current_password, new_password) do
    with true <- User.verify_password(user, current_password),
         {:ok, user} <- User.update_password(user, new_password) do
      # Revoke all existing sessions
      revoke_all_tokens(user.id)
      {:ok, user}
    else
      false -> {:error, :invalid_current_password}
      error -> error
    end
  end

  @doc """
  Request password reset.
  """
  def request_password_reset(email) do
    case User.get_by_email(email) do
      {:ok, user} ->
        token = Token.generate_password_reset_token(user)

        # Send email with token
        # Przma.Mailer.send_password_reset_email(user, token)

        {:ok, token}

      {:error, :not_found} ->
        # Don't reveal if email exists
        :ok
    end
  end

  @doc """
  Reset password with token.
  """
  def reset_password(token, new_password) do
    with {:ok, claims} <- Token.verify_password_reset_token(token),
         {:ok, user} <- User.get(claims["sub"]),
         {:ok, user} <- User.update_password(user, new_password) do
      # Revoke all sessions
      revoke_all_tokens(user.id)
      {:ok, user}
    end
  end
end
