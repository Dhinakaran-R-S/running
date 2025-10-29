defmodule PrzmaWeb.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting middleware using ETS-based token bucket algorithm.
  """

  import Plug.Conn
  import Phoenix.Controller

  @table_name :rate_limit_buckets
  @default_limit 100
  @default_window 60_000  # 1 minute

  def init(opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    window = Keyword.get(opts, :window, @default_window)

    # Create ETS table if it doesn't exist
    case :ets.info(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
      _ ->
        :ok
    end

    %{limit: limit, window: window}
  end

  def call(conn, opts) do
    identifier = get_identifier(conn)

    case check_rate_limit(identifier, opts) do
      :ok ->
        conn

      {:error, :rate_limited, retry_after} ->
        conn
        |> put_resp_header("retry-after", to_string(retry_after))
        |> put_resp_header("x-ratelimit-limit", to_string(opts.limit))
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> put_status(:too_many_requests)
        |> put_view(PrzmaWeb.ErrorView)
        |> render("error.json", error: "Rate limit exceeded")
        |> halt()
    end
  end

  defp get_identifier(conn) do
    # Use user ID if authenticated, otherwise IP address
    case conn.assigns[:current_user_id] do
      nil -> get_client_ip(conn)
      user_id -> "user:#{user_id}"
    end
  end

  defp check_rate_limit(identifier, opts) do
    now = System.system_time(:millisecond)
    window_start = now - opts.window

    case :ets.lookup(@table_name, identifier) do
      [{^identifier, timestamps}] ->
        # Filter to current window
        recent = Enum.filter(timestamps, &(&1 > window_start))

        if length(recent) >= opts.limit do
          oldest = Enum.min(recent)
          retry_after = div(oldest + opts.window - now, 1000)
          {:error, :rate_limited, retry_after}
        else
          # Add current request
          :ets.insert(@table_name, {identifier, [now | recent]})
          :ok
        end

      [] ->
        # First request
        :ets.insert(@table_name, {identifier, [now]})
        :ok
    end
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip
      [] -> to_string(:inet.ntoa(conn.remote_ip))
    end
  end
end
