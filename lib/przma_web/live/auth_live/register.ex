defmodule PrzmaWeb.AuthLive.Register do
  use Phoenix.LiveView
  use PrzmaWeb, :live_view
  import PrzmaWeb.CoreComponents

  alias Przma.Auth
  alias Przma.AuditLog

  @impl true
  def mount(_params, _session, socket) do
    # Store connect info during mount for later use
    peer_data = get_connect_info(socket, :peer_data)
    ip_address = if peer_data && peer_data.address do
      peer_data.address |> :inet.ntoa() |> to_string()
    else
      "unknown"
    end

    {:ok,
     socket
     |> assign(:page_title, "Sign Up")
     |> assign(:form, to_form(%{
       "first_name" => "",
       "last_name" => "",
       "username" => "",
       "email" => "",
       "password" => "",
       "password_confirmation" => ""
     }, as: :register))
     |> assign(:errors, %{})
     |> assign(:loading, false)
     |> assign(:ip_address, ip_address)
     |> assign(:user_agent, get_connect_info(socket, :user_agent) || "unknown")}
  end

  @impl true
  def handle_event("validate", %{"register" => params}, socket) do
    form = to_form(params, as: :register)
    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("submit", %{"register" => params}, socket) do
    socket = assign(socket, :loading, true)

    context = %{
      ip_address: socket.assigns.ip_address,
      user_agent: socket.assigns.user_agent
    }

    case Auth.register(params) do
      {:ok, user} ->
        # Log registration
        AuditLog.log_action(user, :register, :user, user.id, context)

        # Auto-login after registration
        case Auth.authenticate(user.username, params["password"]) do
          {:ok, _user, tokens} ->
            {:noreply,
             socket
             |> put_flash(:info, "Account created successfully! Welcome #{user.username}!")
             |> push_navigate(to: ~p"/dashboard?token=#{tokens.access_token}")}

          _ ->
            {:noreply,
             socket
             |> put_flash(:info, "Account created! Please sign in.")
             |> push_navigate(to: ~p"/auth/login")}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = changeset_errors_to_map(changeset)

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:errors, errors)
         |> put_flash(:error, "Please correct the errors below")}
    end
  end

  defp changeset_errors_to_map(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 flex items-center justify-center p-4">
      <div class="w-full max-w-md p-8 bg-white rounded-lg shadow-lg">
        <div class="mb-8 text-center">
          <h2 class="text-3xl font-bold text-gray-900">Create Account</h2>
          <p class="mt-2 text-gray-600">Sign up to get started</p>
        </div>

        <.form for={@form} phx-submit="submit" phx-change="validate" class="space-y-4">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <.label for="first_name">First Name</.label>
              <.input field={@form[:first_name]} type="text" required />
              <%= if error = @errors[:first_name] do %>
                <p class="mt-1 text-sm text-red-600"><%= List.first(error) %></p>
              <% end %>
            </div>
            <div>
              <.label for="last_name">Last Name</.label>
              <.input field={@form[:last_name]} type="text" required />
              <%= if error = @errors[:last_name] do %>
                <p class="mt-1 text-sm text-red-600"><%= List.first(error) %></p>
              <% end %>
            </div>
          </div>

          <div>
            <.label for="username">Username</.label>
            <.input field={@form[:username]} type="text" required autocomplete="username" />
            <%= if error = @errors[:username] do %>
              <p class="mt-1 text-sm text-red-600"><%= List.first(error) %></p>
            <% end %>
          </div>

          <div>
            <.label for="email">Email</.label>
            <.input field={@form[:email]} type="email" required autocomplete="email" />
            <%= if error = @errors[:email] do %>
              <p class="mt-1 text-sm text-red-600"><%= List.first(error) %></p>
            <% end %>
          </div>

          <div>
            <.label for="password">Password</.label>
            <.input field={@form[:password]} type="password" required autocomplete="new-password" />
            <p class="mt-1 text-xs text-gray-500">
              Min 8 characters, with uppercase, lowercase, and number
            </p>
            <%= if error = @errors[:password] do %>
              <p class="mt-1 text-sm text-red-600"><%= List.first(error) %></p>
            <% end %>
          </div>

          <div>
            <.label for="password_confirmation">Confirm Password</.label>
            <.input field={@form[:password_confirmation]} type="password" required autocomplete="new-password" />
            <%= if error = @errors[:password_confirmation] do %>
              <p class="mt-1 text-sm text-red-600"><%= List.first(error) %></p>
            <% end %>
          </div>

          <.button type="submit" disabled={@loading} class="w-full" phx-disable-with="Creating account...">
            <%= if @loading do %>
              <span class="inline-block animate-spin mr-2">⏳</span> Creating account...
            <% else %>
              Create Account
            <% end %>
          </.button>
        </.form>

        <div class="mt-6 text-center">
          <p class="text-gray-600">
            Already have an account?
            <.link navigate={~p"/auth/login"} class="text-blue-600 hover:text-blue-700 font-medium">
              Sign in
            </.link>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
