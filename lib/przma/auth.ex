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
  import Ecto.Query
  
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

defmodule Przma.Auth.Token do
  @moduledoc """
  JWT token generation and verification.
  """
  
  use Joken.Config
  
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
      "roles" => get_user_roles(user),
      "permissions" => get_user_permissions(user),
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
    Argon2.verify_pass(password, user.password_hash)
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
        |> put_change(:password_hash, Argon2.hash_pwd_salt(password))
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

defmodule Przma.Auth.Permission do
  @moduledoc """
  Permission checking and management.
  """
  
  import Ecto.Query
  alias Przma.Repo
  
  def user_has_permission?(user, permission) when is_binary(permission) do
    query = from u in Przma.Auth.User,
      join: ur in "user_roles", on: ur.user_id == u.id,
      join: r in Przma.Auth.Role, on: r.id == ur.role_id,
      join: rp in "role_permissions", on: rp.role_id == r.id,
      join: p in Przma.Auth.PermissionSchema, on: p.id == rp.permission_id,
      where: u.id == ^user.id and p.name == ^permission,
      select: count(p.id)
    
    Repo.one(query) > 0
  end
end
