defmodule PrzmaWeb.Router do
  use PrzmaWeb, :router

  import PrzmaWeb.Plugs.AuthMiddleware
  import PrzmaWeb.Plugs.TenantMiddleware
  import PrzmaWeb.Plugs.RequirePermission
  import Phoenix.LiveView.Router

  # ============================================================================
  # PIPELINES
  # ============================================================================

  pipeline :api do
    plug :accepts, ["json"]
    plug PrzmaWeb.Plugs.CorsMiddleware
  end

  pipeline :authenticated do
    plug PrzmaWeb.Plugs.AuthMiddleware
    plug PrzmaWeb.Plugs.TenantMiddleware
  end

  pipeline :rate_limited do
    plug PrzmaWeb.Plugs.RateLimiter, limit: 100, window: 60_000
  end

  # ============================================================================
  # PUBLIC ROUTES
  # ============================================================================

  scope "/api/v1", PrzmaWeb do
    pipe_through [:api, :rate_limited]

    # Health checks
    get "/health", HealthController, :index
    get "/health/ready", HealthController, :ready
    get "/health/live", HealthController, :live
    get "/health/status", HealthController, :status
    get "/health/database", HealthController, :database
    get "/health/ai", HealthController, :ai_services

    # Authentication
    post "/auth/register", AuthController, :register
    post "/auth/login", AuthController, :login
    post "/auth/refresh", AuthController, :refresh
    post "/auth/password/request-reset", AuthController, :request_password_reset
    post "/auth/password/reset", AuthController, :reset_password
  end

  # ============================================================================
  # AUTHENTICATED ROUTES
  # ============================================================================

  scope "/api/v1", PrzmaWeb do
    pipe_through [:api, :rate_limited, :authenticated]

    # Current user
    get "/auth/me", AuthController, :me
    post "/auth/logout", AuthController, :logout
    post "/auth/password/change", AuthController, :change_password
    post "/auth/sessions/revoke-all", AuthController, :revoke_all_sessions

    # Activities
    get "/activities", ActivityController, :index
    get "/activities/:id", ActivityController, :show
    post "/activities", ActivityController, :create
    post "/activities/from-text", ActivityController, :create_from_text
    put "/activities/:id", ActivityController, :update
    delete "/activities/:id", ActivityController, :delete
    get "/activities/:id/enrichment", ActivityController, :enrichment_status
    post "/activities/search", ActivityController, :search

    # Members
    get "/members", MemberController, :index
    get "/members/:id", MemberController, :show
    post "/members", MemberController, :create
    put "/members/:id", MemberController, :update
    delete "/members/:id", MemberController, :delete
    get "/members/:id/activity-summary", MemberController, :activity_summary
    put "/members/:id/roles", MemberController, :update_roles
    post "/members/invite", MemberController, :invite

    # Conversations
    get "/conversations", ConversationController, :index
    get "/conversations/:id", ConversationController, :show
    post "/conversations", ConversationController, :create
    put "/conversations/:id", ConversationController, :update
    delete "/conversations/:id", ConversationController, :delete
    post "/conversations/:id/end", ConversationController, :end_conversation
    post "/conversations/:id/archive", ConversationController, :archive
    post "/conversations/:id/participants", ConversationController, :add_participant
    delete "/conversations/:id/participants/:member_id", ConversationController, :remove_participant

    # Messages
    get "/conversations/:conversation_id/messages", MessageController, :index
    post "/conversations/:conversation_id/messages", MessageController, :create
    post "/conversations/:conversation_id/ai-response", MessageController, :generate_ai_response

    # Audit Logs (admin only)
    get "/audit-logs", AuditLogController, :index
    get "/audit-logs/threats", AuditLogController, :threats
    get "/audit-logs/compliance-report", AuditLogController, :compliance_report
  end

  # ============================================================================
  # ADMIN ROUTES
  # ============================================================================

  pipeline :admin_only do
    plug PrzmaWeb.Plugs.RequirePermission, permission: "admin.access"
  end

  scope "/api/v1/admin", PrzmaWeb.Admin, as: :admin do
    pipe_through [:api, :authenticated, :admin_only]

    # Requires admin role
    # pipe_through [RequirePermission, permission: "admin.access"]

    # Organization management
    resources "/organizations", OrganizationController, only: [:index, :show, :update]

    # User management
    resources "/users", UserController, only: [:index, :show, :update, :delete]

    # System settings
    get "/settings", SettingsController, :show
    put "/settings", SettingsController, :update
  end

  # ============================================================================
  # WEBHOOKS
  # ============================================================================

  scope "/webhooks", PrzmaWeb do
    pipe_through :api

    post "/activities", WebhookController, :activities
    post "/notifications", WebhookController, :notifications
  end

# ============================================================================
# WEB ROUTES (LiveView / Browser)
# ============================================================================

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {PrzmaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", PrzmaWeb do
    pipe_through :browser

    get "/", RedirectController, :to_login

    live "/auth/login", AuthLive.Login
    live "/auth/register", AuthLive.Register
    live "/auth/reset-password", AuthLive.ResetPassword
    live "/dashboard", DashboardLive, :index

  end

  # ============================================================================
  # DEVELOPMENT ROUTES
  # ============================================================================

  if Application.compile_env(:przma, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard",
        metrics: PrzmaWeb.Telemetry,
        ecto_repos: [Przma.Repo]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

defmodule PrzmaWeb.ConversationController do
  use PrzmaWeb, :controller

  alias Przma.Conversations
  alias PrzmaWeb.ErrorView

  action_fallback PrzmaWeb.FallbackController

  def index(conn, params) do
    organization_id = conn.assigns.current_tenant_id
    conversations = Conversations.list_conversations(organization_id, params)
    json(conn, %{data: conversations})
  end

  def show(conn, %{"id" => id}) do
    organization_id = conn.assigns.current_tenant_id
    case Conversations.get_conversation(id, organization_id) do
      {:ok, conversation} ->
        json(conn, %{data: conversation})
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> render(ErrorView, "404.json")
    end
  end

  def create(conn, %{"conversation" => attrs}) do
    organization_id = conn.assigns.current_tenant_id
    user_id = conn.assigns.current_user_id

    attrs = attrs
    |> Map.put("organization_id", organization_id)
    |> Map.put("initiated_by_id", user_id)

    case Conversations.create_conversation(attrs) do
      {:ok, conversation} ->
        conn
        |> put_status(:created)
        |> json(%{data: conversation})
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(ErrorView, "error.json", changeset: changeset)
    end
  end

  def add_participant(conn, %{"id" => id, "member_id" => member_id}) do
    case Conversations.add_participant(id, member_id) do
      :ok ->
        send_resp(conn, :no_content, "")
      error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: error})
    end
  end

  def end_conversation(conn, %{"id" => id}) do
    organization_id = conn.assigns.current_tenant_id
    user_id = conn.assigns.current_user_id

    with {:ok, conversation} <- Conversations.get_conversation(id, organization_id),
         {:ok, updated} <- Conversations.end_conversation(conversation, user_id) do
      json(conn, %{data: updated})
    end
  end
end

defmodule PrzmaWeb.MessageController do
  use PrzmaWeb, :controller

  alias Przma.Conversations

  def index(conn, %{"conversation_id" => conversation_id} = params) do
    case Conversations.get_messages(conversation_id, params) do
      {:ok, messages} ->
        json(conn, %{data: messages})
      error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: error})
    end
  end

  def create(conn, %{"conversation_id" => conversation_id, "message" => attrs}) do
    user_id = conn.assigns.current_user_id

    case Conversations.create_message(conversation_id, user_id, attrs) do
      {:ok, message} ->
        conn
        |> put_status(:created)
        |> json(%{data: message})
      error ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: error})
    end
  end

  def generate_ai_response(conn, %{"conversation_id" => conversation_id}) do
    case Conversations.generate_ai_response(conversation_id) do
      {:ok, message} ->
        json(conn, %{data: message})
      error ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: error})
    end
  end
end
