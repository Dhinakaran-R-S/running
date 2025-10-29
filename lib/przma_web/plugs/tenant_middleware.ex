defmodule PrzmaWeb.Plugs.TenantMiddleware do
  @moduledoc """
  Ensures tenant context is loaded for all requests.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Przma.MultiTenant

  def init(opts), do: opts

  def call(conn, _opts) do
    tenant_id = conn.assigns[:current_tenant_id]

    if tenant_id do
      case MultiTenant.get_tenant(tenant_id) do
        tenant when not is_nil(tenant) ->
          assign(conn, :current_tenant, tenant)

        nil ->
          conn
          |> put_status(:forbidden)
          |> put_view(PrzmaWeb.ErrorView)
          |> render("403.json")
          |> halt()
      end
    else
      conn
    end
  end
end
