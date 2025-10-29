defmodule Przma.Workers.CleanupWorker do
  @moduledoc """
  Scheduled worker for cleaning up old data.

  Runs daily at 3 AM via Oban cron.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    priority: 4

  alias Przma.Repo
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Running cleanup tasks")

    cleanup_expired_sessions()
    cleanup_expired_tokens()
    cleanup_old_audit_logs()
    cleanup_orphaned_cas_objects()

    :ok
  end

  defp cleanup_expired_sessions do
    cutoff = DateTime.utc_now() |> DateTime.add(-30, :day)

    count = from(s in Przma.Auth.Session,
      where: s.expires_at < ^cutoff or s.status == :expired
    )
    |> Repo.delete_all()

    Logger.info("Cleaned up #{elem(count, 0)} expired sessions")
  end

  defp cleanup_expired_tokens do
    cutoff = DateTime.utc_now()

    count = from(t in Przma.Auth.RefreshToken,
      where: t.expires_at < ^cutoff
    )
    |> Repo.delete_all()

    Logger.info("Cleaned up #{elem(count, 0)} expired tokens")
  end

  defp cleanup_old_audit_logs do
    # Keep audit logs for 1 year
    cutoff = DateTime.utc_now() |> DateTime.add(-365, :day)

    count = from(a in Przma.AuditLog,
      where: a.timestamp < ^cutoff and a.severity != :critical
    )
    |> Repo.delete_all()

    Logger.info("Cleaned up #{elem(count, 0)} old audit logs")
  end

  defp cleanup_orphaned_cas_objects do
    # Remove CAS objects with reference_count = 0 that are older than 7 days
    cutoff = DateTime.utc_now() |> DateTime.add(-7, :day)

    count = from(c in Przma.CAS.Object,
      where: c.reference_count == 0 and c.inserted_at < ^cutoff
    )
    |> Repo.delete_all()

    Logger.info("Cleaned up #{elem(count, 0)} orphaned CAS objects")
  end
end
