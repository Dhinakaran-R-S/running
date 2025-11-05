defmodule PrzmaWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use PrzmaWeb, :controller
      use PrzmaWeb, :view

  The definitions below will be executed for every controller,
  view, etc, so keep them short and clean, focused on imports,
  uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:json],
        layouts: [json: PrzmaWeb.LayoutView]

      import Plug.Conn
      import PrzmaWeb.Gettext

      unquote(verified_routes())
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/przma_web/templates",
        namespace: PrzmaWeb

      import Phoenix.Controller,
        only: [get_flash: 1, get_flash: 2, view_module: 1, view_template: 1]

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {PrzmaWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: PrzmaWeb.Endpoint,
        router: PrzmaWeb.Router,
        statics: PrzmaWeb.static_paths()
    end
  end

  defp html_helpers do
  quote do
    import Phoenix.HTML
    import Phoenix.LiveView.Helpers
    import Phoenix.Component
    alias PrzmaWeb.Router.Helpers, as: Routes
  end
end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, get_flash: 1, get_flash: 2, view_module: 1]

      # Include HTML helpers (forms, tags, etc)
      import Phoenix.HTML

      # Import core UI components (if you have them)
      import PrzmaWeb.CoreComponents

      # Import translation and route helpers
      import PrzmaWeb.Gettext
      alias PrzmaWeb.Router.Helpers, as: Routes

      unquote(PrzmaWeb.verified_routes())
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
