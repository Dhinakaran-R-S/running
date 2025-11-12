defmodule PrzmaWeb.RedirectController do
  use PrzmaWeb, :controller

  def to_login(conn, _params) do
    redirect(conn, to: "/auth/login")
  end
end
