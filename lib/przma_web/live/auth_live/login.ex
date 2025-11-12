defmodule PrzmaWeb.AuthLive.Login do
  use PrzmaWeb, :live_view
  alias Przma.Accounts
  alias PrzmaWeb.Router.Helpers, as: Routes
  import PrzmaWeb.CoreComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Login")
     |> assign(:form, to_form(%{"username" => "", "password" => ""}, as: :login))
     |> assign(:error_message, nil)
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("validate", %{"login" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :login))}
  end

  @impl true
  def handle_event("login", %{"login" => %{"username" => username, "password" => password}}, socket) do
    socket = assign(socket, :loading, true)

    case Accounts.authenticate_user(username, password) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Welcome back #{user.first_name}!")
         |> push_navigate(to: Routes.dashboard_path(socket, :index))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:error_message, "Invalid username or password")
         |> assign(:loading, false)
         |> put_flash(:error, "Invalid username or password")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 flex flex-col justify-center items-center">
      <div class="w-full max-w-md bg-white p-8 rounded-xl shadow-md">
        <h2 class="text-2xl font-semibold text-center text-gray-800 mb-6">
          Sign in to your account
        </h2>

        <%= if @error_message do %>
          <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-2 rounded mb-4">
            <%= @error_message %>
          </div>
        <% end %>

        <.form for={@form} phx-submit="login" phx-change="validate" class="space-y-5">
          <div>
            <label class="block text-sm font-medium text-gray-700">Username</label>
            <.input field={@form[:username]} type="text" placeholder="Enter username" required />
          </div>

          <div>
            <label class="block text-sm font-medium text-gray-700">Password</label>
            <.input field={@form[:password]} type="password" placeholder="Enter password" required />
          </div>

          <div class="flex items-center justify-between">
            <.link navigate={~p"/auth/reset-password"} class="text-sm text-blue-600 hover:underline">
              Forgot password?
            </.link>
          </div>

          <.button type="submit" disabled={@loading} class="w-full bg-blue-600 hover:bg-blue-700 text-white py-2 rounded-md">
            <%= if @loading do %>
              <span class="animate-spin mr-2">⏳</span> Signing in...
            <% else %>
              Sign In
            <% end %>
          </.button>
        </.form>

        <p class="mt-6 text-center text-gray-600 text-sm">
          Don’t have an account?
          <.link navigate={~p"/auth/register"} class="text-blue-600 hover:underline">Sign up</.link>
        </p>
      </div>
    </div>
    """
  end
end
