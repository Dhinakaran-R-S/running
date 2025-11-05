defmodule PrzmaWeb.AuthLive do
  use PrzmaWeb, :live_view
  alias Przma.Auth.User
  alias Przma.AuthRepo

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:current_tab, "login")
      |> assign(:errors, [])
      |> assign(:loading, false)
      |> assign(:login_form, %{"email" => "", "password" => ""})
      |> assign(:register_form, %{"email" => "", "username" => "", "password" => ""})

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <h2 class="text-center text-3xl font-extrabold text-gray-900">Welcome to Przma</h2>

        <!-- Tabs -->
        <div class="flex border-b border-gray-200">
          <button phx-click="switch_tab" phx-value-tab="login"
            class={[
              "flex-1 py-2 text-center border-b-2 font-medium text-sm",
              if(@current_tab == "login", do: "border-indigo-500 text-indigo-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300")
            ]}>
            Login
          </button>
          <button phx-click="switch_tab" phx-value-tab="register"
            class={[
              "flex-1 py-2 text-center border-b-2 font-medium text-sm",
              if(@current_tab == "register", do: "border-indigo-500 text-indigo-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300")
            ]}>
            Register
          </button>
        </div>

        <!-- Error Display -->
        <div :if={@errors != []} class="bg-red-50 border border-red-200 rounded-md p-3 text-sm text-red-700">
          <ul class="list-disc pl-5">
            <li :for={e <- @errors}><%= e %></li>
          </ul>
        </div>

        <!-- Login Form -->
        <div :if={@current_tab == "login"} class="mt-8">
          <.form for={@login_form} phx-submit="login_submit" class="space-y-5">
            <div>
              <label>Email</label>
              <input name="email" type="email" value={@login_form["email"]}
                class="w-full border rounded-md p-2 mt-1" required />
            </div>

            <div>
              <label>Password</label>
              <input name="password" type="password" value={@login_form["password"]}
                class="w-full border rounded-md p-2 mt-1" required />
            </div>

            <button type="submit"
              class={[
                "w-full py-2 px-4 rounded-md text-white",
                if(@loading, do: "bg-indigo-400", else: "bg-indigo-600 hover:bg-indigo-700")
              ]}
              disabled={@loading}>
              <%= if @loading, do: "Signing in...", else: "Sign In" %>
            </button>
          </.form>
        </div>

        <!-- Register Form -->
        <div :if={@current_tab == "register"} class="mt-8">
          <.form for={@register_form} phx-submit="register_submit" class="space-y-5">
            <div>
              <label>Username</label>
              <input name="username" type="text" value={@register_form["username"]}
                class="w-full border rounded-md p-2 mt-1" required />
            </div>

            <div>
              <label>Email</label>
              <input name="email" type="email" value={@register_form["email"]}
                class="w-full border rounded-md p-2 mt-1" required />
            </div>

            <div>
              <label>Password</label>
              <input name="password" type="password" value={@register_form["password"]}
                class="w-full border rounded-md p-2 mt-1" required />
            </div>

            <button type="submit"
              class={[
                "w-full py-2 px-4 rounded-md text-white",
                if(@loading, do: "bg-indigo-400", else: "bg-indigo-600 hover:bg-indigo-700")
              ]}
              disabled={@loading}>
              <%= if @loading, do: "Creating account...", else: "Create Account" %>
            </button>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, current_tab: tab, errors: [])}
  end

  @impl true
  def handle_event("register_submit", params, socket) do
    socket = assign(socket, :loading, true)
    case User.create_user(params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account created successfully! Please log in.")
         |> assign(:current_tab, "login")
         |> assign(:loading, false)}

      {:error, changeset} ->
        errors = extract_changeset_errors(changeset)
        {:noreply, assign(socket, errors: errors, loading: false)}
    end
  end

  @impl true
  def handle_event("login_submit", %{"email" => email, "password" => password}, socket) do
    socket = assign(socket, :loading, true)
    with {:ok, user} <- User.get_by_email(email),
         true <- User.verify_password(user, password) do
      {:noreply,
       socket
       |> put_flash(:info, "Login successful!")
       |> assign(:loading, false)
       |> push_navigate(to: "/dashboard")}
    else
      _ ->
        {:noreply,
         socket
         |> assign(:errors, ["Invalid email or password"])
         |> assign(:loading, false)}
    end
  end

  # Helper
  defp extract_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {field, errors} ->
      Enum.map(errors, fn e -> "#{Phoenix.Naming.humanize(field)} #{e}" end)
    end)
  end
end
