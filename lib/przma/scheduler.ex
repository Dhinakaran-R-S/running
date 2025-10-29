defmodule Przma.Scheduler do
  @moduledoc """
  Scheduled task coordinator using Oban Cron.

  Defines recurring jobs for maintenance and analytics.
  """

  @doc """
  Returns Oban cron configuration.
  """
  def cron_config do
    [
      # Daily insights generation at 2 AM
      {"0 2 * * *", Przma.Workers.DailyInsightsWorker},

      # Hourly activity enrichment catch-up
      {"0 * * * *", Przma.Workers.EnrichmentCatchupWorker},

      # Every 15 minutes: update PERMA scores
      {"*/15 * * * *", Przma.Workers.PermaUpdateWorker},

      # Weekly reports on Sunday at 9 AM
      {"0 9 * * 0", Przma.Workers.WeeklyReportWorker},

      # Daily cleanup of old data at 3 AM
      {"0 3 * * *", Przma.Workers.CleanupWorker},

      # Every 5 minutes: sync offline changes
      {"*/5 * * * *", Przma.Workers.OfflineSyncWorker}
    ]
  end
end
