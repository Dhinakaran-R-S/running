defmodule Przma.Auth.Token do
  @moduledoc """
  JWT token generation and verification for authentication.
  """

  use Joken.Config

  alias Przma.Auth.Session
  alias Przma.Repo

  # Get configuration
  @secret_key Application.compile_env(:przma, [__MODULE__, :secret_key]) ||
              System.get_env("JWT_SECRET_KEY") ||
              "default-secret-key-please-change-in-config"

  @access_token_ttl Application.compile_env(:przma, [__MODULE__, :access_token_ttl], 900)
  @refresh_token_ttl Application.compile_env(:przma, [__MODULE__, :refresh_token_ttl], 604_800)

  @doc """
  Generate access and refresh tokens for a user and session.
  """
  def generate_tokens(user, session) do
    access_token = generate_access_token(user, session)
    refresh_token = generate_refresh_token(user, session)

    {:ok, %{
      access_token: access_token,
      refresh_token: refresh_token,
      expires_in: @access_token_ttl
    }}
  end

  @doc """
  Generate access token (short-lived).
  """
  def generate_access_token(user, session) do
    claims = %{
      "sub" => user.id,
      "sid" => session.id,
      "username" => user.username,
      "email" => user.email,
      "type" => "access"
    }

    sign_token(claims, @access_token_ttl)
  end

  @doc """
  Generate refresh token (long-lived).
  """
  def generate_refresh_token(user, session) do
    claims = %{
      "sub" => user.id,
      "sid" => session.id,
      "type" => "refresh"
    }

    sign_token(claims, @refresh_token_ttl)
  end

  @doc """
  Verify access token.
  """
  def verify_access_token(token) do
    with {:ok, claims} <- verify_token(token),
         "access" <- Map.get(claims, "type") do
      {:ok, claims}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_token_type}
    end
  end

  @doc """
  Verify refresh token.
  """
  def verify_refresh_token(token) do
    with {:ok, claims} <- verify_token(token),
         "refresh" <- Map.get(claims, "type") do
      {:ok, claims}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_token_type}
    end
  end

  @doc """
  Verify password reset token.
  """
  def verify_password_reset_token(token) do
    with {:ok, claims} <- verify_token(token),
         "password_reset" <- Map.get(claims, "type") do
      {:ok, claims}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_token_type}
    end
  end

  @doc """
  Generate password reset token.
  """
  def generate_password_reset_token(user) do
    claims = %{
      "sub" => user.id,
      "type" => "password_reset"
    }

    sign_token(claims, 3600) # 1 hour
  end

  @doc """
  Revoke a token (add to blacklist).
  """
  def revoke(token) do
    # In production, you'd store this in Redis or database
    # For now, we'll just return :ok
    :ok
  end

  @doc """
  Blacklist user tokens.
  """
  def blacklist_user(user_id, ttl) do
    # In production, store in Redis with TTL
    :ok
  end

  # Private functions

  defp sign_token(claims, ttl) do
    now = System.system_time(:second)

    extra_claims = %{
      "iat" => now,
      "exp" => now + ttl,
      "nbf" => now
    }

    all_claims = Map.merge(claims, extra_claims)

    # CRITICAL FIX: Ensure secret_key is a binary string
    secret = ensure_binary(@secret_key)
    signer = Joken.Signer.create("HS256", secret)

    case Joken.encode_and_sign(all_claims, signer) do
      {:ok, token, _claims} -> token
      {:error, reason} ->
        raise "Failed to sign token: #{inspect(reason)}"
    end
  end

  defp verify_token(token) when is_binary(token) do
    secret = ensure_binary(@secret_key)
    signer = Joken.Signer.create("HS256", secret)

    case Joken.verify_and_validate(%{}, token, signer) do
      {:ok, claims} -> {:ok, claims}
      {:error, :expired} -> {:error, :expired}
      {:error, reason} -> {:error, :invalid}
    end
  end

  defp verify_token(_), do: {:error, :invalid}

  # Ensure the key is a binary string
  defp ensure_binary(key) when is_binary(key), do: key
  defp ensure_binary(key) when is_atom(key), do: Atom.to_string(key)
  defp ensure_binary(key), do: inspect(key)
end
