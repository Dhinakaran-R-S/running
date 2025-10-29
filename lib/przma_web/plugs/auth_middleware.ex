defmodule PrzmaWeb.Plugs.AuthMiddleware do
  @moduledoc """
  Plug for JWT authentication and user/tenant loading.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Przma.Auth.Token
  alias Przma.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- extract_token(conn),
         {:ok, claims} <- Token.verify_access_token(token),
         {:ok, user} <- Accounts.get_user(claims["sub"]) do

      conn
      |> assign(:current_user, user)
      |> assign(:current_user_id, user.id)
      |> assign(:current_tenant_id, user.tenant_id)
      |> assign(:current_roles, claims["roles"])
      |> assign(:current_permissions, claims["permissions"])
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> put_view(PrzmaWeb.ErrorView)
        |> render("401.json")
        |> halt()
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :no_token}
    end
  end
end
