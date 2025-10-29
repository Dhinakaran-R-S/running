defmodule Przma.Workers.PushNotificationWorker do
  @moduledoc """
  Worker for sending push notifications.
  """

  use Oban.Worker,
    queue: :push,
    max_attempts: 3,
    priority: 2

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"member_id" => _member_id, "type" => type, "data" => _data}}) do
    Logger.info("Sending push notification: #{type}")

    # TODO: Implement push notification using FCM/APNS
    # Example: Przma.PushService.send(member_id, type, data)

    :ok
  end
end
