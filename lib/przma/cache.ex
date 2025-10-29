defmodule Przma.Cache do
  @moduledoc """
  Simple ETS-based cache with TTL support.

  For production, consider using Cachex or Nebulex.
  """

  use GenServer

  @table_name :przma_cache
  @cleanup_interval 60_000  # 1 minute

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stores a value in cache with optional TTL (in seconds).
  """
  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, :infinity)
    expires_at = calculate_expiry(ttl)

    :ets.insert(@table_name, {key, value, expires_at})
    :ok
  end

  @doc """
  Retrieves a value from cache.
  """
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expires_at}] ->
        if expired?(expires_at) do
          :ets.delete(@table_name, key)
          nil
        else
          value
        end

      [] -> nil
    end
  end

  @doc """
  Deletes a value from cache.
  """
  def delete(key) do
    :ets.delete(@table_name, key)
    :ok
  end

  @doc """
  Clears all cache entries.
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private Functions

  defp calculate_expiry(:infinity), do: :infinity
  defp calculate_expiry(ttl) when is_integer(ttl) do
    System.system_time(:second) + ttl
  end

  defp expired?(:infinity), do: false
  defp expired?(expires_at) do
    System.system_time(:second) > expires_at
  end

  defp cleanup_expired do
    now = System.system_time(:second)

    :ets.foldl(fn {key, _value, expires_at}, acc ->
      if expires_at != :infinity && expires_at < now do
        :ets.delete(@table_name, key)
      end
      acc
    end, :ok, @table_name)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
