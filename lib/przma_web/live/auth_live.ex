defmodule PrzmaWeb.AuthLive do
  use PrzmaWeb, :live_view
  alias Przma.Auth.User

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:current_tab, "login")
      |> assign(:errors, [])
      |> assign(:loading, false)

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
          <form phx-submit="login" class="space-y-5">
            <div>
              <label class="block text-sm font-medium text-gray-700">Email</label>
              <input type="email" name="email" class="mt-1 block w-full rounded-md border border-gray-300 px-3 py-2" required />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700">Password</label>
              <input type="password" name="password" class="mt-1 block w-full rounded-md border border-gray-300 px-3 py-2" required />
            </div>

            <button type="submit" disabled={@loading}
              class={[
                "w-full py-2 px-4 rounded-md text-white font-medium",
                if(@loading, do: "bg-indigo-400 cursor-not-allowed", else: "bg-indigo-600 hover:bg-indigo-700")
              ]}>
              <%= if @loading, do: "Signing in...", else: "Sign In" %>
            </button>
          </form>
        </div>

        <!-- Register Form -->
        <div :if={@current_tab == "register"} class="mt-8">
          <form phx-submit="register" class="space-y-5">
            <div>
              <label class="block text-sm font-medium text-gray-700">Username</label>
              <input type="text" name="username" class="mt-1 block w-full rounded-md border border-gray-300 px-3 py-2" required />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700">Email</label>
              <input type="email" name="email" class="mt-1 block w-full rounded-md border border-gray-300 px-3 py-2" required />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700">Password</label>
              <input type="password" name="password" class="mt-1 block w-full rounded-md border border-gray-300 px-3 py-2" required />
            </div>

            <button type="submit" disabled={@loading}
              class={[
                "w-full py-2 px-4 rounded-md text-white font-medium",
                if(@loading, do: "bg-indigo-400 cursor-not-allowed", else: "bg-indigo-600 hover:bg-indigo-700")
              ]}>
              <%= if @loading, do: "Creating account...", else: "Create Account" %>
            </button>
          </form>
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
  def handle_event("register", %{"username" => username, "email" => email, "password" => password}, socket) do
    socket = assign(socket, :loading, true)

    attrs = %{
      "username" => username,
      "email" => email,
      "password" => password,
      "password_confirmation" => password,
      "first_name" => username,
      "last_name" => ""
    }

    case register_user(attrs) do
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
  def handle_event("login", %{"email" => email, "password" => password}, socket) do
    socket = assign(socket, :loading, true)

    with {:ok, user} <- User.get_by_email(email),
         true <- User.verify_password(user, password) do
      {:noreply,
       socket
       |> put_flash(:info, "Login successful!")
       |> assign(:loading, false)
       |> push_navigate(to: "/app/dashboard")}
    else
      _ ->
        {:noreply,
         socket
         |> assign(:errors, ["Invalid email or password"])
         |> assign(:loading, false)}
    end
  end

  defp register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Przma.Repo.insert()
  end

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
