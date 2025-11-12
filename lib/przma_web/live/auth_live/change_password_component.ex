defmodule PrzmaWeb.AuthLive.ChangePasswordComponent do
  use Phoenix.LiveComponent
  use PrzmaWeb, :live_view
  import PrzmaWeb.CoreComponents

  alias Przma.Auth
  alias Przma.AuditLog

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(%{"current_password" => "", "new_password" => ""}, as: :password))
     |> assign(:error, nil)
     |> assign(:success, false)
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("validate", %{"password" => params}, socket) do
    form = to_form(params, as: :password)
    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("submit", %{"password" => %{"current_password" => current, "new_password" => new_pass}}, socket) do
    user = socket.assigns.user
    socket = assign(socket, :loading, true)

    case Auth.change_password(user, current, new_pass) do
      {:ok, _user} ->
        # Log password change
        AuditLog.log_action(user, :password_change, :user, user.id, %{})

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:success, true)
         |> assign(:error, nil)}

      {:error, :invalid_current_password} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Invalid current password")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "Password does not meet requirements")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mt-4">
      <%= if @success do %>
        <div class="p-4 bg-green-50 border border-green-200 rounded-lg">
          <p class="text-green-800 text-sm">Password changed successfully!</p>
        </div>
      <% else %>
        <%= if @error do %>
          <div class="mt-4 p-3 bg-red-50 border border-red-200 rounded-lg">
            <p class="text-sm text-red-800"><%= @error %></p>
          </div>
        <% end %>

        <.form for={@form} phx-submit="submit" phx-change="validate" phx-target={@myself} class="mt-4 space-y-4">
          <div>
            <.label for="current_password">Current Password</.label>
            <.input
              field={@form[:current_password]}
              type="password"
              required
              autocomplete="current-password"
            />
          </div>

          <div>
            <.label for="new_password">New Password</.label>
            <.input
              field={@form[:new_password]}
              type="password"
              required
              autocomplete="new-password"
            />
          </div>

          <.button type="submit" disabled={@loading} class="w-full" phx-disable-with="Updating...">
            <%= if @loading, do: "Updating...", else: "Update Password" %>
          </.button>
        </.form>
      <% end %>
    </div>
    """
  end
end
