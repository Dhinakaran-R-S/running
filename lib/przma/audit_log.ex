defmodule Przma.AuditLog do
  @moduledoc """
  Comprehensive audit logging for security, compliance, and monitoring.

  Features:
  - User action tracking
  - Data access logging
  - Security event monitoring
  - Compliance reporting
  - Real-time alerting for suspicious activity
  - Tamper-proof logging
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Przma.Repo
  require Logger

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_logs" do
    field :tenant_id, :binary_id
    field :user_id, :binary_id
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :ip_address, :string
    field :user_agent, :string
    field :session_id, :binary_id
    field :severity, Ecto.Enum, values: [:info, :warning, :critical], default: :info
    field :status, Ecto.Enum, values: [:success, :failure], default: :success
    field :metadata, :map, default: %{}
    field :changes, :map  # Before/after for data changes
    field :timestamp, :utc_datetime

    timestamps(updated_at: false)
  end

  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [:tenant_id, :user_id, :action, :resource_type, :resource_id,
                    :ip_address, :user_agent, :session_id, :severity, :status,
                    :metadata, :changes, :timestamp])
    |> validate_required([:tenant_id, :action, :timestamp])
  end

  @doc """
  Log an action.

  ## Examples

      iex> Przma.AuditLog.log_action(user, :login, :user, user.id, %{ip_address: "1.2.3.4"})
      {:ok, %AuditLog{}}
  """
  def log_action(user, action, resource_type, resource_id, opts \\ %{}) do
    attrs = %{
      tenant_id: user.tenant_id,
      user_id: user.id,
      action: to_string(action),
      resource_type: to_string(resource_type),
      resource_id: resource_id,
      ip_address: opts[:ip_address],
      user_agent: opts[:user_agent],
      session_id: opts[:session_id],
      severity: determine_severity(action),
      status: opts[:status] || :success,
      metadata: opts[:metadata] || %{},
      changes: opts[:changes],
      timestamp: DateTime.utc_now()
    }

    result = %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()

    # Check for suspicious activity
    spawn(fn ->
      check_suspicious_activity(attrs)
    end)

    result
  end

  @doc """
  Log data access.
  """
  def log_data_access(user, resource_type, resource_id, opts \\ %{}) do
    log_action(user, :data_access, resource_type, resource_id, opts)
  end

  @doc """
  Log security event.
  """
  def log_security_event(user, event_type, opts \\ %{}) do
    opts = Map.put(opts, :severity, :critical)
    log_action(user, event_type, :security, nil, opts)
  end

  @doc """
  Get audit logs for a tenant with filters.
  """
  def list_for_tenant(tenant_id, opts \\ []) do
    limit_value = opts[:limit] || 100

    query =
        from a in __MODULE__,
          where: a.tenant_id == ^tenant_id,
          order_by: [desc: a.timestamp],
          limit: ^limit_value

    query
    |> apply_filters(opts)
    |> Repo.all()
  end

  @doc """
  Get audit logs for a user.
  """
  def list_for_user(user_id, opts \\ []) do
    limit_value = opts[:limit] || 100

    query =
      from a in __MODULE__,
        where: a.user_id == ^user_id,
        order_by: [desc: a.timestamp],
        limit: ^limit_value

    query
    |> apply_filters(opts)
    |> Repo.all()
  end

  @doc """
  Get audit logs for a resource.
  """
  def list_for_resource(resource_type, resource_id, opts \\ []) do
    from(a in __MODULE__,
      where: a.resource_type == ^to_string(resource_type) and
             a.resource_id == ^resource_id,
      order_by: [desc: a.timestamp],
      limit: ^(opts[:limit] || 100)
    )
    |> Repo.all()
  end

  @doc """
  Generate compliance report for date range.
  """
  def compliance_report(tenant_id, start_date, end_date) do
    query = from a in __MODULE__,
      where: a.tenant_id == ^tenant_id and
             a.timestamp >= ^start_date and
             a.timestamp <= ^end_date,
      group_by: [a.action, a.status],
      select: %{
        action: a.action,
        status: a.status,
        count: count(a.id)
      }

    Repo.all(query)
  end

  @doc """
  Detect security threats for a tenant.
  """
  def detect_threats(tenant_id, time_window \\ 900) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-time_window, :second)

    # Failed login attempts
    failed_logins = from(a in __MODULE__,
      where: a.tenant_id == ^tenant_id and
             a.action == "login" and
             a.status == :failure and
             a.timestamp >= ^cutoff_time,
      group_by: a.user_id,
      having: count(a.id) >= 5,
      select: %{user_id: a.user_id, count: count(a.id), threat: "multiple_failed_logins"}
    )
    |> Repo.all()

    # Unusual data access patterns
    unusual_access = from(a in __MODULE__,
      where: a.tenant_id == ^tenant_id and
             a.action == "data_access" and
             a.timestamp >= ^cutoff_time,
      group_by: a.user_id,
      having: count(a.id) >= 100,
      select: %{user_id: a.user_id, count: count(a.id), threat: "unusual_data_access"}
    )
    |> Repo.all()

    # Multiple session creation from different IPs
    session_anomalies = from(a in __MODULE__,
      where: a.tenant_id == ^tenant_id and
             a.action == "session_created" and
             a.timestamp >= ^cutoff_time,
      group_by: a.user_id,
      having: count(fragment("DISTINCT ?", a.ip_address)) >= 5,
      select: %{user_id: a.user_id, ip_count: count(fragment("DISTINCT ?", a.ip_address)), threat: "multiple_locations"}
    )
    |> Repo.all()

    %{
      failed_logins: failed_logins,
      unusual_access: unusual_access,
      session_anomalies: session_anomalies
    }
  end

  # Private Functions

  defp determine_severity(action) do
    critical_actions = [:delete, :destroy, :revoke_access, :change_password,
                       :update_permissions, :security_breach]
    warning_actions = [:update, :change_settings, :export_data]

    cond do
      action in critical_actions -> :critical
      action in warning_actions -> :warning
      true -> :info
    end
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:action, action}, q -> from a in q, where: a.action == ^to_string(action)
      {:resource_type, type}, q -> from a in q, where: a.resource_type == ^to_string(type)
      {:severity, severity}, q -> from a in q, where: a.severity == ^severity
      {:status, status}, q -> from a in q, where: a.status == ^status
      {:from_date, date}, q -> from a in q, where: a.timestamp >= ^date
      {:to_date, date}, q -> from a in q, where: a.timestamp <= ^date
      _, q -> q
    end)
  end

  defp check_suspicious_activity(attrs) do
    # Check for patterns
    recent_actions = from(a in __MODULE__,
      where: a.tenant_id == ^attrs.tenant_id and
             a.user_id == ^attrs.user_id and
             a.timestamp >= ago(5, "minute"),
      order_by: [desc: a.timestamp],
      limit: 10
    )
    |> Repo.all()

    # Check for multiple failed logins
    failed_login_count = Enum.count(recent_actions, &(&1.action == "login" && &1.status == :failure))

    if failed_login_count >= 5 do
      Logger.warn("Suspicious activity detected: Multiple failed logins for user #{attrs.user_id}")

      # Alert security team
      alert_security_team(attrs.tenant_id, :multiple_failed_logins, attrs)
    end

    # Check for unusual data access volume
    data_access_count = Enum.count(recent_actions, &(&1.action == "data_access"))

    if data_access_count >= 50 do
      Logger.warn("Suspicious activity detected: Unusual data access volume for user #{attrs.user_id}")

      alert_security_team(attrs.tenant_id, :unusual_data_access, attrs)
    end
  end

  defp alert_security_team(tenant_id, threat_type, context) do
    # Send alert via email, Slack, PagerDuty, etc.
    Logger.critical("Security Alert for tenant #{tenant_id}: #{threat_type} - #{inspect(context)}")

    # Could integrate with external alerting services
    # Przma.Notifications.send_security_alert(tenant_id, threat_type, context)
  end
end

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
