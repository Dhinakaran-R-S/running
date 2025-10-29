defmodule Przma.Workers.NotificationWorker do
  @moduledoc """
  Worker for sending notifications.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    priority: 2

  alias Przma.Notifications
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"member_id" => member_id, "type" => type, "data" => data}}) do
    Logger.info("Sending notification to member #{member_id}: #{type}")

    case Notifications.send_notification(member_id, type, data) do
      :ok -> :ok
      {:error, reason} ->
        Logger.error("Failed to send notification: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
