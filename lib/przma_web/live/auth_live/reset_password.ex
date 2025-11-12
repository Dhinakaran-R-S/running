defmodule PrzmaWeb.AuthLive.ResetPassword do
  use Phoenix.LiveView
  use PrzmaWeb, :live_view
  import PrzmaWeb.CoreComponents

  alias Przma.Auth

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reset Password")
     |> assign(:form, to_form(%{"email" => ""}, as: :reset))
     |> assign(:success, false)
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("validate", %{"reset" => params}, socket) do
    form = to_form(params, as: :reset)
    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("submit", %{"reset" => %{"email" => email}}, socket) do
    socket = assign(socket, :loading, true)

    # Always return success to prevent email enumeration
    Auth.request_password_reset(email)

    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:success, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 flex items-center justify-center p-4">
      <div class="w-full max-w-md p-8 bg-white rounded-lg shadow-lg">
        <%= if @success do %>
          <div class="text-center">
            <div class="mx-auto w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mb-4">
              <.icon name="hero-check-circle" class="w-8 h-8 text-green-600" />
            </div>
            <h2 class="text-2xl font-bold text-gray-900 mb-2">Check Your Email</h2>
            <p class="text-gray-600 mb-6">
              If an account exists with that email, we've sent password reset instructions.
            </p>
            <.link navigate={~p"/auth/login"} class="text-blue-600 hover:text-blue-700 font-medium">
              Back to Sign In
            </.link>
          </div>
        <% else %>
          <div class="mb-8 text-center">
            <h2 class="text-3xl font-bold text-gray-900">Reset Password</h2>
            <p class="mt-2 text-gray-600">Enter your email to receive reset instructions</p>
          </div>

          <.form for={@form} phx-submit="submit" phx-change="validate" class="space-y-6">
            <div>
              <.label for="email">Email Address</.label>
              <.input
                field={@form[:email]}
                type="email"
                placeholder="your@email.com"
                required
                autocomplete="email"
              />
            </div>

            <.button type="submit" disabled={@loading} class="w-full" phx-disable-with="Sending...">
              <%= if @loading do %>
                Sending...
              <% else %>
                Send Reset Link
              <% end %>
            </.button>
          </.form>

          <div class="mt-6 text-center">
            <.link navigate={~p"/auth/login"} class="text-blue-600 hover:text-blue-700 font-medium">
              Back to Sign In
            </.link>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
