defmodule Przma.Workers.EmailWorker do
  @moduledoc """
  Worker for sending emails.
  """

  use Oban.Worker,
    queue: :emails,
    max_attempts: 5,
    priority: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"member_id" => member_id, "type" => type, "data" => data}}) do
    Logger.info("Sending email to member #{member_id}: #{type}")

    # TODO: Implement email sending using your preferred email service
    # Example: Przma.Mailer.send_email(member_id, type, data)

    :ok
  end
end
