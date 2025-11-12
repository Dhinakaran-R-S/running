defmodule Przma.Auth.Token do
  @moduledoc """
  JWT token generation and verification.
  """

  use Joken.Config
  import Joken, except: [current_time: 0]

  @signing_algorithm "HS256"
  @access_token_ttl 900
  @refresh_token_ttl 604_800
  @password_reset_ttl 3600

  def generate_tokens(user, session) do
    access_token = generate_access_token(user, session)
    refresh_token = generate_refresh_token(user, session)

    {:ok, %{
      access_token: access_token,
      refresh_token: refresh_token,
      token_type: "Bearer",
      expires_in: @access_token_ttl
    }}
  end

  def generate_access_token(user, session) do
    claims = %{
      "sub" => user.id,
      "sid" => session.id,
      "tenant_id" => user.tenant_id,
      # "roles" => get_user_roles(user),
      "roles" => [],
      # "permissions" => get_user_permissions(user),
      "permissions" => [],
      "type" => "access",
      "iat" => current_time(),
      "exp" => current_time() + @access_token_ttl,
      "jti" => generate_jti()
    }

    sign_token(claims)
  end

  def generate_refresh_token(user, session) do
    claims = %{
      "sub" => user.id,
      "sid" => session.id,
      "tenant_id" => user.tenant_id,
      "type" => "refresh",
      "iat" => current_time(),
      "exp" => current_time() + @refresh_token_ttl,
      "jti" => generate_jti()
    }

    token = sign_token(claims)

    # Store refresh token for revocation
    store_refresh_token(token, user.id, session.id)

    token
  end

  def generate_password_reset_token(user) do
    claims = %{
      "sub" => user.id,
      "type" => "password_reset",
      "iat" => current_time(),
      "exp" => current_time() + @password_reset_ttl,
      "jti" => generate_jti()
    }

    sign_token(claims)
  end

  def verify_access_token(token) do
    with {:ok, claims} <- verify_token(token),
         true <- claims["type"] == "access",
         false <- is_revoked?(token) do
      {:ok, claims}
    else
      false -> {:error, :invalid_token_type}
      true -> {:error, :revoked}
      error -> error
    end
  end

  def verify_refresh_token(token) do
    with {:ok, claims} <- verify_token(token),
         true <- claims["type"] == "refresh",
         false <- is_revoked?(token) do
      {:ok, claims}
    else
      false -> {:error, :invalid_token_type}
      true -> {:error, :revoked}
      error -> error
    end
  end

  def verify_password_reset_token(token) do
    with {:ok, claims} <- verify_token(token),
         true <- claims["type"] == "password_reset",
         false <- is_revoked?(token) do
      {:ok, claims}
    else
      false -> {:error, :invalid_token_type}
      true -> {:error, :revoked}
      error -> error
    end
  end

  def revoke(token) do
    case verify_token(token) do
      {:ok, claims} ->
        # Add to blacklist
        Przma.Cache.put("blacklist:#{claims["jti"]}", true, ttl: claims["exp"] - current_time())
        :ok

      error -> error
    end
  end

  def blacklist_user(user_id, ttl) do
    Przma.Cache.put("blacklist_user:#{user_id}", true, ttl: ttl)
  end

  # Private Functions

  defp sign_token(claims) do
    signer = Joken.Signer.create(@signing_algorithm, get_secret_key())
    {:ok, token, _claims} = Joken.generate_and_sign(claims, signer)
    token
  end

  defp verify_token(token) do
    signer = Joken.Signer.create(@signing_algorithm, get_secret_key())

    case Joken.verify_and_validate(token, signer) do
      {:ok, claims} -> {:ok, claims}
      {:error, :expired} -> {:error, :expired}
      {:error, _} -> {:error, :invalid}
    end
  end

  defp is_revoked?(token) do
    case verify_token(token) do
      {:ok, claims} ->
        Przma.Cache.get("blacklist:#{claims["jti"]}") != nil ||
        Przma.Cache.get("blacklist_user:#{claims["sub"]}") != nil

      _ -> false
    end
  end

  defp store_refresh_token(token, user_id, session_id) do
    # Store in database for tracking
    Przma.Repo.insert!(%Przma.Auth.RefreshToken{
      token: token,
      user_id: user_id,
      session_id: session_id,
      expires_at: DateTime.utc_now() |> DateTime.add(@refresh_token_ttl, :second)
    })
  end

  defp get_user_roles(user) do
    user
    |> Przma.Repo.preload(:roles)
    |> Map.get(:roles, [])
    |> Enum.map(& &1.name)
  end

  defp get_user_permissions(user) do
    user
    |> Przma.Repo.preload(roles: :permissions)
    |> Map.get(:roles, [])
    |> Enum.flat_map(& &1.permissions)
    |> Enum.map(& &1.name)
    |> Enum.uniq()
  end

  defp generate_jti do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp current_time do
    DateTime.utc_now() |> DateTime.to_unix()
  end

  defp get_secret_key do
    Application.get_env(:przma, :secret_key_base)
  end
end
