defmodule Przma.AuditLog.Middleware do
  @moduledoc """
  Plug middleware for automatic audit logging of HTTP requests.
  """

  @behaviour Plug

  import Plug.Conn
  alias Przma.AuditLog

  def init(opts), do: opts

  def call(conn, _opts) do
    start_time = System.monotonic_time()

    register_before_send(conn, fn conn ->
      if should_log?(conn) do
        duration_ms = System.monotonic_time() - start_time
        log_request(conn, duration_ms)
      end

      conn
    end)
  end

  defp should_log?(conn) do
    # Log authenticated requests to sensitive endpoints
    conn.assigns[:current_user] != nil &&
    conn.request_path != "/health" &&
    conn.request_path != "/metrics"
  end

  defp log_request(conn, duration_ms) do
    user = conn.assigns[:current_user]

    action = determine_action(conn.method, conn.request_path)
    {resource_type, resource_id} = extract_resource(conn)

    metadata = %{
      method: conn.method,
      path: conn.request_path,
      duration_ms: duration_ms,
      status_code: conn.status
    }

    status = if conn.status < 400, do: :success, else: :failure

    AuditLog.log_action(user, action, resource_type, resource_id, %{
      ip_address: get_client_ip(conn),
      user_agent: get_user_agent(conn),
      session_id: get_session(conn, :session_id),
      metadata: metadata,
      status: status
    })
  end

  defp determine_action("GET", _path), do: :read
  defp determine_action("POST", _path), do: :create
  defp determine_action("PUT", _path), do: :update
  defp determine_action("PATCH", _path), do: :update
  defp determine_action("DELETE", _path), do: :delete
  defp determine_action(_, _path), do: :unknown

  defp extract_resource(conn) do
    case conn.path_params do
      %{"resource" => type, "id" => id} -> {type, id}
      %{"id" => id} -> {conn.private[:phoenix_action], id}
      _ -> {conn.private[:phoenix_controller], nil}
    end
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      [] -> to_string(:inet.ntoa(conn.remote_ip))
    end
  end

  defp get_user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [agent | _] -> agent
      [] -> "unknown"
    end
  end
end
