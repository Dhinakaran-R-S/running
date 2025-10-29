defmodule PrzmaWeb.Plugs.CorsMiddleware do
  @moduledoc """
  CORS middleware for API endpoints.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", get_allowed_origin(conn))
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "Authorization, Content-Type")
    |> put_resp_header("access-control-max-age", "86400")
    |> handle_preflight()
  end

  defp handle_preflight(%{method: "OPTIONS"} = conn) do
    conn
    |> send_resp(200, "")
    |> halt()
  end
  defp handle_preflight(conn), do: conn

  defp get_allowed_origin(conn) do
    # In production, check against whitelist
    case get_req_header(conn, "origin") do
      [origin | _] -> origin
      [] -> "*"
    end
  end
end
