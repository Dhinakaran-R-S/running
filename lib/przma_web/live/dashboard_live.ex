defmodule PrzmaWeb.DashboardLive do
  use PrzmaWeb, :live_view
  import PrzmaWeb.CoreComponents

  alias Przma.Auth
  alias Przma.AuditLog

  @impl true
  def mount(_params, _session, socket) do
    # Get token from URL params
    token = case get_connect_params(socket) do
      %{"token" => t} -> t
      _ -> nil
    end

    case token do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in to access this page")
         |> push_navigate(to: ~p"/auth/login")}

      token ->
        case Auth.Token.verify_access_token(token) do
          {:ok, claims} ->
            case Przma.Accounts.get_user(claims["sub"]) do
              {:ok, user} ->
                {:ok,
                 socket
                 |> assign(:page_title, "Dashboard")
                 |> assign(:current_user, user)
                 |> assign(:current_token, token)
                 |> assign(:show_change_password, false)}

              _ ->
                {:ok, push_navigate(socket, to: ~p"/auth/login")}
            end

          _ ->
            {:ok,
             socket
             |> put_flash(:error, "Session expired. Please login again.")
             |> push_navigate(to: ~p"/auth/login")}
        end
    end
  end

  @impl true
  def handle_event("toggle_change_password", _, socket) do
    {:noreply, assign(socket, :show_change_password, !socket.assigns.show_change_password)}
  end

  @impl true
  def handle_event("logout", _, socket) do
    user = socket.assigns.current_user

    # Log logout
    AuditLog.log_action(user, :logout, :user, user.id, %{})

    {:noreply,
     socket
     |> put_flash(:info, "Logged out successfully")
     |> push_navigate(to: ~p"/auth/login")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <nav class="bg-white shadow-sm border-b">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center h-16">
            <h1 class="text-xl font-bold text-gray-900">PRZMA Dashboard</h1>
            <div class="flex items-center gap-4">
              <div class="text-right">
                <p class="text-sm font-medium text-gray-900">
                  <%= @current_user.username %>
                </p>
                <p class="text-xs text-gray-500"><%= @current_user.email %></p>
              </div>
              <.button phx-click="logout" class="bg-red-600 hover:bg-red-700">
                Logout
              </.button>
            </div>
          </div>
        </div>
      </nav>

      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div class="bg-white p-6 rounded-lg shadow">
            <h2 class="text-lg font-semibold mb-4">User Information</h2>
            <div class="space-y-3">
              <div>
                <span class="text-sm text-gray-500">User ID:</span>
                <p class="font-mono text-sm"><%= @current_user.id %></p>
              </div>
              <div>
                <span class="text-sm text-gray-500">Email:</span>
                <p><%= @current_user.email %></p>
              </div>
              <div>
                <span class="text-sm text-gray-500">Status:</span>
                <span class="ml-2 px-2 py-1 bg-green-100 text-green-800 text-xs rounded-full">
                  <%= @current_user.status %>
                </span>
              </div>
              <div>
                <span class="text-sm text-gray-500">MFA:</span>
                <span class="ml-2">
                  <%= if @current_user.mfa_enabled, do: "✓ Enabled", else: "✗ Disabled" %>
                </span>
              </div>
              <div>
                <span class="text-sm text-gray-500">Roles:</span>
                <div class="flex gap-2 mt-1 flex-wrap">
                  <%= if @current_user.roles && length(@current_user.roles) > 0 do %>
                    <%= for role <- @current_user.roles do %>
                      <span class="px-2 py-1 bg-blue-100 text-blue-800 text-xs rounded">
                        <%= role.name %>
                      </span>
                    <% end %>
                  <% else %>
                    <span class="text-gray-400 text-sm">No roles assigned</span>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <div class="bg-white p-6 rounded-lg shadow">
            <h2 class="text-lg font-semibold mb-4">Account Security</h2>
            <.button phx-click="toggle_change_password" class="w-full">
              <%= if @show_change_password, do: "Cancel", else: "Change Password" %>
            </.button>

            <%= if @show_change_password do %>
              <.live_component
                module={PrzmaWeb.AuthLive.ChangePasswordComponent}
                id="change-password"
                user={@current_user}
              />
            <% end %>
          </div>
        </div>
      </main>
    </div>
    """
  end
end
