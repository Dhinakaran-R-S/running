defmodule PrzmaWeb.Plugs.AuthMiddleware do
  @moduledoc """
  Plug for JWT authentication and user/tenant loading.
  """
  
  import Plug.Conn
  import Phoenix.Controller
  
  alias Przma.Auth.Token
  alias Przma.Accounts
  
  def init(opts), do: opts
  
  def call(conn, _opts) do
    with {:ok, token} <- extract_token(conn),
         {:ok, claims} <- Token.verify_access_token(token),
         {:ok, user} <- Accounts.get_user(claims["sub"]) do
      
      conn
      |> assign(:current_user, user)
      |> assign(:current_user_id, user.id)
      |> assign(:current_tenant_id, user.tenant_id)
      |> assign(:current_roles, claims["roles"])
      |> assign(:current_permissions, claims["permissions"])
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> put_view(PrzmaWeb.ErrorView)
        |> render("401.json")
        |> halt()
    end
  end
  
  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :no_token}
    end
  end
end

defmodule PrzmaWeb.Plugs.TenantMiddleware do
  @moduledoc """
  Ensures tenant context is loaded for all requests.
  """
  
  import Plug.Conn
  import Phoenix.Controller
  
  alias Przma.MultiTenant
  
  def init(opts), do: opts
  
  def call(conn, _opts) do
    tenant_id = conn.assigns[:current_tenant_id]
    
    if tenant_id do
      case MultiTenant.get_tenant(tenant_id) do
        tenant when not is_nil(tenant) ->
          assign(conn, :current_tenant, tenant)
        
        nil ->
          conn
          |> put_status(:forbidden)
          |> put_view(PrzmaWeb.ErrorView)
          |> render("403.json")
          |> halt()
      end
    else
      conn
    end
  end
end

defmodule PrzmaWeb.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting middleware using ETS-based token bucket algorithm.
  """
  
  import Plug.Conn
  import Phoenix.Controller
  
  @table_name :rate_limit_buckets
  @default_limit 100
  @default_window 60_000  # 1 minute
  
  def init(opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    window = Keyword.get(opts, :window, @default_window)
    
    # Create ETS table if it doesn't exist
    case :ets.info(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
      _ ->
        :ok
    end
    
    %{limit: limit, window: window}
  end
  
  def call(conn, opts) do
    identifier = get_identifier(conn)
    
    case check_rate_limit(identifier, opts) do
      :ok ->
        conn
      
      {:error, :rate_limited, retry_after} ->
        conn
        |> put_resp_header("retry-after", to_string(retry_after))
        |> put_resp_header("x-ratelimit-limit", to_string(opts.limit))
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> put_status(:too_many_requests)
        |> put_view(PrzmaWeb.ErrorView)
        |> render("error.json", error: "Rate limit exceeded")
        |> halt()
    end
  end
  
  defp get_identifier(conn) do
    # Use user ID if authenticated, otherwise IP address
    case conn.assigns[:current_user_id] do
      nil -> get_client_ip(conn)
      user_id -> "user:#{user_id}"
    end
  end
  
  defp check_rate_limit(identifier, opts) do
    now = System.system_time(:millisecond)
    window_start = now - opts.window
    
    case :ets.lookup(@table_name, identifier) do
      [{^identifier, timestamps}] ->
        # Filter to current window
        recent = Enum.filter(timestamps, &(&1 > window_start))
        
        if length(recent) >= opts.limit do
          oldest = Enum.min(recent)
          retry_after = div(oldest + opts.window - now, 1000)
          {:error, :rate_limited, retry_after}
        else
          # Add current request
          :ets.insert(@table_name, {identifier, [now | recent]})
          :ok
        end
      
      [] ->
        # First request
        :ets.insert(@table_name, {identifier, [now]})
        :ok
    end
  end
  
  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      [] -> to_string(:inet.ntoa(conn.remote_ip))
    end
  end
end

defmodule PrzmaWeb.Plugs.CorsMiddleware do
  @moduledoc """
  CORS middleware for API endpoints.
  """
  
  import Plug.Conn
  
  def init(opts), do: opts
  
  def call(conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", get_allowed_origin(conn))
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "Authorization, Content-Type")
    |> put_resp_header("access-control-max-age", "86400")
    |> handle_preflight()
  end
  
  defp handle_preflight(%{method: "OPTIONS"} = conn) do
    conn
    |> send_resp(200, "")
    |> halt()
  end
  defp handle_preflight(conn), do: conn
  
  defp get_allowed_origin(conn) do
    # In production, check against whitelist
    case get_req_header(conn, "origin") do
      [origin | _] -> origin
      [] -> "*"
    end
  end
end

defmodule PrzmaWeb.Plugs.RequirePermission do
  @moduledoc """
  Plug to require specific permission for endpoint access.
  """
  
  import Plug.Conn
  import Phoenix.Controller
  
  alias Przma.Auth.Permission
  
  def init(permission), do: permission
  
  def call(conn, permission) do
    user = conn.assigns[:current_user]
    
    if user && Permission.user_has_permission?(user, permission) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> put_view(PrzmaWeb.ErrorView)
      |> render("403.json")
      |> halt()
    end
  end
end

defmodule PrzmaWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.
  """
  
  use Phoenix.Controller
  
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(PrzmaWeb.ErrorView)
    |> render("404.json")
  end
  
  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(PrzmaWeb.ErrorView)
    |> render("401.json")
  end
  
  def call(conn, {:error, changeset = %Ecto.Changeset{}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(PrzmaWeb.ErrorView)
    |> render("error.json", changeset: changeset)
  end
  
  def call(conn, {:error, reason}) do
    conn
    |> put_status(:bad_request)
    |> put_view(PrzmaWeb.ErrorView)
    |> render("error.json", error: reason)
  end
end
