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
